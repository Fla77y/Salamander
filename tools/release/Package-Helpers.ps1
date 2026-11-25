# Internal helpers for the Windows x64 build and distribution pipeline.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Production-Binary-Contract.ps1')

function Find-Executable {
    param([string]$Name, [string[]]$Candidates)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { return $command.Source }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }
    throw "Required tool '$Name' was not found. Checked: $($Candidates -join '; ')"
}

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Command failed with exit code $exitCode : $Executable $($Arguments -join ' ')"
    }
}

function Get-VisualStudio2026 {
    # A VS 2026 Developer PowerShell already identifies its active installation.
    # Prefer it over vswhere's optional component registration when MSBuild exists.
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:VSINSTALLDIR)) {
        $candidates.Add($env:VSINSTALLDIR)
    }

    $installerDir = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio\Installer'
    $vswhere = Join-Path $installerDir 'vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $found = @(& $vswhere -products '*' -version '[18.0,19.0)' -property installationPath)
        if ($LASTEXITCODE -ne 0) {
            throw "Visual Studio discovery failed: $vswhere (exit code $LASTEXITCODE)."
        }
        foreach ($path in $found) {
            if (-not [string]::IsNullOrWhiteSpace($path)) { $candidates.Add($path.Trim()) }
        }
    }

    foreach ($candidate in $candidates) {
        $root = [IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
        # Do not accidentally select VS 2022 or an unrelated MSBuild installation.
        if ($root -notmatch '(?i)[\\/]Microsoft Visual Studio[\\/]18[\\/]') { continue }
        $msbuild = Join-Path $root 'MSBuild\Current\Bin\MSBuild.exe'
        if (Test-Path -LiteralPath $msbuild -PathType Leaf) { return $root }
    }

    throw ('Visual Studio 2026 MSBuild.exe not found. Checked installation roots: ' +
           ($candidates -join '; ') + '. VSINSTALLDIR=' + $env:VSINSTALLDIR)
}

function Get-MsvcRuntimeFolders {
    param([string]$VisualStudioDir)
    $root = Join-Path $VisualStudioDir 'VC\Redist\MSVC'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "MSVC redistributable directory is missing: $root"
    }

    foreach ($folder in (Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name -Descending)) {
        $release = Join-Path $folder.FullName 'x64\Microsoft.VC143.CRT'
        $debug = Join-Path $folder.FullName 'debug_nonredist\x64\Microsoft.VC143.DebugCRT'
        if ((Test-Path -LiteralPath (Join-Path $release 'vcruntime140.dll')) -and
            (Test-Path -LiteralPath (Join-Path $debug 'vcruntime140d.dll'))) {
            return @{ Release = $release; Debug = $debug }
        }
    }
    throw 'Matching x64 MSVC v143 Release and Debug CRT files were not found. Install v143 build tools.'
}

function Get-DebugUcrtFolder {
    $base = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft SDKs\Windows Kits\10\ExtensionSDKs\Microsoft.UniversalCRT.Debug'
    if (-not (Test-Path -LiteralPath $base)) {
        throw "Debug UCRT SDK extension not found: $base"
    }
    foreach ($version in (Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name -Descending)) {
        $folder = Join-Path $version.FullName 'Redist\Debug\x64'
        if (Test-Path -LiteralPath (Join-Path $folder 'ucrtbased.dll') -PathType Leaf) {
            return $folder
        }
    }
    throw 'ucrtbased.dll was not found in the Windows SDK debug UCRT extension.'
}

