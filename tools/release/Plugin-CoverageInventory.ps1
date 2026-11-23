#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Read-only inventory of solution plug-in projects and actual SPL payloads.
# A project/source folder is NOT proof of a built, staged or working plug-in.

function Get-SplInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Description
    )

    $root = Join-Path $Directory 'plugins'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "$Description plug-in directory is missing: $root"
    }

    $modules = [Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    # Include all SPLs in the provided output tree, not just plugins/.
    # Unexpected root-level binaries would otherwise disappear from reports.
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Recurse -Filter '*.spl')) {
        $underPluginRoot = $file.FullName.StartsWith(
            ([IO.Path]::GetFullPath($root).TrimEnd('\') + '\'),
            [StringComparison]::OrdinalIgnoreCase)
        if (-not $underPluginRoot) {
            throw "Unexpected $Description SPL outside plugins tree: $($file.FullName)"
        }
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
        $parts = @($relative -split '[\\/]')
        if ($parts.Count -ne 2 -or
            -not [string]::Equals(
                $parts[0], [IO.Path]::GetFileNameWithoutExtension($parts[1]),
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected $Description SPL location: $($file.FullName)"
        }
        if (-not $modules.TryAdd($parts[0], $file.FullName)) {
            throw "Duplicate $Description SPL module: $($file.FullName)"
        }
    }
    return ,$modules
}

function Get-SalamanderPluginInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [string]$BuiltDirectory,
        [string]$StagedDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($StagedDirectory) -and
        [string]::IsNullOrWhiteSpace($BuiltDirectory)) {
        throw 'Staged plug-ins require a build directory for comparison.'
    }

    $pluginSources = Join-Path $Repository 'src\plugins'
    $solution = Join-Path $Repository 'src\vcxproj\salamand.sln'
    if (-not (Test-Path -LiteralPath $pluginSources -PathType Container) -or
        -not (Test-Path -LiteralPath $solution -PathType Leaf)) {
        throw "Repository is missing Salamander solution or plug-in sources: $Repository"
    }

    $sourceNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($directory in @(Get-ChildItem -LiteralPath $pluginSources -Directory)) {
        if ($directory.Name -ine 'shared') {
            [void]$sourceNames.Add($directory.Name)
        }
    }

    # Only a top-level plugin.vcxproj under the correspondingly named plugin
    # folder identifies a plug-in project. Lang, helper DLL and library
    # projects must never be counted as plug-in modules.
    $projectNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $solutionText = Get-Content -LiteralPath $solution -Raw
    $projectPattern = '(?m)^Project\("[^"]+"\)\s*=\s*"(?<name>[^"]+)",\s*"(?<path>[^"]+\.vcxproj)"'
    foreach ($match in [regex]::Matches($solutionText, $projectPattern)) {
        $project = $match.Groups['name'].Value
        $relative = $match.Groups['path'].Value.Replace('\', '/')
        $expected = "../plugins/$project/vcxproj/$project.vcxproj"
        if ([string]::Equals($relative, $expected,
                             [StringComparison]::OrdinalIgnoreCase)) {
            if (-not $projectNames.Add($project)) {
                throw "Duplicate Salamander plug-in project: $project"
            }
        }
    }

    $built = $null
    $staged = $null
    if (-not [string]::IsNullOrWhiteSpace($BuiltDirectory)) {
        $built = Get-SplInventory -Directory $BuiltDirectory -Description 'built'
    }
    if (-not [string]::IsNullOrWhiteSpace($StagedDirectory)) {
        $staged = Get-SplInventory -Directory $StagedDirectory -Description 'staged'
    }

    $names = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $sourceNames) { [void]$names.Add($name) }
    foreach ($name in $projectNames) { [void]$names.Add($name) }
    if ($null -ne $built) {
        foreach ($name in $built.Keys) { [void]$names.Add($name) }
    }
    if ($null -ne $staged) {
        foreach ($name in $staged.Keys) { [void]$names.Add($name) }
    }

    foreach ($name in @($names | Sort-Object)) {
        $hasBuilt = $null -ne $built -and $built.ContainsKey($name)
        $hasStaged = $null -ne $staged -and $staged.ContainsKey($name)

        $builtHash = if ($hasBuilt -and $null -ne $staged) {
            (Get-FileHash -LiteralPath $built[$name] -Algorithm SHA256).Hash
        } else { '' }
        $stagedHash = if ($hasStaged) {
            (Get-FileHash -LiteralPath $staged[$name] -Algorithm SHA256).Hash
        } else { '' }
        $payloadStatus = if ($null -eq $staged) { 'NOT_CHECKED' }
                         elseif (-not $hasBuilt -and -not $hasStaged) { 'NOT_SHIPPED' }
                         elseif (-not $hasBuilt) { 'MISSING_BUILT' }
                         elseif (-not $hasStaged) { 'MISSING_STAGED' }
                         elseif ($builtHash -cne $stagedHash) { 'HASH_MISMATCH' }
                         else { 'MATCH' }
        [pscustomobject]@{
            Plugin               = $name
            SourceDirectory      = $sourceNames.Contains($name)
            SolutionProject      = $projectNames.Contains($name)
            BuiltModule          = if ($null -eq $built) { 'NOT_CHECKED' }
                                   elseif ($hasBuilt) { 'PRESENT' } else { 'ABSENT' }
            StagedModule         = if ($null -eq $staged) { 'NOT_CHECKED' }
                                   elseif ($hasStaged) { 'PRESENT' } else { 'ABSENT' }
            BuiltPath            = if ($hasBuilt) { $built[$name] } else { '' }
            StagedPath           = if ($hasStaged) { $staged[$name] } else { '' }
            BuiltSHA256          = $builtHash
            StagedSHA256         = $stagedHash
            PayloadStatus        = $payloadStatus
            Capabilities         = 'NOT_ASSESSED'
            UnicodeAcceptance    = 'NOT_TESTED'
            LongPathAcceptance   = 'NOT_TESTED'
            Evidence             = ''
        }
    }
}

function Get-SalamanderPluginOperationMatrix {
    [CmdletBinding()]
    param([Parameter(Mandatory,ValueFromPipeline)][psobject]$InputObject)

    process {
        # Applicability is deliberately unresolved until each plug-in API
        # is inspected. A name such as "zip" is not evidence of capability.
        foreach ($operation in @('List','Open','Copy','Move','Rename','Delete',
                                 'Find','Pack','Extract','View','Thumbnail','Menu')) {
            [pscustomobject]@{
                Plugin = [string]$InputObject.Plugin
                Operation = $operation
                Applicable = 'NOT_ASSESSED'
                UnicodeStatus = 'NOT_TESTED'
                LongPathStatus = 'NOT_TESTED'
                NegativeCases = 'NOT_TESTED'
                Evidence = ''
            }
        }
    }
}
