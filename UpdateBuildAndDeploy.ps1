#Requires -Version 7.4
<#
.SYNOPSIS
Builds Release binaries, runs regression tests, and packages 7z archives.
.DESCRIPTION
Requires Windows, Visual Studio 2022 C++ tools, and 7-Zip. Does not install files.
#>
[CmdletBinding()]
param(
    [ValidateSet('Both', 'Win32', 'x64')]
    [string] $Platform = 'Both',
    [string] $BuildRoot = '',
    [string] $SevenZip = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }

$repository = $PSScriptRoot
$solution = Join-Path $repository 'src\vcxproj\salamand.sln'
$testProject = Join-Path $repository 'tests\ShellFileOperationNameListTests.vcxproj'
$integrationTestProject = Join-Path $repository 'tests\Win32FilesystemIntegrationTests.vcxproj'
$artifacts = Join-Path $repository 'artifacts'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $artifacts "UpdateBuildAndDeploy-$timestamp.log"
$architectures = if ($Platform -eq 'Both') { @('Win32', 'x64') } else { @($Platform) }
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    $BuildRoot = Join-Path $repository '.Build\OpenSal'
}
$BuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
$env:OPENSAL_BUILD_DIR = $BuildRoot.TrimEnd('\', '/') + '\'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

# Locate MSBuild using the selected developer environment or vswhere.
function Find-MSBuild {
    $command = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $vswhere = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'MSBuild is missing. Install Visual Studio 2022 Desktop development with C++.'
    }
    $installation = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installation)) {
        throw 'No Visual Studio installation with MSBuild found.'
    }
    $msbuild = Join-Path ($installation | Select-Object -First 1) 'MSBuild\Current\Bin\MSBuild.exe'
    if (-not (Test-Path -LiteralPath $msbuild)) { throw "MSBuild not found: $msbuild" }
    return $msbuild
}

# Locate an existing 7z.exe without installing third-party software.
function Find-SevenZip {
    param([string] $Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) { throw "7-Zip missing: $Override" }
        return (Resolve-Path -LiteralPath $Override).Path
    }
    $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $standard = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
    if (Test-Path -LiteralPath $standard -PathType Leaf) { return $standard }
    throw '7z.exe missing. Install 7-Zip or specify -SevenZip.'
}

# Execute an external process, rejecting any nonzero exit code.
function Invoke-Checked {
    param([string] $Executable, [string[]] $Arguments)
    Write-Host "Executing: $Executable $($Arguments -join ' ')"
    & $Executable @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "$Executable failed with exit code $exitCode." }
}

