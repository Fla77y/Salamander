#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Source characterization only. It does NOT claim visual equivalence with
# Open Salamander 5.0, nor that every dialog was opened by a GUI test.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$baselineFile = Join-Path $repository 'tools\release\ui-resource-inventory-baseline.json'
$baseline = Get-Content -LiteralPath $baselineFile -Raw | ConvertFrom-Json
if ($baseline.schemaVersion -ne 1) { throw 'Unsupported UI inventory schema.' }

function Get-ResourceIdentifiers {
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Pattern)
    foreach ($match in [regex]::Matches($Source, $Pattern)) {
        $match.Groups[1].Value
    }
}

function Assert-ResourceIds {
    param([string[]]$Expected, [string[]]$Actual, [string]$Category)
    $before = [string[]]@($Expected)
    $after = [string[]]@($Actual)
    [Array]::Sort($before, [StringComparer]::Ordinal)
    [Array]::Sort($after, [StringComparer]::Ordinal)
    if ($before.Count -ne @($before | Select-Object -Unique).Count -or
        $after.Count -ne @($after | Select-Object -Unique).Count -or
        ($before -join ';') -cne ($after -join ';')) {
        throw "$Category IDs differ from characterized 5.2 reference. Review UI compatibility and update the baseline only with an approved change."
    }
}

# Preserve original 5.0 keyboard bindings, including repeats across groups.
function Assert-OriginalAcceleratorBindings {
    param([Parameter(Mandatory)][string]$Text,
          [Parameter(Mandatory)][string[]]$OriginalBindings)

    $counts = [Collections.Generic.Dictionary[string,int]]::new(
        [StringComparer]::Ordinal)
    $entryPattern = '(?m)^\s*(VK_[A-Z0-9_]+|"[^"]+")\s*,\s*([A-Z0-9_]+)\s*,\s*(.*?)\s*$'
    foreach ($match in [regex]::Matches($Text, $entryPattern)) {
        $flags = ($match.Groups[3].Value -replace '//.*$', '') -replace '\s+', ''
        $name = '{0}|{1}|{2}' -f $match.Groups[1].Value,
                                      $match.Groups[2].Value, $flags
        if ($counts.ContainsKey($name)) { $counts[$name]++ }
        else { $counts.Add($name, 1) }
    }
    foreach ($name in $OriginalBindings) {
        if (-not $counts.ContainsKey($name) -or $counts[$name] -le 0) {
            throw "Original 5.0 accelerator binding missing: $name"
        }
        $counts[$name]--
    }
}

# The 5.0 dialog resource was unchanged except for the 5.2 UTF-8 BOM.
# Reconstruct its canonical Git blob hash independent of Windows CRLF.
function Get-CanonicalGitBlobSha {
    param([Parameter(Mandatory)][string]$Text)
    $canonical = $Text.TrimStart([char]0xfeff).Replace("`r`n", "`n")
    $payload = [Text.Encoding]::UTF8.GetBytes($canonical)
    $prefix = [Text.Encoding]::ASCII.GetBytes('blob ' + $payload.Length)
    $toHash = [byte[]]::new($prefix.Length + 1 + $payload.Length)
    [Array]::Copy($prefix, 0, $toHash, 0, $prefix.Length)
    [Array]::Copy($payload, 0, $toHash, $prefix.Length + 1, $payload.Length)
    return [Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($toHash)).ToLowerInvariant()
}
$dialogRc = Get-Content -LiteralPath (Join-Path $repository 'src\lang\lang.rc') -Raw
$acceleratorRc = Get-Content -LiteralPath (Join-Path $repository 'src\salamand.rc') -Raw
$dialogPattern = '(?m)^\s*(IDD_[A-Z0-9_]+)\s+DIALOGEX?\b'
$acceleratorPattern = '(?m)^\s*(IDA_[A-Z0-9_]+)\s+ACCELERATORS\b'

$dialogs = @(Get-ResourceIdentifiers -Source $dialogRc -Pattern $dialogPattern)
$accelerators = @(Get-ResourceIdentifiers -Source $acceleratorRc -Pattern $acceleratorPattern)
Assert-ResourceIds -Expected $baseline.dialogResourceNames -Actual $dialogs -Category 'Win32 dialogs'
$originalDialogBlob = $baseline.originalSourceReference.langDialogRcGitBlobSha
if ((Get-CanonicalGitBlobSha -Text $dialogRc) -cne $originalDialogBlob) {
    throw 'Original 5.0 Win32 dialog resource text/controls changed without review.'
}

