#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Read-only ABI smoke test for every built x64 plug-in, including PictView.
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
. (Join-Path $PSScriptRoot '..\Plugin-Binary-Inventory.ps1')

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
# Keep the five mandatory built-in modules as hard requirements. In
# addition, inspect every other SPL actually built by the solution.
$requiredPlugins = @('7zip', 'checksum', 'filecomp', 'renamer', 'pictview')
$builtNames = @(Get-BuiltPluginNames -BuildDirectory $BuildDirectory)
$pluginNames = @($requiredPlugins + $builtNames | Sort-Object -Unique)
foreach ($name in $pluginNames) {
    # Arrange: both the source export declaration and the built plug-in
    # must exist; missing binaries are failures, never optional skips.
    $declaration = Join-Path $repository "src\plugins\$name\$name.def"
    $binary = Join-Path $BuildDirectory "plugins\$name\$name.spl"
    # Source .def declarations are mandatory for the established five. Other
    # built modules can use a different file name/location (DiskMapPlugin.def)
    # or linker directives; verify their actual PE export table instead.
    if ($name -in $requiredPlugins -and
        -not (Test-Path -LiteralPath $declaration -PathType Leaf)) {
        throw "Missing required plug-in export definition: $declaration"
    }
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
        throw "Missing built plug-in binary: $binary"
    }
    $source = if ($name -in $requiredPlugins) {
        Get-Content -LiteralPath $declaration -Raw -Encoding UTF8
    } else { $null }

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
        if ($name -in $requiredPlugins -and -not [regex]::IsMatch($source,
                "(?im)^\s*EXPORTS\s+$([regex]::Escape($symbol))\s*$")) {
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
Write-Host "PASS: all $($pluginNames.Count) discovered/required x64 plug-in PE/SDK export contracts inspected without loading plug-in code."