$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $log -Force | Out-Null
    $transcriptStarted = $true
    Write-Host "Repository: $repository"
    Write-Host "Build directory: $BuildRoot"
    Write-Host "Architectures: $($architectures -join ', ')"
    $msbuild = Find-MSBuild
    $archiveTool = Find-SevenZip -Override $SevenZip

    foreach ($architecture in $architectures) {
        Write-Host "=== Release rebuild: $architecture ==="
        Invoke-Checked -Executable $msbuild -Arguments @(
            $solution, '/t:Rebuild', '/m', '/nr:false', '/v:minimal',
            '/p:Configuration=Release', "/p:Platform=$architecture",
            '/p:PreferredToolArchitecture=x64'
        )
        $shortPlatform = if ($architecture -eq 'Win32') { 'x86' } else { 'x64' }
        $releaseDir = Join-Path $BuildRoot "salamander\Release_$shortPlatform"
        if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'salamand.exe') -PathType Leaf)) {
            throw "Compiled salamand.exe missing: $releaseDir"
        }

        Write-Host "=== Build and run regression tests: $architecture ==="
        $testOutput = Join-Path $BuildRoot "Tests\Release_$shortPlatform"
        $testIntermediate = Join-Path $BuildRoot "Tests\Intermediate_$shortPlatform"
        New-Item -ItemType Directory -Force -Path $testOutput, $testIntermediate | Out-Null
        Invoke-Checked -Executable $msbuild -Arguments @(
            $testProject, '/t:Rebuild', '/nr:false', '/v:minimal',
            '/p:Configuration=Release', "/p:Platform=$architecture",
            "/p:OutDir=$($testOutput.TrimEnd('\'))\",
            "/p:IntDir=$($testIntermediate.TrimEnd('\'))\"
        )
        $testExecutable = Join-Path $testOutput 'ShellFileOperationNameListTests.exe'
        if (-not (Test-Path -LiteralPath $testExecutable -PathType Leaf)) {
            throw "Test executable missing: $testExecutable"
        }
        Invoke-Checked -Executable $testExecutable -Arguments @()

        Write-Host "=== Build and run real Windows filesystem integration tests: $architecture ==="
        Invoke-Checked -Executable $msbuild -Arguments @(
            $integrationTestProject, '/t:Rebuild', '/nr:false', '/v:minimal',
            '/p:Configuration=Release', "/p:Platform=$architecture",
            "/p:OutDir=$($testOutput.TrimEnd('\'))\",
            "/p:IntDir=$($testIntermediate.TrimEnd('\'))\"
        )
        $integrationExecutable = Join-Path $testOutput 'Win32FilesystemIntegrationTests.exe'
        if (-not (Test-Path -LiteralPath $integrationExecutable -PathType Leaf)) {
            throw "Integration test executable missing: $integrationExecutable"
        }
        Invoke-Checked -Executable $integrationExecutable -Arguments @()

        Write-Host "=== Stage runtime files: $architecture ==="
        $stageRoot = Join-Path $artifacts "stage-$shortPlatform-$timestamp"
        $stage = Join-Path $stageRoot 'salamander'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        & robocopy.exe $releaseDir $stage /E /R:1 /W:1 /NP /XD Intermediate obj .vs /XF *.pdb *.ilk *.obj *.tlog *.idb *.lastbuildstate *.exp *.lib *.ipch *.log
        $copyStatus = $LASTEXITCODE
        if ($copyStatus -ge 8) { throw "Robocopy failed with code $copyStatus." }
        if (-not (Test-Path -LiteralPath (Join-Path $stage 'salamand.exe') -PathType Leaf)) {
            throw 'Staging did not include salamand.exe.'
        }

        # Stage data files required by the portable runtime. These source
        # assets are not produced by MSBuild or by !populate_build_dir.cmd.
        $runtimeDirectories = @(
            @{ Source = 'src\res\toolbars'; Target = 'toolbars' },
            @{ Source = 'convert\centeuro'; Target = 'convert\centeuro' },
            @{ Source = 'convert\cyrillic'; Target = 'convert\cyrillic' },
            @{ Source = 'convert\westeuro'; Target = 'convert\westeuro' },
            @{ Source = 'src\plugins\automation\sample-scripts'; Target = 'plugins\automation\scripts' },
            @{ Source = 'src\plugins\ieviewer\cmark-gfm\css'; Target = 'plugins\ieviewer\css' }
        )
        foreach ($directory in $runtimeDirectories) {
            $sourceDirectory = Join-Path $repository $directory.Source
            if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
                throw "Required runtime assets missing: $sourceDirectory"
            }
            $destinationDirectory = Join-Path $stage $directory.Target
            New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
            Copy-Item -Path (Join-Path $sourceDirectory '*') -Destination $destinationDirectory -Recurse -Force
        }

        $archive = Join-Path $artifacts "Salamander-Release-$shortPlatform-$timestamp.7z"
        Push-Location -LiteralPath $stageRoot
        try {
            Invoke-Checked -Executable $archiveTool -Arguments @('a', '-t7z', '-mx=7', '-y', $archive, 'salamander')
        }
        finally { Pop-Location }

        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Archive missing: $archive" }
        Invoke-Checked -Executable $archiveTool -Arguments @('t', $archive)
        Write-Host "SUCCESS: $archive"
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
    Write-Host 'All requested Release builds, tests and archive checks passed.'
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
        Write-Host "Full transcript: $log"
    }
}
