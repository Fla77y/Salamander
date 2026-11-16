#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Verify checksums of the two public Open Salamander Release x64 artifacts.
.DESCRIPTION
    Requires exactly one digest for the portable archive and the installer.
    Refuses Debug artifacts, unexpected names, duplicates, missing files
    and mismatched checksums. Does not execute the downloaded binaries.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DistributionDirectory,
    [switch]$RequirePublicOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$directory = [IO.Path]::GetFullPath($DistributionDirectory)
$manifest = Join-Path $directory 'SHA256SUMS-Release.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Release checksums manifest is missing: $manifest"
}

$expected = @('OpenSalamander-Release-x64.7z',
              'OpenSalamander-Release-x64-Setup.exe')
# The internal build directory may contain Debug packages. Only a downloaded
# public artifact is constrained to exactly these three top-level files.
if ($RequirePublicOnly) {
    $allowed = @($expected) + @('SHA256SUMS-Release.txt')
    $entries = @(Get-ChildItem -LiteralPath $directory -Force)
    if ($entries.Count -ne $allowed.Count -or
        @($entries | Where-Object {
            -not $_.PSIsContainer -and $_.Name -cnotin $allowed -or $_.PSIsContainer
        }).Count -gt 0) {
        throw 'Public artifact contains unexpected, missing, or non-file entries.'
    }
}

$lines = @(Get-Content -LiteralPath $manifest)
if ($lines.Count -ne $expected.Count) {
    throw "Release checksums must list exactly $($expected.Count) public artifacts."
}

$seen = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($line in $lines) {
    $entry = [regex]::Match(
        $line, '^(?<digest>[0-9a-f]{64}) \*(?<name>[A-Za-z0-9_.-]+)$')
    if (-not $entry.Success) {
        throw "Malformed SHA256SUMS-Release.txt entry: $line"
    }

    $name = $entry.Groups['name'].Value
    if ($name -cnotin $expected -or -not $seen.Add($name)) {
        throw "Unexpected or duplicate public Release checksum: $name"
    }
    $artifactPath = Join-Path $directory $name
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "Release artifact referenced by checksum is missing: $artifactPath"
    }
    $actual = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
    if (-not $actual.Equals($entry.Groups['digest'].Value,
                            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release artifact SHA256 mismatch: $name"
    }
}
if ($seen.Count -ne $expected.Count) {
    throw 'Release checksums are missing a required public artifact.'
}
Write-Host 'PASS: release-only SHA256 manifest matches the portable archive and installer.'
