#requires -Version 7.4
# Regression tests for cold, rebuild and incremental build selection and CHM invalidation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
. (Join-Path $repository 'tools\release\Build-Helpers.ps1')
. (Join-Path $repository 'tools\release\Package-Helpers.ps1')

# Arrange: Debug Unicode path comparisons use the MSVC standard library.
$debugProperties = Get-Content -LiteralPath (Join-Path $repository 'src\vcxproj\sal_debug.props') -Raw

# Act and assert: keep the stack and uninitialized-variable checks without
# the incompatible narrowing instrumentation that aborted the x86 F5 test.
if ($debugProperties -match '<SmallerTypeCheck>true</SmallerTypeCheck>|_ALLOW_RTCc_IN_STL' -or
    $debugProperties -notmatch '<BasicRuntimeChecks>EnableFastChecks</BasicRuntimeChecks>') {
    throw 'Core Debug builds must use /RTC1 and must not enable /RTCc for the MSVC standard library.'
}

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Scenario)
    if ($Actual -cne $Expected) {
        throw "$Scenario : expected '$Expected', got '$Actual'."
    }
}

function New-OptionSet {
    param([string[]]$Options)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($option in $Options) { [void]$set.Add($option) }
    return ,$set
}

# Arrange: each invocation has an independent set of requested CLI switches.
$cases = @(
    @{ Options = @('--build'); Expected = 'Rebuild' },
    @{ Options = @('--build-delta'); Expected = 'Delta' },
    @{ Options = @('--build-clean'); Expected = 'Clean' },
    @{ Options = @('--test'); Expected = 'None' }
)
foreach ($case in $cases) {
    # Act
    $mode = Get-BuildMode -RequestedSet (New-OptionSet $case.Options)
    # Assert
    Assert-Equal $mode $case.Expected "Mode: $($case.Options -join ', ')"
}

# Arrange: ambiguous build requests must never silently choose a different mode.
foreach ($options in @(@('--build', '--build-delta'),
                       @('--build', '--build-clean'),
                       @('--build-clean', '--build-delta'))) {
    # Act
    $caught = $false
    try { Get-BuildMode -RequestedSet (New-OptionSet $options) | Out-Null }
    catch { $caught = $true }
    # Assert
    if (-not $caught) { throw "Conflicting build options accepted: $($options -join ', ')" }
}

