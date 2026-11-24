#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Arrange: inspect the *active* solution, excluding historical samples.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$solutionPath = Join-Path $repository 'src\vcxproj\salamand.sln'
$solutionText = Get-Content -LiteralPath $solutionPath -Raw
$vsFinder = Get-Content -LiteralPath (
    Join-Path $repository 'src\vcxproj\find-vs2026.cmd') -Raw
$manager = Get-Content -LiteralPath (
    Join-Path $repository 'tools\Manage-Salamander.ps1') -Raw
$packageHelpers = Get-Content -LiteralPath (
    Join-Path $repository 'tools\release\Package-Helpers.ps1') -Raw
$config = Get-Content -LiteralPath (Join-Path $repository '.vsconfig') -Raw |
    ConvertFrom-Json

# Act / Assert: VS 2026 is the only MSBuild version selected. v143 is still
# supported under VS 2026; do not arbitrarily force v145 without builds/tests.
if ($solutionText -notmatch '(?m)^# Visual Studio Version 18\s*$' -or
    $solutionText -notmatch '(?m)^VisualStudioVersion = 18\.' -or
    $vsFinder -notmatch '\[18\.0,19\.0\)' -or
    $manager -notmatch 'Get-VisualStudio2026' -or
    $packageHelpers -notmatch '\[18\.0,19\.0\)') {
    throw 'Active solution metadata or MSBuild resolver is not VS 2026.'
}
if ($config.components -notcontains 'Microsoft.VisualStudio.Workload.NativeDesktop' -or
    $config.components -notcontains 'Microsoft.VisualStudio.Component.Windows11SDK.26100' -or
    $config.components -notcontains 'Microsoft.VisualStudio.Component.VC.14.44.17.14.x86.x64') {
    throw 'VS 2026 reproducible desktop, SDK or supported v143 components missing.'
}

$matches = [regex]::Matches(
    $solutionText,
    '(?m)^Project\([^\r\n]+?\)\s*=\s*"[^"]+",\s*"([^"]+\.vcxproj)"')
if ($matches.Count -lt 10) {
    throw "Unexpectedly few active C++ projects in solution: $($matches.Count)."
}

foreach ($match in $matches) {
    $relative = $match.Groups[1].Value
    $projectPath = [IO.Path]::GetFullPath(
        (Join-Path (Split-Path -Parent $solutionPath) $relative))
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
        throw "Referenced C++ project missing: $relative"
    }
    $projectText = Get-Content -LiteralPath $projectPath -Raw
    $toolsets = @([regex]::Matches(
        $projectText, '<PlatformToolset>([^<]+)</PlatformToolset>') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($toolsets.Count -eq 0 -or
        @($toolsets | Where-Object { $_ -notin @('v143', 'v145') }).Count -gt 0) {
        throw "Unsupported/unmigrated toolset in active project $relative : $($toolsets -join ', ')"
    }
}

# Release and Debug must both compile across Win32 and x64 in GitHub CI.
# A Debug-only runner cannot qualify the shipping Release configuration.
$buildWorkflow = Get-Content -LiteralPath (
    Join-Path $repository '.github\workflows\pr-msbuild.yml') -Raw
foreach ($required in @(
    'platform: ["Win32", "x64"]',
    'configuration: ["Debug", "Release"]',
    'BUILD_CONFIGURATION: ${{ matrix.configuration }}',
    'msbuild @arguments'
)) {
    if (-not $buildWorkflow.Contains($required)) {
        throw "VS2026 CI build matrix is incomplete: $required"
    }
}

Write-Host "PASS: VS 2026 solution metadata and $($matches.Count) active C++ projects use supported MSVC toolsets."


# BUILD-01 / UP-01: source-level guard for all 33 plug-in Build.0 mappings.
# These declarations are prerequisites, NOT proof of successful compilation.
$pluginBaseline = Get-Content -LiteralPath (
    Join-Path $repository 'tools\release\plugin-source-inventory-baseline.json') -Raw |
    ConvertFrom-Json

function Assert-PluginBuildMatrix {
    param(
        [Parameter(Mandatory)][string]$Solution,
        [Parameter(Mandatory)][string[]]$RequiredPlugins
    )
    $seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $projects = [regex]::Matches($Solution,
        '(?m)^Project\("[^"]+"\)\s*=\s*"(?<name>[^"]+)",\s*"(?<path>[^"]+\.vcxproj)",\s*"\{(?<guid>[A-Fa-f0-9-]+)\}"')
    foreach ($project in $projects) {
        $name = $project.Groups['name'].Value
        $path = $project.Groups['path'].Value.Replace('\', '/')
        $expectedPath = "../plugins/$name/vcxproj/$name.vcxproj"
        if (-not [string]::Equals($path, $expectedPath,
                                  [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (-not $seen.Add($name)) {
            throw "Duplicate plug-in build project declaration: $name"
        }
        $guid = $project.Groups['guid'].Value
        foreach ($configuration in @('Debug|Win32', 'Debug|x64',
                                     'Release|Win32', 'Release|x64')) {
            $requiredLine = "{$guid}.$configuration.Build.0 = $configuration"
            if (-not [regex]::IsMatch($Solution,
                    '(?m)^\s*' + [regex]::Escape($requiredLine) + '\s*$',
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                throw "Missing plug-in Build.0 mapping for $name : $configuration"
            }
        }
    }
    foreach ($name in $RequiredPlugins) {
        if (-not $seen.Contains($name)) {
            throw "Required plug-in solution project missing: $name"
        }
    }
    if ($seen.Count -ne $RequiredPlugins.Count) {
        throw "Unexpected plug-in build project count: $($seen.Count)"
    }
    return $seen.Count
}

# Arrange: source baseline and actual Visual Studio 2026 solution.
$required = [string[]]@($pluginBaseline.solutionPluginProjects)
if ($required.Count -ne 33) {
    throw "Unexpected plug-in source baseline size: $($required.Count)"
}
# Act/Assert: all four genuine Build.0 mappings must exist for each project.
$count = Assert-PluginBuildMatrix -Solution $solutionText -RequiredPlugins $required

# RED negative: removing or misrouting even one Build.0 mapping must fail.
$sevenZipProject = [regex]::Match($solutionText,
    '(?m)^Project\("[^"]+"\)\s*=\s*"7zip",\s*"[^"]+",\s*"\{(?<guid>[A-Fa-f0-9-]+)\}"')
if (-not $sevenZipProject.Success) {
    throw 'Cannot construct plug-in matrix regression: 7zip project missing.'
}
$line = '{' + $sevenZipProject.Groups['guid'].Value +
    '}.Release|x64.Build.0 = Release|x64'
if (-not $solutionText.Contains($line)) {
    throw 'Cannot construct plug-in matrix regression: expected 7zip mapping missing.'
}
foreach ($broken in @(
    $solutionText.Replace($line, ''),
    $solutionText.Replace($line, $line.Replace('= Release|x64', '= Debug|x64'))
)) {
    $rejected = $false
    try { $null = Assert-PluginBuildMatrix -Solution $broken -RequiredPlugins $required }
    catch {
        if ($_.Exception.Message -notmatch 'Missing plug-in Build\.0 mapping for 7zip') {
            throw "Wrong reason for invalid solution mapping: $($_.Exception.Message)"
        }
        $rejected = $true
    }
    if (-not $rejected) {
        throw 'A missing or incorrect plug-in Build.0 mapping was accepted.'
    }
}
Write-Host "PASS: $count plug-ins have all four declared Win32/x64 Debug/Release Build.0 mappings; negative cases rejected."
