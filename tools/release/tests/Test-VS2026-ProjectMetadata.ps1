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

Write-Host "PASS: VS 2026 solution metadata and $($matches.Count) active C++ projects use supported MSVC toolsets."
