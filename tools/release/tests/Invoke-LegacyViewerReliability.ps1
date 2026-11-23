#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Measures repeatability of the isolated Unicode Find viewer in one x64 configuration.
.DESCRIPTION
    Builds the instrumented GUI once, then runs independent ViewUnicode cases
    with fresh GUID-scoped configurations. Preserves each console transcript
    and a CSV summary keyed by source and binary hashes. Does not change the
    production application, rerun failed GUI commands, or kill processes.
    A passing series is not proof of all Legacy Find or package scenarios.
.EXAMPLE
    pwsh -NoProfile -File .\tools\release\tests\Invoke-LegacyViewerReliability.ps1 -Configuration Debug -Iterations 5
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [ValidateRange(1, 20)][int]$Iterations = 5,
    [string]$OutputDirectory = 'D:\Build\OpenSal\logs\legacy-viewer-reliability'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) {
    throw 'The Unicode Find viewer reliability test requires interactive Windows.'
}

$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$driver = Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1'
$builder = Join-Path $PSScriptRoot 'Build-IsolatedGuiTest.ps1'
$sourceSha = (& git -C $repository rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceSha -notmatch '^[0-9a-f]{40}$') {
    throw 'Cannot identify the exact source commit for the reliability test.'
}
$dirty = @(& git -C $repository status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
    throw 'The tracked working tree must be clean before recording a repeatability result.'
}
if (@(Get-Process salamand -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close running Salamander instances before testing; no processes will be terminated.'
}

$binary = & $builder -Configuration $Configuration -OutputName 'isolated-legacy-find'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    throw "Isolated Salamander test executable was not built: $binary"
}
$binarySha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
$session = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) (
    'viewunicode-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' +
    [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($session)
$summary = Join-Path $session 'Summary.csv'
$results = [Collections.Generic.List[object]]::new()
$failed = $false
$orphaned = $false

Write-Host "ViewUnicode source SHA: $sourceSha"
Write-Host "ViewUnicode binary SHA-256: $binarySha256"
Write-Host "Evidence directory: $session"

try {
    for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
        $existing = @(Get-Process salamand -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            $orphaned = $true
            throw "Salamander process still running before iteration $iteration; refusing further GUI input."
        }
        $currentSha = (& git -C $repository rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $currentSha -cne $sourceSha) {
            throw 'Source commit changed during repeatability test.'
        }
        if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -cne $binarySha256) {
            throw 'Isolated GUI binary changed during repeatability test.'
        }

        $log = Join-Path $session ('ViewUnicode-{0:D2}-{1}.log' -f $iteration, $Configuration)
        Write-Host "=== ViewUnicode $Configuration x64 iteration $iteration/$Iterations ==="
        $started = [DateTime]::UtcNow
        & pwsh -Sta -NoProfile -File $driver -SalamanderExe $binary -IsolatedConfiguration -LegacyFindScenario ViewUnicode 2>&1 |
            Tee-Object -FilePath $log | Out-Host
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 1 }
        $survivors = @(Get-Process salamand -ErrorAction SilentlyContinue)
        $orphanCount = $survivors.Count
        [void]$results.Add([pscustomobject]@{
            Iteration = $iteration
            Configuration = $Configuration
            SourceSha = $sourceSha
            BinarySha256 = $binarySha256
            ExitCode = $exitCode
            DurationSeconds = [Math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 2)
            SurvivingProcesses = $orphanCount
            Log = $log
        })
        if ($exitCode -ne 0) {
            $failed = $true
            Write-Warning "ViewUnicode iteration $iteration failed; original transcript: $log"
        }
        if ($orphanCount -gt 0) {
            $orphaned = $true
            Write-Warning 'Test ended with a running Salamander process; no unknown process will be killed.'
            break
        }
    }
}
finally {
    $results | Export-Csv -LiteralPath $summary -NoTypeInformation -Encoding utf8
    Write-Host "ViewUnicode repeatability summary: $summary"
    $results | Format-Table Iteration, Configuration, ExitCode, DurationSeconds, SurvivingProcesses -AutoSize |
        Out-String | Write-Host
}

if ($failed -or $orphaned) { exit 1 }
Write-Host "PASS: $($results.Count) isolated ViewUnicode iterations passed without surviving Salamander processes."
