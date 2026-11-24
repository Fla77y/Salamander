#requires -Version 7.4
# Independent self-test for the --test-all collector. No build or GUI needed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\Test-RunCollection.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) (
    'OpenSal-TestRun-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
try {
    Initialize-TestRun -CollectFailures
    $script:continued = $false
    Invoke-TestCase -Name 'synthetic fail' -Action { throw 'expected synthetic failure' } -BlocksGui 6>$null
    Invoke-TestCase -Name 'synthetic pass' -Action { $script:continued = $true }
    Invoke-TestCase -Name 'synthetic gated GUI' -Action {
        throw 'GUI action should never run'
    } -RequiresGuiSafety 3>$null 6>$null

    if (-not $script:continued -or $script:TestOutcomes.Count -ne 3 -or
        $script:TestOutcomes[0].Status -ne 'FAIL' -or
        $script:TestOutcomes[1].Status -ne 'PASS' -or
        $script:TestOutcomes[2].Status -ne 'SKIP') {
        throw 'Independent work did not continue or a blocked GUI action ran.'
    }

    $log = Join-Path $temporary 'aggregate.log'
    $caught = $false
    try { Complete-TestRun -LogPath $log 6>$null }
    catch {
        if ($_.Exception.Message -notmatch '1 Fehler, 1 übersprungen') { throw }
        $caught = $true
    }
    $reportPath = Join-Path $temporary 'aggregate.results.json'
    if (-not $caught -or -not (Test-Path -LiteralPath $reportPath)) {
        throw 'A failed aggregate run must keep a JSON report and fail the caller.'
    }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.Passed -ne 1 -or $report.Failed -ne 1 -or
        $report.Skipped -ne 1 -or $report.Results.Count -ne 3 -or
        $report.Results[0].Detail -notmatch 'expected synthetic failure') {
        throw 'Aggregated counts, identities or diagnostics are incorrect.'
    }

    Initialize-TestRun -CollectFailures
    $cancellationPropagated = $false
    try {
        Invoke-TestCase -Name 'cancellation' -Action {
            throw [OperationCanceledException]::new('intentional cancellation')
        }
    }
    catch [OperationCanceledException] { $cancellationPropagated = $true }
    if (-not $cancellationPropagated -or $script:TestOutcomes.Count -ne 0) {
        throw 'Cancellation must never be swallowed or counted as an ordinary test failure.'
    }

    Initialize-TestRun
    $caught = $false
    try { Invoke-TestCase -Name 'fail-fast' -Action { throw 'expected fail-fast' } }
    catch {
        if ($_.Exception.Message -ne 'expected fail-fast') { throw }
        $caught = $true
    }
    if (-not $caught -or $script:TestOutcomes.Count -ne 0) {
        throw 'Ordinary --test must keep its original fail-fast semantics.'
    }

    Initialize-TestRun -CollectFailures
    Invoke-TestCase -Name 'clean' -Action { }
    Complete-TestRun -LogPath (Join-Path $temporary 'clean.log') 6>$null
    $clean = Get-Content -LiteralPath (Join-Path $temporary 'clean.results.json') -Raw |
        ConvertFrom-Json
    if ($clean.Failed -ne 0 -or $clean.Skipped -ne 0 -or $clean.Passed -ne 1) {
        throw 'Successful aggregate run produced an incorrect report.'
    }
    Write-Host 'PASS: independent failures, GUI gating, JSON report and fail-fast compatibility.'
}
finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
