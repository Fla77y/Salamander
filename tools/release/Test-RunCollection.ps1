#requires -Version 7.4
# Collect independent test failures without changing fail-fast behavior of --test.
Set-StrictMode -Version Latest

function Initialize-TestRun {
    param([switch]$CollectFailures)
    $script:CollectTestFailures = [bool]$CollectFailures
    $script:TestOutcomes = [System.Collections.Generic.List[object]]::new()
    $script:GuiTestsBlocked = $false
}

function Add-TestOutcome {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'SKIP')][string]$Status,
        [string]$Detail = '',
        [long]$DurationMs = 0
    )
    [void]$script:TestOutcomes.Add([pscustomobject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
        DurationMs = $DurationMs
    })
}

function Skip-TestCase {
    param([Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)][string]$Reason)
    if (-not $script:CollectTestFailures) {
        throw "Test '$Name' cannot run: $Reason"
    }
    Add-TestOutcome -Name $Name -Status SKIP -Detail $Reason
    Write-Warning "SKIP: $Name – $Reason"
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [switch]$BlocksGui,
        [switch]$RequiresGuiSafety
    )
    # GUI tests can perform file operations. Do not continue them if their
    # isolation/driver contracts fail, even when other tests keep running.
    if ($script:CollectTestFailures -and $RequiresGuiSafety -and $script:GuiTestsBlocked) {
        Skip-TestCase -Name $Name -Reason 'GUI safety prerequisites failed'
        return
    }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        if ($script:CollectTestFailures) {
            Add-TestOutcome -Name $Name -Status PASS -DurationMs $watch.ElapsedMilliseconds
        }
    }
    catch {
        # Ctrl+C and explicit cancellation are not ordinary test failures.
        # Never continue potentially destructive GUI tests after cancellation.
        if ($_.Exception -is [System.Management.Automation.PipelineStoppedException] -or
            $_.Exception -is [OperationCanceledException]) { throw }
        if (-not $script:CollectTestFailures) { throw }
        $detail = $_.Exception.Message
        Add-TestOutcome -Name $Name -Status FAIL -Detail $detail -DurationMs $watch.ElapsedMilliseconds
        if ($BlocksGui) { $script:GuiTestsBlocked = $true }
        Write-Host "FAIL: $Name – $detail" -ForegroundColor Red
    }
    finally {
        $watch.Stop()
    }
}

function Complete-TestRun {
    param([Parameter(Mandatory)][string]$LogPath)
    if (-not $script:CollectTestFailures) { return }

    $results = @($script:TestOutcomes.ToArray())
    $passed = @($results | Where-Object Status -eq PASS).Count
    $failed = @($results | Where-Object Status -eq FAIL).Count
    $skipped = @($results | Where-Object Status -eq SKIP).Count
    $summaryPath = [IO.Path]::ChangeExtension($LogPath, '.results.json')
    $summary = [pscustomobject]@{
        LogPath = $LogPath
        Passed = $passed
        Failed = $failed
        Skipped = $skipped
        Results = $results
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8

    Write-Host '=== TEST-ALL ERGEBNISSE ==='
    foreach ($result in $results) {
        Write-Host ("{0,-4} {1} ({2} ms)" -f $result.Status, $result.Name, $result.DurationMs)
        if ($result.Status -ne 'PASS') {
            Write-Host "     $($result.Detail)"
        }
    }
    Write-Host "PASS: $passed | FAIL: $failed | SKIP: $skipped"
    Write-Host "Maschinenlesbarer Bericht: $summaryPath"

    if ($failed -gt 0 -or $skipped -gt 0) {
        throw "Testabnahme fehlgeschlagen: $failed Fehler, $skipped übersprungen. Siehe $summaryPath"
    }
}
