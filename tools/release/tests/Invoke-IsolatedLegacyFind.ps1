#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([ValidateSet('Release','Debug')][string]$Configuration = 'Release')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Close running Salamander instances before running the isolated Legacy Find suite.'
}

$driver = Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1'
# A GUI scenario added to the driver is automatically exercised unless it
# requires a separately authorized fixture or touches the real Recycle Bin.
$optIn = @('EncryptedFixture','NearLimit','RecycleRestore')
$scenarioAttribute = (Get-Command -Name $driver).Parameters['LegacyFindScenario'].Attributes |
    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
$scenarios = @($scenarioAttribute.ValidValues | Where-Object { $_ -notin $optIn })

$binary = & (Join-Path $PSScriptRoot 'Build-IsolatedGuiTest.ps1') -Configuration $Configuration -OutputName 'isolated-legacy-find'
foreach ($case in $scenarios) {
    Write-Host "=== LEGACY FIND GUI: $Configuration x64 $case ==="
    & pwsh -Sta -NoProfile -File $driver -SalamanderExe $binary -IsolatedConfiguration -LegacyFindScenario $case
    if ($LASTEXITCODE -ne 0) { throw "Legacy Find GUI case failed: $Configuration x64 $case" }
}
Write-Host "PASS: $($scenarios.Count) isolated Legacy Find GUI scenarios on $Configuration x64."
