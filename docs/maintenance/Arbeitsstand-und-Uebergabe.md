# Salamander 5.2 – aktueller Entwicklungsstand und Übergabe

> **Startpunkt für jede neue ChatGPT-, Codex- oder Entwickler-Sitzung.**
> Letzte fachliche Auswertung: **24.11.2026, 17:09 CET**.
> **Letzter tatsächlicher Windows-Lauf:** `bugfix/v5.2`, SHA `d93cb4d5eb63a61d406c3d98c1ef6979621c5d5e`, 24.11.2026 17:06:29–17:09:22 CET; isoliertes `--test-gui-legacy-find --debug`: Debug-x64-Build PASS, **36 PASS / 1 FAIL / 0 SKIP**, nur `ExternalEditor` Win32 5. Letzter vollständiger `--build-delta --test`-PASS weiterhin `9f524264`.
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
| 24.11.2026 14:02–14:03 / `a928794c...` | `manage.cmd --test` **PASS** unter PowerShell 7.7.0, Windows NT 10.0.26300, sauberer Checkout: AST-Parser **66 PS-Skripte**, Kontinuitäts-/Aggregationstest und **21 native C++-Regressionen PASS** | Tatsächlich ausgeführter Test; physischer Cross-Volume-Fall mangels `OPENSAL_CROSS_VOLUME_TEST_DIR` **SKIP**; kein Nachweis aller GUI-, Plugin- oder VM-Szenarien |
| 24.11.2026 / `02acf27c...` | `manage.cmd --test-gui-legacy-find --debug`: **36 PASS, 1 FAIL, 0 SKIP**. Native External-Editor-Variante PASS, PowerShell-Variante FAIL (`NOT_STARTED`); ursprüngliche Viewer-/Find-/Unicode-Tests dabei PASS | Gesamtkommando Exitcode 1, keine Freigabe |
| 24.11.2026 14:32–14:34 / `9f524264...` | `manage.cmd --build-delta --test` **PASS**: Debug/Release x64 Delta mit VS 2026/MSVC 18.12.3, zwei Produkt-VERSIONINFO-Prüfungen, HTML-Hilfe, 66 PS-Skripte, **22 native C++-Regressionen** einschließlich neuem `unicode_directory_panel_alias.cpp` (tatsächlicher 8.3-Positivfall PASS) | Letzter tatsächlich geprüfter Produkt-HEAD; `long_path_io.cpp` Cross-Volume-Fall **SKIP** ohne `OPENSAL_CROSS_VOLUME_TEST_DIR`; kein GUI-End-to-End-Beleg |
| 24.11.2026 14:34 / `9f524264...` | GUI-Elternverzeichnis Release und Debug sowie Legacy-Find Debug jeweils **vor Teststart blockiert**: vorhandene `salamand.exe`-Instanz; kein Test der Produktfunktionen | Drei CLI-Fehler mit Umgebungsursache, **nicht** Produkt-PASS/FAIL; laufende Benutzerinstanz nicht automatisch beenden |
| 24.11.2026 14:59–15:02 / `3119af03...` | Isolierter `--test-gui-legacy-find --debug`: **36 PASS / 1 FAIL / 0 SKIP**; PowerShell-Host-Preflight ausdrücklich PASS, `ExternalEditor` danach **FAIL/NOT_STARTED**; `ExternalEditorNative` PASS; alle anderen Szenarien PASS | **Reproduzierter Produkt-/Startpfadfehler**; direkte Host-Ausführung gut, Win32-Editorstart oder Parameterübergabe unklar. Alle nachträglichen Korrekturen ungetestet. |
| 24.11.2026 15:12 / `3820e636...` | `--build-delta --test` **FAIL im Debug-MSVC-Build**: C2039 in `src/fileswn5.cpp:1516`, Makro `HANDLES` behandelt Namespaced-Funktion irrtümlich als Member von `C__Handles`. Anschließender isolierter `--test-gui-legacy-find --debug` **FAIL ebenfalls im Compile** | **Compilerfehler, keine Produkt-GUI-Ergebnisse**; Makrobenutzung danach zu `HANDLES(CreateProcess(...))` korrigiert, Windows-Verifikation offen |
| 24.11.2026 15:28–15:32 / `8a6de88...` | Isolierter Legacy-Find-Debug-x64-Build **PASS**; GUI-Suite **34 PASS / 3 FAIL / 0 SKIP**: `AdvancedInputs` Shift `0xFF81`; `ShellClipboard` Copy-Dateiliste/Preferred DropEffect Timeout; `ExternalEditor` `NOT_STARTED` trotz erfolgreich unabhängig gestartetem PowerShell-Host; eigener Dialog „Open Salamander“ sichtbar | Kompilierungsfehler nachweislich behoben, **drei getrennte offene GUI-Befunde**, kein allgemeiner GUI-PASS und keine neue vollständige `--test`-Abnahme |

