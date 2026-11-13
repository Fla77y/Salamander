#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Command-line entry: manage.cmd --update --build --test --setup --run
# Keep the tool native to PowerShell/Windows; all output is transcript-logged.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$requestedActions = @($args)
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$buildRoot = 'D:\Build\OpenSal'
$configuration = 'Release'
$validOptions = @('--update', '--build', '--test', '--setup', '--run',
                  '--debug', '--release', '--all', '--test-gui', '--test-gui-manual', '--help', '-h', '/?')
$requestedSet = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)

$logDirectory = Join-Path ([IO.Path]::GetFullPath($buildRoot)) 'logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory (
    'manage-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' +
    [Guid]::NewGuid().ToString('N').Substring(0, 6) + '.log')

$exitCode = 0
$transcriptStarted = $false

function Write-Usage {
    @'
Open Salamander – Verwaltung für Visual Studio 2026

  manage.cmd --update       Aktuellen Git-Branch sicher aktualisieren (nur fast-forward)
  manage.cmd --build        Debug und Release, jeweils x64, neu erstellen; CHM-Hilfe bauen
  manage.cmd --test         Windows-Dateisystem-/Namens-Tests und Projekt-Regressionstests
  manage.cmd --setup        Debug- und Release-7z plus Inno-Setup-Pakete erzeugen
  manage.cmd --test-gui     Automatisierter GUI-Test: lange Pfade, Unicode-Dateien, F5
  manage.cmd --test-gui-manual  Testdaten behalten und Salamander zum manuellen Test starten
  manage.cmd --run          Release-Version starten
  manage.cmd --run --debug  Debug-Version starten
  manage.cmd --all          Update, Build, Test, Setup und Release-Start
  manage.cmd --help         Diese Hilfe anzeigen

Mehrere Aktionen kombinieren:
  manage.cmd --update --build --test --setup
  manage.cmd --build --test --run

Voraussetzungen:
  Windows 11, PowerShell 7.4+, VS 2026 mit MSVC v143/ATL, Windows SDK.
  Für Build: HTML Help Workshop (hhc.exe).
  Für Setup: 7-Zip (7z.exe), Inno Setup (ISCC.exe), Debug-UCRT-Komponenten.

Build-Ausgabe:  D:\Build\OpenSal\salamander\Debug_x64 und Release_x64
Pakete:        D:\Build\OpenSal\dist
Protokolle:    D:\Build\OpenSal\logs

Die gesamte Ausgabe einschließlich Fehlern wird zum Schluss in die
Windows-Zwischenablage kopiert. Bei einem Testfehler wird kein Setup/Run
mehr gestartet; der Exitcode ist ungleich 0.
'@ | Write-Host
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @()
    )
    & $Command @Arguments
    $status = $LASTEXITCODE
    if ($status -ne 0) {
        throw "'$Command' ist mit Exitcode $status fehlgeschlagen."
    }
}

