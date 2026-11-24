#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release',
    [Parameter(Mandatory)][ValidateSet('History','Clipboard','RecycleFile','RecycleDirectory')][string]$Scenario
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Close all existing Salamander instances; this runner never kills them.'
}
$mode = switch ($Scenario) {
    History { '-LongNavigationHistoryOnly' }
    Clipboard { '-LongClipboardMoveOnly' }
    RecycleFile { '-LongRecycleOnly' }
    RecycleDirectory { '-LongRecycleDirectoryOnly' }
}
$binary = & (Join-Path $PSScriptRoot 'Build-IsolatedGuiTest.ps1') -Configuration $Configuration -OutputName 'isolated-long-paths'
& pwsh -Sta -NoProfile -File (Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1') -SalamanderExe $binary -IsolatedConfiguration $mode
if ($LASTEXITCODE -ne 0) { throw "Isolated long-path $Configuration $Scenario failed." }
if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Salamander process still running after isolated long-path scenario.'
}
