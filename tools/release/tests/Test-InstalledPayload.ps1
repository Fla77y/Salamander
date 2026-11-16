#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Verify that the Inno-installed Release payload matches the portable Release.
.DESCRIPTION
    Read-only. Compares the full relative file set and SHA-256 of every file.
    Permits only the paired Inno Setup uninstaller files in addition to the
    portable payload; blocks any other injected or omitted installation file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableDirectory,
    [Parameter(Mandatory)][string]$InstalledDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$portable = [IO.Path]::GetFullPath($PortableDirectory)
$installed = [IO.Path]::GetFullPath($InstalledDirectory)
foreach ($directory in @($portable, $installed)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Payload comparison directory is missing: $directory"
    }
}

function Get-PayloadFiles {
    <#
    .SYNOPSIS
        Build a case-insensitive relative-file inventory, refusing reparse points.
    #>
    param([Parameter(Mandatory)][string]$Root)

    $files = [System.Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in (Get-ChildItem -LiteralPath $Root -Recurse -Force)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Installed payload contains a reparse point.'
        }
        if ($entry.PSIsContainer) { continue }
        $relative = [IO.Path]::GetRelativePath($Root, $entry.FullName).Replace('\', '/')
        if (-not $files.TryAdd($relative, $entry.FullName)) {
            throw "Duplicate case-insensitive payload path: $relative"
        }
    }
    return ,$files
}

# Arrange: enumerate the complete portable and installed inventories.
$expected = Get-PayloadFiles -Root $portable
$actual = Get-PayloadFiles -Root $installed
if ($expected.Count -eq 0) {
    throw 'Portable release payload is empty.'
}

# Act / Assert: every installed application file must match the portable
# version byte-for-byte, regardless of its extension or relative path.
foreach ($relative in $expected.Keys) {
    if (-not $actual.ContainsKey($relative)) {
        throw "Installer omitted portable payload file: $relative"
    }
    $sourceHash = (Get-FileHash -LiteralPath $expected[$relative] -Algorithm SHA256).Hash
    $installedHash = (Get-FileHash -LiteralPath $actual[$relative] -Algorithm SHA256).Hash
    if (-not $sourceHash.Equals($installedHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Installer content differs from portable package: $relative"
    }
}

$extra = @($actual.Keys | Where-Object { -not $expected.ContainsKey($_) })
if ($extra.Count -ne 2) {
    throw "Expected only Inno Setup uninstall metadata as extra installed files: $($extra -join '; ')"
}
$uninstallExe = @($extra | Where-Object { $_ -match '^unins[0-9]{3}\.exe$' })
if ($uninstallExe.Count -ne 1) {
    throw 'Installer did not create exactly one expected uninstaller executable.'
}
$pairedData = [IO.Path]::ChangeExtension($uninstallExe[0], '.dat')
if ($extra -notcontains $pairedData) {
    throw 'Installer uninstaller metadata does not match its executable.'
}
Write-Host "PASS: all $($expected.Count) installed payload files match portable Release SHA-256 hashes."
