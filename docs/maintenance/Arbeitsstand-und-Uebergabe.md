# Salamander 5.2 – aktueller Entwicklungsstand und Übergabe

> **Startpunkt für jede neue ChatGPT-, Codex- oder Entwickler-Sitzung.**
> Letzte fachliche Auswertung: **24.11.2026, 13:56 CET**.
> Branch zum zuletzt protokollierten Windows-Lauf: `bugfix/v5.2`, SHA `8a5cb99da350a494f94fdb57087c7b7f8221c336` (**`--test` FAIL**). Letzter erfolgreich protokollierter `--test`-Lauf: `02acf27c87ddbe509d7044e3a416c5ebf265224d`.
> **Dieses Datum und diese SHA sind ein Snapshot, kein automatisch aktueller Git-HEAD.**
> Die Dokumentationscommits danach benötigen eigene, angemessene Prüfungen.
> **Release 5.2: NO-GO.** Keine vollständige A0–A7-, Plugin- oder VM-Abnahme.

## 1. Unverzichtbare Lesereihenfolge

1. [`Anforderungen.md`](../../Anforderungen.md): wörtliche Produktvorgaben A0–A7.
2. [`AGENTS.md`](../../AGENTS.md): verbindliche Architektur-, Sicherheits-, TDD-, Git- und Arbeitsregeln.
3. **Diese Datei**: letzte belegte Ergebnisse, unmittelbarer Anschluss und Sperren.
4. [`Testluecken-und-Abnahmeplan-5.2.md`](Testluecken-und-Abnahmeplan-5.2.md): **einzige maßgebliche Aufgaben-/Gap-Liste** mit stabilen IDs, Prioritäten und Abnahmebedingungen.
5. [`Entwicklungsjournal.md`](Entwicklungsjournal.md): zeitliche Entscheidungen, Benutzeraufträge, Befunde, Änderungen und Verifikationsgeschichte.
6. Je nach Auftrag: [Legacy-Find-UTF16-Migration](Legacy-Find-UTF16-Migration.md), [Unicode-LongPath-Implementation](Unicode-LongPath-Implementation.md), [Plugin-Inventar](Plugin-Inventar-und-Testmatrix-5.2.md), [Release-Gates](../../tools/release/Release-5.2-Gates.md), [WIC-Migration](../pictview-wic-migration.md).

**Zu Beginn immer den tatsächlichen Branch, `git status`, HEAD, Quellcode und vorhandene CI-Ergebnisse lesen.** Historische Aussagen sind keine automatisch aktuellen Tatsachen. Chatarchive 01–12 und `Master-Prompt.odt` wurden für die Erstkonsolidierung ausgewertet; die daraus abgeleiteten dauerhaften Regeln stehen in `AGENTS.md`, die Produktvorgaben unverändert in `Anforderungen.md` und die Entwicklungsgeschichte im Journal. Archiv-PDFs sind historische Kontextquellen, keine aktuelle technische Autorität.

## 2. Produkt und zwingende Invarianten