function Copy-ResourceDirectory {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Required resource directory not found: $Source"
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Add-ApplicationResources {
    param([string]$Repository, [string]$Stage)
    Copy-ResourceDirectory (Join-Path $Repository 'convert') (Join-Path $Stage 'convert')
    Copy-ResourceDirectory (Join-Path $Repository 'src\res\toolbars') (Join-Path $Stage 'toolbars')
    Copy-ResourceDirectory (Join-Path $Repository 'src\plugins\automation\sample-scripts') (Join-Path $Stage 'plugins\automation\scripts')
    Copy-ResourceDirectory (Join-Path $Repository 'src\plugins\ieviewer\cmark-gfm\css') (Join-Path $Stage 'plugins\ieviewer\css')
    # Preserve the built converter copied by robocopy. Only its documented
    # settings examples and usage guide are runtime/user resources, not the
    # entire C++ source directory.
    $zip2sfxSource = Join-Path $Repository 'src\plugins\zip\zip2sfx'
    $zip2sfxStage = Join-Path $Stage 'plugins\zip\zip2sfx'
    New-Item -ItemType Directory -Path $zip2sfxStage -Force | Out-Null
    foreach ($name in @('readme.txt', 'sample.set', 'sam_cz.set')) {
        Copy-Item -LiteralPath (Join-Path $zip2sfxSource $name) -Destination (Join-Path $zip2sfxStage $name) -Force
    }
    Copy-Item -LiteralPath (Join-Path $Repository 'LICENSE') -Destination (Join-Path $Stage 'LICENSE') -Force
    Copy-Item -LiteralPath (Join-Path $Repository 'doc\third_party.txt') -Destination (Join-Path $Stage 'THIRD_PARTY_LICENSES.txt') -Force
}

function Copy-Runtime {
    param([string]$Stage, [string]$Configuration, [hashtable]$CrtFolders)
    Copy-Item -Path (Join-Path $CrtFolders.Release '*.dll') -Destination $Stage -Force
    if ($Configuration -eq 'Debug') {
        Copy-Item -Path (Join-Path $CrtFolders.Debug '*.dll') -Destination $Stage -Force
        $ucrt = Get-DebugUcrtFolder
        Copy-Item -Path (Join-Path $ucrt '*.dll') -Destination $Stage -Force
        @(
            'INTERNAL DEBUG BUILD - NOT FOR PUBLIC DISTRIBUTION'
            'Microsoft debug C++ runtime DLLs and Debug builds may be deployed only'
            'to your own test machines exclusively for debugging and testing.'
            'Do not upload or publish this package as a public release.'
        ) | Set-Content -LiteralPath (Join-Path $Stage 'INTERNAL-TEST-ONLY.txt') -Encoding UTF8
    }
}

function Assert-CoreHelpMappings {
    param([string]$Repository)

    # The default CHM page may be visible even when F1 context mapping is broken.
    $projectPath = Join-Path $Repository 'help\src\salamand.hhp'
    $projectDir = Split-Path -Parent $projectPath
    $projectText = [IO.File]::ReadAllText($projectPath)

    $mapSection = [regex]::Match(
        $projectText,
        '(?ms)^\[MAP\]\s*\r?\n(?<lines>.*?)(?=^\[[^\]]+\]|\z)')
    if (-not $mapSection.Success) {
        throw "Missing core help [MAP] section: $projectPath"
    }

    $headers = [regex]::Matches(
        $mapSection.Groups['lines'].Value, '(?m)^\s*#include\s+"([^"]+)"')
    if ($headers.Count -eq 0) {
        throw 'Core help [MAP] section contains no header includes.'
    }

    $mappedSymbols = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($header in $headers) {
        $headerPath = [IO.Path]::GetFullPath(
            (Join-Path $projectDir $header.Groups[1].Value))
        if (-not (Test-Path -LiteralPath $headerPath -PathType Leaf)) {
            throw "Missing core help [MAP] header: $headerPath"
        }
        $headerText = [IO.File]::ReadAllText($headerPath)
        foreach ($definition in [regex]::Matches(
            $headerText, '(?m)^\s*#define\s+([A-Za-z_]\w*)\s+\d+\b')) {
            [void]$mappedSymbols.Add($definition.Groups[1].Value)
        }
    }

    foreach ($symbol in @('IDH_INTRODUCTION', 'CM_HELP_KEYBOARD')) {
        if (-not $mappedSymbols.Contains($symbol)) {
            throw "Core help [MAP] does not define $symbol."
        }
        if ($projectText -notmatch "(?m)^\s*$symbol\s*=\s*(\S+)") {
            throw "Core help [ALIAS] does not map $symbol."
        }
    }

    $stopListMatch = [regex]::Match(
        $projectText,
        '(?mi)^\s*Full text search stop list file\s*=\s*(.+?)\s*$')
    if ($stopListMatch.Success) {
        $stopList = [IO.Path]::GetFullPath(
            (Join-Path $projectDir $stopListMatch.Groups[1].Value.Trim()))
        if (-not (Test-Path -LiteralPath $stopList -PathType Leaf)) {
            throw "Core help stop list does not exist: $stopList"
        }
    }
}

# Determines whether a CHM output can safely be reused across all variants.
function Test-HelpNeedsBuild {
    param([Parameter(Mandatory)][string]$ProjectPath,
          [Parameter(Mandatory)][string]$CompiledName,
          [Parameter(Mandatory)][string[]]$OutputDirectories)
    $sourceRoot = Split-Path -Parent $ProjectPath
    $inputs = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File |
        Where-Object { $_.Extension -notin @('.chm', '.log', '.tmp') })
    $projectText = [IO.File]::ReadAllText($ProjectPath)
    foreach ($match in [regex]::Matches($projectText, '(?mi)^\s*(?:Full text search stop list file|Contents file|Index file)\s*=\s*(.+?)\s*$')) {
        $reference = $match.Groups[1].Value.Trim().Trim('"')
        if ([IO.Path]::IsPathRooted($reference)) { return $true }
        $source = [IO.Path]::GetFullPath((Join-Path $sourceRoot $reference))
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return $true }
        $inputs += Get-Item -LiteralPath $source
    }
    $latest = ($inputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    foreach ($directory in $OutputDirectories) {
        $output = Join-Path $directory (Join-Path 'help\english' $CompiledName)
        if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { return $true }
        $item = Get-Item -LiteralPath $output
        if ($item.Length -lt 1024 -or $item.LastWriteTimeUtc -lt $latest) { return $true }
    }
    return $false
}

