#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
    Verify WER-enabled core builds in fresh isolated VS2026 output directories.
.DESCRIPTION
    Builds Debug Win32 and Release x64 by default. -AllConfigurations also
    builds Debug x64 and Release Win32. Never launches the GUI or changes WER
    registry settings. Instrumented EXEs are private GUI test binaries only,
    never production release artifacts.
#>
[CmdletBinding()]
param([switch]$AllConfigurations, [string]$MSBuildPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')).TrimEnd('\')
. (Join-Path $PSScriptRoot '..\Package-Helpers.ps1')
$buildRoot = [IO.Path]::GetFullPath(
    (Join-Path $repository ('.Build\wer-build-' + [guid]::NewGuid().ToString('N'))))

# Never reuse developer outputs or traverse a junction/reparse point.
$ancestor = $buildRoot
while (-not $ancestor.Equals($repository, [StringComparison]::OrdinalIgnoreCase)) {
    if (-not $ancestor.StartsWith($repository + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Build directory escapes the repository: $ancestor"
    }
    if ((Test-Path -LiteralPath $ancestor) -and
        (Get-Item -LiteralPath $ancestor -Force).Attributes.HasFlag(
            [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing build through a reparse point: $ancestor"
    }
    $ancestor = Split-Path -Parent $ancestor
}

$project = Join-Path $repository 'src\vcxproj\salamand.vcxproj'
$msbuildRelative = 'MSBuild\Current\Bin\amd64\MSBuild.exe'

# vswhere can miss an otherwise usable VS 2026 installation when its MSBuild
# component metadata is incomplete. Prefer the already initialized VS
# Developer PowerShell environment, but validate the actual executable.
if (-not [string]::IsNullOrWhiteSpace($MSBuildPath)) {
    $msbuild = [IO.Path]::GetFullPath($MSBuildPath)
    $source = 'explicit -MSBuildPath'
}
elseif (-not [string]::IsNullOrWhiteSpace($env:VSINSTALLDIR) -and
        (Test-Path -LiteralPath (Join-Path $env:VSINSTALLDIR $msbuildRelative) -PathType Leaf)) {
    $msbuild = Join-Path $env:VSINSTALLDIR $msbuildRelative
    $source = 'VSINSTALLDIR (Developer PowerShell)'
}
else {
    $msbuild = Join-Path (Get-VisualStudio2026) $msbuildRelative
    $source = 'vswhere'
}

if (-not (Test-Path -LiteralPath $msbuild -PathType Leaf)) {
    throw "MSBuild executable not found ($source): $msbuild"
}
$msbuild = (Resolve-Path -LiteralPath $msbuild).ProviderPath
$version = [Diagnostics.FileVersionInfo]::GetVersionInfo($msbuild).FileMajorPart
if ($version -ne 18) {
    throw "Expected Visual Studio 2026 MSBuild major version 18; found $version at $msbuild"
}
Write-Host "Verified VS2026 MSBuild ($source): $msbuild"

$variants = @(
    @{ Configuration = 'Debug'; Platform = 'Win32'; Output = 'Debug_x86' },
    @{ Configuration = 'Release'; Platform = 'x64'; Output = 'Release_x64' }
)
if ($AllConfigurations) {
    $variants += @(
        @{ Configuration = 'Debug'; Platform = 'x64'; Output = 'Debug_x64' },
        @{ Configuration = 'Release'; Platform = 'Win32'; Output = 'Release_x86' }
    )
}

$previousBuild = $env:OPENSAL_BUILD_DIR
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
try {
    $env:OPENSAL_BUILD_DIR = $buildRoot + '\'
    $env:TEMP = Join-Path $buildRoot 'temp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null

    Write-Host "Isolated build root: $buildRoot"
    Write-Host "Git commit: $((& git -C $repository rev-parse --short HEAD) -join '')"
    foreach ($variant in $variants) {
        $configuration = $variant.Configuration
        $platform = $variant.Platform
        $expectedBinary = Join-Path $buildRoot (
            'salamander\' + $variant.Output + '\salamand.exe')
        $arguments = @(
            $project, '/nologo', '/nr:false', '/m:1',
            "/p:Configuration=$configuration", "/p:Platform=$platform",
            '/p:PreferredToolArchitecture=x64',
            '/p:OpenSalamanderIsolatedGuiTest=true',
            "/p:UserRootDir=$buildRoot\user-props\"
        )

        Write-Host "=== WER BUILD: $configuration $platform ==="
        $propertyOutput = @(& $msbuild @arguments /getProperty:OutDir,IntDir)
        if ($LASTEXITCODE -ne 0) {
            throw "MSBuild property evaluation failed: $configuration $platform"
        }
        $properties = ($propertyOutput -join [Environment]::NewLine) | ConvertFrom-Json
        foreach ($name in @('OutDir', 'IntDir')) {
            $value = $properties.Properties.$name
            if ([string]::IsNullOrWhiteSpace($value)) {
                throw "Missing MSBuild property: $name"
            }
            $actual = [IO.Path]::GetFullPath($value)
            if (-not $actual.StartsWith($buildRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing external MSBuild $name output: $actual"
            }
            Write-Host "Verified $name : $actual"
        }

        & $msbuild @arguments /t:Build /v:minimal
        if ($LASTEXITCODE -ne 0) {
            throw "WER build failed: $configuration $platform (exit code $LASTEXITCODE)"
        }
        if (-not (Test-Path -LiteralPath $expectedBinary -PathType Leaf)) {
            throw "Built executable not found: $expectedBinary"
        }
        Write-Host "PASS: $configuration $platform : $expectedBinary"
        Write-Host "SHA256: $((Get-FileHash -LiteralPath $expectedBinary -Algorithm SHA256).Hash)"
    }
    Write-Host 'PASS: all requested WER-enabled core builds completed.'
}
finally {
    $env:OPENSAL_BUILD_DIR = $previousBuild
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}
