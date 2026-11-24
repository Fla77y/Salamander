#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Release','Debug')][string]$Configuration,
    [Parameter(Mandatory)][ValidateSet('isolated-unicode-copy','isolated-legacy-find','isolated-long-paths')][string]$OutputName
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
. (Join-Path $PSScriptRoot '..\Package-Helpers.ps1')
$output = [IO.Path]::GetFullPath((Join-Path $repository ".Build\$OutputName"))
$buildTemp = Join-Path $output 'temp'
# The project, its language module and build temp all stay inside this checkout.
$parent = $buildTemp
while ($parent -ne $repository) {
    if (-not $parent.StartsWith($repository + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe isolated build output: $parent"
    }
    if ((Test-Path -LiteralPath $parent) -and
        (Get-Item -LiteralPath $parent -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing isolated build through a reparse point: $parent"
    }
    $parent = Split-Path -Parent $parent
}
$previousBuild = $env:OPENSAL_BUILD_DIR
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
try {
    $env:OPENSAL_BUILD_DIR = $output + '\'
    $env:TEMP = $buildTemp
    $env:TMP = $buildTemp
    [void][IO.Directory]::CreateDirectory($buildTemp)
    $msbuild = Join-Path (Get-VisualStudio2026) 'MSBuild\Current\Bin\amd64\MSBuild.exe'
    $project = Join-Path $repository 'src\vcxproj\salamand.vcxproj'
    $arguments = @($project, '/nologo', '/nr:false', '/m:1',
        '/p:Platform=x64', "/p:Configuration=$Configuration", '/p:PreferredToolArchitecture=x64',
        '/p:OpenSalamanderIsolatedGuiTest=true', "/p:UserRootDir=$output\user-props\")
    $properties = @(& $msbuild @arguments /getProperty:OutDir,IntDir)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect isolated MSBuild output paths.' }
    $evaluated = ($properties -join "`n") | ConvertFrom-Json
    foreach ($path in @($evaluated.Properties.OutDir, $evaluated.Properties.IntDir)) {
        $absolute = [IO.Path]::GetFullPath($path)
        if (-not $absolute.StartsWith($output + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "MSBuild output escapes isolated root: $absolute"
        }
        Write-Host "Verified isolated output: $absolute"
    }
    & $msbuild @arguments /t:Build /v:minimal | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Isolated GUI build failed: $Configuration x64" }
    return Join-Path $evaluated.Properties.OutDir 'salamand.exe'
}
finally {
    $env:OPENSAL_BUILD_DIR = $previousBuild
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}
