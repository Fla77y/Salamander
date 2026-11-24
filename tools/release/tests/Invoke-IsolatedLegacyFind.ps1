#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([ValidateSet('Release','Debug')][string]$Configuration = 'Release',
      [ValidateSet('ExternalEditor','ExternalEditorNative')][string]$EditorScenario,
      [ValidateSet('EncryptedFixture','NearLimit','RecycleRestore')][string]$SpecialScenario,
      [string]$EncryptedFixture)
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
if ($EditorScenario -and $SpecialScenario) { throw 'Select only one focused scenario.' }
if (($SpecialScenario -eq 'EncryptedFixture') -ne [bool]$EncryptedFixture) {
    throw 'EncryptedFixture requires an explicitly provided disposable EFS file.'
}
$scenarioAttribute = (Get-Command -Name $driver).Parameters['LegacyFindScenario'].Attributes |
    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
$scenarios = @($scenarioAttribute.ValidValues | Where-Object { $_ -notin $optIn })
# Optional focused editor diagnosis; default full-suite coverage is unchanged.
if ($PSBoundParameters.ContainsKey('EditorScenario')) {
    if ($EditorScenario -notin $scenarios) { throw 'Requested editor scenario is not registered.' }
    $scenarios = @($EditorScenario)
}

if ($SpecialScenario) {
    if ($SpecialScenario -notin $scenarioAttribute.ValidValues) { throw 'Unknown special scenario.' }
    $scenarios = @($SpecialScenario)
}
$fixtureArgs = @()
if ($EncryptedFixture) { $fixtureArgs = @('-LegacyFindEncryptedFixture', $EncryptedFixture) }

$binary = & (Join-Path $PSScriptRoot 'Build-IsolatedGuiTest.ps1') -Configuration $Configuration -OutputName 'isolated-legacy-find'

# A failed scenario must not hide failures in later, independent GUI cases.
# Every case launches its own disposable process/configuration. Never start
# another case if a previous one left Salamander running.
. (Join-Path $PSScriptRoot '..\Test-RunCollection.ps1')
Initialize-TestRun -CollectFailures
$unsafeToContinue = $false
foreach ($case in $scenarios) {
    $caseName = "Legacy Find $Configuration x64 $case"
    if (-not $unsafeToContinue -and
        @(Get-Process salamand -ErrorAction SilentlyContinue).Count -ne 0) {
        $unsafeToContinue = $true
    }
    if ($unsafeToContinue) {
        Skip-TestCase -Name $caseName -Reason 'Salamander process still running; further GUI tests are unsafe.'
        continue
    }
    Write-Host "=== LEGACY FIND GUI: $Configuration x64 $case ==="
    Invoke-TestCase -Name $caseName -Action {
        & pwsh -Sta -NoProfile -File $driver -SalamanderExe $binary -IsolatedConfiguration -LegacyFindScenario $case @fixtureArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Legacy Find GUI case failed: $Configuration x64 $case (exit code $LASTEXITCODE)."
        }
    }
}
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$logs = Join-Path $repository '.Build\logs'
[void][IO.Directory]::CreateDirectory($logs)
$runId = [guid]::NewGuid().ToString('N')
Complete-TestRun -LogPath (Join-Path $logs "legacy-find-$Configuration-$runId.log")
Write-Host "PASS: $($scenarios.Count) isolated Legacy Find GUI scenarios on $Configuration x64."