- **Natives C++/Win32-Programm, kein Godot/C#-Projekt**. Originale 5.0-UI, Bedienung, Ressourcen und Funktionen erhalten; keine Eigenersatz-Dialoge oder stillen Reduktionen (A0).
- Durchgängige **echte UTF-16-Dateiidentität**, auch bei nicht in ANSI/ACP darstellbaren Zeichen, Namenskollisionen, Unicode-Kombinationszeichen und Surrogatpaaren; keine verlustbehafteten Best-Fit-Ersatzpfade oder unberechtigte Dateiaktionen (A1).
- Langpfade und UNC durch **Hauptprogramm und sämtliche Plugins**, nicht nur in Hilfsbibliotheken (A2); `CFileData`, Plugin-SDK, alte ABI und Win32-/CRT-Grenzen kompatibel halten.
- Visual Studio 2026, `src/vcxproj/salamand.sln`, Debug/Release, x86/x64 soweit vorhanden (A3).
- `manage.cmd` bei jeder **relevanten** Build-/Test-/Release-Änderung mitpflegen; `--update` nicht ungefragt ausführen, `--build`, `--build-delta`, `--build-clean`, `--test`, `--test-all`, `--setup` semantisch erhalten (A4).
- Release-7z/Installer ohne Buildmüll, aber vollständig lauffähig auf sauberer VM (A5).
- `Strg+F` öffnet unverändert **ursprüngliches `IDD_FIND`** mit Advanced, Filtern, Regex, Verlauf, Duplikaten und Ergebnisaktionen; separate Unicode-Find-Funktion ersetzt es nicht (A6).
- PictView verwendet **WIC**, keine Wiederbelebung proprietärer PVW32-Konverter; echte Format-/Host-Abnahme offen (A7).
- Für Änderungen: **Analyse → reproduzierbarer RED-Test → minimale GREEN-Änderung → Refactor → echte Tests → Ergebnis/Tracker/Journal im selben Commit**. Bestehende Tests nur bei nachweisbar veraltetem Vertrag ändern; nie zur Kaschierung eines Produktfehlers.

## 3. Zuletzt tatsächlich belegte Ergebnisse

| Datum / Quell-SHA | Lauf / Befund | Verifikationsgrenze |
| --- | --- | --- |
| 23.11.2026 / `a7ab5b40...` | vollständiges `--test-all` historisch PASS; belegt im Abnahmeplan | **historische Baseline**, nicht aktueller Branch |
| 24.11.2026 / `a43341ca...` | Buildausgabe auf Repository-`.Build/` umgestellt; erster Delta-Build ca. 122 s, zweiter ca. 8 s, jeweils erfolgreich | kein vollständiger Clean-Build-/Release-Beleg für alle späteren Commits |
| 24.11.2026 / `dbcf0d13...` | `--test-gui-unicode-multiselect --release` PASS, F5/F6 synchron und 17-MiB-Hintergrundtransfer | nur diese GUI-Konfiguration |
| 24.11.2026 / `dbcf0d13...` | `--test-gui-unicode-parent` **FAIL in Release und Debug**: modaler Dialog lehnt nicht-ACP-Unicode-Verzeichnis ab | offener **Produktfehler** |
| 24.11.2026 / `02acf27c...` | `manage.cmd --test` PASS; alle registrierten nativen C++-Regressionen einschließlich `about_build_info.cpp`, Unicode-Dateiidentität, Worker-I/O | historisch erfolgreich; gilt nicht automatisch auf späteren SHAs |
| 24.11.2026 13:56 / `8a5cb99d...` | `manage.cmd --test` **FAIL vor den übrigen Tests**: ParserError in neuem `Test-DevelopmentContinuity.ps1:37`, interpoliertes `$id:`; Aggregationstest davor PASS | **Testinfrastrukturfehler**, keine Aussage zu Produktregressionen; Korrektur `${id}:` und neue AST-Parser-Vorprüfung eingecheckt, Windows-Run nach Fix ausstehend |
| 24.11.2026 / `02acf27c...` | `manage.cmd --test-gui-legacy-find --debug`: **36 PASS, 1 FAIL, 0 SKIP**. Native External-Editor-Variante PASS, PowerShell-Variante FAIL (`NOT_STARTED`); ursprüngliche Viewer-/Find-/Unicode-Tests dabei PASS | Gesamtkommando Exitcode 1, keine Freigabe |

Die beiden letzten Benutzerprotokolle stammen aus `manage-20261124-125928-575-54f5eb.log` und `manage-20261124-130047-583-958536.log`. Diese Logs befinden sich **nur lokal** unter `.Build/logs/`, nicht im Git. Testresultate nicht ohne eindeutige SHA/Variante/Datum in einen späteren Commit übertragen. Im nativen `long_path_io.cpp`-Test wurde der optionale echte Cross-Volume-Fall mangels `OPENSAL_CROSS_VOLUME_TEST_DIR` **SKIP** gemeldet; das ist kein PASS.

