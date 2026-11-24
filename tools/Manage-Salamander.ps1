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
$buildRoot = Join-Path $repository '.Build'
$configuration = 'Release'
$validOptions = @('--update', '--build', '--test', '--setup', '--run',
                  '--test-gui-large-unicode-copy', '--test-gui-legacy-find', '--test-clipboard-snapshot',
                  '--debug', '--release', '--all', '--build-delta', '--build-clean', '--test-all', '--test-gui', '--test-gui-max-path', '--test-gui-baseline', '--test-gui-operations-baseline', '--test-gui-names', '--test-gui-unicode-rename', '--test-gui-unicode-recycle', '--test-gui-unicode-permanent-delete', '--test-gui-unicode-parent', '--test-recycle-restore', '--test-plugin-exports', '--test-plugin-load', '--test-gui-row-identities', '--test-gui-unicode-multiselect', '--test-gui-unicode-directory-rename', '--test-gui-unicode-transfer', '--test-gui-unicode-transfer-collision', '--test-gui-bestfit', '--test-gui-name-collisions', '--test-gui-unsafe-unicode-operations', '--test-gui-unicode-find', '--test-gui-manual', '--test-gui-temp-delete', '--test-pictview', '--test-pictview-window', '--test-pictview-host', '--diagnose-gui', '--help', '-h', '/?')
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
  manage.cmd --build        Debug und Release x64 vollstaendig neu bauen (MSBuild Rebuild)
  manage.cmd --build-delta  Schneller inkrementeller Build (MSBuild Build)
  manage.cmd --build-clean  Output-Ordner loeschen und vollstaendig neu bauen
  manage.cmd --test         Windows-Dateisystem-/Namens-Tests und Projekt-Regressionstests
  manage.cmd --test-all     Alle automatisierten Tests: --test und sämtliche GUI-Modi
                            Unabhängige Fehler sammeln, JSON-Bericht schreiben; Exitcode 1 bei Fehler/SKIP
                            (Release und Debug x64; --release/--debug begrenzt die GUI-Modi)
                            Legacy-Suche und große Unicode-Kopien: isolierte Testbuilds im Worktree
  manage.cmd --test-gui-large-unicode-copy  32-MiB-Kopie, Pause/Abbruch, Zielkollision und gesperrte Quelle
  manage.cmd --test-gui-legacy-find  Legacy-Suche (Strg+F), Filter, Unicode, Focus File und Viewer
  manage.cmd --test-clipboard-snapshot  Native Zwischenablage-Sicherung/-Wiederherstellung prüfen
  manage.cmd --setup        Debug- und Release-7z plus Inno-Setup-Pakete erzeugen
  manage.cmd --test-pictview  WIC-Decoder (13 Endungen), Langpfade, Export, Clipboard: MSVC x86/x64
  manage.cmd --test-pictview-window  Zusätzlich echten WIC-Viewer-HWND testen
                                 (unverriegelter Windows-Desktop erforderlich)
  manage.cmd --test-pictview-host  F3-Plugin-Hosttest: BMP, PNG, JPEG, GIF, TIFF, ICO
                                 (opt-in, vorher andere Salamander-Instanzen schließen)
  manage.cmd --test-gui     Automatisierter GUI-Test: lange Pfade, Unicode-Dateien, F5
  manage.cmd --test-gui-max-path  Reale GUI-Prüfung nahe 32767: 32700 Gesamt- und 255 UTF-16-Namenseinheiten
  manage.cmd --test-gui-baseline  GUI-Automation zunächst mit kurzen ASCII-Pfaden prüfen
  manage.cmd --test-gui-operations-baseline  F2/F5/F6/F8 auf sicherer ASCII-Teststruktur prüfen
  manage.cmd --test-gui-names  Unicode-Dateinamen in der GUI bei kurzen Pfaden prüfen
  manage.cmd --test-gui-unicode-rename  Echte UTF-16-F2-Umbenennung im Dateipanel prüfen
  manage.cmd --test-gui-unicode-recycle  F8-Dateioperation mit UTF-16 und Windows-Papierkorb prüfen
  manage.cmd --test-gui-unicode-permanent-delete  Dauerhaftes F8 für eindeutig erkannte UTF-16-Datei prüfen
  manage.cmd --test-gui-unicode-parent  F5/F6 in kurzen Unicode-Elternverzeichnissen prüfen
  manage.cmd --test-recycle-restore  Opt-in: echten Unicode-F8-Papierkorb und verlustfreie Wiederherstellung prüfen
  manage.cmd --test-plugin-exports  x64-Debug/Release-Plugins auf PE-Exports und SDK-ABI prüfen (nur lesen)
  manage.cmd --test-plugin-load  Opt-in: reale Plugin-Manager-Initialisierung für vier Plugins (lädt alle installierten)
  manage.cmd --test-gui-unicode-transfer  UTF-16-F5/F6 mit einem Dateieintrag prüfen
  manage.cmd --test-gui-unicode-transfer-collision  UTF-16-F5/F6-Zielkollision ohne Überschreiben prüfen
  manage.cmd --test-gui-bestfit  Best-Fit-ANSI-Namensverfälschung ohne Fragezeichen prüfen
  manage.cmd --test-gui-name-collisions  Gleiche ANSI-Aliase mit getrennten UTF-16-Identitäten prüfen
  manage.cmd --test-gui-row-identities  UTF-16-Identität jedes Panel-Eintrags prüfen
  manage.cmd --test-gui-unicode-multiselect  F5/F6 für zwei markierte Unicode-/ASCII-Dateien prüfen
  manage.cmd --test-gui-unicode-directory-rename  F2-Umbenennung eines Unicode-Verzeichnisses prüfen
  manage.cmd --test-gui-unsafe-unicode-operations  F2/F5/F6/F8 mit nicht darstellbaren Unicode-Namen sicher abweisen
  manage.cmd --test-gui-unicode-find  Neues F2-Unicode-Suchfenster: Suche, Pfade, Copy/Move/Rename, Kollisionsschutz
  manage.cmd --test-gui-temp-delete  GUI-Löschpfad via F8-Handler (CM_DELETEFILES), ohne Desktop-Fokus
  manage.cmd --diagnose-gui  Einzeltest vs. --test-all-Vorlauf vergleichen (Release x64);
                            --debug waehlt Debug x64; optional lokale Hang-Dumps
  manage.cmd --test-gui-manual  Testdaten behalten und Salamander zum manuellen Test starten
  manage.cmd --run          Release-Version starten
  manage.cmd --run --debug  Debug-Version starten
  manage.cmd --all          Update, Build, Test, Setup und Release-Start
  manage.cmd --help         Diese Hilfe anzeigen

