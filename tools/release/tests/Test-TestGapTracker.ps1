#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Protect the canonical A0-A7 coverage plan against accidental deletion and
# unsupported PASS claims. Source check only; it does not execute tests.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$plan = Get-Content -LiteralPath (Join-Path $repository 'docs\maintenance\Testluecken-und-Abnahmeplan-5.2.md') -Raw
$baseline = Get-Content -LiteralPath (Join-Path $repository 'tools\release\test-gap-ids-baseline.json') -Raw | ConvertFrom-Json

if ($baseline.schemaVersion -ne 1) {
    throw 'Unsupported test-gap ID baseline.'
}

function Assert-TrackedGaps {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string[]]$RequiredIds
    )

    $pattern = '(?m)^### \[(?<check>[ xX])\] (?<id>[A-Z0-9]+-\d+) – .+$'
    $matches = [regex]::Matches($Text, $pattern)
    $seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    foreach ($match in $matches) {
        $id = $match.Groups['id'].Value
        if (-not $seen.Add($id)) {
            throw "Duplicate test-gap ID: $id"
        }

        # A checkbox is only an approved PASS if its own section contains
        # a real source SHA, executed command and log reference.
        if ($match.Groups['check'].Value -in @('x','X')) {
            $start = $match.Index
            $next = [regex]::new('(?m)^#{1,3}\s').Match(
                $Text, $start + $match.Length)
            $end = if ($next.Success) { $next.Index } else { $Text.Length }
            $section = $Text.Substring($start, $end - $start)
            if ($section -notmatch '(?m)^-\s+\*\*Nachweis:\*\*\s+SHA=[0-9a-f]{40};\s+Test=[^;]+;\s+Log=[^;\r\n]+') {
                throw "Checked test-gap $id lacks exact SHA / executed command / log evidence."
            }
        }
    }
    foreach ($required in $RequiredIds) {
        if (-not $seen.Contains($required)) {
            throw "Missing mandatory test-gap ID: $required"
        }
    }
    if ($seen.Count -lt $RequiredIds.Count) {
        throw 'Too few unique test-gap IDs.'
    }
    return $seen.Count
}

$count = Assert-TrackedGaps -Text $plan -RequiredIds $baseline.requiredGapIds
$agents = Get-Content -LiteralPath (Join-Path $repository 'AGENTS.md') -Raw
$readme = Get-Content -LiteralPath (Join-Path $repository 'README.md') -Raw
$planRelative = 'docs/maintenance/Testluecken-und-Abnahmeplan-5.2.md'
if (-not $agents.Contains($planRelative) -or -not $readme.Contains($planRelative)) {
    throw 'The canonical gap tracker must remain linked from AGENTS.md and README.md.'
}

# Negatives: the contract itself must reject removal and unsupported PASS.
$withoutOne = $plan.Replace('### [ ] A0-01 –', '### [ ] BROKEN –')
$blocked = $false
try { $null = Assert-TrackedGaps -Text $withoutOne -RequiredIds $baseline.requiredGapIds }
catch {
    if ($_.Exception.Message -notmatch 'Missing mandatory test-gap ID: A0-01') { throw }
    $blocked = $true
}
if (-not $blocked) { throw 'Deleting A0-01 did not make the tracker contract fail.' }

$falselyChecked = $plan.Replace('### [ ] A0-01 –', '### [x] A0-01 –')
$blocked = $false
try { $null = Assert-TrackedGaps -Text $falselyChecked -RequiredIds $baseline.requiredGapIds }
catch {
    if ($_.Exception.Message -notmatch 'A0-01 lacks exact SHA') { throw }
    $blocked = $true
}
if (-not $blocked) { throw 'Marking A0-01 PASS without an execution log was accepted.' }

Write-Host "PASS: $count stable A0-A7 test gaps retained; unsupported closure and missing IDs rejected."
