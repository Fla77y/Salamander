#requires -Version 7.4
<#
.SYNOPSIS
    Update, rebuild, compile HTML help, validate, and package Open Salamander.
.DESCRIPTION
    Creates Debug and Release x64 portable 7z archives and Inno Setup installers.
    The Debug artifacts contain non-redistributable Microsoft debug runtimes and
    are exclusively for testing on computers owned by the developer.
    Full clean-machine compatibility must be validated in a clean Windows 11 VM.
.EXAMPLE
    pwsh -File .\tools\release\Update-Build-Test-Package.ps1
.EXAMPLE
    pwsh -File .\tools\release\Update-Build-Test-Package.ps1 -SkipUpdate -SkipInstaller
#>
[CmdletBinding()]
param(
    [string]$BuildRoot = 'D:\Build\OpenSal',
    [switch]$SkipUpdate,
    [switch]$SkipInstaller,
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'Package-Helpers.ps1')

$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).ProviderPath
$solution = Join-Path $repository 'src\vcxproj\salamand.sln'
$buildRootFull = [IO.Path]::GetFullPath($BuildRoot)
$env:OPENSAL_BUILD_DIR = $buildRootFull.TrimEnd('\') + '\'
$artifactDir = Join-Path $buildRootFull 'dist'
$stageRoot = Join-Path $buildRootFull 'package-stage'
$variantPaths = @{
    Debug = Join-Path $buildRootFull 'salamander\Debug_x64'
    Release = Join-Path $buildRootFull 'salamander\Release_x64'
}

if ($buildRootFull.TrimEnd('\').StartsWith($repository + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BuildRoot must be outside the Git repository to keep updates safe.'
}

if (-not (Test-Path -LiteralPath $solution -PathType Leaf)) {
    throw "Solution does not exist: $solution"
}

if (-not $SkipUpdate) {
    Write-Host 'Checking Git working tree and updating current branch...'
    $dirty = @(& git -C $repository status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) { throw 'git status failed.' }
    if ($dirty.Count -gt 0) { throw "Working tree is not clean. Commit or stash changes, or run with -SkipUpdate. $($dirty -join '; ')" }
    $currentBranch = (& git -C $repository branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) {
        throw 'Cannot update while HEAD is detached.'
    }
    $beforeUpdate = (& git -C $repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read current Git revision.' }
    Invoke-Checked 'git' @('-C', $repository, 'fetch', '--prune', 'origin')
    Invoke-Checked 'git' @('-C', $repository, 'pull', '--ff-only', 'origin', $currentBranch)
    $afterUpdate = (& git -C $repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read updated Git revision.' }
    if ($afterUpdate -ne $beforeUpdate) {
        $changedPipeline = @(& git -C $repository diff --name-only $beforeUpdate $afterUpdate -- 'tools/release/Update-Build-Test-Package.ps1' 'tools/release/Package-Helpers.ps1' 'tools/release/OpenSalamander.iss')
        if ($LASTEXITCODE -ne 0) { throw 'Unable to compare pipeline versions after Git update.' }
        if ($changedPipeline.Count -gt 0) {
            throw 'The update changed release pipeline scripts. Run the command again to load the new version safely.'
        }
    }
}

$vsDir = Get-VisualStudio2026
$msbuild = Join-Path $vsDir 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild)) { throw "MSBuild not found: $msbuild" }

$pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
$pf = [Environment]::GetFolderPath('ProgramFiles')
$hhcExe = Find-Executable 'hhc.exe' @(
    (Join-Path $pf86 'HTML Help Workshop\hhc.exe')
)
$sevenZipExe = Find-Executable '7z.exe' @(
    (Join-Path $pf '7-Zip\7z.exe'),
    (Join-Path $pf86 '7-Zip\7z.exe')
)
$dumpbinExe = Find-Executable 'dumpbin.exe' @(
    (Get-ChildItem -LiteralPath (Join-Path $vsDir 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'bin\Hostx64\x64\dumpbin.exe' })
)

$isccExe = $null
if (-not $SkipInstaller) {
    $isccExe = Find-Executable 'ISCC.exe' @(
        (Join-Path $pf86 'Inno Setup 6\ISCC.exe'),
        (Join-Path $pf 'Inno Setup 6\ISCC.exe'),
        (Join-Path $pf86 'Inno Setup 7\ISCC.exe'),
        (Join-Path $pf 'Inno Setup 7\ISCC.exe')
    )
}

$crt = Get-MsvcRuntimeFolders -VisualStudioDir $vsDir

New-Item -ItemType Directory -Path $buildRootFull -Force | Out-Null
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Write-Host "Visual Studio: $vsDir"
Write-Host "Build root: $env:OPENSAL_BUILD_DIR"
Write-Host 'Rebuilding x64 Debug and Release...'

if ($SkipBuild) { Write-Host 'Rebuild übersprungen: vorhandene Builds werden auf Vollständigkeit geprüft.' }
foreach ($configuration in @('Debug', 'Release')) {
    Write-Host "=== $configuration x64 ==="
    if (-not $SkipBuild) {
        Invoke-Checked $msbuild @(
        $solution,
        '/t:Rebuild',
        "/p:Configuration=$configuration",
        '/p:Platform=x64',
        '/p:PreferredToolArchitecture=x64',
        '/m',
        '/nr:false',
        '/v:minimal'
        )
    }
    $expectedBinary = Join-Path $variantPaths[$configuration] 'salamand.exe'
    if (-not (Test-Path -LiteralPath $expectedBinary -PathType Leaf)) {
        throw "MSBuild reported success but the expected executable is missing: $expectedBinary"
    }
}

Build-CompiledHelp -Repository $repository -HhcExe $hhcExe -OutputDirectories @(
    $variantPaths.Debug, $variantPaths.Release
)

foreach ($configuration in @('Debug', 'Release')) {
    Write-Host "=== Packaging $configuration x64 ==="
    $stage = Join-Path $stageRoot ("OpenSalamander-{0}-x64" -f $configuration)
    New-DistributionStage -BuiltDirectory $variantPaths[$configuration] -Stage $stage -Repository $repository -Configuration $configuration -CrtFolders $crt
    Test-DistributionStage -Stage $stage -Configuration $configuration -DumpbinExe $dumpbinExe

    $archive = Join-Path $artifactDir ("OpenSalamander-{0}-x64.7z" -f $configuration)
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Push-Location $stage
    try {
        Invoke-Checked $sevenZipExe @('a', '-t7z', '-mx=7', '-y', $archive, '.\*')
    }
    finally { Pop-Location }
    Invoke-Checked $sevenZipExe @('t', '-y', $archive)
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw "Archive was not created: $archive"
    }

    if (-not $SkipInstaller) {
        $installer = Join-Path $artifactDir ("OpenSalamander-{0}-x64-Setup.exe" -f $configuration)
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        Invoke-Checked $isccExe @(
            "/DSourceDir=$stage",
            "/DOutputDir=$artifactDir",
            "/DConfiguration=$configuration",
            '/DArchitecture=x64',
            (Join-Path $PSScriptRoot 'OpenSalamander.iss')
        )
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw "Inno Setup did not create the installer: $installer"
        }
    }
}

$artifactManifest = Join-Path $artifactDir 'SHA256SUMS.txt'
$packages = @(Get-ChildItem -LiteralPath $artifactDir -File |
    Where-Object { $_.Extension -eq '.7z' -or $_.Name -like '*-Setup.exe' } |
    Sort-Object Name)
$checksums = foreach ($package in $packages) {
    '{0} *{1}' -f (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $package.Name
}
$checksums | Set-Content -LiteralPath $artifactManifest -Encoding utf8

Write-Host ''
Write-Host 'Package generation complete. Artifacts:'
Get-ChildItem -LiteralPath $artifactDir -File |
    Where-Object { $_.Extension -eq '.7z' -or $_.Name -like '*-Setup.exe' } |
    Select-Object Name, Length, FullName | Format-Table -AutoSize
Write-Warning 'Debug packages are INTERNAL TEST ONLY and must not be publicly redistributed.'
Write-Warning 'A clean Windows 11 VM installation/run/uninstall test is still required.'