## 4. Aktive Fehler und nächste konkrete Arbeit

0. **P1 – Testinfrastruktur / MGMT-02, MGMT-03:** Windows-`--test` vom 24.11. 13:56 auf `8a5cb99d` brach in `Test-DevelopmentContinuity.ps1:37` durch den PowerShell-Parserfehler `$id:` ab. Der neue Syntaxfix `${id}:` ist eingecheckt; `Test-PowerShellSyntax.ps1` nutzt PowerShells echten AST-Parser für die Repository-Skripte und prüft den Original-Fehler als Negativfixture. Ausführung **noch nicht belegt**. **Als Erstes** gezielt Parser-Vorprüfung und Kontinuitätstest, dann `manage.cmd --test` ausführen. Kein Produkt-PASS aus dem abgebrochenen Lauf ableiten.

1. **P0 – Unicode-Elternverzeichnis, A1/A2, UP-06 und UP-04:** `src/fileswn2.cpp::ChangeUnicodePathToDisk` verweigert absichtlich Pfade ohne exakte ANSI-Projektion. Debug und Release scheitern deshalb bei `--test-gui-unicode-parent` mit Modal-Dialog und `WM_COMMAND 775`-Timeout. Den Schutz **nicht entfernen oder durch verlustbehaftete Zeichen ersetzen**. Aufrufkette `src/fileswn3.cpp::ChangeDir` → `ChangeUnicodePathToDisk` → `ChangeLongPathToDisk`/Panel-Liste, Pfadhistorie, Plugin- und Shell-Grenzen prüfen; kompatiblen vollständigen W-Pfadpfad entwerfen, mit echten positiven/negativen GUI-Regressionen absichern. Solange die Panel-Invarianten unklar sind, bleibt das ein bewusst blockierter Übergang.
2. **P1 – Legacy Find ExternalEditor / FIND-04, QA-03:** `src/finddlg1.cpp::OnEditFile` → `src/fileswnb.cpp::WM_USER_EDITFILE` → `src/fileswn5.cpp::EditFile`. Der Debug-Originaltest mit WindowsApps/MSIX-`pwsh.exe` erreicht den Probe-Status nicht; `ExternalEditorNative` mit `cmd.exe` funktioniert. Untersuchen: registrierte Argumente, reales CreateProcess-Ergebnis, Initialverzeichnis, Sicherheitsrichtlinien, Quoting, Startbedingungen. Beide Tests **beibehalten**; keine stumme Umleitung des Anwender-Editors.
3. **P1 – About:** `src/logo.cpp` zeigt eine zusätzliche Zeile mit Datum/Uhrzeit des **EXE-Dateiänderungszeitstempels** sowie Debug/Release und Architektur. Der native Formatierungstest bestand; optische Darstellung, Tooltip/Layout, Lokalisierung und eine womöglich nachträglich veränderte EXE-Zeit wurden noch nicht am tatsächlichen GUI-Dialog verifiziert. Dateiänderungszeit ist nicht automatisch ein fälschungssicherer Linker-Buildzeitstempel.
4. **P0/P1 – weitere Hauptprogramm-/Plugin-Lücken:** Große gemischte Datei-/Ordnerauswahlen, gesamte Verzeichnisbäume, Cross-Volume inklusive ADS, Shell-/Editor-/Archiv-/Plugin-Grenzen, UNC/SMB und Reparse Points. **Der ausdrücklich beauftragte funktionsfähige UnRAR-Ersatz (Chat 09) ist weiterhin nicht belegt und muss in UP-03 geprüft werden.** Das Microsoft-Abhängigkeitsinventar liegt in `Microsoft-Dependencies-2026.md`. Siehe **UP-02 bis UP-07** und **QA-01**. Programm nicht als vollständig unicode-/langpfadfähig deklarieren.
5. **A0, A5, A7 – Release:** Original-UI-A/B, alle Plugins, WIC-Host/Animationsparität, x86-Matrix, echte saubere Windows-11-VM, Installer-/Uninstall-/Upgrade-, Lizenz-/Signaturgates fehlen. Keine GO-Entscheidung.