function Update-Branch {
    Write-Host '=== GIT UPDATE ==='
    $workingTree = @(& git -C $repository status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) { throw 'Git-Status konnte nicht gelesen werden.' }
    if ($workingTree.Count -gt 0) {
        throw ('Das Arbeitsverzeichnis enthält ungesicherte Änderungen. ' +
               'Bitte committen oder sichern, nicht automatisch löschen. ' +
               ($workingTree -join '; '))
    }

    $branch = (& git -C $repository branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        throw 'Git-HEAD ist detached. Der Update-Vorgang erfordert einen Branch.'
    }
    $before = (& git -C $repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Git-HEAD vor Update nicht lesbar.' }
    Invoke-Native 'git' @('-C', $repository, 'fetch', '--prune', 'origin')
    Invoke-Native 'git' @('-C', $repository, 'pull', '--ff-only', 'origin', $branch)
    $after = (& git -C $repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Git-HEAD nach Update nicht lesbar.' }
    Write-Host "Branch: $branch"
    Write-Host "Revision: $after"

    if ($before -ne $after) {
        $managedFiles = @('manage.cmd', 'tools/Manage-Salamander.ps1',
                          'tools/release/Package-Helpers.ps1',
                          'tools/release/Update-Build-Test-Package.ps1')
        $changed = @(& git -C $repository diff --name-only $before $after -- @managedFiles)
        if ($LASTEXITCODE -ne 0) { throw 'Git-Diff der Verwaltungsskripte fehlgeschlagen.' }
        if ($changed.Count -gt 0) {
            throw ('Verwaltungsskripte haben sich durch das Update geändert. ' +
                   'Bitte manage.cmd erneut mit den gewünschten Parametern ausführen.')
        }
    }
}

function Get-VariantDirectory {
    param([string]$Mode)
    Join-Path $buildRoot ('salamander\' + $Mode + '_x64')
}

function Build-Variants {
    Write-Host '=== BUILD DEBUG + RELEASE x64, inklusive Hilfe ==='
    $vs = Get-VisualStudio2026
    $msbuild = Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
    if (-not (Test-Path -LiteralPath $msbuild -PathType Leaf)) {
        throw "MSBuild.exe nicht gefunden: $msbuild"
    }
    $solution = Join-Path $repository 'src\vcxproj\salamand.sln'
    $env:OPENSAL_BUILD_DIR = $buildRoot.TrimEnd('\') + '\'
    foreach ($mode in @('Debug', 'Release')) {
        Write-Host "=== MSBUILD $mode | x64 ==="
        Invoke-Native $msbuild @(
            $solution, '/t:Rebuild', "/p:Configuration=$mode",
            '/p:Platform=x64', '/p:PreferredToolArchitecture=x64',
            '/m', '/nr:false', '/v:minimal'
        )
        $app = Join-Path (Get-VariantDirectory $mode) 'salamand.exe'
        if (-not (Test-Path -LiteralPath $app -PathType Leaf)) {
            throw "MSBuild meldet Erfolg, aber salamand.exe fehlt: $app"
        }
    }

    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $hhc = Find-Executable 'hhc.exe' @(
        (Join-Path $pf86 'HTML Help Workshop\hhc.exe')
    )
    Build-CompiledHelp -Repository $repository -HhcExe $hhc -OutputDirectories @(
        (Get-VariantDirectory 'Debug'), (Get-VariantDirectory 'Release')
    )
    Write-Host 'Build + Haupt- und Plugin-Hilfe erstellt.'
}

function Run-Tests {
    Write-Host '=== TESTS ==='

    $regression = Join-Path $repository 'tools\release\tests\Test-Package-Helpers.ps1'
    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $regression)

    $filesystem = Join-Path $repository 'tools\release\tests\Test-FilenamesAndPaths.ps1'
    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $filesystem)

    # Added by the long-path migration branches. Do not report full support
    # when the tests (or the production code using them) are absent.
    $cppTests = @(
        'tools\tests\quicksearch_bounds.cpp',
        'tools\tests\long_path_io.cpp'
    )
    $available = @($cppTests | Where-Object {
        Test-Path -LiteralPath (Join-Path $repository $_) -PathType Leaf
    })
    if ($available.Count -gt 0) {
        $vs = Get-VisualStudio2026
        $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
        if (-not (Test-Path -LiteralPath $vcvars -PathType Leaf)) {
            throw "MSVC x64-Umgebung nicht gefunden: $vcvars"
        }
        $testDir = Join-Path $buildRoot 'tests'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        foreach ($relative in $available) {
            $source = Join-Path $repository $relative
            $exe = Join-Path $testDir (([IO.Path]::GetFileNameWithoutExtension($relative)) + '.exe')
            $cmdPath = Join-Path $testDir ('compile-' +
                [IO.Path]::GetFileNameWithoutExtension($relative) + '.cmd')
            # cmd.exe reads this file, keeping paths with spaces quoted. Test
            # outputs stay outside Git and all failures propagate to PowerShell.
            @(
                '@echo off'
                'call "' + $vcvars + '" >nul'
                'if errorlevel 1 exit /b 1'
                'cl /nologo /W4 /WX /std:c++17 /EHsc /utf-8 /Fe:"' +
                    $exe + '" "' + $source + '"'
                'if errorlevel 1 exit /b 1'
                '"' + $exe + '"'
                'exit /b %errorlevel%'
            ) | Set-Content -LiteralPath $cmdPath -Encoding Ascii
            Write-Host "C++-Regression: $relative"
            Invoke-Native 'cmd.exe' @('/d', '/c', $cmdPath)
        }
    }
    else {
        Write-Warning ('Die Langpfad-C++-Tests befinden sich noch in einem ' +
                       'separaten Entwicklungsbranch. KEIN vollständiger ' +
                       'Salamander-Langpfadtest bestätigt.')
    }

    Write-Warning ('Die Dateisystemtests prüfen Windows/.NET und isolierte ' +
                   'C++-Funktionen. Salamanders GUI, Dateitransfers und ' +
                   'Plugins müssen zusätzlich manuell an Testdaten geprüft werden.')
}

function Build-Setups {
    param([bool]$AlreadyBuilt)
    Write-Host '=== PAKETE: 7z und Setups, Debug + Release ==='
    $packager = Join-Path $repository 'tools\release\Update-Build-Test-Package.ps1'
    $parameters = @('-NoProfile', '-File', $packager,
                    '-BuildRoot', $buildRoot, '-SkipUpdate')
    if ($AlreadyBuilt) { $parameters += '-SkipBuild' }
    Invoke-Native 'pwsh.exe' $parameters
}

function Run-Salamander {
    Write-Host "=== RUN $configuration x64 ==="
    $app = Join-Path (Get-VariantDirectory $configuration) 'salamand.exe'
    if (-not (Test-Path -LiteralPath $app -PathType Leaf)) {
        throw "salamand.exe nicht vorhanden: $app. Bitte zuerst --build ausführen."
    }
    $process = Start-Process -FilePath $app -WorkingDirectory (Split-Path -Parent $app) -PassThru
    Write-Host "Gestartet: $app (PID $($process.Id))"
}

try {
    Start-Transcript -LiteralPath $logPath -IncludeInvocationHeader -ErrorAction Stop | Out-Null
    $transcriptStarted = $true
    Write-Host "Salamander-Verwaltung – $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Repository: $repository"
    Write-Host "Log: $logPath"

    foreach ($option in $requestedActions) {
        if ($option -notin $validOptions) { throw "Unbekannter Parameter: '$option' (manage.cmd --help)" }
        [void]$requestedSet.Add($option)
    }
    if ($requestedSet.Contains('--debug') -and $requestedSet.Contains('--release')) {
        throw '--debug und --release dürfen nicht kombiniert werden.'
    }
    if ($requestedSet.Contains('--debug')) { $configuration = 'Debug' }

    if ($requestedActions.Count -eq 0 -or $requestedSet.Contains('--help') -or
        $requestedSet.Contains('-h') -or $requestedSet.Contains('/?')) {
        Write-Usage
    }
    else {
        if ($requestedSet.Contains('--all')) {
            foreach ($mode in @('--update', '--build', '--test', '--setup', '--run')) {
                [void]$requestedSet.Add($mode)
            }
        }

        . (Join-Path $repository 'tools\release\Package-Helpers.ps1')
        $buildRoot = [IO.Path]::GetFullPath($buildRoot)
        New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

        if ($requestedSet.Contains('--update')) { Update-Branch }
        if ($requestedSet.Contains('--build')) { Build-Variants }
        if ($requestedSet.Contains('--test')) { Run-Tests }
        if ($requestedSet.Contains('--test-gui')) {
            Write-Host '=== AUTOMATISIERTER SALAMANDER-GUI-LANGPFADTEST ==='
            $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
            $testedExe = Join-Path (Get-VariantDirectory $configuration) 'salamand.exe'
            Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                      '-SalamanderExe', $testedExe)
        }
        if ($requestedSet.Contains('--test-gui-manual')) {
            Write-Host '=== MANUELLER SALAMANDER-GUI-LANGPFADTEST ==='
            $testScript = Join-Path $repository 'tools\release\tests\Test-FilenamesAndPaths.ps1'
            Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $testScript, '-KeepFixture')
            Run-Salamander
            Write-Host 'Prüfe in Salamander: lange Pfade öffnen, 255-Zeichen-Dateinamen,'
            Write-Host 'Unicode-Namen, F5 Kopieren, F6 Verschieben, Umbenennen, Löschen'
            Write-Host 'nur in der Teststruktur, Suchen, Viewer und Plugins.'
            Write-Host 'Die Testdateien werden bewusst NICHT automatisch entfernt.'
            Write-Warning 'Die GUI-Prüfung ist manuell; diese Ausgabe bescheinigt KEIN Bestehen.'
        }
        if ($requestedSet.Contains('--setup')) {
            Build-Setups -AlreadyBuilt:$requestedSet.Contains('--build')
        }
        if ($requestedSet.Contains('--run')) { Run-Salamander }

        Write-Host '=== Alle angeforderten Schritte erfolgreich abgeschlossen. ==='
    }
}
catch {
    $exitCode = 1
    Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($transcriptStarted) {
        Write-Host "Protokoll: $logPath"
        Write-Host 'Die gesamte protokollierte Ausgabe wird nun in die Zwischenablage kopiert.'
        Stop-Transcript | Out-Null
        try {
            $completeOutput = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
            Set-Clipboard -Value $completeOutput -ErrorAction Stop
        }
        catch {
            # Preserve build/test exit codes; the log is still available.
            [Console]::Error.WriteLine(
                "WARNUNG: Clipboard-Kopie nicht möglich. Log: $logPath. $($_.Exception.Message)")
        }
    }
}
exit $exitCode
