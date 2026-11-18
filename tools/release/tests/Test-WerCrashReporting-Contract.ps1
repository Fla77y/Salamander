#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Headless contracts for replacing the external SalMon reporter with WER.
.DESCRIPTION
    This test does not change registry settings, launch Salamander or crash a process.
    A real WER crash/dump acceptance test must be performed separately on Windows.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
function Read-Source([string]$relativePath) {
    return [IO.File]::ReadAllText((Join-Path $repo $relativePath))
}

# Arrange / Act / Assert: product and solution must not link or invoke SalMon.
foreach ($former in @(
    'src\salmon', 'src\salmoncl.cpp', 'src\salmoncl.h',
    'src\vcxproj\salmon'
)) {
    if (Test-Path -LiteralPath (Join-Path $repo $former)) {
        throw "Legacy reporter still ships in the source tree: $former"
    }
}
$solution = Read-Source 'src\vcxproj\salamand.sln'
$project = Read-Source 'src\vcxproj\salamand.vcxproj'
$entry = Read-Source 'src\salamdr1.cpp'
$stack = Read-Source 'src\callstk.cpp'
$stackHeader = Read-Source 'src\callstk.h'
if ($solution -match '(?i)salmon' -or
    $project -match '(?i)salmoncl' -or
    $entry -match '(?i)salmon' -or
    $stack -match '(?i)salmon|SetUnhandledExceptionFilter|PreventSetUnhandledExceptionFilter' -or
    $stackHeader -match '(?i)salmon|ThreadBugReportF|CreateBugReportFile') {
    throw 'SalMon process and custom exception-filter hooks must be absent from the product.'
}
if ($stack -notmatch '(?s)CCallStack::HandleException\(.*?EXCEPTION_CONTINUE_SEARCH' -or
    $stack -match 'TerminateProcess\(' -or
    $entry -match '"/ENTRY:MyEntryPoint"(?s:.*?)WinMainCRTStartup') {
    throw 'Exceptions must be allowed to reach the system WER handler without forced process termination.'
}
if ((Read-Source 'src\lang\texts.rc2') -match 'IDS_SALMON_' -or
    (Read-Source 'src\texts.rh2') -match 'IDS_SALMON_') {
    throw 'SalMon dialog and upload strings are still included.'
}
Write-Host 'PASS: product has no SalMon executable, uploads, dialogs or crash-handler interception.'

# Arrange / Act / Assert: stale build output must not leak into packages.
$package = Read-Source 'tools\release\Package-Helpers.ps1'
if ($package -notmatch "(?i)'salmon\.exe'" -or
    $package -notmatch "(?s)Test-DistributionStage.*?utils\\salmon\.exe") {
    throw 'Portable/installer stage must exclude and reject stale SalMon binaries.'
}
Write-Host 'PASS: distribution stage excludes legacy SalMon even from stale incremental builds.'

# WER LocalDumps is HKLM-only according to Microsoft's documented contract.
# Enabling must be an intentional elevated action; status must remain read-only.
$werPath = Join-Path $repo 'tools\release\Configure-LocalCrashDumps.ps1'
if (-not (Test-Path -LiteralPath $werPath -PathType Leaf)) {
    throw 'Optional WER LocalDumps configuration helper missing.'
}
$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $werPath, [ref]$tokens, [ref]$errors)
if (@($errors).Count -gt 0) {
    throw "WER configuration has parse errors: $($errors -join '; ')"
}
$wer = [IO.File]::ReadAllText($werPath)
if ($wer -notmatch 'RegistryHive\]::LocalMachine' -or
    $wer -notmatch 'RegistryView\]::Registry32' -or
    $wer -notmatch 'RegistryView\]::Registry64' -or
    $wer -notmatch 'IsInRole' -or
    $wer -notmatch 'DumpType' -or
    $wer -notmatch 'DumpCount' -or
    $wer -notmatch 'salamand\.exe' -or
    $wer -notmatch '(?s)-Enable.*?ReadOnly|ReadOnly.*?-Enable' -or
    $wer -match 'CurrentUser|Enable.*Automatic') {
    throw 'LocalDumps must require explicit elevation, honor both registry views, and leave status read-only.'
}
Write-Host 'PASS: WER local dump configuration is explicit and never a startup side effect.'
