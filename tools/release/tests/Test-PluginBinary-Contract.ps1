#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Read-only ABI smoke test for the priority x64 plug-ins, including PictView.
.DESCRIPTION
    Inspects PE headers and export tables with Visual Studio dumpbin.
    Never loads or executes a plug-in DLL. Successful checks do NOT prove
    plug-in menu operations or Unicode/long-path compatibility.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDirectory,
    [Parameter(Mandatory)][string]$VisualStudioRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This integration test requires Windows.' }
. (Join-Path $PSScriptRoot '..\Plugin-Export-Parser.ps1')
. (Join-Path $PSScriptRoot '..\Plugin-CoverageInventory.ps1')

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$toolchainRoot = Join-Path $VisualStudioRoot 'VC\Tools\MSVC'
if (-not (Test-Path -LiteralPath $toolchainRoot -PathType Container)) {
    throw "Missing Visual Studio C++ toolchains: $toolchainRoot"
}

$dumpbin = Get-ChildItem -LiteralPath $toolchainRoot -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'bin\Hostx64\x64\dumpbin.exe' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($dumpbin)) {
    throw "dumpbin.exe not found beneath $toolchainRoot"
}

$requiredExports = @('SalamanderPluginEntry', 'SalamanderPluginGetReqVer')
$requiredPluginNames = @('7zip', 'checksum', 'filecomp', 'renamer', 'pictview')
$inventory = @(Get-SalamanderPluginInventory -Repository $repository -BuiltDirectory $BuildDirectory)
$builtPlugins = @($inventory | Where-Object { $_.BuiltModule -ceq 'PRESENT' })
if ($builtPlugins.Count -eq 0) {
    throw 'No built SPL binaries available for ABI verification.'
}
# Preserve the existing five-module mandatory ABI contract: a missing
# required module is a hard failure, never an untested/optional skip.
foreach ($required in $requiredPluginNames) {
    if (@($builtPlugins | Where-Object { $_.Plugin -ieq $required }).Count -eq 0) {
        throw "Missing required built plug-in binary: $required"
    }
}
foreach ($plugin in $builtPlugins) {
    # Audit all actually built SPLs, not only the five originally selected.
    # A binary without a corresponding Solution plug-in is untracked and
    # must not be silently treated as an approved build artifact.
    $name = [string]$plugin.Plugin
    if (-not $plugin.SolutionProject) {
        throw "Built plug-in lacks a Solution declaration: $name"
    }
    # DiskMap keeps its original module definition under DiskMapPlugin.
    $declaration = if ($name -ieq 'diskmap') {
        Join-Path $repository 'src\plugins\diskmap\DiskMapPlugin\DiskMapPlugin.def'
    } else {
        Join-Path $repository "src\plugins\$name\$name.def"
    }
    $binary = $plugin.BuiltPath
    if (-not (Test-Path -LiteralPath $declaration -PathType Leaf)) {
        throw "Missing plug-in export definition: $declaration"
    }
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
        throw "Missing built plug-in binary: $binary"
    }
    $source = Get-Content -LiteralPath $declaration -Raw -Encoding UTF8

    # Act: dumpbin only reads the image; it cannot run DllMain or any
    # SalamanderPluginEntry callback. Preserve its real native exit code.
    $dump = @(& $dumpbin /nologo /headers /exports $binary 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "dumpbin failed for $binary (exit $LASTEXITCODE)"
    }
    $report = $dump -join [Environment]::NewLine

    # Assert: require x64 COFF machine and the two exported ABI entry points.
    if ($report -notmatch '(?im)^\s*8664\s+machine\b') {
        throw "Plug-in is not a supported x64 PE image: $binary"
    }
    foreach ($symbol in $requiredExports) {
        if (-not (Test-ModuleDefinitionExport -Definition $source -Name $symbol)) {
            throw "Export $symbol missing in $declaration"
        }
        if (-not (Test-PeNamedExport -Report $report -Name $symbol)) {
            # When the ABI is really absent, show the actual dumpbin rows.
            # This also diagnoses unforeseen linker output formats without
            # guessing that a plug-in is broken.
            $nearby = @($dump | Where-Object {
                $_ -match '(?i)ordinal\s+hint\s+RVA|SalamanderPlugin'
            } | Select-Object -First 12)
            if ($nearby.Count -eq 0) {
                $nearby = @($dump | Select-Object -Last 12)
            }
            $diagnostic = "No exact public PE export '$symbol' in $binary. dumpbin excerpt:" +
                          [Environment]::NewLine + ($nearby -join [Environment]::NewLine)
            throw $diagnostic
        }
    }
    Write-Host "PASS: $name x64 plug-in binary exports required Salamander SDK entry points"
}
Write-Host "PASS: $($builtPlugins.Count) built x64 plug-in PE export tables inspected; five mandatory modules enforced."