Die früheren Benutzerprotokolle `manage-20261124-125928-575-54f5eb.log`, `manage-20261124-130047-583-958536.log` und `manage-20261124-140223-783-8d6f75.log` sowie der neue erfolgreiche Lauf `manage-20261124-143247-926-e31128.log` und die drei blockierten GUI-Läufe `manage-20261124-143441-351-f441ec.log`, `manage-20261124-143443-659-54878a.log`, `manage-20261124-143445-886-a11170.log` und der neue fehlgeschlagene Debug-Legacy-Find-Lauf `manage-20261124-145926-376-de4931.log` sowie die fehlgeschlagenen Build-/GUI-Build-Läufe `manage-20261124-151235-015-5be57f.log` und `manage-20261124-151238-827-08f672.log` befinden sich **nur lokal** unter `.Build/logs/`, nicht im Git. Testresultate nicht ohne eindeutige SHA/Variante/Datum in einen späteren Commit übertragen. Im nativen `long_path_io.cpp`-Test wurde der optionale echte Cross-Volume-Fall mangels `OPENSAL_CROSS_VOLUME_TEST_DIR` **SKIP** gemeldet; das ist kein PASS.

## 4. Aktive Fehler und nächste konkrete Arbeit

**24.11.2026, 17:06–17:09 CET, `d93cb4d5`:** isolierter Debug-x64-Build PASS, Legacy Find **36 PASS / 1 FAIL / 0 SKIP**; `AdvancedInputs`, `ShellClipboard`, `ExternalEditorNative` PASS, `ExternalEditor` FAIL/NOT_STARTED, CreateProcess Win32 **5 (ERROR_ACCESS_DENIED)**. Log: `manage-20261124-170629-100-b3066a.log`. Gleiches Ergebnis im Lauf 15:57–16:01. Nutzer-Gegenproben: vier A/W-API-/ApplicationName-Kombinationen im PowerShell-Prozess PASS (Exit 7); absoluter MSIX-EXE-Start aus administrativer cmd.exe PASS (Exit 7); vollständige ursprüngliche Editor-Fixture aus cmd.exe PASS (Exit 0, SAVED). Allgemeine MSIX-Startblockade nicht belegt. Neue testbuild- und GUID-gesteuerte One-shot-Datei `process-temp/editor-launch.txt` erfasst vor CreateProcess expandierten Befehl, Argumente, Arbeitsverzeichnis, Commandline, ApplicationName, ACP und Startflags. GUI-Runner meldet sie bei FAIL mit dem vorhandenen Win32-Dialog; bei PASS verlangt er eine nichtleere Datei. **Kein Windows-Lauf auf dem neuen Diagnosecode; Produktfehler bleibt offen.**

**Unmittelbar nächster Schritt:** Diagnosecommit beziehen und `pwsh -NoProfile -File tools/release/tests/Invoke-IsolatedLegacyFind.ps1 -Configuration Debug -EditorScenario ExternalEditor` ausführen; `Editor-launch` und `Owned-error-dialog` auswerten. Der normale Manager-Test bleibt vollständig.