## 5. Build, Tests, Sicherheitsvorkehrungen

```powershell
cd C:\Repositories\Salamander
git status --short
git branch --show-current
git rev-parse HEAD
# Nur nach ausdrücklicher Zustimmung aktualisieren:
# git pull --ff-only origin bugfix/v5.2
pwsh -NoProfile -File .\tools\release\tests\Test-PowerShellSyntax.ps1
pwsh -NoProfile -File .\tools\release\tests\Test-DevelopmentContinuity.ps1
.\manage.cmd --build-delta
.\manage.cmd --test
.\manage.cmd --test-gui-unicode-parent --release
.\manage.cmd --test-gui-unicode-parent --debug
.\manage.cmd --test-gui-legacy-find --debug
# Erst nach angemessener Einzeltest-Verifikation:
.\manage.cmd --test-all
```

- **Buildroot:** `<Repository>/.Build/`, gitignoriert. Keine persönlichen `D:\Build\OpenSal`- oder TEMP-Pfade fest verdrahten; für lokale isolierte GUI-Fälle gehören die Outputs ebenfalls in `.Build/`.
- `--test-all` sammelt eigenständige PowerShell-, native und GUI-Fehler inklusive PASS/FAIL/SKIP und JSON unter `.Build/logs`. Bei Fehler bleibt Exitcode ungleich null. Der isolierte Legacy-Find-Runner sammelt inzwischen Fälle separat; frühere Logik brach beim ersten Fehler ab.
- Auf GUI-Desktop ohne fremde Salamander-Prozesse testen; test-eigene GUID-Registry, TEMP und Clipboard schonend behandeln. **Keine fremden Prozesse abschießen, keine Benutzerdateien verändern**, keine unautorisierte Shell-/Setup-/Update-Aktion, keine Screenshots/Dumps ungeprüft versionieren.
- **Dokumentationspflicht für jeden Folgeauftrag:** Nach Umsetzung Journalzeile mit Datum, Auftrag, Ursache/Entscheidung, Files/Commit, Tests und Status ergänzen; alle betroffenen Gap-IDs im zentralen Abnahmeplan aktualisieren; **diese Datei** zum Sitzungsschluss auf den neuen belegten Stand setzen. Wenn die Sitzung ohne Code endet, trotzdem Befund/Blockade dokumentieren, sofern ein Commit autorisiert ist.

## 6. Übergabe zwischen ChatGPT und Codex

**Empfohlener Startauftrag:** „Arbeite im Repository `Fla77y/Salamander` weiter. Lies zuerst `AGENTS.md`, `Anforderungen.md`, `docs/maintenance/Arbeitsstand-und-Uebergabe.md`, `docs/maintenance/Entwicklungsjournal.md` und `docs/maintenance/Testluecken-und-Abnahmeplan-5.2.md`. Vergleiche sie mit dem aktuellen Branch/HEAD und beginne bei den priorisierten offenen Punkten. Ändere keine bestehenden Testverträge ohne begründeten Nachweis.“

**Einschränkung:** Codex kann `AGENTS.md` beim Repositoryzugriff automatisch berücksichtigen. Ein neuer ChatGPT-Chat lädt **GitHub-Dateien nicht garantiert von selbst**; er benötigt Zugriff auf das Repository und passende Projektanweisungen bzw. den obigen Startauftrag. Dokumente ermöglichen die nahtlose fachliche Übergabe, ersetzen aber keine Laufzeitverifikation und keine Berechtigungen.
