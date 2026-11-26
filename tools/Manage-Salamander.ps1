#requires -Version 7.4
# SPDX-FileCopyrightText: 2026 Open Salamander Authors
# SPDX-License-Identifier: GPL-2.0-or-later

# Command-line entry: manage.cmd --update --build --test --setup --run
# Keep the tool native to PowerShell/Windows; all output is transcript-logged.
$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$requestedActions = @($args)
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$buildRoot = Join-Path $repository '.Build'
$configuration = 'Release'
$validOptions = @('--update', '--build', '--test', '--setup', '--run',
                  '--test-gui-large-unicode-copy', '--test-gui-large-unicode-parent-copy', '--test-gui-long-history', '--test-gui-long-clipboard', '--test-gui-viewer-reliability', '--test-gui-legacy-find', '--test-clipboard-snapshot',
                  '--test-legacy-find-efs', '--test-legacy-find-near-limit', '--test-wer-build',
                  '--debug', '--release', '--all', '--build-delta', '--build-clean', '--test-all', '--test-gui', '--test-gui-max-path', '--test-gui-baseline', '--test-gui-operations-baseline', '--test-gui-names', '--test-gui-unicode-rename', '--test-gui-unicode-recycle', '--test-gui-unicode-permanent-delete', '--test-gui-unicode-parent', '--test-recycle-restore', '--test-plugin-exports', '--test-zip-sfx', '--test-gui-zip-host', '--test-gui-zip-mutation', '--test-gui-7zip-host', '--test-gui-renamer', '--test-plugin-renamer', '--test-plugin-renamer-native', '--test-plugin-zip', '--test-plugin-7z', '--test-plugin-load', '--test-gui-row-identities', '--test-gui-unicode-multiselect', '--test-gui-unicode-directory-rename', '--test-gui-unicode-transfer', '--test-gui-unicode-transfer-collision', '--test-gui-bestfit', '--test-gui-name-collisions', '--test-gui-unsafe-unicode-operations', '--test-gui-unicode-find', '--test-gui-manual', '--test-gui-temp-delete', '--test-pictview', '--test-pictview-window', '--test-pictview-host', '--test-plugin-pictview', '--test-plugin-pictview-unicode', '--diagnose-gui', '--help', '-h', '/?')
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
  manage.cmd --test-all     Alle registrierten automatischen Standardtests; Opt-ins als begründete SKIPs
  manage.cmd --test-zip-sfx  Store/Deflate, ohne/mit ZipCrypto, beide Buildvarianten (7-Zip, Windows-Desktop; Passwort automatisch)
  manage.cmd --test-gui-zip-host  ZIP-Archivpanel und Deflate-Extraktion ohne/mit ZipCrypto (7-Zip, Windows-Desktop)
  manage.cmd --test-gui-zip-mutation  ZIP erstellen, hinzufügen, ersetzen, löschen (7-Zip, Windows-Desktop)
  manage.cmd --test-plugin-zip  Alle vorhandenen ZIP-SFX-/Host-/Mutationstests
  manage.cmd --test-plugin-7z  7-Zip-Host: selektives Entpacken und Abbruch (7-Zip, Windows-Desktop)
  manage.cmd --test-gui-7zip-host  Einzelaktion der 7-Zip-Hostbaseline
  manage.cmd --test-plugin-renamer  Native Renamer-Verträge und 120 Hostfälle je gewählter Variante (Windows-Desktop für Hostfälle)
  manage.cmd --test-gui-renamer  Einzelaktion der Renamer-Funktionsmatrix
  manage.cmd --test-plugin-renamer-native  Native Renamer-Regel-/Puffergrenztests ohne GUI (Debug/Release)
                            JSON-Bericht; Exitcode 1 bei FAIL oder erforderlichem SKIP
                            Geplante Scope-Ausschlüsse sind kein PASS und keine Release-Abnahme.
                            (Release und Debug x64; --release/--debug begrenzt die GUI-Modi)
                            Legacy-Suche und große Unicode-Kopien: isolierte Testbuilds im Worktree
                            GUI-Tests warten vor dem Start auf das reguläre Schließen vorhandener
                            Salamander-Instanzen und setzen danach automatisch fort (Strg+C bricht ab).
  manage.cmd --test-gui-large-unicode-copy  32-MiB-Kopie, Pause/Abbruch, Zielkollision und gesperrte Quelle
  manage.cmd --test-gui-large-unicode-parent-copy  Vier 32-MiB-Fälle mit Unicode-Eltern
  manage.cmd --test-gui-long-history  Langpfad-Navigation und Historie
  manage.cmd --test-gui-long-clipboard  Unicode CF_HDROP Copy/Move über Langpfade
  manage.cmd --test-gui-viewer-reliability  Fünf unabhängige ViewUnicode-Läufe je Variante
  manage.cmd --test-wer-build  Vier isolierte WER-Core-Buildvarianten
  manage.cmd --test-legacy-find-efs  Opt-in: OPENSAL_EFS_TEST_FILE muss eigene EFS-Fixture sein
  manage.cmd --test-legacy-find-near-limit  Opt-in: echte 32700-UTF-16-Suche
  manage.cmd --test-gui-legacy-find  Legacy-Suche (Strg+F), Filter, Unicode, Focus File und Viewer
  manage.cmd --test-clipboard-snapshot  Native Zwischenablage-Sicherung/-Wiederherstellung prüfen
  manage.cmd --setup        Debug- und Release-7z plus Inno-Setup-Pakete erzeugen
  manage.cmd --test-pictview  WIC-Decoder (13 Endungen), Langpfade, Export, Clipboard: MSVC x86/x64
  manage.cmd --test-pictview-window  Zusätzlich echten WIC-Viewer-HWND testen
                                 (unverriegelter Windows-Desktop erforderlich)
  manage.cmd --test-pictview-host  F3-Plugin-Hosttest: BMP, PNG, JPEG, GIF, TIFF, ICO
  manage.cmd --test-plugin-pictview  WIC-Unit-/Fenstertests und echte F3-Hosttests (Opt-in)
  manage.cmd --test-plugin-pictview-unicode  F3 mit langem UTF-16-PNG-Pfad (Opt-in)
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
  manage.cmd --test-plugin-load  Opt-in: reale Plugin-Manager-Initialisierung aller deklarierten Plugins inkl. UnRAR
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
    [void]$RequestedSet.Add('--test-zip-sfx')
    [void]$RequestedSet.Add('--test-clipboard-snapshot')
    [void]$RequestedSet.Add('--test-wer-build')
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
        [string[]]$Arguments = @(),
        [string]$NativeTestName
    )
    # Native child processes (especially nested pwsh.exe) can write directly
    # to the host without their output being captured by Start-Transcript.
    # Route both stdout and stderr back through this PowerShell host, keeping
    # each line visible live AND in the management log. Do not mask exit codes.
    & $Command @Arguments 2>&1 | ForEach-Object {
        $line = [string]$_
        Write-Host $line
        if ($line -match '^SKIP:\s*(?<reason>.+)$') {
            $reason = $Matches.reason
            if ($NativeTestName -and $script:CollectTestFailures) {
                $planned = $NativeTestName -eq 'long_path_io' -and
                    $reason -in @('cross-volume UTF-16 move requires OPENSAL_CROSS_VOLUME_TEST_DIR',
                                   'ACP has no candidate non-question-mark best-fit mapping')
                Skip-TestCase -Name "Native C++ subcase: $NativeTestName - $reason" -Reason $reason -Planned:$planned
            }
            elseif (@($Arguments | Where-Object {
                [IO.Path]::GetFileName($_) -eq 'Test-SalamanderGui-LongPaths.ps1'
            }).Count -gt 0 -and $script:CollectTestFailures) {
                # A direct GUI test can return success after an environment
                # refusal. Do not turn its explicit SKIP into a PASS.
                $script:CurrentTestSkipReason = $reason
            }
        }
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

# A successful host build is not evidence that the optional PictView SDK
# entry point exists in the linked SPL. Inspect the actual output without
# loading it or executing any plug-in code.
function Assert-PictViewUnicodeExport {
    param([Parameter(Mandatory)][string]$VisualStudioRoot,
          [Parameter(Mandatory)][string]$VariantDirectory)
    . (Join-Path $repository 'tools\release\Plugin-Export-Parser.ps1')
    $toolchainRoot = Join-Path $VisualStudioRoot 'VC\Tools\MSVC'
    $dumpbin = Get-ChildItem -LiteralPath $toolchainRoot -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName 'bin\Hostx64\x64\dumpbin.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($dumpbin)) {
        throw "dumpbin.exe not found beneath $toolchainRoot"
    }
    $binary = Join-Path $VariantDirectory 'plugins\pictview\pictview.spl'
    $item = Get-Item -LiteralPath $binary -ErrorAction Stop
    if ($item.PSIsContainer) { throw "Expected PictView binary, found directory: $binary" }
    $hash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
    Write-Host "PictView binary: $binary; UTC write time: $($item.LastWriteTimeUtc.ToString('o')); SHA256: $hash"
    $dump = @(& $dumpbin /nologo /headers /exports $binary 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "dumpbin failed for $binary (exit $exitCode): $($dump -join ' ')" }
    $report = $dump -join [Environment]::NewLine
    if ($report -notmatch '(?im)^\s*8664\s+machine\b') {
        throw "PictView output is not an x64 PE image: $binary"
    }
    foreach ($symbol in @('SalamanderPluginEntry', 'SalamanderPluginGetReqVer',
                          'SalamanderPluginQueryUnicodeViewer')) {
        if (-not (Test-PeNamedExport -Report $report -Name $symbol)) {
            $rows = @($dump | Where-Object { $_ -match '(?i)ordinal\s+hint\s+RVA|SalamanderPlugin' })
            throw ("Missing exact PictView PE export '$symbol' in $binary. " +
                   "Export rows: $($rows -join ' | ')")
        }
        Write-Host "PASS: PictView PE export $symbol"
    }
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
    Invoke-ZipSfxBuild -Msbuild $msbuild -Repository $repository -BuildRoot $buildRoot -Mode $Mode -Invoke {
        param($Executable, $Arguments)
        Invoke-Native $Executable $Arguments
    }
    Invoke-UnrarRuntimeBuild -Msbuild $msbuild -Repository $repository -BuildRoot $buildRoot -Invoke {
        param($Executable, $Arguments)
        Invoke-Native $Executable $Arguments
    }
    foreach ($variant in @('Debug', 'Release')) {
        $binary = Join-Path (Get-VariantDirectory $variant) 'salamand.exe'
        $productVersionTest = Join-Path $repository 'tools\release\tests\Test-ProductVersion.ps1'
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $productVersionTest,
                                  '-BinaryPath', $binary)
        Assert-PictViewUnicodeExport -VisualStudioRoot $vs -VariantDirectory (Get-VariantDirectory $variant)
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
    $registryTest = Join-Path $repository 'tools\release\tests\Test-TestRegistry.ps1'
    Invoke-TestCase -Name 'Test-TestRegistry.ps1' -BlocksGui -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $registryTest)
    }

    $testCollector = Join-Path $repository 'tools\release\tests\Test-Manage-TestAggregation.ps1'
    Invoke-TestCase -Name 'Test-Manage-TestAggregation.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $testCollector)
    }

    $guiWaitContract = Join-Path $repository 'tools\release\tests\Test-Manage-GuiWait.ps1'
    Invoke-TestCase -Name 'Test-Manage-GuiWait.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $guiWaitContract)
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

    $longPathTest = Join-Path $repository 'tools\tests\Test-LongPaths.ps1'
    Invoke-TestCase -Name 'Test-LongPaths.ps1' -Action {
        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $longPathTest)
    }
    $resolverTest = Join-Path $repository 'src\vcxproj\tests\test-find-vs2026.cmd'
    Invoke-TestCase -Name 'test-find-vs2026.cmd' -Action {
        Invoke-Native 'cmd.exe' @('/d', '/c', $resolverTest)
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
        'tools\tests\editor_process_launch.cpp',
        'tools\tests\win32_unicode_rename_dialog.cpp',
        'tools\tests\win32_unicode_recycle.cpp',
        'tools\tests\shell_file_operation_name_list.cpp',
        'tools\tests\long_path_io.cpp',
        'tools\tests\unicode_directory_delete.cpp',
        'tools\tests\legacy_find_utf16_identity.cpp',
        'tools\tests\plugin_module_path.cpp',
        'tools\tests\plugin_unicode_sdk.cpp',
        'tools\tests\isolated_test_configuration.cpp',
        'tools\tests\worker_copy_paths.cpp',
        'tools\tests\worker_copy_io.cpp',
        'tools\tests\win32_utf16_static_text.cpp',
        'tools\tests\unicode_find.cpp',
        'tools\tests\win32_max_path.cpp',
        'tools\tests\bug_report_path.cpp'
    )
    $available = @($cppTests | Where-Object {
        $exists = Test-Path -LiteralPath (Join-Path $repository $_) -PathType Leaf
        if (-not $exists) {
            $missingSource = $_
            Invoke-TestCase -Name "Native C++: $missingSource" -BlocksGui -Action {
                throw "Registered native test source missing: $missingSource"
            }
        }
        $exists
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
                Invoke-Native 'cmd.exe' @('/d', '/c', $cmdPath) -NativeTestName $testName
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
        if ($requestedSet.Contains('--test-plugin-zip')) {
            foreach ($option in @('--test-zip-sfx','--test-gui-zip-host','--test-gui-zip-mutation')) {
                [void]$requestedSet.Add($option)
            }
        }
        if ($requestedSet.Contains('--test-plugin-7z')) {
            [void]$requestedSet.Add('--test-gui-7zip-host')
        }
        if ($requestedSet.Contains('--test-plugin-renamer')) {
            [void]$requestedSet.Add('--test-gui-renamer')
            [void]$requestedSet.Add('--test-plugin-renamer-native')
        }
        if ($requestedSet.Contains('--test-plugin-pictview')) {
            [void]$requestedSet.Add('--test-pictview-window')
            [void]$requestedSet.Add('--test-pictview-host')
        }
        if (@($requestedSet | Where-Object { $_ -like '--test*' }).Count -gt 0) {
            . (Join-Path $repository 'tools\release\Test-RunCollection.ps1')
            Initialize-TestRun -CollectFailures:($requestedSet.Contains('--test-all') -or $requestedSet.Contains('--test-gui-renamer') -or $requestedSet.Contains('--test-plugin-renamer-native'))
        }

        if ($requestedSet.Contains('--test-all') -and $requestedSet.Contains('--test-gui-manual')) {
            throw '--test-gui-manual is a separate manual action; do not combine with --test-all.'
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
        . (Join-Path $repository 'tools\release\Wait-SalamanderGuiAvailability.ps1')
        $null = Get-BuildMode -RequestedSet $requestedSet
        $buildRoot = [IO.Path]::GetFullPath($buildRoot)
        New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

        if ($requestedSet.Contains('--update')) { Update-Branch }
        $buildMode = Get-BuildMode -RequestedSet $requestedSet
        if ($buildMode -ne 'None') { Build-Variants -Mode $buildMode }
        if ($requestedSet.Contains('--test')) { Run-Tests }
        if ($requestedSet.Contains('--test-plugin-renamer-native')) {
            $renamerNative = Join-Path $repository 'tools\release\tests\Invoke-RenamerNativeTests.ps1'
            foreach ($nativeMode in @('Debug','Release')) {
                if ($requestedSet.Contains('--debug') -and $nativeMode -ne 'Debug') { continue }
                if ($requestedSet.Contains('--release') -and $nativeMode -ne 'Release') { continue }
                Invoke-TestCase -Name "Renamer native contracts $nativeMode x64" -Action {
                    $vs = Get-VisualStudio2026
                    $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
                    Invoke-Native 'pwsh.exe' @('-NoProfile','-NonInteractive','-File',$renamerNative,
                        '-Vcvars64',$vcvars,'-BuildRoot',$buildRoot,'-Configuration',$nativeMode)
                }
            }
        }
        if ($requestedSet.Contains('--test-wer-build')) {
            $werBuild = Join-Path $repository 'tools\release\tests\Invoke-WerBuildVerification.ps1'
            Invoke-TestCase -Name 'WER isolated core build matrix' -Action {
                Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $werBuild, '-AllConfigurations')
            }
        }

        # Isolated SFX executables do not use the running Salamander host or
        # send foreground keystrokes. Exercise all eight cases independently.
        if ($requestedSet.Contains('--test-zip-sfx')) {
            $sfxTest = Join-Path $repository 'tools\release\tests\Test-ZipSfxRoundtrip.ps1'
            foreach ($sfxMode in @('Release', 'Debug')) {
                if ($requestedSet.Contains('--release') -and $sfxMode -ne 'Release') { continue }
                if ($requestedSet.Contains('--debug') -and $sfxMode -ne 'Debug') { continue }
                foreach ($sfxMethod in @('Store', 'Deflate')) {
                    foreach ($sfxEncryption in @('None', 'ZipCrypto')) {
                        Invoke-TestCase -Name "ZIP SFX $sfxMode $sfxMethod $sfxEncryption" -Action {
                            $sevenZip = Find-Executable '7z.exe' @(
                                (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) '7-Zip\7z.exe'),
                                (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) '7-Zip\7z.exe'))
                            Invoke-Native 'pwsh.exe' @('-NoProfile', '-NonInteractive', '-File', $sfxTest,
                                '-BuildDirectory', (Get-VariantDirectory $sfxMode), '-BuildRoot', $buildRoot,
                                '-SevenZipExe', $sevenZip, '-Method', $sfxMethod, '-Encryption', $sfxEncryption)
                        }
                    }
                }
            }
        }

        # Only GUI-sensitive test actions need an idle Salamander desktop.
        # Wait ONCE before any GUI child starts; the existing per-case checks
        # still catch leaked test processes and unexpected new instances.
        # Do not wait when earlier --test-all failures already blocked GUI.
        if (Test-RequiresGuiIdleGate -RequestedSet $requestedSet) {
            if (-not (($requestedSet.Contains('--test-all') -or $requestedSet.Contains('--test-gui-renamer')) -and $script:GuiTestsBlocked)) {
                Wait-ForSalamanderGuiAvailability
            }
        }

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
            foreach ($optMode in @(Get-AutomatedGuiModes -RequestedSet $requestedSet)) {
                $testedExe = Join-Path (Get-VariantDirectory $optMode) 'salamand.exe'
                Invoke-TestCase -Name "Recycle restore $optMode short file" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $guiTest,
                                              '-SalamanderExe', $testedExe,
                                              '-ShortUnicodeRecycleOnly', '-VerifyRecycleRestore')
                }
                $longPathRunner = Join-Path $repository 'tools\release\tests\Invoke-IsolatedLongPaths.ps1'
                foreach ($recycleCase in @('RecycleFile','RecycleDirectory')) {
                    Invoke-TestCase -Name "Recycle restore $optMode $recycleCase" -RequiresGuiSafety -Action {
                        Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $longPathRunner,
                            '-Configuration', $optMode, '-Scenario', $recycleCase)
                    }
                }
                $legacySpecial = Join-Path $repository 'tools\release\tests\Invoke-IsolatedLegacyFind.ps1'
                Invoke-TestCase -Name "Legacy Find $optMode RecycleRestore" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $legacySpecial,
                        '-Configuration', $optMode, '-SpecialScenario', 'RecycleRestore')
                }
            }
        }
        # Explicit opt-in: the Salamander plug-in manager's Test All action
        # initializes every installed plug-in, including third-party modules.
        # This must never run implicitly as part of --test-all.
        if ($requestedSet.Contains('--test-plugin-load')) {
            Write-Host '=== OPT-IN: ECHTE PLUGIN-MANAGER-INITIALISIERUNG ==='
            foreach ($optMode in @(Get-AutomatedGuiModes -RequestedSet $requestedSet)) {
                Invoke-TestCase -Name "Plugin initialization $optMode" -RequiresGuiSafety -Action {
                    . (Join-Path $repository 'tools\release\Plugin-Runtime-Prerequisites.ps1')
                    $pluginBuild = Get-VariantDirectory $optMode
                    Assert-UnrarRuntime -Directory $pluginBuild
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
            }
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
            foreach ($optMode in @(Get-AutomatedGuiModes -RequestedSet $requestedSet)) {
                $targetExe = Join-Path (Get-VariantDirectory $optMode) 'salamand.exe'
                foreach ($imageFormat in @('Bmp','Png','Jpeg','Gif','Tiff','Ico')) {
                    Invoke-TestCase -Name "PictView F3 $optMode $imageFormat" -RequiresGuiSafety -Action {
                        Write-Host "=== PICTVIEW HOST F3: $imageFormat ==="
                        Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $hostGui,
                                                   '-SalamanderExe', $targetExe,
                                                   '-ImageFormat', $imageFormat)
                    }
                }
            }
        }
        if ($requestedSet.Contains('--test-plugin-pictview-unicode')) {
            $hostGui = Join-Path $repository 'tools\release\tests\Test-PictView-Host.ps1'
            foreach ($optMode in @(Get-AutomatedGuiModes -RequestedSet $requestedSet)) {
                $targetExe = Join-Path (Get-VariantDirectory $optMode) 'salamand.exe'
                Invoke-TestCase -Name "PictView F3 $optMode UnicodeLongPath" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-File', $hostGui,
                                               '-SalamanderExe', $targetExe,
                                               '-ImageFormat', 'Png', '-UnicodeLongPath')
                }
            }
        }
        $automatedGuiModes = @(Get-AutomatedGuiModes -RequestedSet $requestedSet)
        foreach ($guiMode in $automatedGuiModes) {
            if ($requestedSet.Contains('--test-gui-large-unicode-parent-copy')) {
                $largeCopyTest = Join-Path $repository 'tools\release\tests\Invoke-IsolatedUnicodeCopy.ps1'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-large-unicode-parent-copy" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $largeCopyTest,
                                              '-Configuration', $guiMode, '-UnicodeParentDirectories')
                }
            }
            if ($requestedSet.Contains('--test-gui-long-history')) {
                $longPathRunner = Join-Path $repository 'tools\release\tests\Invoke-IsolatedLongPaths.ps1'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-long-history" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $longPathRunner,
                                              '-Configuration', $guiMode, '-Scenario', 'History')
                }
            }
            if ($requestedSet.Contains('--test-gui-long-clipboard')) {
                $longPathRunner = Join-Path $repository 'tools\release\tests\Invoke-IsolatedLongPaths.ps1'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-long-clipboard" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $longPathRunner,
                                              '-Configuration', $guiMode, '-Scenario', 'Clipboard')
                }
            }
            if ($requestedSet.Contains('--test-gui-viewer-reliability')) {
                $viewerReliability = Join-Path $repository 'tools\release\tests\Invoke-LegacyViewerReliability.ps1'
                Invoke-TestCase -Name "GUI $guiMode --test-gui-viewer-reliability (5 iterations)" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $viewerReliability,
                                              '-Configuration', $guiMode, '-Iterations', '5',
                                              '-OutputDirectory', (Join-Path $logDirectory 'legacy-viewer-reliability'))
                }
            }
            if ($requestedSet.Contains('--test-legacy-find-efs')) {
                $legacySpecial = Join-Path $repository 'tools\release\tests\Invoke-IsolatedLegacyFind.ps1'
                Invoke-TestCase -Name "Legacy Find $guiMode EncryptedFixture" -RequiresGuiSafety -Action {
                    if ([string]::IsNullOrWhiteSpace($env:OPENSAL_EFS_TEST_FILE)) {
                        throw 'Explicit EFS test requires OPENSAL_EFS_TEST_FILE pointing to a disposable encrypted file.'
                    }
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $legacySpecial,
                        '-Configuration', $guiMode, '-SpecialScenario', 'EncryptedFixture',
                        '-EncryptedFixture', $env:OPENSAL_EFS_TEST_FILE)
                }
            }
            if ($requestedSet.Contains('--test-legacy-find-near-limit')) {
                $legacySpecial = Join-Path $repository 'tools\release\tests\Invoke-IsolatedLegacyFind.ps1'
                Invoke-TestCase -Name "Legacy Find $guiMode NearLimit" -RequiresGuiSafety -Action {
                    Invoke-Native 'pwsh.exe' @('-NoProfile', '-File', $legacySpecial,
                        '-Configuration', $guiMode, '-SpecialScenario', 'NearLimit')
                }
            }

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
            if ($requestedSet.Contains('--test-gui-zip-host')) {
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                foreach ($zipHostEncryption in @('None','ZipCrypto')) {
                    Invoke-TestCase -Name "ZIP plugin host $guiMode Deflate $zipHostEncryption" -RequiresGuiSafety -Action {
                        $sevenZip = Find-Executable '7z.exe' @(
                            (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) '7-Zip\7z.exe'),
                            (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) '7-Zip\7z.exe'))
                        Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-NonInteractive', '-File', $guiTest,
                            '-SalamanderExe', $testedExe, '-ZipHostEncryption', $zipHostEncryption,
                            '-ZipHostSevenZip', $sevenZip)
                    }
                }
            }
            if ($requestedSet.Contains('--test-gui-renamer')) {
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                foreach ($renamerCase in @('Prefix','Suffix','Extension','LiteralDollar','LowerName','UpperExtension','CaseSensitive','CaseInsensitive','ReplaceOnce','ReplaceAll','WholeWords','ExcludeExtension','RegexCapture','RegexLower','RegexUpper','RegexUpperCapital','RegexUpperMixed','RegexBrace','Counter','CounterDescending','CounterFraction','CounterMalformed','CounterMultipleDots','CounterDotOnly','InvalidVariable','InvalidRegex','InvalidReference','InvalidModifier','DuplicateCancel','CollisionCancel','Cancel','Undo','SingleSelection','MaskFilter','Manual','VariableLower','VariableUpper','VariableMixed','VariableCaseInsensitive','SubstringLeft','SubstringRight','SubstringMiddle','SubstringClamp','SubstringCase','MultipleDots','NoExtension','DotfileExtension','DeleteSubstring','ReplaceExtensionToo','RegexWholeMatch','RegexCaseInsensitive','RegexAll','RegexAnchored','RegexEscapedDollar','RegexEmptyReplacement','CounterDefault','CounterHexLower','CounterHexUpper','CounterLeftAlign','CounterZeroStep','CounterNegativeFraction','CounterTrailingPoint','CounterInvalidStart','CounterInvalidBase','CounterInvalidFill','TrailingDollar','UnclosedVariable','EmptyVariable','WrongRegexBracket','ManualSwap','ManualSwapUndo','ManualChainUndo','TreeDirectory','TreeDirectoryUndo','TreeEmptyDirectory','TreeRecursiveMask','TreeRecursiveUndo','TreeRelativeMove','TreeRelativeUndo','TreeFullPathMove','TreeFullPathUndo','TreeUnicodeNames','TreeUnicodeRoot','TreeNormalization','TreeLongRoot','TreeLongLeaf','TreeAds','TreeAdsUndo','TreeMetadataVariables','AdvancedValidateOnly','AdvancedNoOp','AdvancedManualFew','AdvancedManualMany','AdvancedManualTrailingBlank','AdvancedManualInteriorBlank','AdvancedReservedName','AdvancedInvalidCharacter','AdvancedClipboardExportOriginal','AdvancedClipboardExportEdited','AdvancedClipboardImport','AdvancedClipboardRoundTrip','AdvancedClipboardUndo','AdvancedClipboardMalformed','AdvancedClipboardUnicode','AdvancedSortSize','AdvancedSortTime','AdvancedSortSizeTie','AdvancedReadOnly','AdvancedLockCancel','AdvancedLockSkipAll','AdvancedLockOneSkip','AdvancedLockRetry','AdvancedUndoLockCancel','AdvancedUndoLockRetry','AdvancedUndoDecline','AdvancedOverwriteCancel','AdvancedOverwriteSuccess','AdvancedOverwriteLockedSource','AdvancedOverwriteLockedTarget','AdvancedOverwriteReadOnlyTarget')) {
                    Invoke-TestCase -Name "Renamer plugin host $guiMode $renamerCase" -RequiresGuiSafety -Action {
                        Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-NonInteractive', '-File', $guiTest,
                            '-SalamanderExe', $testedExe, '-RenamerHostCase', $renamerCase)
                    }
                }
            }
            if ($requestedSet.Contains('--test-gui-7zip-host')) {
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                foreach ($archiveCase in @('Extract','Cancel')) {
                    Invoke-TestCase -Name "7-Zip plugin host $guiMode $archiveCase" -RequiresGuiSafety -Action {
                        $sevenZip = Find-Executable '7z.exe' @(
                            (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) '7-Zip\7z.exe'),
                            (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) '7-Zip\7z.exe'))
                        Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-NonInteractive', '-File', $guiTest,
                            '-SalamanderExe', $testedExe, '-ZipHostEncryption', 'None',
                            '-ZipHostSevenZip', $sevenZip, '-SevenZipHostCase', $archiveCase)
                    }
                }
            }
            if ($requestedSet.Contains('--test-gui-zip-mutation')) {
                $guiTest = Join-Path $repository 'tools\release\tests\Test-SalamanderGui-LongPaths.ps1'
                $testedExe = Join-Path (Get-VariantDirectory $guiMode) 'salamand.exe'
                foreach ($zipMutation in @('Create','Add','Replace','Delete')) {
                    Invoke-TestCase -Name "ZIP plugin host $guiMode $zipMutation" -RequiresGuiSafety -Action {
                        $sevenZip = Find-Executable '7z.exe' @(
                            (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) '7-Zip\7z.exe'),
                            (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) '7-Zip\7z.exe'))
                        Invoke-Native 'pwsh.exe' @('-Sta', '-NoProfile', '-NonInteractive', '-File', $guiTest,
                            '-SalamanderExe', $testedExe, '-ZipHostEncryption', 'None',
                            '-ZipHostSevenZip', $sevenZip, '-ZipHostMutation', $zipMutation)
                    }
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
        if ($requestedSet.Contains('--test-all')) {
            try {
                $registry = Get-Content -LiteralPath (Join-Path $repository 'tools\release\Test-Registry.json') -Raw | ConvertFrom-Json
                foreach ($excluded in $registry.ScopeExclusions) {
                    if (-not $excluded.Option -or -not $requestedSet.Contains([string]$excluded.Option)) {
                        if ($excluded.PerVariant) {
                            foreach ($excludedMode in @(Get-AutomatedGuiModes -RequestedSet $requestedSet)) {
                                Skip-TestCase -Name "$($excluded.Name) $excludedMode x64" -Reason $excluded.Reason -Planned
                            }
                        }
                        else {
                            Skip-TestCase -Name $excluded.Name -Reason $excluded.Reason -Planned
                        }
                    }
                }
            }
            catch {
                if ($_.Exception -is [System.Management.Automation.PipelineStoppedException] -or
                    $_.Exception -is [OperationCanceledException]) { throw }
                Add-TestOutcome -Name 'Test registry scope reporting' -Status FAIL -Detail $_.Exception.Message
            }
            Complete-TestRun -LogPath $logPath
        }
        elseif ($requestedSet.Contains('--test-gui-renamer') -or $requestedSet.Contains('--test-plugin-renamer-native')) {
            # Publish every independently attempted Renamer case, including RED
            # outcomes, even without --test-all. A failure still blocks setup/run.
            Complete-TestRun -LogPath $logPath
        }
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
    $runStopwatch.Stop()
    $elapsed = $runStopwatch.Elapsed
    # Total hours must not wrap at midnight; record before closing the transcript.
    Write-Host ('Gesamtlaufzeit: {0:00}:{1:00}:{2:00}.{3:000}' -f
        [long][Math]::Floor($elapsed.TotalHours), $elapsed.Minutes,
        $elapsed.Seconds, $elapsed.Milliseconds)
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