Mehrere Aktionen kombinieren:
  manage.cmd --update --build --test-all --setup
  manage.cmd --build --test --run
  manage.cmd --build --test-all  Vollständige Suite auf beiden x64-Binaries
  manage.cmd --test-pictview  WIC-Tests lokal mit x86 und x64 kompilieren und ausführen
  manage.cmd --test-pictview-window  Zusätzlich einen echten WIC-Viewer öffnen/schließen
  manage.cmd --test-pictview-host  Sechs Bildformate mit echtem PictView-F3 prüfen (opt-in)

Voraussetzungen:
  Windows 11, PowerShell 7.4+, VS 2026 mit MSVC v143/ATL, Windows SDK.
  Für Build: HTML Help Workshop (hhc.exe).
  Für Setup: 7-Zip (7z.exe), Inno Setup (ISCC.exe), Debug-UCRT-Komponenten.

Build-Ausgabe:  <Repository>\.Build\salamander\Debug_x64 und Release_x64
Pakete:        <Repository>\.Build\dist
Protokolle:    <Repository>\.Build\logs

Die gesamte Ausgabe einschließlich Fehlern wird zum Schluss in die
Windows-Zwischenablage kopiert. Bei einem Testfehler wird kein Setup/Run
mehr gestartet; der Exitcode ist ungleich 0.
'@ | Write-Host
}

# Select all existing and future automated GUI options from the CLI
# registry. Manual GUI tests retain test fixtures and require user input,
# so they are deliberately excluded from an unattended test suite.
function Expand-AutomatedTestActions {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$RequestedSet,
        [Parameter(Mandatory)][string[]]$AvailableOptions
    )
    if (-not $RequestedSet.Contains('--test-all')) { return }

    [void]$RequestedSet.Add('--test')
    [void]$RequestedSet.Add('--test-pictview')
    [void]$RequestedSet.Add('--test-pictview-window')
    [void]$RequestedSet.Add('--test-plugin-exports')
    [void]$RequestedSet.Add('--test-clipboard-snapshot')
    foreach ($option in $AvailableOptions) {
        if ($option.StartsWith('--test-gui', [StringComparison]::OrdinalIgnoreCase) -and
            $option -ne '--test-gui-manual') {
            [void]$RequestedSet.Add($option)
        }
    }
}

