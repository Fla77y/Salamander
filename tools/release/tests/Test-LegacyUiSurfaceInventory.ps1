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

$dialogRc = Get-Content -LiteralPath (Join-Path $repository 'src\lang\lang.rc') -Raw
$acceleratorRc = Get-Content -LiteralPath (Join-Path $repository 'src\salamand.rc') -Raw
$dialogPattern = '(?m)^\s*(IDD_[A-Z0-9_]+)\s+DIALOGEX?\b'
$acceleratorPattern = '(?m)^\s*(IDA_[A-Z0-9_]+)\s+ACCELERATORS\b'

$dialogs = @(Get-ResourceIdentifiers -Source $dialogRc -Pattern $dialogPattern)
$accelerators = @(Get-ResourceIdentifiers -Source $acceleratorRc -Pattern $acceleratorPattern)
Assert-ResourceIds -Expected $baseline.dialogResourceNames -Actual $dialogs -Category 'Win32 dialogs'
Assert-ResourceIds -Expected $baseline.acceleratorGroupNames -Actual $accelerators -Category 'Win32 accelerators'

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
if ('IDD_FIND' -in $idsWithoutFind) {
    throw 'Resource inventory collector failed to detect removal of IDD_FIND.'
}
Write-Host "PASS: $($dialogs.Count) Win32 dialog resources, $($accelerators.Count) accelerator groups and critical legacy shortcuts are source-characterized."
Write-Host 'NOTE: Original 5.0 visual and interactive UI parity remains open (A0-01).'
