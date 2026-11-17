#requires -Version 7.4
# Shared MSBuild orchestration for fresh and incremental builds.
Set-StrictMode -Version Latest

function Get-BuildMode {
    param([Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$RequestedSet)
    $modes = @('--build', '--build-delta', '--build-clean') |
        Where-Object { $RequestedSet.Contains($_) }
    if ($modes.Count -gt 1) {
        throw "Conflicting build modes: $($modes -join ', '). Choose exactly one."
    }
    if ($modes.Count -eq 0) { return 'None' }
    switch ($modes[0]) {
        '--build' { return 'Rebuild' }
        '--build-delta' { return 'Delta' }
        '--build-clean' { return 'Clean' }
    }
}

function Assert-BuildDirectory {
    param([Parameter(Mandatory)][string]$Repository,
          [Parameter(Mandatory)][string]$BuildRoot)
    $repo = [IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
    $root = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\', '/')
    if ($root.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
        $root.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $repo.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BuildRoot must be separate from the repository and its parent directories.'
    }
}

function Invoke-SalamanderBuild {
    param([Parameter(Mandatory)][string]$Msbuild,
          [Parameter(Mandatory)][string]$Solution,
          [Parameter(Mandatory)][string]$Repository,
          [Parameter(Mandatory)][string]$BuildRoot,
          [Parameter(Mandatory)][ValidateSet('Delta', 'Rebuild', 'Clean')][string]$Mode,
          [string[]]$Configurations = @('Debug', 'Release'),
          [Parameter(Mandatory)][scriptblock]$Invoke)
    Assert-BuildDirectory -Repository $Repository -BuildRoot $BuildRoot
    $env:OPENSAL_BUILD_DIR = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\') + '\'
    foreach ($configuration in $Configurations) {
        if ($configuration -notin @('Debug', 'Release')) {
            throw "Unsupported build configuration: $configuration"
        }
        $output = Join-Path $BuildRoot "salamander\${configuration}_x64"
        $intermediateParent = Join-Path $BuildRoot 'salamander'
        foreach ($parent in @($BuildRoot, $intermediateParent)) {
            if (Test-Path -LiteralPath $parent) {
                $parentItem = Get-Item -LiteralPath $parent -Force
                if ($parentItem.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
                    throw "Refusing to build through a junction/symlink: $parent"
                }
            }
        }
        if ($Mode -eq 'Clean' -and (Test-Path -LiteralPath $output)) {
            $item = Get-Item -LiteralPath $output -Force
            if ($item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
                throw "Refusing to clean a junction/symlink: $output"
            }
            Remove-Item -LiteralPath $output -Recurse -Force
        }
        $target = if ($Mode -eq 'Delta' -or $Mode -eq 'Clean') { '/t:Build' } else { '/t:Rebuild' }
        Write-Host "=== MSBuild $configuration x64 ($Mode) ==="
        $arguments = @($Solution, $target, "/p:Configuration=$configuration",
            '/p:Platform=x64', '/p:PreferredToolArchitecture=x64',
            '/m', '/nr:false', '/v:minimal')
        & $Invoke $Msbuild $arguments
        $binary = Join-Path $output 'salamand.exe'
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
            throw "Build completed without expected binary: $binary"
        }
    }
}