function Build-CompiledHelp {
    param([string]$Repository, [string]$HhcExe, [string[]]$OutputDirectories,
          [switch]$Incremental)
    Assert-CoreHelpMappings -Repository $Repository
    $mainHelp = Get-Item -LiteralPath (Join-Path $Repository 'help\src\salamand.hhp')
    $pluginHelp = @(Get-ChildItem -LiteralPath (Join-Path $Repository 'src\plugins') -File -Filter '*.hhp' -Recurse |
        Where-Object { $_.Directory.Name -eq 'help' } | Sort-Object FullName)
    $projects = @($mainHelp) + $pluginHelp
    Write-Host "Compiling $($projects.Count) HTML Help projects..."

    foreach ($project in $projects) {
        $text = [IO.File]::ReadAllText($project.FullName)
        $compiledMatch = [regex]::Match($text, '(?mi)^\s*Compiled file\s*=\s*(.+?)\s*$')
        if (-not $compiledMatch.Success) { throw "Missing 'Compiled file=' in $($project.FullName)" }
        $compiledName = $compiledMatch.Groups[1].Value.Trim().Trim('"')
        if ([IO.Path]::GetFileName($compiledName) -ne $compiledName -or
            -not $compiledName.EndsWith('.chm', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe or unsupported CHM output name in $($project.FullName): $compiledName"
        }
        if ($Incremental -and -not (Test-HelpNeedsBuild -ProjectPath $project.FullName `
                -CompiledName $compiledName -OutputDirectories $OutputDirectories)) {
            Write-Host "  Reusing unchanged help: $compiledName"
            continue
        }
        $compiledFile = Join-Path $project.DirectoryName $compiledName
        Remove-Item -LiteralPath $compiledFile -Force -ErrorAction SilentlyContinue
        Write-Host "  $($project.FullName)"
        $process = Start-Process -FilePath $HhcExe -ArgumentList @($project.Name) -WorkingDirectory $project.DirectoryName -PassThru -NoNewWindow
        # Wait for the compiler itself. Start-Process -Wait also waits for
        # descendant processes, which can outlive a finished help build.
        if (-not $process.WaitForExit(120000)) {
            if (-not $process.HasExited) { $process.Kill() }
            throw "HTML Help Compiler timed out: $($project.FullName)"
        }
        # hhc.exe can return 1 even on success. Validate the actual new output.
        if (-not (Test-Path -LiteralPath $compiledFile -PathType Leaf) -or
            (Get-Item -LiteralPath $compiledFile).Length -lt 1024) {
            throw "HTML Help Compiler failed (exit code $($process.ExitCode)): $($project.FullName)"
        }
        foreach ($directory in $OutputDirectories) {
            $destination = Join-Path $directory 'help\english'
            New-Item -ItemType Directory -Force -Path $destination | Out-Null
            Copy-Item -LiteralPath $compiledFile -Destination (Join-Path $destination $compiledName) -Force
        }
        Remove-Item -LiteralPath $compiledFile -Force
    }
}

function New-DistributionStage {
    param([string]$BuiltDirectory, [string]$Stage, [string]$Repository, [string]$Configuration, [hashtable]$CrtFolders)
    if (-not (Test-Path -LiteralPath (Join-Path $BuiltDirectory 'salamand.exe'))) {
        throw "Build output is missing salamand.exe: $BuiltDirectory"
    }
    Assert-ProductionBinary -Path (Join-Path $BuiltDirectory 'salamand.exe')
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
    New-Item -ItemType Directory -Path $Stage -Force | Out-Null
    # Incremental build outputs can retain deleted reporter binaries.
    # Never include them in a portable archive or installer.
    $copyArgs = @($BuiltDirectory, $Stage, '/E', '/XD', 'Intermediate',
                  '/XF', '*.obj', '*.pch', '*.idb', '*.ilk', '*.tlog', '*.lastbuildstate',
                  'salmon.exe', 'salmon.pdb', 'salmon.lib', 'salmon.exp')
    if ($Configuration -eq 'Release') {
        # Keep private debug symbols and linker intermediates in the original
        # build output, not in end-user archives or installers. Developer-only
        # Debug packages may retain their symbols for postmortem analysis.
        $copyArgs += @('*.pdb', '*.lib', '*.exp')
    }
    & robocopy.exe @copyArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Staging copy failed with robocopy exit code $LASTEXITCODE" }
    Add-ApplicationResources -Repository $Repository -Stage $Stage
    Copy-Runtime -Stage $Stage -Configuration $Configuration -CrtFolders $CrtFolders
}

# Verify the complete SPL set against the actual build output. Robocopy's
# success code alone cannot prove no built plug-in was lost or modified.
# No plug-in is loaded or executed by this comparison.
function Assert-StagedBuiltPlugins {
    param(
        [Parameter(Mandatory)][string]$BuiltDirectory,
        [Parameter(Mandatory)][string]$Stage
    )
    $sourceRoot = Join-Path $BuiltDirectory 'plugins'
    $stageRoot = Join-Path $Stage 'plugins'
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $stageRoot -PathType Container)) {
        throw 'Built or staged plug-in directory is missing.'
    }

    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $built = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.spl')
    if ($built.Count -eq 0) { throw 'No built plug-ins were found for release staging.' }

    foreach ($source in $built) {
        $relative = [IO.Path]::GetRelativePath($sourceRoot, $source.FullName).Replace('\', '/')
        if (-not $expected.Add($relative)) {
            throw "Duplicate built plug-in identity: $relative"
        }
        $destination = Join-Path $stageRoot $relative
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw "Built plug-in missing from distribution: $relative"
        }
        $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
        $stageHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($sourceHash -cne $stageHash) {
            throw "Staged plug-in content differs from build: $relative"
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $Stage -Recurse -File -Filter '*.spl')) {
        $relative = [IO.Path]::GetRelativePath($Stage, $file.FullName).Replace('\', '/')
        if (-not $relative.StartsWith('plugins/', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unbuilt SPL outside the distribution plug-in tree: $relative"
        }
        $pluginRelative = $relative.Substring('plugins/'.Length)
        if (-not $expected.Contains($pluginRelative)) {
            throw "Unbuilt plug-in unexpectedly included in distribution: $relative"
        }
    }
    Write-Host "PASS: all $($built.Count) built SPL modules were staged with exact SHA-256 content."
}

# Independent, versioned Release file contract. Do not derive it from a
# stage, a build tree, or an internal package checksum manifest.
function Get-ReleasePayloadEntries {
    $contract = Join-Path $PSScriptRoot 'Release-Payload.tsv'
    $lines = [IO.File]::ReadAllLines($contract)
    $header = @('Path', 'Configuration', 'Kind', 'Origin', 'Purpose') -join [char]9
    if ($lines.Length -lt 2 -or $lines[0] -cne $header) {
        throw 'Invalid Release payload contract header.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries = foreach ($line in $lines[1..($lines.Length - 1)]) {
        $fields = $line.Split([char]9)
        if ($fields.Length -ne 5 -or $fields[1] -cne 'Release' -or
            $fields[2] -cnotin @('Build', 'Source', 'Runtime', 'Generated') -or
            [string]::IsNullOrWhiteSpace($fields[4])) {
            throw "Invalid Release payload contract row: $line"
        }
        foreach ($relative in @($fields[0], $fields[3])) {
            if ($relative -notmatch '^[A-Za-z0-9_ .()/\-]+$' -or
                @($relative.Split('/') | Where-Object {
                    $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' -or $_.EndsWith('.') -or $_.EndsWith(' ')
                }).Count -ne 0) {
                throw "Unsafe Release payload contract path: $relative"
            }
        }
        if (-not $seen.Add($fields[0])) { throw "Duplicate Release payload contract path: $($fields[0])" }
        [pscustomobject]@{ Path = $fields[0]; Kind = $fields[2]; Origin = $fields[3]; Purpose = $fields[4] }
    }
    $generated = @($entries | Where-Object { $_.Kind -eq 'Generated' })
    if ($generated.Count -ne 1 -or $generated[0].Path -cne 'SHA256SUMS.txt' -or
        $generated[0].Origin -cne 'SHA256SUMS.txt') {
        throw 'Release payload contract must designate exactly the root SHA256SUMS.txt as generated.'
    }
    $entries
}

function Assert-ReleasePayload {
    param([Parameter(Mandatory)][string]$Root,
          [ValidateSet('Absent', 'Optional', 'Present')][string]$ManifestState = 'Present',
          [switch]$Installed)
    $Root = [IO.Path]::GetFullPath($Root)
    $directory = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe Release payload root: $Root"
    }
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in (Get-ReleasePayloadEntries)) {
        if ($row.Kind -eq 'Generated' -and $ManifestState -ne 'Present') { continue }
        [void]$expected.Add($row.Path)
    }
    $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $unexpected = [Collections.Generic.List[string]]::new()
    $uninstall = [Collections.Generic.List[string]]::new()
    foreach ($entry in (Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Release payload contains a reparse point: $($entry.FullName)"
        }
        if ($entry.PSIsContainer) { continue }
        $relative = [IO.Path]::GetRelativePath($Root, $entry.FullName).Replace('\', '/')
        if (-not $actual.Add($relative)) { throw "Duplicate Release payload path: $relative" }
        if ($expected.Contains($relative)) { continue }
        if ($ManifestState -eq 'Optional' -and $relative -ieq 'SHA256SUMS.txt') { continue }
        if ($Installed -and $relative -match '^unins[0-9]{3}\.(exe|dat)$') {
            $uninstall.Add($relative)
            continue
        }
        $unexpected.Add($relative)
    }
    $missing = @($expected | Where-Object { -not $actual.Contains($_) } | Sort-Object)
    if ($missing.Count -ne 0 -or $unexpected.Count -ne 0) {
        throw "Release payload path mismatch. Missing: $($missing -join '; '); Unexpected: $($unexpected -join '; ')"
    }
    if ($Installed) {
        $exe = @($uninstall | Where-Object { $_ -match '\.exe$' })
        if ($uninstall.Count -ne 2 -or $exe.Count -ne 1 -or
            $uninstall -notcontains [IO.Path]::ChangeExtension($exe[0], '.dat')) {
            throw 'Release installation must contain exactly one paired Inno Setup uninstaller EXE and DAT.'
        }
    }
    Write-Host "PASS: independent Release payload path contract ($($actual.Count) files, manifest $ManifestState)."
}

function Assert-ReleasePayloadOrigins {
    param([Parameter(Mandatory)][string]$Stage,
          [Parameter(Mandatory)][string]$Repository,
          [Parameter(Mandatory)][string]$BuiltDirectory,
          [Parameter(Mandatory)][string]$RuntimeDirectory)
    # A fresh stage may not import an already-generated manifest from a build.
    Assert-ReleasePayload -Root $Stage -ManifestState Absent
    $roots = @{ Source = $Repository; Build = $BuiltDirectory; Runtime = $RuntimeDirectory }
    foreach ($row in (Get-ReleasePayloadEntries)) {
        if ($row.Kind -eq 'Generated') { continue }
        $source = Join-Path $roots[$row.Kind] $row.Origin
        $target = Join-Path $Stage $row.Path
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Required Release payload origin missing: $($row.Path) from $source"
        }
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
            throw "Release payload differs from authorized origin: $($row.Path) from $source"
        }
    }
    Write-Host 'PASS: every non-generated Release payload file matches its declared origin by SHA-256.'
}

function Test-DistributionStage {
    param([string]$Stage, [string]$Configuration, [string]$DumpbinExe)
    if (Test-Path -LiteralPath (Join-Path $Stage 'utils\salmon.exe') -PathType Leaf) {
        throw 'Distribution contains the removed SalMon crash reporter.'
    }
    # Version 5.2 promises native WIC PictView. Its plug-in, language
    # resource, and native EXIF sidecar must actually ship in both variants.
    foreach ($required in @('salamand.exe', 'help\english\salamand.chm',
                            'LICENSE', 'THIRD_PARTY_LICENSES.txt', 'vcruntime140.dll', 'msvcp140.dll',
                            'plugins\pictview\pictview.spl',
                            'plugins\pictview\lang\english.slg',
                            'plugins\pictview\exif.dll', 'plugins\unrar\unrar.spl',
                            'plugins\unrar\lang\english.slg', 'plugins\unrar\unrar.dll',
                            'plugins\unrar\UNRAR-LICENSE.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Stage $required) -PathType Leaf)) {
            throw "Distribution is incomplete. Missing: $required in $Stage"
        }
    }
    Assert-ProductionBinary -Path (Join-Path $Stage 'salamand.exe')
    if ($Configuration -eq 'Debug') {
        foreach ($required in @('vcruntime140d.dll', 'msvcp140d.dll', 'ucrtbased.dll', 'INTERNAL-TEST-ONLY.txt')) {
            if (-not (Test-Path -LiteralPath (Join-Path $Stage $required) -PathType Leaf)) {
                throw "Debug test distribution is incomplete. Missing: $required"
            }
        }
    } else {
        # Defense in depth: also check nested plug-in directories. The
        # staging filter alone must not define the Release safety contract.
        $forbiddenBuildExtensions = @('.pdb', '.lib', '.exp', '.obj', '.pch',
                                     '.idb', '.ilk', '.tlog', '.lastbuildstate')
        $buildArtifacts = @(Get-ChildItem -LiteralPath $Stage -Recurse -File |
            Where-Object { $_.Extension -in $forbiddenBuildExtensions })
        if ($buildArtifacts.Count -ne 0) {
            $examples = @($buildArtifacts | Select-Object -First 8 |
                ForEach-Object { [IO.Path]::GetRelativePath($Stage, $_.FullName) })
            throw "Release stage contains build-only compiler/linker files: $($examples -join '; ')"
        }
        $debugDlls = @(Get-ChildItem -LiteralPath $Stage -Recurse -File | Where-Object {
            $_.Name -match '^(?:msvcp\d+(?:_\d+)?|vcruntime\d+(?:_\d+)?|concrt\d*)d\.dll$|^ucrtbased\.dll$'
        })
        if ($debugDlls.Count -ne 0) {
            throw "Release distribution contains forbidden debug runtime DLLs: $($debugDlls.Name -join ', ')"
        }
    }

    if ($Configuration -eq 'Release') {
        Assert-ReleasePayload -Root $Stage -ManifestState Optional
    }

    # Check direct imports of every executable, DLL and Salamander plug-in against
    # the staged application and Windows system DLLs. An actual clean-VM test is
    # still required because this cannot validate delayed dynamic LoadLibrary calls.
    $windows = Join-Path $env:SystemRoot 'System32'
    $unresolved = [System.Collections.Generic.List[string]]::new()
    $binaries = @(Get-ChildItem -LiteralPath $Stage -Recurse -File |
        Where-Object { $_.Extension -in @('.exe', '.dll', '.spl') })
    foreach ($binary in $binaries) {
        $output = @(& $DumpbinExe '/dependents' $binary.FullName 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "dumpbin failed for $($binary.FullName)" }
        foreach ($line in $output) {
            if ($line -notmatch '^\s*([A-Za-z0-9_.-]+\.dll)\s*$') { continue }
            $dll = $Matches[1]
            if ($dll -match '^(api-ms-win-|ext-ms-win-)') { continue }
            if ((Test-Path -LiteralPath (Join-Path $binary.DirectoryName $dll)) -or
                (Test-Path -LiteralPath (Join-Path $Stage $dll)) -or
                (Test-Path -LiteralPath (Join-Path $windows $dll))) { continue }
            $unresolved.Add("$($binary.Name): $dll")
        }
    }
    if ($unresolved.Count -gt 0) {
        throw "Unresolved PE imports (potential missing runtime dependencies): $($unresolved -join '; ')"
    }

    $manifest = Join-Path $Stage 'SHA256SUMS.txt'
    $manifestFullPath = [IO.Path]::GetFullPath($manifest)
    $files = @(Get-ChildItem -LiteralPath $Stage -File -Recurse -Force |
        Where-Object { $_.FullName -ine $manifestFullPath } | Sort-Object FullName)
    $entries = foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($Stage, $file.FullName).Replace('\', '/')
        '{0} *{1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
    }
    $entries | Set-Content -LiteralPath $manifest -Encoding utf8
    Write-Host "Validated $($binaries.Count) PE files and $($files.Count) package files: $Configuration"
}

# Called by the real packaging pipeline before any archive/installer.
# The SFX subtree has an explicit runtime allowlist; in particular no raw
# stub, build utility, C++ source or undeclared language package may ship.
function Assert-StagedZipSfx {
    param([string]$BuiltDirectory, [string]$Stage)
    Assert-ZipSfxPayload -Directory $Stage -ReferenceDirectory $BuiltDirectory
    $allowed = @((Get-ZipSfxPayloadPaths)) + @(
        'plugins\zip\zip2sfx\readme.txt',
        'plugins\zip\zip2sfx\sample.set',
        'plugins\zip\zip2sfx\sam_cz.set')
    foreach ($relative in $allowed) {
        if (-not (Test-Path -LiteralPath (Join-Path $Stage $relative) -PathType Leaf)) {
            throw "Missing required ZIP SFX distribution file: $relative"
        }
    }
    foreach ($subdirectory in @('plugins\zip\sfx', 'plugins\zip\zip2sfx')) {
        foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $Stage $subdirectory) -Recurse -File -Force)) {
            $relative = [IO.Path]::GetRelativePath($Stage, $file.FullName)
            if ($relative -notin $allowed) {
                throw "Unexpected ZIP SFX distribution file: $relative"
            }
        }
    }
    Write-Host 'PASS: exact ZIP SFX runtime allowlist and built/staged SHA-256 identity.'
}

