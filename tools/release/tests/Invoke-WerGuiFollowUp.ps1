#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Run one explicitly authorized isolated GUI scenario and copy its log.
.DESCRIPTION
    -AllowDesktop authorizes only the selected case on an unlocked exclusive
    Windows desktop. Existing Salamander processes are never terminated.
    No rebuild, WER registry changes, upload or deliberate crash.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)]
    [ValidateSet('DebugX86Copy', 'ReleaseX64Short')][string]$Scenario,
    [switch]$AllowDesktop,
    [switch]$CaptureHangDump
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) { throw 'This GUI acceptance requires Windows.' }
if (-not $AllowDesktop) {
    throw 'Desktop not authorized. Pass -AllowDesktop only on an unlocked exclusive desktop.'
}

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')).TrimEnd('\')
$root = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
$expectedParent = [IO.Path]::GetFullPath((Join-Path $repository '.Build')).TrimEnd('\')
if (-not (Split-Path -Parent $root).Equals(
    $expectedParent, [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $root) -notmatch '^wer-build-[0-9a-f]{32}$') {
    throw "Refusing non-isolated WER build root: $root"
}
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Build directory not found: $root"
}
$variant = if ($Scenario -eq 'DebugX86Copy') { 'Debug_x86' } else { 'Release_x64' }
$exe = Join-Path $root "salamander\$variant\salamand.exe"
$test = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
$logs = Join-Path $root 'gui-followup-logs'

# No junction, symlink or redirected executable inside the verified tree.
foreach ($path in @(
    $expectedParent, $root, (Join-Path $root 'salamander'),
    (Join-Path $root "salamander\$variant"), $exe, $logs
)) {
    if ((Test-Path -LiteralPath $path) -and
        (Get-Item -LiteralPath $path -Force).Attributes.HasFlag(
            [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing test through a reparse point: $path"
    }
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Test binary not found: $exe"
}
if (-not (Test-Path -LiteralPath $test -PathType Leaf)) {
    throw "GUI driver not found: $test"
}
if (@(Get-Process -Name salamand -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Another Salamander is running. No GUI test started.'
}

[void][IO.Directory]::CreateDirectory($logs)
$id = [guid]::NewGuid().ToString('N')
$log = Join-Path $logs "$Scenario-$id.log"
$temp = Join-Path $root "gui-temp-$id"
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$previousDump = $env:OPENSAL_GUI_CAPTURE_HANG_DUMP
$testExitCode = -1
try {
    $env:TEMP = $temp
    $env:TMP = $temp
    $env:OPENSAL_GUI_CAPTURE_HANG_DUMP = if ($CaptureHangDump) { '1' } else { $null }
    [void][IO.Directory]::CreateDirectory($temp)

    $arguments = @('-Sta', '-NoProfile', '-File', $test,
                   '-SalamanderExe', $exe, '-IsolatedConfiguration')
    if ($Scenario -eq 'DebugX86Copy') {
        $arguments += @('-LargeUnicodeCopyOnly', '-LargeUnicodeCopyCase', 'Copy')
    }
    else {
        $arguments += '-ShortOperationsOnly'
    }
    Write-Host "GUI scenario: $Scenario"
    Write-Host "Test binary: $exe"
    Write-Host "Log file: $log"
    & pwsh @arguments 2>&1 | Tee-Object -FilePath $log
    $testExitCode = $LASTEXITCODE
}
finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    $env:OPENSAL_GUI_CAPTURE_HANG_DUMP = $previousDump
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $report = [IO.File]::ReadAllText($log) +
            [Environment]::NewLine + "GUI-Test-Exitcode: $testExitCode"
        try {
            $report | Set-Clipboard
            Write-Host "GUI log copied to clipboard: $log"
        }
        catch {
            Write-Warning "Clipboard unavailable; saved GUI log remains at $log : $($_.Exception.Message)"
        }
    }
}
if ($testExitCode -ne 0) {
    throw "GUI test failed ($Scenario), exit code $testExitCode; log: $log"
}
Write-Host "PASS: $Scenario GUI acceptance completed."