**Testinfrastrukturfehler vom 13:56-Lauf inzwischen verifiziert behoben (MGMT-02/MGMT-03):** Der ParserError aus `Test-DevelopmentContinuity.ps1` wurde mit `${id}:` korrigiert. Auf `a928794c` lief `manage.cmd --test` am 24.11. von 14:02 bis 14:03 erfolgreich; die Parser-Vorprüfung prüfte 66 Skripte und erkannte den negativen Syntaxfall. Die weitergehenden MGMT-02-/MGMT-03-Abnahmekriterien sind dennoch offen.

1. **P0 – Unicode-Elternverzeichnis, A1/A2, UP-06 und UP-04:** Der reproduzierbare Fehler in Debug/Release auf `dbcf0d13` ist noch nicht abschließend behoben. **Teilimplementierung 24.11.:** `src/fileswn2.cpp::ChangeUnicodePathToDisk` nimmt jetzt einen Windows-8.3-Kurznamen nur dann als Zugang, wenn er verlustfrei nach ANSI konvertierbar ist und **Original- und Alias-Verzeichnis dieselbe Volume-/File-ID** besitzen; `GetDiskPathW()` bleibt die echte Unicode-Identität. Ein nativer Regressionstest `unicode_directory_panel_alias.cpp` ist in `--test` registriert. **Auf Volumes ohne 8.3-Alias bleibt die Navigation bewusst gesperrt; das ist keine vollständige A1/A2-Lösung.** Die GUI-Pfadanzeige/Verlauf, sämtliche Dateipanel-Operationen, UNC und allgemeine native W-Panelnavigation müssen noch migriert/geprüft werden. Der neue **native 8.3-Regressionstest ist auf `9f524264` unter Windows PASS**, aber beide **GUI-Durchläufe wurden vor der Produktausführung durch eine bereits laufende Salamander-Instanz blockiert**. Keinesfalls best-fit ANSI-Fallback oder stilles falsches Ziel zulassen.
2. **P1 – Legacy Find ExternalEditor / FIND-04, QA-03:** **Am 24.11. 14:59–15:02 auf `3119af03` real erneut FAIL:** `--test-gui-legacy-find --debug` mit 36 PASS/1 FAIL/0 SKIP, nur `ExternalEditor` `NOT_STARTED`; `ExternalEditorNative` PASS. Der neu eingeführte **unabhängige PowerShell-Preflight lief PASS**, einschließlich korrekter Testdatei-Veränderung, und setzte danach den Erfolgsmaker zurück. Der Fehler liegt daher wahrscheinlich in `src/fileswn5.cpp::CFilesWindow::EditFile` bei CreateProcess/Argumenten, aber eine endgültige Ursache ist noch nicht gemessen. **Neue ungetestete, enge Produktkorrektur:** `src/common/win32_editor_process_launch.h` übergibt bei *nachweisbar vorhandenem, absolutem `.exe`-Pfad* das Programm ausdrücklich als `lpApplicationName` an `CreateProcessA`, statt es nur aus `lpCommandLine` erkennen zu lassen; relative und andere Programme behalten den ursprünglichen Null-Anwendungsnamen. Regression `tools/tests/editor_process_launch.cpp` in `--test`; Original-Find/PowerShell-/cmd.exe-Tests unverändert; statischer Vertrag `Test-LegacyFind-UiContract.ps1` erweitert. Bei erneutem Fehler protokolliert der GUI-Test nur Fenstertitel des eigenen isolierten Salamander-Prozesses. **Nächste Verifikation:** `manage.cmd --build-delta --test`, danach `--test-gui-legacy-find --debug` und ggf. `--release`. Bis zum echten Windows-PASS bleibt FIND-04/QA-03 offen; kein ungestütztes Erfolgsversprechen. **Neuer Build-Befund 15:12 / `3820e636`:** Der Fix kompiliert in diesem Zustand nicht: `HANDLES` ist ein Member-Dispatch-Makro (`__Handles.SetInfo(...).CreateProcess(...)`), kein generischer Wrapper. Aufruf nun als **`HANDLES(CreateProcess(Salamander::GetExplicitEditorApplicationName(expCommand), ...))`** korrigiert und Handle-Tracking beibehalten; redundant gewordene Hilfsfunktion entfernt, nativer Test auf echten `CreateProcessA` umgestellt und Quellenvertrag gegen `HANDLES(Salamander::...)` ergänzt. **Noch kein neuer Build-/Test-/GUI-PASS; FIND-04/QA-03 weiterhin offen.** **Neuer tatsächlicher Test auf `8a6de88` um 15:28:** Debug-x64-Kompilierung PASS, die GUI-Editoraktion weiterhin FAIL/`NOT_STARTED`; test-eigener Dialog `Open Salamander` sichtbar. Die explizite `lpApplicationName`-Korrektur allein genügt somit nachweislich nicht. **Nächster Schritt:** GUI-Diagnose liest künftig ausschließlich die Kindtexte des verifizierten eigenen `Open Salamander`-Dialogs aus, um den genauen Startfehler festzustellen. Kein automatisches Schließen und kein Editor-Retry. Die aktuelle Änderung ist nur eine Diagnostikerweiterung, noch ohne Windows-Test.
3. **P1 – About:** `src/logo.cpp` zeigt eine zusätzliche Zeile mit Datum/Uhrzeit des **EXE-Dateiänderungszeitstempels** sowie Debug/Release und Architektur. Der native Formatierungstest bestand; optische Darstellung, Tooltip/Layout, Lokalisierung und eine womöglich nachträglich veränderte EXE-Zeit wurden noch nicht am tatsächlichen GUI-Dialog verifiziert. Dateiänderungszeit ist nicht automatisch ein fälschungssicherer Linker-Buildzeitstempel.
4. **P0/P1 – weitere Hauptprogramm-/Plugin-Lücken:** Große gemischte Datei-/Ordnerauswahlen, gesamte Verzeichnisbäume, Cross-Volume inklusive ADS, Shell-/Editor-/Archiv-/Plugin-Grenzen, UNC/SMB und Reparse Points. **Der ausdrücklich beauftragte funktionsfähige UnRAR-Ersatz (Chat 09) ist weiterhin nicht belegt und muss in UP-03 geprüft werden.** Das Microsoft-Abhängigkeitsinventar liegt in `Microsoft-Dependencies-2026.md`. Siehe **UP-02 bis UP-07** und **QA-01**. Programm nicht als vollständig unicode-/langpfadfähig deklarieren.
5. **A0, A5, A7 – Release:** Original-UI-A/B, alle Plugins, WIC-Host/Animationsparität, x86-Matrix, echte saubere Windows-11-VM, Installer-/Uninstall-/Upgrade-, Lizenz-/Signaturgates fehlen. Keine GO-Entscheidung.

