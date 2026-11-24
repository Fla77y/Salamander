#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
# Contract for waiting on user-owned Salamander processes before GUI tests.
# No real Salamander instance is launched, touched or terminated by this test.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Wait-SalamanderGuiAvailability.ps1')

function New-RequestedOptions {
    param([string[]]$Options)
    $set = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($option in $Options) { [void]$set.Add($option) }
    return ,$set
}

foreach ($option in @('--test-all','--test-gui-unicode-parent',
                      '--test-gui-legacy-find','--test-gui-manual',
                      '--test-pictview-window','--test-pictview-host',
                      '--test-recycle-restore','--test-plugin-load',
                      '--diagnose-gui')) {
    if (-not (Test-RequiresGuiIdleGate -RequestedSet (New-RequestedOptions @($option)))) {
        throw "The GUI safety gate must apply to $option."
    }
}
foreach ($option in @('--build-delta','--test','--setup','--run','--test-pictview')) {
    if (Test-RequiresGuiIdleGate -RequestedSet (New-RequestedOptions @($option))) {
        throw "Non-GUI action $option must never wait for Salamander."
    }
}

$script:lookups = 0
$script:waits = 0
$probe = {
    $script:lookups++
    if ($script:lookups -le 2) { 3123 }
}
$pause = {
    param([int]$Milliseconds)
    if ($Milliseconds -ne 1000) { throw 'Unexpected polling interval.' }
    $script:waits++
}
# Closing the last instance must automatically resume, without a keypress.
$warnings = @()
Wait-ForSalamanderGuiAvailability -GetRunningProcessIds $probe -Pause $pause -WarningVariable warnings
if ($script:lookups -ne 3 -or $script:waits -ne 2 -or $warnings.Count -ne 1 -or
    $warnings[0].Message -notmatch '3123' -or
    $warnings[0].Message -notmatch 'automatisch') {
    throw 'GUI wait did not warn once and continue after the last process exited.'
}

$script:lookups = 0
$script:waits = 0
Wait-ForSalamanderGuiAvailability -GetRunningProcessIds { $script:lookups++ } -Pause { $script:waits++ }
if ($script:lookups -ne 1 -or $script:waits -ne 0) {
    throw 'Idle GUI preflight must never pause.'
}

$script:lookups = 0
$script:waits = 0
$cancelled = $false
try {
    Wait-ForSalamanderGuiAvailability -GetRunningProcessIds { $script:lookups++; 4124 } -Pause {
        $script:waits++
        throw [OperationCanceledException]::new('intentional cancel')
    } 3>$null
}
catch [OperationCanceledException] { $cancelled = $true }
if (-not $cancelled -or $script:lookups -ne 1 -or $script:waits -ne 1) {
    throw 'Explicit cancellation must propagate immediately; never swallow it.'
}

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$manager = [IO.File]::ReadAllText((Join-Path $repository 'tools\Manage-Salamander.ps1'))
$pos = $manager.IndexOf('        if (Test-RequiresGuiIdleGate -RequestedSet $requestedSet)', [StringComparison]::Ordinal)
$nonGui = $manager.IndexOf("if (" + '$requestedSet' + ".Contains('--test')) { Run-Tests }", [StringComparison]::Ordinal)
$nextGui = $manager.IndexOf("if (" + '$requestedSet' + ".Contains('--test-clipboard-snapshot'))", [StringComparison]::Ordinal)
if ($pos -lt 0 -or $nonGui -lt 0 -or $nextGui -lt 0 -or
    $nonGui -gt $pos -or $nextGui -lt $pos -or
    $manager.IndexOf('Wait-ForSalamanderGuiAvailability', $pos, [StringComparison]::Ordinal) -lt $pos -or
    -not $manager.Contains('$script:GuiTestsBlocked')) {
    throw 'Manager must wait once after non-GUI tests and before GUI-sensitive steps.'
}
Write-Host 'PASS: user-owned Salamander GUI wait warns once, resumes automatically, preserves Ctrl+C and non-GUI behavior.'
