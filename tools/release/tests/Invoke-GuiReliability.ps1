#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Compares isolated GUI F8 runs against the same test after --test-all's prelude.
.DESCRIPTION
    Keeps one x64 binary/configuration fixed, alternates run order to reduce
    ordering bias, records each complete transcript and exit status, and checks
    for surviving Salamander processes. Does not change production binaries.
    The GUI is not fully hermetic: Windows clipboard, registry and desktop
    state are shared. A difference is evidence for further investigation, not
    proof of a specific root cause.
.EXAMPLE
    pwsh -NoProfile -File .\tools\release\tests\Invoke-GuiReliability.ps1 -Iterations 3 -Configuration Release -CaptureHangDump
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 20)][int]$Iterations = 3,
    [ValidateSet('Release', 'Debug')][string]$Configuration = 'Release',
    [switch]$CaptureHangDump,
    [string]$OutputDirectory = 'D:\Build\OpenSal\logs\gui-reliability'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) { throw 'GUI A/B comparison requires Windows.' }
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$manage = Join-Path $repository 'manage.cmd'
if (-not (Test-Path -LiteralPath $manage -PathType Leaf)) {
    throw "Management entry point not found: $manage"
}
$configurationSwitch = if ($Configuration -eq 'Debug') { '--debug' } else { '--release' }
# Reject comparisons of binaries built from different inputs or replaced
# concurrently by another build. Source HEAD alone does not identify a binary.
$binary = Join-Path (
    Join-Path 'D:\Build\OpenSal\salamander' ('{0}_x64' -f $Configuration)
) 'salamand.exe'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    throw "Build $Configuration x64 first: $binary"
}
$expectedHash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
Write-Host "Test binary SHA256 ($Configuration x64): $expectedHash"
$session = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) (
    'compare-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' +
    [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($session)
$results = [System.Collections.Generic.List[object]]::new()
$originalDumpSetting = [Environment]::GetEnvironmentVariable(
    'OPENSAL_GUI_CAPTURE_HANG_DUMP', 'Process')
$originalClipboardSetting = [Environment]::GetEnvironmentVariable(
    'OPENSAL_MANAGE_SKIP_CLIPBOARD', 'Process')
$stoppedForOrphan = $false
$scenarios = @(
    @{ Name = 'Isolated'; Options = @('--test-gui-temp-delete') },
    @{ Name = 'AfterPrelude'; Options = @('--test', '--test-plugin-exports',
        '--test-pictview', '--test-pictview-window', '--test-gui-temp-delete') }
)

try {
    # Each nested manager otherwise copies its full transcript to the global
    # clipboard, an A/B side effect absent within a single --test-all run.
    [Environment]::SetEnvironmentVariable(
        'OPENSAL_MANAGE_SKIP_CLIPBOARD', '1', 'Process')
    if ($CaptureHangDump) {
        [Environment]::SetEnvironmentVariable(
            'OPENSAL_GUI_CAPTURE_HANG_DUMP', '1', 'Process')
    }

    for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
        # Alternate AB / BA: neither scenario always benefits from running first.
        $order = if ($iteration % 2 -eq 0) { @($scenarios[1], $scenarios[0]) }
                 else { @($scenarios[0], $scenarios[1]) }
        foreach ($scenario in $order) {
            # Never terminate arbitrary user instances. Refuse to start another
            # test if any Salamander process outlived its previous runner.
            $existing = @(Get-Process salamand -ErrorAction SilentlyContinue)
            if ($existing.Count -gt 0) {
                $pids = ($existing | ForEach-Object Id) -join ','
                throw "Salamander process(es) still running ($pids). Stop comparison; do not kill unknown processes."
            }

            $currentHash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
            if ($currentHash -cne $expectedHash) {
                throw "Test binary changed during A/B comparison: $binary"
            }
            $options = @($configurationSwitch) + @($scenario.Options)
            $stem = '{0:D2}-{1}-{2}' -f $iteration, $scenario.Name, $Configuration
            $log = Join-Path $session ($stem + '.log')
            $started = [DateTime]::UtcNow
            Write-Host ("=== A/B {0} {1} x64, iteration {2}/{3} ===" -f
                $scenario.Name, $Configuration, $iteration, $Iterations)
            # Each management invocation runs in its own process; its full
            # transcript and native child failures are preserved verbatim.
            # A preconditioned run executes the full native/ABI/WIC test
            # prelude and can take minutes. Do not swallow its progress: keep
            # the exact live output visible while writing the per-run log.
            & $manage @options 2>&1 | Tee-Object -FilePath $log | Out-Host
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) {
                Write-Warning 'Management child did not report an exit code.'
                $exitCode = 1
            }
            $duration = [Math]::Round(
                ([DateTime]::UtcNow - $started).TotalSeconds, 2)
            $survivors = @(Get-Process salamand -ErrorAction SilentlyContinue)
            $orphanCount = $survivors.Count
            $logText = Get-Content -LiteralPath $log -Raw -Encoding utf8
            $startup = [regex]::Match($logText,
                'Salamander main GUI thread responds after startup readiness probe \((\d+) attempt\(s\)\)')
            $clipboard = [regex]::Match($logText,
                'Salamander GUI responsive before clipboard publication \((\d+) attempt\(s\)\)')
            $hang = [regex]::Match($logText,
                'GUI startup remained unresponsive \(phase=([^)]*)\)')
            $startupAttempts = $null
            $beforeClipboardAttempts = $null
            $hangPhase = ''
            if ($startup.Success) { $startupAttempts = [int]$startup.Groups[1].Value }
            if ($clipboard.Success) { $beforeClipboardAttempts = [int]$clipboard.Groups[1].Value }
            if ($hang.Success) { $hangPhase = $hang.Groups[1].Value }
            [void]$results.Add([pscustomobject]@{
                Iteration = $iteration
                Scenario = $scenario.Name
                Configuration = $Configuration
                ExitCode = $exitCode
                DurationSeconds = $duration
                StartupAttempts = $startupAttempts
                BeforeClipboardAttempts = $beforeClipboardAttempts
                HangPhase = $hangPhase
                SurvivingProcesses = $orphanCount
                Log = $log
            })
            Write-Host ("Result: {0}; exit={1}; elapsed={2}s; survivors={3}; log={4}" -f
                $scenario.Name, $exitCode, $duration, $orphanCount, $log)
            if ($exitCode -ne 0) {
                Write-Warning "Test case failed; full log: $log"
                Get-Content -LiteralPath $log -Tail 18 | ForEach-Object { Write-Host $_ }
            }
            if ($orphanCount -gt 0) {
                Write-Warning 'Not continuing: an existing Salamander process would invalidate subsequent comparisons.'
                $stoppedForOrphan = $true
                break
            }
        }
        if ($stoppedForOrphan) { break }
    }
}
finally {
    # Restore every inherited setting even when a child test fails.
    [Environment]::SetEnvironmentVariable(
        'OPENSAL_MANAGE_SKIP_CLIPBOARD', $originalClipboardSetting, 'Process')
    if ($CaptureHangDump) {
        [Environment]::SetEnvironmentVariable(
            'OPENSAL_GUI_CAPTURE_HANG_DUMP', $originalDumpSetting, 'Process')
    }
    $summary = Join-Path $session 'Summary.csv'
    $results | Export-Csv -LiteralPath $summary -NoTypeInformation -Encoding utf8
    Write-Host "=== GUI A/B Summary: $summary ==="
    $results | Format-Table -Property @(
        'Iteration', 'Scenario', 'Configuration', 'ExitCode',
        'StartupAttempts', 'BeforeClipboardAttempts', 'HangPhase',
        'DurationSeconds', 'SurvivingProcesses'
    ) -AutoSize | Out-String | Write-Host
}

# No "green" result if either test variant failed or process cleanup failed.
if ($stoppedForOrphan -or @($results | Where-Object {
        $_.ExitCode -ne 0 -or $_.SurvivingProcesses -ne 0
    }).Count -gt 0) {
    Exit 1
}
Write-Host 'PASS: all isolated and preconditioned GUI comparison runs completed.'