**Neue GUI-Voraussetzungsprüfung / MGMT-02, QA-03 (nach `9f524264`, noch nicht auf Windows ausgeführt):**
`tools/release/Wait-SalamanderGuiAvailability.ps1` wird von `tools/Manage-Salamander.ps1` nach den nichtinteraktiven Tests, vor GUI-relevanten Aktionen eingebunden.
Bei bereits laufender `salamand.exe` meldet der Manager deren PID(s) einmal, wartet im Abstand von 1000 ms auf das **reguläre Schließen durch den Benutzer** und setzt automatisch fort, sobald keine Instanz mehr läuft.
Kein automatisches `Stop-Process`, kein Fenster-/Tastaturzugriff, mit Strg+C abbrechbar.
Der Poll wird **nur einmal vor der GUI-Suite** ausgeführt; verbleibende eigene Testprozesse nach einem fehlerhaften GUI-Fall und unerwartete neue Instanzen werden weiterhin durch die vorhandenen untergeordneten Schutzprüfungen abgewehrt.
Für normale `--test`, `--build`, `--setup` und `--run` wird nicht gewartet.
`tools/release/tests/Test-Manage-GuiWait.ps1` ist in `--test` und `--test-all` registriert und prüft mehrere PID, den Wegfall der Prozesse, die Nicht-GUI-Ausnahme und Cancellation mit simulierten Prozessabfragen.
**Noch offen:** echter Windows-PowerShell-Lauf des neuen Tests und erneute Debug-/Release-GUI-Produkttests. Der letzte reale erfolgreiche Build/Test-Quellstand bleibt `9f524264`; Produktfehler sind damit nicht als behoben nachgewiesen.
**Weitere offene GUI-Befunde aus `8a6de88`, 15:28–15:32 (FIND-04 / QA-03):**
- **AdvancedInputs:** `SelectLegacyFindRow` hat korrekt vor Tastaturnavigation abgebrochen, weil `GetKeyState(VK_SHIFT)=0xFF81`; die am Test-STA abgefragte *queued* KeyState kann gegenüber der tatsächlichen physisch gehaltenen Taste veraltet sein. Neuer Testtreiber prüft `GetAsyncKeyState` mit bis zu 2 Sekunden Wartezeit auf Freigabe physisch gedrückter Shift/Ctrl/Alt-Tasten, verwirft niemals einen aktuell gedrückten Modifikator und sendet keine künstliche Key-up-Nachricht. Bei anhaltendem Zustand weiterhin FAIL mit physischen und queued Werten.
- **ShellClipboard:** tatsächlicher Copy-Clipboard-Befehl hat die erwarteten zwei Pfade und den Drop-Effekt nicht innerhalb des ursprünglichen Timeouts geliefert; *Cut wurde in diesem Fall nicht erreicht*. Neuer Fehlerbericht erfasst nur Sequenznummern, Formatnamen, Pfadanzahl, Effekt, Fehlercode, Foreground und Fenster des eigenen Testprozesses. Die exakten Datei-/Effekt-/Byte-Assertions bleiben unverändert, keine Wiederholung des Copy-Befehls.
- **ExternalEditor:** Kontroll-PowerShell PASS, GUI-Aktion `NOT_STARTED`, test-eigener Dialog `Open Salamander`; Kindtexte des eigenen Dialogs werden beim nächsten Timeout ausschließlich mit zeitbegrenztem `WM_GETTEXT` und PID-/Dialogklassenprüfung protokolliert, weil fremdprozessuales `GetWindowTextW` bei Child-Controls unzuverlässig ist. Ursache noch nicht belegbar, kein weiteres spekulatives Produkthandling.
**Diese drei Treiber-/Vertragsänderungen sind statisch gegengeprüft, aber noch NICHT unter Windows ausgeführt.** Empfehlung: erst `manage.cmd --test` für Vertrags-/Syntaxgates, dann GUI-Debug-Lauf bei möglichst ungestörtem interaktivem Desktop; den neuen Fehlerbericht auf genaue Win32- und Clipboard-Befunde prüfen.
## 5. Build, Tests, Sicherheitsvorkehrungen

```powershell
cd C:\Repositories\Salamander
git status --short
git branch --show-current
git rev-parse HEAD
# Nur nach ausdrücklicher Zustimmung aktualisieren:
# git pull --ff-only origin bugfix/v5.2
# Optional für gezielte Diagnose; bereits innerhalb --test auf a928794c bestanden:
# pwsh -NoProfile -File .\tools\release\tests\Test-PowerShellSyntax.ps1
# pwsh -NoProfile -File .\tools\release\tests\Test-DevelopmentContinuity.ps1
.\manage.cmd --build-delta
.\manage.cmd --test  # Bereits PASS auf 9f524264, einschließlich nativer 8.3-Regression
# Wenn Salamander noch läuft, meldet manage.cmd dies und wartet vor GUI-Tests
# automatisch auf das reguläre Schließen durch den Benutzer (Strg+C: Abbruch).
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