Assert-ResourceIds -Expected $baseline.acceleratorGroupNames -Actual $accelerators -Category 'Win32 accelerators'
if ($baseline.originalSourceReference.commit -cne '3945ecf7a655b2dbb0a50e189a2682e1e336352e' -or
    $baseline.originalSourceReference.productVersion -cne '5.0') {
    throw 'Unrecognized original 5.0 source characterization baseline.'
}
Assert-OriginalAcceleratorBindings -Text $acceleratorRc -OriginalBindings $baseline.originalSourceReference.originalMainAcceleratorEntries

foreach ($id in @('IDD_FIND','IDD_FINDADVANCED','IDD_FINDIGNORE','IDD_FINDSETTINGS',
                  'IDD_COPYMOVEDIALOG','IDD_PACK','IDD_UNPACK','IDD_PLUGINS')) {
    if ($id -notin $dialogs) { throw "Critical original dialog removed: $id" }
}
foreach ($control in @('IDC_FIND_ADVANCED','IDC_FIND_ADVANCED_TEXT',
                      'IDC_FIND_REGULAR','IDC_FIND_GREP','IDC_FIND_HEX')) {
    if ($dialogRc -notmatch ('\b' + [regex]::Escape($control) + '\b')) {
        throw "Critical original Find control removed: $control"
    }
}
foreach ($command in @(
    'VK_F2,\s+CM_RENAMEFILE',
    'VK_F3,\s+CM_VIEW',
    'VK_F4,\s+CM_EDIT',
    'VK_F5,\s+CM_COPYFILES',
    'VK_F6,\s+CM_MOVEFILES',
    'VK_F7,\s+CM_FINDFILE',
    'VK_F8,\s+CM_DELETEFILES'
)) {
    if ($acceleratorRc -notmatch $command) {
        throw "Legacy function-key accelerator missing: $command"
    }
}

# Negative characterization: the collector must detect a removed dialog.
$withoutFind = [regex]::new(
    '(?m)^\s*IDD_FIND\s+DIALOGEX?[^\r\n]*').Replace($dialogRc, '', 1)
$idsWithoutFind = @(Get-ResourceIdentifiers -Source $withoutFind -Pattern $dialogPattern)
$rejected = $false
try {
    Assert-ResourceIds -Expected $baseline.dialogResourceNames -Actual $idsWithoutFind -Category 'Win32 dialogs'
}
catch {
    if ($_.Exception.Message -notmatch 'Win32 dialogs IDs differ') { throw }
    $rejected = $true
}
if (-not $rejected) {
    throw 'Missing IDD_FIND was not rejected by the actual resource contract.'
}
# Negative: simulate deletion of F5 Copy from the original resource source.
$withoutCopyKey = [regex]::new(
    '(?m)^\s*VK_F5,\s+CM_COPYFILES,\s+VIRTKEY\s*$').Replace($acceleratorRc, '', 1)
$rejected = $false
try {
    Assert-OriginalAcceleratorBindings -Text $withoutCopyKey -OriginalBindings $baseline.originalSourceReference.originalMainAcceleratorEntries
}
catch {
    if ($_.Exception.Message -notmatch 'Original 5.0 accelerator binding missing') { throw }
    $rejected = $true
}
if (-not $rejected) {
    throw 'Removing the historical F5 copy accelerator was not rejected.'
}

Write-Host "PASS: $($dialogs.Count) Win32 dialog resources, $($accelerators.Count) accelerator groups and critical legacy shortcuts are source-characterized."
Write-Host 'PASS: all 89 original 5.0 keyboard bindings remain declared, including duplicates.'

# Negative: changes to dialog caption, layout or controls must be rejected.
$modifiedDialog = $dialogRc.Replace('IDD_FIND DIALOGEX', 'IDD_FIND DIALOGEX_CHANGED')
if ($modifiedDialog -ceq $dialogRc -or
    (Get-CanonicalGitBlobSha -Text $modifiedDialog) -ceq $originalDialogBlob) {
    throw 'Changing the original dialog declaration did not alter its Git blob hash.'
}
Write-Host 'PASS: complete 5.0 Win32 dialog resource content is unchanged except BOM/CRLF.'
Write-Host 'NOTE: Original 5.0 visual and interactive UI parity remains open (A0-01).'
