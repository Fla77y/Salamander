#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Regression: session handoff must be discoverable from the same checkout
# as its code, requirements, release gates and test-gap tracker.
# Structural checks only: no claim that written status equals actual runtime.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$required = [ordered]@{
    Requirements = 'Anforderungen.md'
    Agents = 'AGENTS.md'
    Readme = 'README.md'
    Handoff = 'docs/maintenance/Arbeitsstand-und-Uebergabe.md'
    Journal = 'docs/maintenance/Entwicklungsjournal.md'
    Backlog = 'docs/maintenance/Testluecken-und-Abnahmeplan-5.2.md'
    Gates = 'tools/release/Release-5.2-Gates.md'
}
$source = @{}
foreach ($entry in $required.GetEnumerator()) {
    $path = Join-Path $repository $entry.Value
    if (-not [IO.File]::Exists($path)) {
        throw "Required development-continuity file missing: $($entry.Value)"
    }
    $source[$entry.Key] = [IO.File]::ReadAllText($path)
    if ([string]::IsNullOrWhiteSpace($source[$entry.Key])) {
        throw "Development-continuity file empty: $($entry.Value)"
    }
}

# The original owner requirements are immutable 0–7 constraints.
foreach ($id in 0..7) {
    if ($source.Requirements -notmatch "(?m)^### An(?:foarderung|forderung) $id:") {
        throw "Required original product constraint A$id is missing."
    }
}
foreach ($requiredLink in @('Anforderungen.md',
    'Arbeitsstand-und-Uebergabe.md', 'Entwicklungsjournal.md',
    'Testluecken-und-Abnahmeplan-5.2.md')) {
    foreach ($owner in @('Agents','Readme')) {
        if (-not $source[$owner].Contains($requiredLink)) {
            throw "$owner no longer links the development handoff source: $requiredLink"
        }
    }
}
$requiredHeadings = @{
    Handoff = @('## 1. Unverzichtbare Lesereihenfolge',
                '## 3. Zuletzt tatsächlich belegte Ergebnisse',
                '## 4. Aktive Fehler und nächste konkrete Arbeit',
                'NO-GO')
    Journal = @('## Chronologie', '## Entscheidungsregeln',
                '2026-11-24', 'Chat 01', 'Chat 12')
    Backlog = @('## 11. Arbeitsreihenfolge und Meilensteine',
                'MGMT-02', 'UP-04', 'QA-03')
}
foreach ($entry in $requiredHeadings.GetEnumerator()) {
    foreach ($needle in $entry.Value) {
        if (-not $source[$entry.Key].Contains($needle)) {
            throw "$($entry.Key) lost required development context: $needle"
        }
    }
}
if ($source.Handoff -notmatch '02acf27c87ddbe509d7044e3a416c5ebf265224d' -and
    $source.Handoff -notmatch 'git rev-parse HEAD') {
    throw 'Handoff must distinguish recorded test commit from the current HEAD.'
}

Write-Host 'PASS: repository requirements, agent bootstrap, journal, handoff and central gap tracker are linked and structurally intact.'
