#requires -Version 7.4
# Shared MSBuild orchestration for fresh and incremental builds.
Set-StrictMode -Version Latest

function Get-BuildMode {
    param([Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$RequestedSet)
    $modes = @(@('--build', '--build-delta', '--build-clean') |
        Where-Object { $RequestedSet.Contains($_) })
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
    $expectedInternalRoot = Join-Path $repo '.Build'
    if ($root.Equals($expectedInternalRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    if ($root.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
        $root.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $repo.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BuildRoot must be outside the repository or exactly its .Build directory.'
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
        $target = if ($Mode -eq 'Delta') { '/t:Build' } else { '/t:Rebuild' }
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

# Historical SFX packages embed two Win32 executables, independently of
# the architecture/configuration of the host ZIP plug-in.
function Get-ZipSfxLanguages {
    [ordered]@{
        english            = @('ENGLISH_VERSION', 'windows-1252')
        czech              = @('CZECH_VERSION', 'windows-1250')
        slovak             = @('SLOVAK_VERSION', 'windows-1250')
        german             = @('GERMAN_VERSION', 'windows-1252')
        hungarian          = @('HUNGARIAN_VERSION', 'windows-1250')
        spanish            = @('SPANISH_VERSION', 'windows-1252')
        romanian           = @('ROMANIAN_VERSION', 'windows-1250')
        russian            = @('RUSSIAN_VERSION', 'windows-1251')
        chinesesimplified  = @('CHINESESIMPL_VERSION', 'gb2312')
        dutch              = @('DUTCH_VERSION', 'windows-1252')
        french             = @('FRENCH_VERSION', 'windows-1252')
    }
}

function Assert-ZipSfxPackage {
    param([Parameter(Mandatory)][string]$Path)
    # CSfxFileHeader (pack 4) in sfxmake/sfxmake.h: 19 DWORDs.
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 76 -or
        [BitConverter]::ToUInt32($bytes, 0) -ne 0x01584654 -or
        [BitConverter]::ToUInt32($bytes, 4) -ne 5 -or
        [BitConverter]::ToUInt32($bytes, 8) -ne 5) {
        throw "Invalid SFX package signature/version: $Path"
    }
    $textSize = [uint64][BitConverter]::ToUInt32($bytes, 40)
    $smallOffset = [uint64][BitConverter]::ToUInt32($bytes, 44)
    $smallSize = [uint64][BitConverter]::ToUInt32($bytes, 48)
    $bigOffset = [uint64][BitConverter]::ToUInt32($bytes, 56)
    $bigSize = [uint64][BitConverter]::ToUInt32($bytes, 60)
    if ($textSize -eq 0 -or $smallSize -eq 0 -or $bigSize -eq 0 -or
        $smallOffset -ne (76 + $textSize) -or
        $bigOffset -ne ($smallOffset + $smallSize) -or
        ($bigOffset + $bigSize) -ne $bytes.LongLength) {
        throw "Invalid SFX package section bounds: $Path"
    }
}

function Assert-ZipSfxWin32Executable {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) {
        throw "Missing DOS header in Win32 SFX executable: $Path"
    }
    $pe = [BitConverter]::ToInt32($bytes, 60)
    if ($pe -lt 64 -or $pe -gt ($bytes.Length - 26) -or
        [BitConverter]::ToUInt32($bytes, $pe) -ne 0x00004550 -or
        [BitConverter]::ToUInt16($bytes, ($pe + 4)) -ne 0x014C -or
        [BitConverter]::ToUInt16($bytes, ($pe + 24)) -ne 0x010B) {
        throw "Expected x86 PE32 SFX executable: $Path"
    }
}

function Get-ZipSfxPayloadPaths {
    'plugins\zip\zip2sfx\zip2sfx.exe'
    foreach ($language in (Get-ZipSfxLanguages).Keys) {
        "plugins\zip\sfx\$language.sfx"
    }
}

function Assert-ZipSfxPayload {
    param([Parameter(Mandatory)][string]$Directory,
          [string]$ReferenceDirectory)
    foreach ($relative in (Get-ZipSfxPayloadPaths)) {
        $path = Join-Path $Directory $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing required ZIP SFX payload: $path"
        }
        if ($relative.EndsWith('.sfx')) { Assert-ZipSfxPackage -Path $path }
        else { Assert-ZipSfxWin32Executable -Path $path }
        if ($ReferenceDirectory) {
            $source = Join-Path $ReferenceDirectory $relative
            if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) {
                throw "Staged ZIP SFX payload differs from build: $relative"
            }
        }
    }
    Write-Host "PASS: ZIP SFX Win32 converter and all 11 version-5 language packages: $Directory"
}

function New-ZipSfxDirectory {
    param([string]$Root, [string]$Relative)
    # Do not write the SFX cache or installed build outputs through junctions.
    $directory = [IO.Path]::GetFullPath($Root)
    foreach ($component in @('') + @($Relative -split '[\\/]')) {
        if ($component) { $directory = Join-Path $directory $component }
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $item = Get-Item -LiteralPath $directory -Force
        if (-not $item.PSIsContainer -or $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
            throw "Unsafe SFX build directory: $directory"
        }
    }
    return $directory
}

function Copy-ZipSfxBuildFile {
    param([string]$Source, [string]$Destination)
    if (Test-Path -LiteralPath $Destination) {
        $item = Get-Item -LiteralPath $Destination -Force
        if ($item.PSIsContainer -or $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
            throw "Unsafe SFX build destination: $Destination"
        }
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Invoke-ZipSfxBuild {
    param([Parameter(Mandatory)][string]$Msbuild,
          [Parameter(Mandatory)][string]$Repository,
          [Parameter(Mandatory)][string]$BuildRoot,
          [Parameter(Mandatory)][ValidateSet('Delta', 'Rebuild', 'Clean')][string]$Mode,
          [Parameter(Mandatory)][scriptblock]$Invoke)
    Assert-BuildDirectory -Repository $Repository -BuildRoot $BuildRoot
    $zip = Join-Path $Repository 'src\plugins\zip'
    $cache = New-ZipSfxDirectory -Root $BuildRoot -Relative 'zip-sfx'
    $target = if ($Mode -eq 'Delta') { '/t:Build' } else { '/t:Rebuild' }

    function Build-ZipSfxProject {
        param([string]$Project, [string]$Configuration, [string]$Folder,
              [string]$Language = 'ENGLISH_VERSION', [string]$Codepage = 'windows-1252')
        $out = New-ZipSfxDirectory -Root $cache -Relative $Folder
        $intermediate = New-ZipSfxDirectory -Root $out -Relative 'Intermediate'
        # Bypass the legacy signing/cross-variant copy post-build hook.
        $arguments = @((Join-Path $zip "vcxproj\$Project"), $target, '/m', '/nr:false', '/v:minimal',
            "/p:Configuration=$Configuration", '/p:Platform=Win32',
            "/p:OPENSAL_BUILD_DIR=$cache/", "/p:OutDir=$out/", "/p:IntDir=$intermediate/",
            '/p:PostBuildEventUseInBuild=false', "/p:SALAMANDER_SFX_LANGUAGE=$Language",
            "/p:SALAMANDER_SFX_CODEPAGE=$Codepage")
        & $Invoke $Msbuild $arguments
    }

    Write-Host '=== ZIP SFX tools and 11 language packages (Win32 Release) ==='
    Build-ZipSfxProject 'sfxmake\sfxmake.vcxproj' 'Release' 'Maker'
    Build-ZipSfxProject 'zip2sfx\zip2sfx.vcxproj' 'Release' 'Converter'
    $maker = Join-Path $cache 'Maker\sfxmake.exe'
    $converter = Join-Path $cache 'Converter\zip2sfx.exe'
    Assert-ZipSfxWin32Executable -Path $maker
    Assert-ZipSfxWin32Executable -Path $converter

    # Each language has separate object and executable paths, so a Delta
    # build cannot accidentally reuse another language's compiled resources.
    $languages = Get-ZipSfxLanguages
    foreach ($language in $languages.Keys) {
        $definition = $languages[$language]
        $languageDir = New-ZipSfxDirectory -Root $cache -Relative $language
        Write-Host "=== ZIP SFX $language ==="
        Build-ZipSfxProject 'selfextr\selfextr.vcxproj' 'Release' "$language\Release" $definition[0] $definition[1]
        Build-ZipSfxProject 'selfextr\selfextr.vcxproj' 'ReleaseEx' "$language\ReleaseEx" $definition[0] $definition[1]
        Assert-ZipSfxWin32Executable -Path (Join-Path $languageDir 'Release\sfxsmall.exe')
        Assert-ZipSfxWin32Executable -Path (Join-Path $languageDir 'ReleaseEx\sfxbig.exe')
        # A fresh temporary output prevents a stale package from satisfying
        # a successful maker invocation that did not actually write a file.
        $temporary = Join-Path $languageDir ([guid]::NewGuid().ToString('N') + '.sfx')
        Push-Location $languageDir
        try {
            & $Invoke $maker @($temporary, (Join-Path $zip "selfextr\language\$language\texts.txt"), '5', '5')
            Assert-ZipSfxPackage -Path $temporary
            Copy-ZipSfxBuildFile -Source $temporary -Destination (Join-Path $languageDir "$language.sfx")
        }
        finally {
            Pop-Location
            if (Test-Path -LiteralPath $temporary -PathType Leaf) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
    }

    # Both x64 host modes historically share the same standalone Win32
    # Release converter and language packages. Never stage maker/stub builds.
    foreach ($configuration in @('Debug', 'Release')) {
        $variant = Join-Path $BuildRoot "salamander\${configuration}_x64"
        $sfx = New-ZipSfxDirectory -Root $BuildRoot -Relative "salamander\${configuration}_x64\plugins\zip\sfx"
        $cli = New-ZipSfxDirectory -Root $BuildRoot -Relative "salamander\${configuration}_x64\plugins\zip\zip2sfx"
        Copy-ZipSfxBuildFile -Source $converter -Destination (Join-Path $cli 'zip2sfx.exe')
        foreach ($language in $languages.Keys) {
            Copy-ZipSfxBuildFile -Source (Join-Path $cache "$language\$language.sfx") -Destination (Join-Path $sfx "$language.sfx")
        }
        Assert-ZipSfxPayload -Directory $variant
    }
}