# --test-all exercises both build variants unless the user explicitly
# selects one. Ordinary GUI switches keep their existing Release default.
function Get-AutomatedGuiModes {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$RequestedSet
    )
    if ($RequestedSet.Contains('--test-all') -and
        -not $RequestedSet.Contains('--debug') -and
        -not $RequestedSet.Contains('--release')) {
        return @('Release', 'Debug')
    }
    if ($RequestedSet.Contains('--debug')) { return 'Debug' }
    return 'Release'
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @()
    )
    # Native child processes (especially nested pwsh.exe) can write directly
    # to the host without their output being captured by Start-Transcript.
    # Route both stdout and stderr back through this PowerShell host, keeping
    # each line visible live AND in the management log. Do not mask exit codes.
    & $Command @Arguments 2>&1 | ForEach-Object {
        Write-Host ([string]$_)
    }
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
                          'tools/release/Test-RunCollection.ps1',
                          'tools/release/Package-Helpers.ps1',
                          'tools/release/Build-Helpers.ps1',
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
    param([ValidateSet('Delta', 'Rebuild', 'Clean')][string]$Mode = 'Rebuild')
    $vs = Get-VisualStudio2026
    $msbuild = Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
    if (-not (Test-Path -LiteralPath $msbuild -PathType Leaf)) {
        throw "MSBuild.exe nicht gefunden: $msbuild"
    }
    $solution = Join-Path $repository 'src\vcxproj\salamand.sln'
    Invoke-SalamanderBuild -Msbuild $msbuild -Solution $solution -Repository $repository `
        -BuildRoot $buildRoot -Mode $Mode -Invoke {
            param($Executable, $Arguments)
            Invoke-Native $Executable $Arguments
        }
    foreach ($variant in @('Debug', 'Release')) {
        $binary = Join-Path (Get-VariantDirectory $variant) 'salamand.exe'
        $productVersionTest = Join-Path $repository 'tools\release\tests\Test-ProductVersion.ps1'
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $productVersionTest,
                                  '-BinaryPath', $binary)
    }
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $hhc = Find-Executable 'hhc.exe' @((Join-Path $pf86 'HTML Help Workshop\hhc.exe'))
    Build-CompiledHelp -Repository $repository -HhcExe $hhc -OutputDirectories @(
        (Get-VariantDirectory 'Debug'), (Get-VariantDirectory 'Release')
    ) -Incremental:($Mode -eq 'Delta')
    Write-Host "Build ($Mode) und HTML-Hilfe abgeschlossen."
}

function Run-Tests {
    Write-Host '=== TESTS ==='

    # Detect every PowerShell parse error before executing an otherwise
    # healthy first test. This also guards files not yet reached by the suite.
    $syntaxPreflight = Join-Path $repository 'tools\release\tests\Test-PowerShellSyntax.ps1'
    Invoke-TestCase -Name 'Test-PowerShellSyntax.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $syntaxPreflight)
    }

    # The collector itself is regression-tested before any other test step.
    $testCollector = Join-Path $repository 'tools\release\tests\Test-Manage-TestAggregation.ps1'
    Invoke-TestCase -Name 'Test-Manage-TestAggregation.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $testCollector)
    }

    # Keep the versioned requirements and cross-session handoff discoverable.
    # This is a structural documentation regression, not proof of a green release.
    $continuityContract = Join-Path $repository 'tools\release\tests\Test-DevelopmentContinuity.ps1'
    Invoke-TestCase -Name 'Test-DevelopmentContinuity.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $continuityContract)
    }

    # This process runs the rest of the suite via nested pwsh.exe. Verify
    # that child stdout/stderr reach the transcript and failures are fatal.
    $nativeOutputContract = Join-Path $repository 'tools\release\tests\Test-Manage-Native-Output.ps1'
    Invoke-TestCase -Name 'Test-Manage-Native-Output.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $nativeOutputContract)
    }

    $productVersionTest = Join-Path $repository 'tools\release\tests\Test-ProductVersion.ps1'
    Invoke-TestCase -Name 'Test-ProductVersion.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $productVersionTest)
    }

    $productionBinaryContract = Join-Path $repository 'tools\release\tests\Test-ProductionBinary-Contract.ps1'
    Invoke-TestCase -Name 'Test-ProductionBinary-Contract.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $productionBinaryContract)
    }

    $buildModesTest = Join-Path $repository 'tools\release\tests\Test-BuildModes.ps1'
    Invoke-TestCase -Name 'Test-BuildModes.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $buildModesTest)
    }

    $vsDiscoveryTest = Join-Path $repository 'tools\release\tests\Test-VS2026Discovery.ps1'
    Invoke-TestCase -Name 'Test-VS2026Discovery.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $vsDiscoveryTest)
    }

    $pictviewContract = Join-Path $repository 'tools\release\tests\Test-PictView-Management.ps1'
    Invoke-TestCase -Name 'Test-PictView-Management.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $pictviewContract)
    }

    # Guard the active VS 2026 solution metadata and every referenced C++
    # project against accidental reintroduction of unsupported old toolsets.
    $vs2026Contract = Join-Path $repository 'tools\release\tests\Test-VS2026-ProjectMetadata.ps1'
    Invoke-TestCase -Name 'Test-VS2026-ProjectMetadata.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $vs2026Contract)
    }

    # Guard the original, fully featured Ctrl+F dialog while its worker and
    # result identities are migrated away from ANSI/MAX_PATH.
    # A0-01: protect current Win32 dialog and keyboard resource IDs
    # against silent removal. This is not a 5.0 visual parity test.
    $legacyUiInventoryTest = Join-Path $repository 'tools\release\tests\Test-LegacyUiSurfaceInventory.ps1'
    Invoke-TestCase -Name 'Test-LegacyUiSurfaceInventory.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $legacyUiInventoryTest)
    }

    $legacyFindContract = Join-Path $repository 'tools\release\tests\Test-LegacyFind-UiContract.ps1'
    Invoke-TestCase -Name 'Test-LegacyFind-UiContract.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $legacyFindContract)
    }

    # A0/UP-01: fail when a plug-in source/project silently disappears and
    # exercise the read-only inventory's missing/rogue-module cases.
    # MGMT-03: do not silently remove an A0-A7 test gap or mark it passed
    # without a specific tested commit and execution log.
    $gapTrackerContract = Join-Path $repository 'tools\release\tests\Test-TestGapTracker.ps1'
    Invoke-TestCase -Name 'Test-TestGapTracker.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $gapTrackerContract)
    }

    $pluginCoverageInventory = Join-Path $repository 'tools\release\tests\Test-PluginCoverageInventory.ps1'
    Invoke-TestCase -Name 'Test-PluginCoverageInventory.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $pluginCoverageInventory)
    }

    # PR14: verify standalone discovery of all built SPL module identities.
    $pluginInventoryTest = Join-Path $repository 'tools\release\tests\Test-PluginBinary-Inventory.ps1'
    Invoke-TestCase -Name 'Test-PluginBinary-Inventory.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $pluginInventoryTest)
    }

    $pluginModuleContract = Join-Path $repository 'tools\release\tests\Test-PluginModulePaths-Contract.ps1'
    Invoke-TestCase -Name 'Test-PluginModulePaths-Contract.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $pluginModuleContract)
    }

    # A0-02: test real HKCU semantics only in a freshly owned GUID
    # namespace. Live 5.0 and 5.2 registry roots are never accessed.
    $legacyConfigCanary = Join-Path $repository 'tools\release\tests\Test-LegacyConfig-Canary.ps1'
    Invoke-TestCase -Name 'Test-LegacyConfig-Canary.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $legacyConfigCanary)
    }

    $guiConfigContract = Join-Path $repository 'tools\release\tests\Test-GuiConfig-Isolation.ps1'
    Invoke-TestCase -Name 'Test-GuiConfig-Isolation.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $guiConfigContract)
    }

    $handlesLoaderLockContract = Join-Path $repository 'tools\release\tests\Test-HandlesLoaderLock-Contract.ps1'
    Invoke-TestCase -Name 'Test-HandlesLoaderLock-Contract.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $handlesLoaderLockContract)
    }

    $guiDriverContract = Join-Path $repository 'tools\release\tests\Test-GuiDriver-Contract.ps1'
    Invoke-TestCase -Name 'Test-GuiDriver-Contract.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $guiDriverContract)
    }

    $werContract = Join-Path $repository 'tools\release\tests\Test-WerCrashReporting-Contract.ps1'
    Invoke-TestCase -Name 'Test-WerCrashReporting-Contract.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $werContract)
    }

    $unicodeCopyContract = Join-Path $repository 'tools\release\tests\Test-Manage-UnicodeCopy.ps1'
    Invoke-TestCase -Name 'Test-Manage-UnicodeCopy.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $unicodeCopyContract)
    }

    $guiReliabilityContract = Join-Path $repository 'tools\release\tests\Test-GuiReliability-Contract.ps1'
    Invoke-TestCase -Name 'Test-GuiReliability-Contract.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $guiReliabilityContract)
    }

    # Test-Package-Helpers.ps1 invokes the independent release/GUI contract
    # regressions, including the cross-process clipboard test in STA.
    # Running them separately here duplicates work and test side effects.
    $regression = Join-Path $repository 'tools\release\tests\Test-Package-Helpers.ps1'
    Invoke-TestCase -Name 'Test-Package-Helpers.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $regression)
    }

    $filesystem = Join-Path $repository 'tools\release\tests\Test-FilenamesAndPaths.ps1'
    Invoke-TestCase -Name 'Test-FilenamesAndPaths.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $filesystem)
    }

    # Added by the long-path migration branches. Do not report full support
    # when the tests (or the production code using them) are absent.
    $cppTests = @(
        'tools\tests\about_build_info.cpp',
        'tools\tests\quicksearch_bounds.cpp',
        'tools\tests\utf16_disk_path.cpp',
        'tools\tests\legacy_disk_name_safety.cpp',
        'tools\tests\legacy_default_directory_registry.cpp',
        'tools\tests\saved_panel_path_registry.cpp',
        'tools\tests\win32_unicode_primary_panel.cpp',
        'tools\tests\unicode_directory_panel_alias.cpp',
        'tools\tests\win32_unicode_rename_dialog.cpp',
        'tools\tests\win32_unicode_recycle.cpp',
        'tools\tests\shell_file_operation_name_list.cpp',
        'tools\tests\long_path_io.cpp',
        'tools\tests\unicode_directory_delete.cpp',
        'tools\tests\legacy_find_utf16_identity.cpp',
        'tools\tests\plugin_module_path.cpp',
        'tools\tests\isolated_test_configuration.cpp',
        'tools\tests\worker_copy_paths.cpp',
        'tools\tests\worker_copy_io.cpp',
        'tools\tests\win32_utf16_static_text.cpp',
        'tools\tests\unicode_find.cpp',
        'tools\tests\win32_max_path.cpp',
        'tools\tests\bug_report_path.cpp'
    )
    $available = @($cppTests | Where-Object {
        Test-Path -LiteralPath (Join-Path $repository $_) -PathType Leaf
    })
    if ($available.Count -gt 0) {
        $nativePrerequisites = @{ Vcvars = $null }
        Invoke-TestCase -Name 'Native C++ prerequisites' -BlocksGui -Action {
            $vs = Get-VisualStudio2026
            $candidate = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                throw "MSVC x64-Umgebung nicht gefunden: $candidate"
            }
            New-Item -ItemType Directory -Path (Join-Path $buildRoot 'tests') -Force | Out-Null
            $nativePrerequisites.Vcvars = $candidate
        }
        $vcvars = $nativePrerequisites.Vcvars
        $testDir = Join-Path $buildRoot 'tests'
        if ($null -ne $vcvars) {
            foreach ($relative in $available) {
                Invoke-TestCase -Name "Native C++: $relative" -Action {
                $source = Join-Path $repository $relative
                $testName = [IO.Path]::GetFileNameWithoutExtension($relative)
                $exe = Join-Path $testDir ($testName + '.exe')
                $object = Join-Path $testDir ($testName + '.obj')
                $cmdPath = Join-Path $testDir ('compile-' + $testName + '.cmd')
                # The shell and Unicode dialog require explicit platform libraries.
                # Keep other standalone tests independent of these dependencies.
                $platformLibraries = switch ($testName) {
                    'legacy_default_directory_registry' { ' advapi32.lib' }
                    'saved_panel_path_registry' { ' advapi32.lib' }
                    'win32_unicode_rename_dialog' { ' user32.lib' }
                    'win32_unicode_recycle' { ' ole32.lib shell32.lib uuid.lib' }
                    default { '' }
                }
                # cmd.exe reads this file, keeping paths with spaces quoted. Test
                # outputs stay outside Git and all failures propagate to PowerShell.
                @(
                    '@echo off'
                    'call "' + $vcvars + '" >nul'
                    'if errorlevel 1 exit /b 1'
                    'cl /nologo /W4 /WX /std:c++17 /EHsc /utf-8 /Fo:"' +
                        $object + '" /Fe:"' + $exe + '" "' + $source + '"' + $platformLibraries
                    'if errorlevel 1 exit /b 1'
                    '"' + $exe + '"'
                    'exit /b %errorlevel%'
                ) | Set-Content -LiteralPath $cmdPath -Encoding Ascii
                Write-Host "C++-Regression: $relative"
                Invoke-Native 'cmd.exe' @('/d', '/c', $cmdPath)
                }
            }
        }
        else {
            foreach ($relative in $available) {
                Skip-TestCase -Name "Native C++: $relative" -Reason 'MSVC prerequisites unavailable'
            }
        }
    }
    else {
        if ($script:CollectTestFailures) {
            Invoke-TestCase -Name 'Native C++ source inventory' -Action {
                throw 'No native C++ regressions found; required suite cannot be certified.'
            }
        }
        else {
            Write-Warning ('Die Langpfad-C++-Tests befinden sich noch in einem ' +
                           'separaten Entwicklungsbranch. KEIN vollständiger ' +
                           'Salamander-Langpfadtest bestätigt.')
        }
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
    # Record the source checkout for release test provenance. Pre-existing
    # binaries may have been built from a different commit.
    $gitExecutable = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $gitExecutable) {
        try {
            $headLines = @(& $gitExecutable.Source -C $repository rev-parse --verify HEAD 2>$null)
            if ($LASTEXITCODE -eq 0 -and $headLines.Count -eq 1 -and
                $headLines[0] -match '^[0-9a-fA-F]{40}$') {
                Write-Host "Source checkout git HEAD: $($headLines[0])"
                $trackedChanges = @(& $gitExecutable.Source -C $repository status --porcelain --untracked-files=no 2>$null)
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Source tracked working tree clean: $($trackedChanges.Count -eq 0)"
                }
                else { Write-Warning 'Unable to determine source working tree cleanliness.' }
            }
            else { Write-Warning 'Source git HEAD unavailable (non-Git source directory?).' }
        }
        catch { Write-Warning 'Could not record optional source git revision.' }
    }
    else { Write-Warning 'Git not installed; source SHA cannot be recorded.' }
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

        Expand-AutomatedTestActions -RequestedSet $requestedSet -AvailableOptions $validOptions
        if (@($requestedSet | Where-Object { $_ -like '--test*' }).Count -gt 0) {
            . (Join-Path $repository 'tools\release\Test-RunCollection.ps1')
            Initialize-TestRun -CollectFailures:($requestedSet.Contains('--test-all'))
        }

        if ($requestedSet.Contains('--diagnose-gui')) {
            $allowedDiagnosticOptions = @('--diagnose-gui', '--release', '--debug')
            foreach ($action in $requestedSet) {
                if ($action -notin $allowedDiagnosticOptions) {
                    throw '--diagnose-gui kann nur mit --release oder --debug kombiniert werden.'
                }
            }
        }

        . (Join-Path $repository 'tools\release\Package-Helpers.ps1')
        . (Join-Path $repository 'tools\release\Build-Helpers.ps1')
        $null = Get-BuildMode -RequestedSet $requestedSet
        $buildRoot = [IO.Path]::GetFullPath($buildRoot)
        New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

        if ($requestedSet.Contains('--update')) { Update-Branch }
        $buildMode = Get-BuildMode -RequestedSet $requestedSet
        if ($buildMode -ne 'None') { Build-Variants -Mode $buildMode }
        if ($requestedSet.Contains('--test')) { Run-Tests }
        if ($requestedSet.Contains('--test-clipboard-snapshot')) {
            $snapshotTest = Join-Path $repository 'tools\release\tests\Test-ClipboardSnapshot.ps1'
            Invoke-TestCase -Name 'Clipboard snapshot' -RequiresGuiSafety -Action {
                Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $snapshotTest)
            }
        }
        # Separate acceptance gate: these built plug-ins are inspected but
        # never loaded, and missing artifacts must fail rather than skip.
        if ($requestedSet.Contains('--test-plugin-exports')) {
            $pluginContract = Join-Path $repository 'tools\release\tests\Test-PluginBinary-Contract.ps1'
            foreach ($pluginMode in @('Release', 'Debug')) {
                if ($requestedSet.Contains('--release') -and $pluginMode -ne 'Release') { continue }
                if ($requestedSet.Contains('--debug') -and $pluginMode -ne 'Debug') { continue }
                Write-Host "=== BUILT PLUGIN ABI CONTRACT: $pluginMode x64 ==="
                Invoke-TestCase -Name "Plugin ABI: $pluginMode x64" -Action {
                    $vs = Get-VisualStudio2026
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $pluginContract,
                                              '-BuildDirectory', (Get-VariantDirectory $pluginMode),
                                              '-VisualStudioRoot', $vs)
                }
            }
        }
        # Explicit opt-in: this test executes a shell restore verb on its
        # uniquely identified GUID-scoped fixture. Never included in --test-all.
        if ($requestedSet.Contains('--test-recycle-restore')) {
            Write-Host '=== OPT-IN: UNICODE F8 PAPIERKORB-WIEDERHERSTELLUNG ==='
            $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
            $testedExe = Join-Path (Get-VariantDirectory $configuration) 'salamand.exe'
            Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                      '-SalamanderExe', $testedExe,
                                      '-ShortUnicodeRecycleOnly', '-VerifyRecycleRestore')
        }
        # Explicit opt-in: the Salamander plug-in manager's Test All action
        # initializes every installed plug-in, including third-party modules.
        # This must never run implicitly as part of --test-all.
        if ($requestedSet.Contains('--test-plugin-load')) {
            Write-Host '=== OPT-IN: ECHTE PLUGIN-MANAGER-INITIALISIERUNG ==='
            . (Join-Path $repository 'tools\release\Plugin-Runtime-Prerequisites.ps1')
            $pluginBuild = Get-VariantDirectory $configuration
            $testedExe = Join-Path $pluginBuild 'salamand.exe'
            $pictviewFile = Join-Path $pluginBuild 'plugins\pictview\pictview.spl'
            $verifiedWic = $false
            if (Test-Path -LiteralPath $pictviewFile -PathType Leaf) {
                # PR #8 previously refused global Test All because the old
                # PVW32 converter sidecars were absent. The new WIC viewer
                # needs neither file, but only a *successful real-host smoke*
                # permits bypassing that conservative legacy prerequisite.
                $hostGui = Join-Path $repository 'tools\release\tests\Test-PictView-Host.ps1'
                Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $hostGui,
                                           '-SalamanderExe', $testedExe)
                $verifiedWic = $true
            }
            $missingPictView = @(
                Get-MissingPictViewRuntimeFiles -BuildDirectory $pluginBuild -WicViewerVerified:$verifiedWic
            )
            if ($missingPictView.Count -gt 0) {
                throw ("The optional PictView runtime is incomplete: " +
                       ($missingPictView -join '; ') +
                       ". Do not load unknown converter binaries. Test target plugins individually.")
            }
            $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
            $pluginLoadArgs = @('-Sta', '-NoProfile', '-File', $guiTest,
                                '-SalamanderExe', $testedExe, '-PluginLoadSmokeOnly')
            if ($verifiedWic) { $pluginLoadArgs += '-WicViewerVerified' }
            Invoke-Native 'pwsh.exe' $pluginLoadArgs
        }
        if ($requestedSet.Contains('--test-pictview') -or
            $requestedSet.Contains('--test-pictview-window')) {
            $pictviewRunner = Join-Path $repository 'tools\release\tests\Invoke-PictViewTests.ps1'
            $pictviewArgs = @('-NoProfile', '-File', $pictviewRunner,
                              '-Repository', $repository)
            if ($requestedSet.Contains('--test-pictview-window')) {
                $pictviewArgs += '-InteractiveWindowTests'
            }
            if ($requestedSet.Contains('--test-all')) {
                Invoke-TestCase -Name 'PictView WIC headless' -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $pictviewRunner,
                                               '-Repository', $repository)
                }
                if ($requestedSet.Contains('--test-pictview-window')) {
                    Invoke-TestCase -Name 'PictView interactive window' -RequiresGuiSafety -Action {
                        Invoke-Native 'pwsh.exe' $pictviewArgs
                    }
                }
            }
            else {
                Invoke-Native 'pwsh.exe' $pictviewArgs
            }
        }
        if ($requestedSet.Contains('--test-pictview-host')) {
            # Explicit interactive opt-in, never part of --test-all.
            # Each supported format gets a fresh verified child process.
            $hostGui = Join-Path $repository 'tools\release\tests\Test-PictView-Host.ps1'
            $targetExe = Join-Path (Get-VariantDirectory $configuration) 'salamand.exe'
            foreach ($imageFormat in @('Bmp','Png','Jpeg','Gif','Tiff','Ico')) {
                Write-Host "=== PICTVIEW HOST F3: $imageFormat ==="
                Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $hostGui,
                                           '-SalamanderExe', $targetExe,
                                           '-ImageFormat', $imageFormat)
            }
        }
        $automatedGuiModes = @(Get-AutomatedGuiModes -RequestedSet $requestedSet)
        foreach ($guiMode in $automatedGuiModes) {
            if ($requestedSet.Contains('--test-gui-legacy-find')) {
                $legacyFindTest = Join-Path $repository 'tools\release\tests\Invoke-IsolatedLegacyFind.ps1'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-legacy-find" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $legacyFindTest,
                                              '-Configuration', $guiMode)
                }
            }
            if ($requestedSet.Contains('--test-gui-large-unicode-copy')) {
                $largeCopyTest = Join-Path $repository 'tools\release\tests\Invoke-IsolatedUnicodeCopy.ps1'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-large-unicode-copy" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $largeCopyTest,
                                              '-Configuration', $guiMode)
                }
            }
            if ($requestedSet.Contains('--test-gui-temp-delete')) {
                Write-Host '=== GUI F8 DELETE HANDLER (FOREGROUND-INDEPENDENT CM_DELETEFILES) ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-temp-delete" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-TemporaryDirectoryDeletionOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-baseline')) {
                Write-Host '=== SALAMANDER-GUI-TESTTREIBER, KURZPFAD-BASIS ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-baseline" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-BaselineOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-operations-baseline')) {
                Write-Host '=== SALAMANDER-GUI-OPERATIONEN, ASCII-BASIS ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-operations-baseline" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortOperationsOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unsafe-unicode-operations')) {
                Write-Host '=== SALAMANDER-GUI-SCHUTZ F2/F5/F6/F8 BEI UNICODE ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unsafe-unicode-operations" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeUnsafeOperationsOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-transfer-collision')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE F5/F6 OVERWRITE PROTECTION ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-transfer-collision" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeTransferCollisionOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-recycle')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE F8 RECYCLE BIN ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-recycle" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeRecycleOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-permanent-delete')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE F8 PERMANENT DELETE ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-permanent-delete" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodePermanentDeleteOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-parent')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE PARENT F5/F6 ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-parent" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeParentOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-transfer')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE F5/F6 TRANSFER ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-transfer" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeTransferOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-rename')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE F2 RENAME ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-rename" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeRenameOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-bestfit')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE-ANSI-BEST-FIT ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-bestfit" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeBestFitOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-directory-rename')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE DIRECTORY F2 ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-directory-rename" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeDirectoryRenameOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-multiselect')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE MULTI-SELECTION ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-multiselect" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeMultiSelectOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-row-identities')) {
                Write-Host '=== SALAMANDER-GUI-WIDE ROW IDENTITIES ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-row-identities" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeRowIdentityOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-name-collisions')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE-NAMENSKOLLISIONEN ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-name-collisions" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeCollisionOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-names')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE-NAMEN, KURZER PFAD ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-names" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-ShortUnicodeOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-unicode-find')) {
                Write-Host '=== SALAMANDER-GUI-UNICODE FIND F2 ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-unicode-find" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-UnicodeFindOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui-max-path')) {
                Write-Host '=== SALAMANDER-GUI-GRENZWERTTEST, 32700 UTF-16-PFADE ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-max-path" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe, '-MaximumPathOnly')
                }
            }
            if ($requestedSet.Contains('--test-gui')) {
                Write-Host '=== AUTOMATISIERTER SALAMANDER-GUI-LANGPFADTEST ==='
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                Invoke-TestCase -Name "GUI $guiMode --test-gui" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe)
                }
            }
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
        # Explicit, diagnostic-only: compare identical F8 GUI runs with and
        # without the non-GUI --test-all prelude. Keep this out of --test-all,
        # which must not recursively invoke its own management entry point.
        if ($requestedSet.Contains('--diagnose-gui')) {
            $diagnostic = Join-Path $repository 'tools\release\tests\Invoke-GuiReliability.ps1'
            Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $diagnostic,
                                      '-Configuration', $configuration,
                                      '-CaptureHangDump')
        }
        # Always publish every independent outcome before packaging or starting the app.
        # A failed/blocked --test-all must never permit later release actions.
        if ($requestedSet.Contains('--test-all')) { Complete-TestRun -LogPath $logPath }
        if ($requestedSet.Contains('--setup')) {
            Build-Setups -AlreadyBuilt:($buildMode -ne 'None')
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
        # Nested GUI A/B tests must not publish their entire management
        # transcript to the global clipboard between comparisons. The outer
        # management invocation retains the established default behavior.
        if ($env:OPENSAL_MANAGE_SKIP_CLIPBOARD -eq '1') {
            Write-Host 'Diagnostic child: clipboard copy skipped; full log retained on disk.'
        }
        else {
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
}
exit $exitCode
