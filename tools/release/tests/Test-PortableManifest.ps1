#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Verify every extracted portable-package file against its internal manifest.
.DESCRIPTION
    Refuses missing, changed, duplicate, unlisted or out-of-root entries.
    This verifier reads files only; it does not execute the distribution.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExtractedDirectory,
      [switch]$RequireReleasePayload)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath($ExtractedDirectory)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Portable extraction directory does not exist: $root"
}
if ($RequireReleasePayload) {
    . (Join-Path $PSScriptRoot '..\Package-Helpers.ps1')
    Assert-ReleasePayload -Root $root -ManifestState Present
}
$manifestPath = Join-Path $root 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Portable package has no internal SHA256SUMS.txt.'
}

$actual = @{}
$allEntries = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
foreach ($entry in $allEntries) {
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Portable package contains a reparse point.'
    }
    if ($entry.PSIsContainer) { continue }
    $relative = [IO.Path]::GetRelativePath($root, $entry.FullName).Replace('\', '/')
    if ($actual.ContainsKey($relative)) {
        throw "Duplicate portable file path: $relative"
    }
    $actual.Add($relative, $entry.FullName)
}

$expected = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$lines = @([IO.File]::ReadAllLines($manifestPath))
if ($lines.Count -eq 0) {
    throw 'Portable SHA256SUMS.txt is empty.'
}
foreach ($line in $lines) {
    $match = [regex]::Match($line, '^(?<hash>[0-9a-f]{64}) \*(?<name>.+)$')
    if (-not $match.Success) { throw 'Malformed portable SHA256SUMS entry.' }
    $name = $match.Groups['name'].Value
    # A package manifest must never escape the package root, even if the
    # archive were ever supplied by an untrusted producer.
    if ($name.Contains('\') -or $name.StartsWith('/') -or
        $name.Contains(':') -or
        @($name.Split('/') | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0 -or
        $name -ceq 'SHA256SUMS.txt' -or -not $expected.Add($name)) {
        throw "Unsafe or duplicate portable manifest path: $name"
    }
    if (-not $actual.ContainsKey($name)) {
        throw "Portable manifest references a missing file: $name"
    }
    $hash = (Get-FileHash -LiteralPath $actual[$name] -Algorithm SHA256).Hash
    if (-not $hash.Equals($match.Groups['hash'].Value, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Portable package content checksum differs: $name"
    }
}
if (-not $actual.ContainsKey('SHA256SUMS.txt') -or
    $actual.Count -ne ($expected.Count + 1)) {
    $extra = @($actual.Keys | Where-Object { $_ -cne 'SHA256SUMS.txt' -and -not $expected.Contains($_) })
    throw "Portable package contains unlisted files: $($extra -join '; ')"
}
Write-Host "PASS: verified $($expected.Count) portable-package files against internal SHA256 manifest."
