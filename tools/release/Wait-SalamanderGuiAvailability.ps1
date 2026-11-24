#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Wait only for pre-existing Salamander instances before launching an
# isolated GUI test. Existing per-test safety checks must still detect
# a leaked test process or a new foreign instance between cases.
function Test-RequiresGuiIdleGate {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.HashSet[string]]$RequestedSet
    )
    foreach ($option in $RequestedSet) {
        if ($option.StartsWith('--test-gui', [StringComparison]::OrdinalIgnoreCase) -or
            $option -in @('--test-all', '--test-pictview-window',
                          '--test-pictview-host', '--test-plugin-load',
                          '--test-recycle-restore', '--diagnose-gui')) {
            return $true
        }
    }
    return $false
}

function Wait-ForSalamanderGuiAvailability {
    [CmdletBinding()]
    param(
        # Optional test seams: never replace these defaults in normal use.
        [scriptblock]$GetRunningProcessIds = {
            Get-Process -Name 'salamand' -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Id
        },
        [scriptblock]$Pause = {
            param([int]$Milliseconds)
            Start-Sleep -Milliseconds $Milliseconds
        },
        [ValidateRange(100,60000)][int]$PollMilliseconds = 1000
    )

    $announced = $false
    while ($true) {
        # No process is terminated, signalled, activated, or given input.
        # Only observe the process table and wait for a normal user exit.
        $runningIds = @(
            & $GetRunningProcessIds | Where-Object { $null -ne $_ }
        )
        if ($runningIds.Count -eq 0) {
            if ($announced) {
                Write-Host 'Alle Salamander-Instanzen sind geschlossen. GUI-Tests werden automatisch fortgesetzt.'
            }
            return
        }
        if (-not $announced) {
            $message = ('Salamander läuft noch (PID: {0}). Bitte alle Salamander-Fenster ' +
                        'regulär schließen. Das Skript wartet und setzt die GUI-Tests ' +
                        'anschließend automatisch fort; mit Strg+C abbrechen.')
            Write-Warning ($message -f ($runningIds -join ', '))
            $announced = $true
        }
        # This remains interruptible through Ctrl+C or a propagated cancellation.
        & $Pause $PollMilliseconds
    }
}