# Arrange: a synthetic HTML Help project and its two output variants.
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('sal-build-modes-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$releaseDir = Join-Path $fixture 'release'
$debugDir = Join-Path $fixture 'debug'
try {
    foreach ($directory in @($source, $releaseDir, $debugDir)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $project = Join-Path $source 'test.hhp'
    $page = Join-Path $source 'intro.htm'
    $extra = Join-Path $fixture 'stop.stp'
    @('[OPTIONS]', 'Compiled file=test.chm', 'Full text search stop list file=..\stop.stp',
      '[FILES]', 'intro.htm') | Set-Content -LiteralPath $project -Encoding UTF8
    'help' | Set-Content -LiteralPath $page -Encoding UTF8
    'stop words' | Set-Content -LiteralPath $extra -Encoding UTF8
    $outputPaths = @($releaseDir, $debugDir)
    $old = [datetime]::UtcNow.AddMinutes(-20)
    $new = [datetime]::UtcNow.AddMinutes(-10)
    foreach ($file in @($project, $page, $extra)) {
        [IO.File]::SetLastWriteTimeUtc($file, $old)
    }
    foreach ($directory in $outputPaths) {
        $chm = Join-Path $directory 'help\english\test.chm'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $chm) | Out-Null
        [IO.File]::WriteAllBytes($chm, [byte[]]::new(2048))
        [IO.File]::SetLastWriteTimeUtc($chm, $new)
    }

    # Act/Assert: unchanged inputs and complete output variants are reusable.
    if (Test-HelpNeedsBuild -ProjectPath $project -CompiledName 'test.chm' -OutputDirectories $outputPaths) {
        throw 'Unchanged HTML Help sources caused an unnecessary rebuild.'
    }

    # Act/Assert: changes to a referenced external stop list invalidate the cache.
    [IO.File]::SetLastWriteTimeUtc($extra, [datetime]::UtcNow)
    if (-not (Test-HelpNeedsBuild -ProjectPath $project -CompiledName 'test.chm' -OutputDirectories $outputPaths)) {
        throw 'Changed external HTML Help dependency was ignored.'
    }
    [IO.File]::SetLastWriteTimeUtc($extra, $old)

    # Arrange: the Debug CHM exists at the same location as the compiled help output.
    $debugHelp = Join-Path $debugDir 'help\english\test.chm'
    if (-not (Test-Path -LiteralPath $debugHelp -PathType Leaf)) {
        throw "Missing synthetic Debug help fixture: $debugHelp"
    }
    # Act: remove one of the two independently required outputs.
    Remove-Item -LiteralPath $debugHelp -Force
    # Assert: the incremental check must detect the missing Debug CHM.
    if ((Test-Path -LiteralPath $debugHelp -PathType Leaf) -or
        -not (Test-HelpNeedsBuild -ProjectPath $project -CompiledName 'test.chm' -OutputDirectories $outputPaths)) {
        throw 'Missing Debug help incorrectly reused Release output.'
    }
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}

# Arrange: fake compiler preserves output files and records the invoked MSBuild target.
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('sal-build-out-' + [guid]::NewGuid().ToString('N'))
$repositoryRoot = Join-Path ([IO.Path]::GetTempPath()) ('sal-build-repo-' + [guid]::NewGuid().ToString('N'))
$targets = [System.Collections.Generic.List[string]]::new()
try {
    New-Item -ItemType Directory -Force -Path $buildRoot, $repositoryRoot | Out-Null
    $simulateBuild = {
        param($executable, $arguments)
        $target = @($arguments | Where-Object { $_ -like '/t:*' })
        $targets.Add($target[0])
        $variant = if ($arguments -contains '/p:Configuration=Debug') { 'Debug' } else { 'Release' }
        $out = Join-Path $buildRoot ("salamander\${variant}_x64")
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        [IO.File]::WriteAllText((Join-Path $out 'salamand.exe'), 'fixture')
    }

    # Act: delta and rebuild retain their distinct MSBuild target selection.
    Invoke-SalamanderBuild -Msbuild 'mock-msbuild.exe' -Solution 'mock.sln' `
        -Repository $repositoryRoot -BuildRoot $buildRoot -Mode Delta -Invoke $simulateBuild
    Invoke-SalamanderBuild -Msbuild 'mock-msbuild.exe' -Solution 'mock.sln' `
        -Repository $repositoryRoot -BuildRoot $buildRoot -Mode Rebuild -Invoke $simulateBuild

    # Assert
    Assert-Equal ($targets -join ',') '/t:Build,/t:Build,/t:Rebuild,/t:Rebuild' 'MSBuild target selection'

    # Arrange: a stale binary exists from the previous build.
    $stale = Join-Path $buildRoot 'salamander\Debug_x64\obsolete.dll'
    [IO.File]::WriteAllText($stale, 'stale')
    # Act
    Invoke-SalamanderBuild -Msbuild 'mock-msbuild.exe' -Solution 'mock.sln' `
        -Repository $repositoryRoot -BuildRoot $buildRoot -Mode Clean -Invoke $simulateBuild
    # Assert
    if (Test-Path -LiteralPath $stale) { throw 'Clean build retained an obsolete artifact.' }
    Assert-Equal (($targets | Select-Object -Last 2) -join ',') '/t:Rebuild,/t:Rebuild' 'Clean target selection'

    # Arrange/Act/Assert: destructive clean must reject the repository as a build root.
    $rejected = $false
    # Arrange / Act / Assert: the repository-owned .Build directory is the only allowed internal root.
    Assert-BuildDirectory -Repository $repositoryRoot -BuildRoot (Join-Path $repositoryRoot '.Build')
    $nestedBuildRootRejected = $false
    try { Assert-BuildDirectory -Repository $repositoryRoot -BuildRoot (Join-Path $repositoryRoot 'other-build') }
    catch { $nestedBuildRootRejected = $true }
    if (-not $nestedBuildRootRejected) { throw 'An arbitrary repository subdirectory was accepted as BuildRoot.' }
    try { Assert-BuildDirectory -Repository $repositoryRoot -BuildRoot $repositoryRoot }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsafe build root was accepted.' }
}
finally {
    foreach ($directory in @($buildRoot, $repositoryRoot)) {
        if (Test-Path -LiteralPath $directory) {
            Remove-Item -LiteralPath $directory -Recurse -Force
        }
    }
}

# Arrange/Act/Assert: the central manager and package pipeline keep both paths.
$manager = [IO.File]::ReadAllText((Join-Path $repository 'tools\Manage-Salamander.ps1'))
$pipeline = [IO.File]::ReadAllText((Join-Path $repository 'tools\release\Update-Build-Test-Package.ps1'))
$sharedBuild = [IO.File]::ReadAllText((Join-Path $repository 'tools\release\Build-Helpers.ps1'))
if (-not $sharedBuild.Contains('/t:Build') -or -not $sharedBuild.Contains('/t:Rebuild') -or
    -not $manager.Contains('Invoke-SalamanderBuild') -or
    -not $pipeline.Contains('Invoke-SalamanderBuild')) {
    throw 'Build and Rebuild targets must be selectable via the shared builder.'
}
if (-not $manager.Contains("'--build-delta'") -or -not $manager.Contains("'--build-clean'") -or
    -not $manager.Contains('Build-Setups -AlreadyBuilt:')) {
    throw 'Management CLI must wire incremental and clean modes to packaging.'
}

# Arrange/Act/Assert: self-updating must not continue with a stale loaded
# Build-Helpers function after Git replaces the helper file on disk.
$managerUpdate = [regex]::Match(
    $manager, '(?s)function Update-Branch\s*\{(.*?)\nfunction Get-VariantDirectory'
).Groups[1].Value
$pipelineUpdate = [regex]::Match(
    $pipeline, '(?s)if \(-not \$SkipUpdate\) \{(.*?)\n\$vsDir'
).Groups[1].Value
if ([string]::IsNullOrWhiteSpace($managerUpdate) -or
    [string]::IsNullOrWhiteSpace($pipelineUpdate) -or
    -not $managerUpdate.Contains("'tools/release/Build-Helpers.ps1'") -or
    -not $pipelineUpdate.Contains("'tools/release/Build-Helpers.ps1'")) {
    throw 'Git update must restart when the shared Build-Helpers script changed.'
}
Write-Host 'PASS: Build modes, conflicts, HTML Help cache invalidation and CLI integration.'
