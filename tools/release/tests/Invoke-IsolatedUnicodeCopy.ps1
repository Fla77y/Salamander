#requires -Version 7.4
[CmdletBinding()]
param([ValidateSet('Release', 'Debug')][string]$Configuration = 'Release')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
. (Join-Path $PSScriptRoot '..\Package-Helpers.ps1')
$output = [IO.Path]::GetFullPath((Join-Path $repository '.Build\isolated-unicode-copy'))
# Reject pre-existing junctions in every output ancestor below this checkout.
$parent = $output
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
    $env:TEMP = Join-Path $output 'temp'
    $env:TMP = $env:TEMP
    [void][IO.Directory]::CreateDirectory($env:TEMP)
    $msbuild = Join-Path (Get-VisualStudio2026) 'MSBuild\Current\Bin\amd64\MSBuild.exe'
    $project = Join-Path $repository 'src\vcxproj\salamand.vcxproj'
    $arguments = @($project, '/nologo', '/nr:false', '/m:1',
        '/p:Platform=x64', "/p:Configuration=$Configuration", '/p:PreferredToolArchitecture=x64',
        '/p:OpenSalamanderIsolatedGuiTest=true', "/p:UserRootDir=$output\user-props\")
    # Verify actual MSBuild output paths before compiling any target.
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
    & $msbuild @arguments /t:Build /v:minimal
    if ($LASTEXITCODE -ne 0) { throw "Isolated GUI build failed: $Configuration x64" }
    $binary = Join-Path $output "salamander\${Configuration}_x64\salamand.exe"
    foreach ($case in @('Copy', 'Cancel', 'Collision', 'LockedSource')) {
        Write-Host "=== ISOLATED LARGE UNICODE COPY: $Configuration x64 $case ==="
        & pwsh -Sta -NoProfile -File (Join-Path $PSScriptRoot 'Test-SalamanderGui-LongPaths.ps1') `
            -SalamanderExe $binary -IsolatedConfiguration -LargeUnicodeCopyOnly -LargeUnicodeCopyCase $case
        if ($LASTEXITCODE -ne 0) { throw "Large Unicode GUI case failed: $Configuration x64 $case" }
    }
}
finally {
    $env:OPENSAL_BUILD_DIR = $previousBuild
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}
