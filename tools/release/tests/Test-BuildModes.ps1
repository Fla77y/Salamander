#requires -Version 7.4
# Regression tests for cold, rebuild and incremental build selection and CHM invalidation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
. (Join-Path $repository 'tools\release\Build-Helpers.ps1')
. (Join-Path $repository 'tools\release\Package-Helpers.ps1')

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
    return $set
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
        $chm = Join-Path $directory 'test.chm'
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

    # Act/Assert: missing one binary is not a cache hit.
    Remove-Item -LiteralPath (Join-Path $debugDir 'test.chm') -Force
    if (-not (Test-HelpNeedsBuild -ProjectPath $project -CompiledName 'test.chm' -OutputDirectories $outputPaths)) {
        throw 'Missing Debug help incorrectly reused Release output.'
    }
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}

# Arrange/Act/Assert: the central manager and package pipeline keep both paths.
$manager = [IO.File]::ReadAllText((Join-Path $repository 'tools\Manage-Salamander.ps1'))
$pipeline = [IO.File]::ReadAllText((Join-Path $repository 'tools\release\Update-Build-Test-Package.ps1'))
foreach ($text in @($manager, $pipeline)) {
    if (-not $text.Contains('/t:Build') -or -not $text.Contains('/t:Rebuild')) {
        throw 'Build and Rebuild targets must both be explicitly selectable.'
    }
}
if (-not $manager.Contains("'--build-delta'") -or -not $manager.Contains("'--build-clean'") -or
    -not $manager.Contains('Build-Setups -AlreadyBuilt:')) {
    throw 'Management CLI must wire incremental and clean modes to packaging.'
}
Write-Host 'PASS: Build modes, conflicts, HTML Help cache invalidation and CLI integration.'
