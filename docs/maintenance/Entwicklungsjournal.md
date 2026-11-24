# Salamander 5.2 – chronologisches Entwicklungsjournal

> **Append-only Gedächtnis für ChatGPT, Codex und Entwickler.**
> Letzte Konsolidierung: **2026-11-24**; weitere Einträge nur datiert ergänzen.
> Konsolidiert aus **Salamander-Chat-01.pdf bis Salamander-Chat-12.pdf**,
> `Master-Prompt.odt`, `Anforderungen.md`, den bereits versionierten
> Architektur-/Migrationsdokumenten und den nachfolgenden Benutzerlogs
> bis **24. November 2026, ca. 13:00 CET**.
> **Keine wortgetreuen Chat-Transkripte:** Diese sind umfangreich, enthalten
> redundante Testausgaben und möglicherweise personenbezogene Pfade.
> Das Journal bewahrt die fachlich relevanten Aufträge, Befunde,
> Entscheidungen, Nachweise und Restarbeiten. Details werden über
> Archivnummern und die vorhandenen Repository-Dokumente referenziert.
> **Aktueller Zustand:** [Arbeitsstand-und-Uebergabe](Arbeitsstand-und-Uebergabe.md).
> **Verbindliche Aufgabenliste:** [Testluecken-und-Abnahmeplan-5.2](Testluecken-und-Abnahmeplan-5.2.md).
> **Produktvertrag:** [Anforderungen A0–A7](../../Anforderungen.md).

## Quellenqualität und Nachvollziehbarkeit

- Die Archive **Chat 01–10** liegen als bildbasierte PDFs ohne eingebetteten
  Text vor. Sie wurden über die gerenderten Bildseiten textlich ausgewertet;
  die automatische Erkennung kann einzelne Wörter, Zahlen oder Codefragmente
  falsch erfassen. **Chat 11–12** enthalten extrahierbaren Text.
- Deshalb enthält dieses Journal ausdrücklich **thematische, überprüfte
  Verdichtungen**, keine wörtliche, in jedem Zeichen garantierte Wiedergabe
  der 644 bildbasierten Seiten. Exakte Commit-SHAs, API-Namen und
  Abnahmewerte wurden soweit möglich mit heutigen Repository-Dokumenten
  und späteren Nutzer-Logs abgeglichen.
- Bei einer fachlich strittigen historischen Detailfrage zuerst den
  konkreten Archiv-Chat und dessen Originalseite erneut prüfen. Diese
  Regel verhindert, dass OCR-Verwechslungen zum neuen Programmvertrag werden.
- Die gespeicherten Archiv-PDFs sind historische Projektquellen und
  **nicht** Bestandteil dieses Git-Commits. Die in ihnen enthaltenen
  personenbezogenen lokalen Testpfade, Bildschirmtitel und möglichen
  Diagnosedaten werden absichtlich nicht ins Git kopiert.

## Entscheidungsregeln

**R-01 – Benutzeraufträge erhalten:** Arbeite eigenständig und gründlich an
autorisierten Aufgaben, wiederhole RED/GREEN/Review/Verifikation, frage nicht
unnötig nach und verliere beim Chatwechsel keinen offenen Punkt. Für neue
Sitzungen den aktuellen Branch und die Quellen erneut prüfen.

**R-02 – Originalfunktionen erhalten:** A0–A7 haben Vorrang: Original-UI,
Tastatur, Konfiguration, vollständiger Legacy-Suchdialog, Plugin-ABI, echte
Unicode-/Langpfadidentität, WIC-PictView und saubere Release-Pakete.
Stille Einschränkungen oder Ersatzimplementierungen sind unzulässig.
Ausnahmen nur bei ausdrücklichem Auftrag, wie SalMon→WER.

**R-03 – TDD und Testintegrität:** Aus `Master-Prompt.odt` und den mehrfach
wiederholten Benutzeraufträgen: Analyse → fachlich fehlschlagender RED-Test →
kleine GREEN-Korrektur → Refactor → AAA-/Negativtests → realer Build/GUI-Test.
Tests nie einfach umdefinieren oder kürzen, um PASS zu erzeugen. Einen
veralteten Vertrag zuerst mit dem ursprünglichen beabsichtigten Verhalten
abgleichen; Korrekturen begründen. Alle unabhängigen Fehler sammeln, Risiken
durch GUI-, Registry-, Clipboard- und Dateizugriffe begrenzen.

**R-04 – Architektur/Korrektheit:** Tatsächliches Projekt ist natives
C++/Win32 ohne MFC, **nicht** Godot/C#. KISS, Clean Code, klare Ownership,
RAII wo kompatibel, kompakte nachvollziehbare Methoden, Schutz von API/ABI
und Bestandsverhalten. Englische C++-Namen/Kommentare, deutsche Ergebnisse,
korrekte Fehlerbehandlung, kein unbelegter Build-PASS.

**R-05 – Toolchain/Steuerung:** Visual Studio 2026; `manage.cmd` bei
Build-/Test-/Release-Änderungen eigenständig pflegen. Besonders `--update`
(nur mit Autorisierung), `--build`, `--build-delta`, `--build-clean`,
`--test`, `--test-all`, `--setup`. Nur `bugfix/v5.2` als
regelmäßigen Entwicklungsbranch nutzen, sofern der Nutzer nicht ausdrücklich
etwas anderes bestimmt. Fremde Worktrees/Änderungen nicht überschreiben.

**R-06 – Ehrlicher Status:** Implementiert ≠ statisch geprüft ≠ lokal
ausgeführt ≠ alle Konfigurationen/Plugins/VM bestanden. Ungetestete Lücken
bleiben offen. Keine Speicherung persönlicher Logdetails oder ungeprüfter
Dumps im Repository. Die lokale Testumgebung liegt beim Nutzer; abgelegte
User-Logs sind externe Nachweise, keine automatisch versionierten Artefakte.

**R-07 – Dauerhaftes Protokoll:** Nach jedem autorisierten Auftrag
(1) hier datierten Eintrag ergänzen, (2) betroffene stabile Gap-IDs im
zentralen Abnahmeplan aktualisieren, (3) den kompakten Übergabestand
aktualisieren, (4) `manage.cmd`-/Test-Registry bei Bedarf anpassen.
Zusammengehörige Änderungen im selben autorisierten Commit/PR. Journal
niemals stillschweigend umschreiben; Korrekturen als neue datierte Zeile.

## Zentrale Architekturentscheidungen (auch künftig gültig)

| ID | Entscheidung und Begründung | Source / Bezug |
| --- | --- | --- |
| D-01 | VS 2026 + bestehende MSBuild-/Sln-/Pluginstruktur, keine frei erfundene Projektmigration | Chat 01, 02; A3; `src/vcxproj/` |
| D-02 | Native **UTF-16/W**-Pfade als Identität, ANSI nur exakt und kontrolliert, sonst fail-closed; Namenskollisionen verhindern | Chat 02–04, 09, 12; A1/A2; `src/common/` |
| D-03 | Bestehendes `CFileData`-/Plugin-SDK-/`COperation`-Layout beibehalten; W-Identität über Adapter/Sidecars, Worker und überprüfte Grenzen führen | Chat 09–12; UP-02/04 |
| D-04 | Originalen `IDD_FIND`/Strg+F weiterentwickeln, keine vereinfachte Ersatz-GUI; Alt+Shift+F7 ist ein separater Unicode-Find-Pfad | Chat 05, 09–12; A0/A6 |
| D-05 | PictView über WIC; 13 registrierte Extensions als Testinventar, separate echte Host-/WIC-Codecmatrix, keine proprietären PVW32-Konverter | Chat 06–08, 11; A7 |
| D-06 | GUI-Tests in eigenen Salamander-Prozessen mit GUID-Registry, TEMP, kontrollierter Zwischenablage, eigenen Fixtures, geprüften HWNDs und Bounded-Timeouts. Keine globalen ungesicherten Eingaben oder fremden Prozesskills | Chat 02–04, 10–12; QA-03 |
| D-07 | Große Unicode-F5/F6-Transfers über vorhandenen Hintergrund-Worker mit Fortschritt/Pause/Abbruch; bei F6 Quell-/Zielidentität, kein stilles Überschreiben oder Löschen vor Datenintegritätsprüfung | Chat 11–12; UP-04 |
| D-08 | SalMon-Upload/Crash-Dialoge auf ausdrücklichen Benutzerauftrag entfernt und WER für Crashanalyse vorgesehen; lokale Dumps nur Opt-in | Chat 10; `WER-Local-Crash-Dumps.md` |
| D-09 | Debug-/Release-/x86-/x64-/Pluginmatrix plus Clean-VM-/Installer-Abnahme als Release-Gates; erfolgreicher Testlauf ist keine vollständige Releasefreigabe | Chat 07–12; A0–A7 |
| D-10 | Buildroot standardmäßig `<Repository>/.Build/`, gitignoriert; Verzeichniswechsel darf inkrementelle Builds nicht unnötig komplett erzwingen | aktueller Chat 24.11.; A4 |
| D-11 | `--test-all` führt unabhängige Testfälle sequenziell trotz FAIL weiter; Bericht enthält PASS/FAIL/SKIP, Zeit, Fehlergrund und JSON; bei unsicheren Voraussetzungen keine GUI-Aktion; Gesamtlauf bleibt FAIL | aktueller Chat 24.11.; MGMT-02/03 |
| D-12 | About-Dialog zeigt Debug/Release + x86/x64 und EXE-Dateiänderungszeit; dieser Zeitstempel ist kein unveränderlicher PE-Buildnachweis; tatsächliche GUI-Darstellung gesondert prüfen | aktueller Chat 24.11.; A0 |
| D-13 | Kein neuer Sprint-/Issue-Tracker: die 35 stabilen Gap-IDs des bestehenden Abnahmeplans bleiben einzige maßgebliche To-do-Liste; Journal enthält **Historie**, Übergabe **Momentaufnahme** | Auftrag 24.11.2026 |

## Chronologie

### J-20261113-01 — Chat 01: VS-2026-Migration, Hilfe und erste Langpfadtests

- **Aufträge:** Visual Studio 2022 durch Community 2026 ersetzen;
  Update-Skript sorgfältig anpassen; Build-/Test-/Update-Workflow für Debug/
  Release, HTML-Hilfe und 7z; F1-Hilfe reparieren; Dateinamen-/Langpfadprobleme
  einschließlich GUI und automatisierter Tests vollständig bearbeiten.
- **Befunde/Entscheidungen:** Die reale Salamander-Codebasis ist C++/Win32;
  Toolchain/SDK und MSBuild müssen geprüft werden. Hilfe muss nicht nur gebaut,
  sondern für F1 korrekt bereitgestellt und gefunden werden. Build-/Testpfade
  und GUI-Rückmeldungen getrennt prüfen.
- **Status:** VS-2026- und Hilfebuild wurden damals lokal iteriert;
  spätere Builds/Verträge im Repository bestätigen Teilbereiche. Die
  Vollständigkeit von A1/A2 und Release blieb offen.
- **Nachweise:** `Salamander-Chat-01.pdf`; VS-Build-Dateien, `README.md`,
  `tools/Manage-Salamander.ps1`.

### J-20261113-02 — Chat 02: Test-HWND, Unicode-Dateiidentität, GUI

- **Aufträge:** `manage.cmd --update` benutzen können; vor Umbauten erst
  Tests; F2/F5/F6/F8 und Unicode-GUI weiterentwickeln; Zeit nicht in
  Fehlidentifikation von Prozessen/Fenstern verlieren.
- **Befunde:** Testtreiber hatte anfangs nicht sicher das richtige Salamander-
  Fenster angesprochen; Start-/Fenstertitel und Fensterklassen verifizieren,
  GUID-eigene Fixtures und sichere Auswahl verwenden. Windows-ACP-Aliase
  reichen nicht zur Dateiauswahl oder zum Löschen.
- **Status:** Viele GUI-Baseline-/Unicode-Regressionen später integriert,
  aber lange und nicht-ACP-fähige Elternverzeichnisse weiterhin offen.
- **Nachweise:** `Salamander-Chat-02.pdf`;
  `Test-SalamanderGui-LongPaths.ps1`, `src/fileswn*.cpp`.

### J-20261114-01 — Chat 03: echter MAX_PATH-Fix und iteratives RED/GREEN

- **Aufträge:** Langpfadkorrektur **vollständig** mit Tests; bei Fehlern
  selbstständig erneut iterieren, nicht nur Fortschrittsberichte erzeugen;
  fehlende lokale Windows-Ausführung über Nutzerprotokolle verifizieren.
- **Befunde/Entscheidungen:** W-basierte Pfadnormalisierung und
  Komponentenlängen/GUI-Navigation müssen zusammen getestet werden;
  isolierte native Unit-Tests ersetzen keinen echten GUI-Lauf.
- **Status:** Anfangstests und Meilensteine entstanden, A1/A2 insgesamt offen.
- **Nachweise:** `Salamander-Chat-03.pdf`, spätere
  `Unicode-LongPath-Implementation.md`.

### J-20261114-02 — Chat 04: vollständige Testaufrufe, manuelle Matrix, TEMP-Cleanup

- **Aufträge:** Alle vorhandenen Tests über Manager aufrufbar machen;
  manuelle Checkliste; von GUI-Tests erstellte tiefe temporäre
  Verzeichnisbäume korrekt und sicher löschbar machen.
- **Befunde:** Einzelne Win32-Langpfadfunktionen reichen nicht für F8,
  Shell-/Papierkorb- und rekursive Löschpfade. Test-Fixtures müssen
  eindeutig dem Test gehören und nach Fehlern diagnostizierbar bleiben.
- **Status:** Eigenständige Tests und F8-Szenarien ergänzt; nicht alle
  Unicode-/Plugin-/Delete-Pfade als fertig verifiziert.
- **Nachweise:** `Salamander-Chat-04.pdf`, `tools/tests/unicode_directory_delete.cpp`,
  `tools/release/tests/Test-SalamanderGui-LongPaths.ps1`.

### J-20261115-01 — Chat 05: umfassendes Review, Legacy-Suche, Plugins

- **Auftrag:** Intensives Code-Review aller Änderungen, insbesondere des
  Suchdialogs, Unicode-/Langpfadfähigkeit und Plugin-Kompatibilität.
- **Befunde:** Original-UI/Legacy-Filter und Plugin-SDK-Grenzen müssen
  systematisch auditiert werden; ein einfacherer Suchdialog oder nur
  UTF-16-Hilfsfunktionen erfüllen die Nutzeranforderungen nicht.
- **Status:** Review- und Migrationsarbeiten ausgebaut; siehe Legacy-Find-
  Dokument und UP-02/03/FIND-03.
- **Nachweise:** `Salamander-Chat-05.pdf`.

### J-20261116-01 — Chat 06: GUI-Integration, sichere Testkonfiguration, WIC-Auftrag

- **Aufträge:** Offene Integrationsfälle automatisieren; GUI-Treiber verbessern;
  fortführende Unicode-/Plugin-/Papierkorb-Unterstützung; nicht mehr verfügbare
  proprietäre PictView/UnRAR-Abhängigkeiten untersuchen; PictView auf WIC umstellen.
- **Befunde/Entscheidungen:** Testbuild-Markierung (`ST`) muss von
  Produktionsrelease unterschieden bleiben. GUI-Prozesse/Clipboard/Registry
  isolieren, keine fremde Konfiguration anfassen.
- **Status:** WIC-Umstellung umgesetzt und Tests ergänzt; echte vollständige
  Viewer-/Plugin-/Format-Abnahme offen. UnRAR-Ersatz nicht als fertig belegt.
- **Nachweise:** `Salamander-Chat-06.pdf`, `docs/pictview-wic-migration.md`.

### J-20261116-02 — Chat 07: Version 5.2, PictView/PR und Release-Gates

- **Aufträge:** Version **5.2** setzen, PictView vollständig integrieren;
  `manage.ps1` aktualisieren; lokal ausführbare automatisierte Tests;
  Änderungen aus PR #8 in den gemeinsamen Entwicklungsbranch integrieren;
  Release-Prüfungen bis zur main-Merge-Reife fortsetzen.
- **Befunde:** Integration eines PR ist nicht gleich Releasefreigabe.
  Paketinhalt, WIC-/Plugin-Laufzeit und CI auf derselben Commit-SHA prüfen.
- **Status:** 5.2-Version und WIC-Tests belegt, Release-Gates weiter offen.
- **Nachweise:** `Salamander-Chat-07.pdf`, `Release-5.2-Gates.md`.

### J-20261116-03 — Chat 08: Release-Iteration, Branchdisziplin

- **Aufträge:** Bis zur echten Release-Reife iterieren, keine
  Erfolgsmeldung ohne Endtest; erfolgreiche Änderungen geordnet nach main
  übernehmen, keine verstreuten unkontrollierten Entwicklungsbranches.
- **Entscheidung:** Spätere Arbeit auf festem `bugfix/v5.2`,
  getrennte Referenz-/RC-Branches nur kontrolliert und mit Nachweisen.
- **Status:** Kein aktuell belegtes GO für den heutigen v5.2-Stand.
- **Nachweise:** `Salamander-Chat-08.pdf`, Release-Gates.

### J-20261117-01 — Chat 09: acht konkrete Gesamtaufträge / A0–A7

- **Verbindlicher Auftrag:** Ausschließlich `bugfix/v5.2` verwenden;
  UTF-16 und Langpfade **in Hauptprogramm und Plugins** systematisch testen,
  jede echte Lücke zuerst mit Test absichern; von Salamander nicht löschbare
  eigene Unicode-TEMP-Verzeichnisse per F8-Regression angehen; VS-2026-
  Migration vervollständigen; **funktionierenden UnRAR-Ersatz** erarbeiten;
  veraltete Microsoft-Abhängigkeiten inventarisieren; alle verfügbaren
  automatisierten Tests über `--test-all`; saubere 7z/Setups;
  **Originalen Strg+F/Advanced/Regex-Suchdialog wiederherstellen** und
  Unicode/Langpfade in ihn integrieren.
- **Designentscheidung:** Kein ANSI-Fallback, keine vereinfachte
  Ersatzsuche; Legacy-Find-Worker/-Ergebnisidentitäten und UI gemeinsam
  migrieren. UnRAR-Fähigkeiten/Lizenzen vor Ersatzentscheidung prüfen.
- **Status:** Microsoft-Abhängigkeitsinventar liegt in
  `Microsoft-Dependencies-2026.md`; Legacy-Find-Migration und Manager-
  Registrierung weit fortgeschritten. **UnRAR-Ersatz, sämtliche Plugins,
  A1/A2 End-to-End und Release weiterhin offen**.
- **Nachweise:** `Salamander-Chat-09.pdf`; UP-02/03, FIND-03/04,
  PKG-01…05, A0-01, BUILD-01.

### J-20261117-02 — Chat 10: Build-/GUI-Zuverlässigkeit, WER, Commitrecht

- **Aufträge:** Inkrementellen Delta-Build statt ständigen Rebuilds;
  `--test-gui-temp-delete` einzeln vs. `--test-all` vergleichen; echte
  GUI-Stalls und Dumps diagnostizieren; lokale Testausgabe wieder in
  Zwischenablage; Arbeit direkt mit GitHub auf `bugfix/v5.2`, dort
  Commits erlaubt; SalMon samt Upload-/Crash-Dialogen **ausdrücklich**
  entfernen und durch WER/lokale Analyse ersetzen.
- **Befunde:** OS-DLL-Load und Debug-Handle-Monitor konnten Lock-Inversion
  verursachen; LoaderLock-Verträge/opt-in Dumps ergänzen, nicht bloß Timeout
  erhöhen. WER-Dumps dürfen nicht ohne Nutzerentscheidung aktiviert werden.
- **Status:** SalMon/WER-Migration dokumentiert, Diagnose-/Buildhelfer
  ausgebaut; echte Last-/Wiederholbarkeitsmatrix bleibt offen.
- **Nachweise:** `Salamander-Chat-10.pdf`;
  `WER-Local-Crash-Dumps.md`, `Test-HandlesLoaderLock-Contract.ps1`.

### J-20261118-01 — Chat 11: Delta-Build, Qualitätslücken, erster Aufgabenplan

- **Aufträge:** Buildskripte für volle und echte inkrementelle schnelle
  Builds; Testlücken vollständig und selbstständig schließen; das Ergebnis
  einer späteren Sitzung in **einem versionierten ausführlichen Plan**
  festhalten und schrittweise **von oben nach unten** abarbeiten.
- **Befunde:** Große Unicode-Transfers, Registry-/GUI-Fokus, Plugins
  und Original-Find sind getrennte Akzeptanzbereiche. Ein grünes
  `--test-all` ist keine 100-%-Coverage. Tests ohne GUI-Kontext können
  falsch positive Sicherheit suggerieren.
- **Nachweise:** Historischer kompletter `--test-all`-PASS am
  23.11.2026, Referenz `a7ab5b40...`; Anlage des
  `Testluecken-und-Abnahmeplan-5.2.md` mit 35 stabilen IDs, A0–A7 und
  M0–M6; Inventar der 35 Pluginprojekte / 36 Ordner.
- **Status:** Roadmap und source-/native Tests erweitert, keine
  vollständige Plugin-/VM-/GUI-Freigabe.
- **Nachweise:** `Salamander-Chat-11.pdf`, `test-coverage-audit-2026-11-23.md`.

### J-20261123-01 — Chat 12: Arbeitspakete, Hauptprogramm und große F5/F6-Fälle

- **Aufträge:** Dokumentierte Pakete ohne Rückfragen bearbeiten; nach
  grünen Tests weiterarbeiten; Hauptprogramm-Unicode/-Langpfade
  **vollständig** abschließen; fehlerhafte Workerpfade und Mehrfachauswahl
  gezielt beheben, nicht nur Teileinheiten.
- **Umsetzung damals (Quellstand `ccc46b8f...`):** Große
  Cross-Volume-F6-Dateien über Worker, gemischte F5/F6-Pfade
  hinsichtlich Quell-/Ziel-Dateiidentität geschützt, Worker-Pause/
  -Abbruch/Progress weiterverwendet, `CREATE_NEW` gegen Zielkollision,
  binärer Vergleich vor endgültigem F6-Quellenlöschen und ADS-Regeln.
- **Status zum Ende von Chat 12:** statisch geprüft, **noch kein**
  Windows-Test auf `ccc46b8f...`; weitere Verzeichnisbaum-/Shell-/
  Plugin- und gemischte Batchfälle offen. Der Wunsch nach `.Build/`
  folgte unmittelbar.
- **Nachweise:** `Salamander-Chat-12.pdf`, `src/fileswn8.cpp`,
  `src/worker.cpp`, `tools/tests/worker_copy_io.cpp`.

### J-20261124-01 — aktueller Chat: Buildroot, Testvertragsreparaturen, Sammellauf

- **Benutzeraufträge:** `D:\Build\OpenSal` ins Repository-`.Build/`
  verlagern (physische Migration benötigt lokalen Windows-Zugriff);
  Verzeichnis gitignorieren; sporadisch scheinende Testfehler erklären,
  bestehende Tests nicht unberechtigt ändern; unabhängige Tests
  nach einem Fehler weiter ausführen, statt Gesamt-Suite früh
  abzubrechen.
- **Befunde:** Verschiedene FAILs wurden nach dem jeweils vorherigen
  Fail-fast-Fix erst sichtbar; teils veraltete F5/F6-Verträge, teils
  fehlerhafte C++-Fixture-/Variablendeklarationen. Nicht jeder FAIL ist
  Produktfehler. Status-/Fehleraggregation `Test-RunCollection.ps1`
  speichert JSON und Nonzero-Exit; Opt-in GUI-Prozesse isolieren.
- **Umsetzung:** `.Build/` über
  `tools/Manage-Salamander.ps1`, `Build-Helpers.ps1`,
  Paketierungshelfer und `.gitignore`; Vertragstestkorrekturen
  (`77332349`, `25205cee`), native Variablennamen
  (`82edbc0c`), Sammellauf (`a35cf827`).
- **Nachweis:** Nutzer-Delta-Builds ca. 122 s / 8 s. Erster kompletter
  Sammellauf zuvor **86 PASS, 5 FAIL**; anschließend gezielte
  Regressionen/Korrekturen. Kein gesamtes aktuelles `--test-all`
  PASS auf späterer SHA.

### J-20261124-02 — aktueller Chat: About-Dialog und Test-F5/F6

- **Auftrag:** About-Dialog um Build-Datum/-Uhrzeit und Buildvariante
  Debug/Release erweitern.
- **Umsetzung:** `src/common/about_build_info.h`, `src/logo.cpp`
  und `tools/tests/about_build_info.cpp`; unveränderte historische
  About-Ressource, zusätzliche Textzeile zur Laufzeit.
- **Nachweise:** Nutzer-`--test` am 24.11.2026 auf
  `02acf27c...` PASS, inklusive nativem About-Test;
  `--test-gui-unicode-multiselect --release` auf
  `dbcf0d13...` PASS inklusive 17-MiB-Transfers.
- **Offen:** Sichtbare Platzierung/Lokalisierung und echte About-GUI-
  Prüfung; Datei-`LastWriteTime` ist nicht in jedem Szenario exakt
  die tatsächliche Linker-Buildzeit.

### J-20261124-03 — aktueller Chat: zwei echte verbleibende GUI-Probleme

- **Beobachtet:** `--test-gui-unicode-parent` **Debug+Release FAIL**:
  `ChangeUnicodePathToDisk` zeigt bewusst „outside the active Windows
  code page“; anschließender synchroner WM_COMMAND 775 meldet Timeout.
  **Produktfehler weiterhin offen, keine unsafe ANSI-Umgehung.**
- **Beobachtet:** `--test-gui-legacy-find --debug` auf
  `02acf27c...` mit **36 PASS, 1 FAIL, 0 SKIP**:
  `ExternalEditor` (PowerShell) FAIL `NOT_STARTED`,
  `ExternalEditorNative` PASS. Viewer-Unicode-Fälle erneut PASS.
  Das Originalregressionsszenario bleibt erhalten; separate native
  Vergleichs-Fixture grenzt die Ursache ein.
- **Nachweise:** Nutzer-Logs
  `manage-20261124-125928-575-54f5eb.log`,
  `manage-20261124-130047-583-958536.log`. Keine
  vollständige Release-/VM-Abnahme.
- **Nächster Schritt:** dokumentiert in
  [Arbeitsstand-und-Uebergabe](Arbeitsstand-und-Uebergabe.md).

### J-20261124-04 — Auftrag zur dauerhaften Sitzungskontinuität

- **Auftrag:** Alle Chatarchive 01–12, `Master-Prompt.odt` und
  `Anforderungen.md` als Quellen analysieren; verbindliche Regeln,
  Findings, Aufträge, technische Entscheidungen, Testbelege und offene
  Punkte versionieren; ChatGPT-/Codex-Neustarts sollen nach Möglichkeit
  ohne alte Chatarchive anschlussfähig sein; zentrale Aufgabenliste
  **fortlaufend** aktualisieren, `manage.cmd` und Tests pflegen.
- **Umsetzung:** Originalanforderungen als Root-`Anforderungen.md`
  verfügbar gemacht; Root-`AGENTS.md` um obligatorische Lesereihenfolge
  und Dokumentationsprozess ergänzt; diese Chronik sowie
  `Arbeitsstand-und-Uebergabe.md` angelegt; README und
  bestehenden 35-ID-Abnahmeplan verknüpft; Strukturregression
  `Test-DevelopmentContinuity.ps1` vorgesehen.
- **Grenze:** GitHub-/Codex-Anweisungen und aktuelle Markdown-Dateien
  sichern den **abrufbaren Projektkontext**; sie schalten nicht
  automatisch ein nicht verbundenes neues ChatGPT-Gespräch auf GitHub.
  Ein neues Gespräch muss die Dateien tatsächlich laden.

### J-20261124-05 — PowerShell-Parserfehler der Übergabeprüfung / AST-Preflight

- **Benutzerbefund / Gap-IDs:** `manage.cmd --test` am **24.11.2026
  13:56 CET**, Windows NT 10.0.26300, PowerShell 7.7.0,
  Quell-SHA `8a5cb99da350a494f94fdb57087c7b7f8221c336`,
  sauberer Arbeitsbaum: Der erste Aggregationstest PASS, dann sofortiger
  **ParserError** in `Test-DevelopmentContinuity.ps1:37`.
  Betroffen **MGMT-02/MGMT-03 und QA-03**.
- **Ursache:** Der neue Test enthielt in einem expandierbaren
  PowerShell-String `$id:`. Die unmittelbar folgende Zeichenfolge
  `:` wird als Variablenscope-Syntax interpretiert. Das ist ein
  versehentlich eingeführter Testskript-Defekt, kein Salamander-
  Produktfehler und kein erfolgreich gelaufener Kontinuitätstest.
- **Korrektur:** Interpolation ausdrücklich mit `${id}:` begrenzt.
  Zusätzlich neues, eigenständiges
  `tools/release/tests/Test-PowerShellSyntax.ps1`: PowerShell-AST-
  Parser prüft **alle** PS1-Skripte im Repository-Root und unter
  `tools/` vor der übrigen Testsuite. Eine absichtlich ungültige
  Testfixture mit `$id:` muss vom Parser verworfen werden;
  tatsächliche Parserfehler werden gesammelt und mit Datei/Zeile/Spalte
  ausgegeben. `tools/Manage-Salamander.ps1::Run-Tests` führt die
  Prüfung als ersten `--test`-/`--test-all`-Schritt aus.
- **Commits / Dateien:** `a5e0545df9a4844c42fa48dfc6cd3d3539566d3d`
  (Korrektur der Interpolation), `275c2495` und `83078e7`
  (Syntax-Preflight), `6c7ef4e` (Registrierung im Manager);
  anschließend Fortschreibung der drei Entwicklungsdokumente.
- **Verifikation:** Quellcode aus GitHub zurückgelesen; **eine
  PowerShell-/Windows-Ausführung nach dem Fix liegt noch nicht vor**.
  Der alte `--test`-Lauf ist **FAIL**, die neue Prüfung noch
  `NICHT AUSGEFÜHRT`. Keinen neuen Gesamtgrünstand behaupten.
- **Nächster Schritt:** Nach `git pull --ff-only`
  `pwsh -NoProfile -File .\\tools\\release\\tests\\Test-PowerShellSyntax.ps1`,
  danach `Test-DevelopmentContinuity.ps1` und
  `.\\manage.cmd --test` auf genau dieser Source-SHA ausführen.
  Weitere echte Produktlücken gemäß aktuellem Übergabestand.
  
### J-20261124-06 — Windows bestätigt Parserfix und vollständiges `--test`-PASS

- **Auftrag/Befund, MGMT-02/MGMT-03:** Benutzertranskript
  `manage-20261124-140223-783-8d6f75.log`, 24.11.2026,
  14:02:23–14:03:38 CET, sauberer `bugfix/v5.2`-Checkout bei
  `a928794c7e4072777246d959ee9dd77c129e2d89`;
  Windows NT 10.0.26300 und PowerShell 7.7.0.
- **Verifikation:** `manage.cmd --test` **PASS**, alle angeforderten
  Schritte erfolgreich. `Test-PowerShellSyntax.ps1` parste alle
  **66** Repository-PowerShell-Skripte erfolgreich und erkannte die
  absichtlich ungültige `$id:`-Negativfixture. Testaggregation samt
  Fail-fast-/JSON-/GUI-Gating-Verträgen und
  `Test-DevelopmentContinuity.ps1` (Anforderungen, Dokumentationslinks,
  Journal, Übergabe und Abnahmeplan) ebenfalls **PASS**.
  **21 native C++-Regressionen** einschließlich About-Information,
  Unicode-Dateiidentität, Worker/Long-Path-I/O und 32.700er-Pfad
  ausgeführt; gezeigte Ergebnisse **PASS**.
- **Bewertung:** Der in J-20261124-05 dokumentierte ParserError um
  13:56 ist durch den echten Windows-Lauf **nachweislich behoben**.
  Keine produktive C++-Korrektur oder neue Abschwächung von Tests.
  Der alte FAIL-Beleg wird nicht überschrieben.
- **Einschränkungen:** Der physische Cross-Volume-Move blieb
  **SKIP** (nicht gesetztes `OPENSAL_CROSS_VOLUME_TEST_DIR`).
  Plugin-Inventarprüfungen mit `alpha`, `beta`, `rogue` sind
  synthetisch; keine vollständige Plugin-, GUI-, Installer- oder
  Clean-VM-Abnahme. Unicode-Elternverzeichnis und der externe
  PowerShell-Editor sind als vorherige GUI-FAILs weiterhin offen.
- **Änderungen:** Dokumentationsfortschreibung dieses realen
  Testbelegs in `Entwicklungsjournal.md`, `Arbeitsstand-und-Uebergabe.md`
  und `Testluecken-und-Abnahmeplan-5.2.md`. Der daraus resultierende
  Dokumentations-HEAD ist nicht selbst erneut unter Windows getestet.
- **Nächster Schritt:** P0 Unicode-Panelnavigation mit originaler
  UTF-16-Identität prüfen (UP-04/06); danach Diagnose des
  PowerShell-ExternalEditor-Falls (FIND-04/QA-03) und die noch
  offenen GUI-/Release-Gates. Die MGMT-02/MGMT-03-Gaps bleiben
  bis zum vollständigen Kriteriennachweis **TEILBELEGT/OFFEN**.

### J-20261124-07 — Teilmigration Unicode-Elternverzeichnis und ExternalEditor-Fixture

- **Auftrag / IDs:** Offene Produktfehler beheben: Unicode-Elternverzeichnis in Debug/Release (A1/A2, UP-04/06) sowie Legacy-Find-ExternalEditor (FIND-04, QA-03).
- **Analyse:** Die bisherige Navigation sperrt kurze, nicht-ACP-fähige W-Verzeichnisse bei `ChangeUnicodePathToDisk`. Das Panel führt zugleich einen alten ANSI-`Path` und einen autoritativen `GetDiskPathW()`; normale ANSI-Diskoperationen ohne exakte Zuordnung wären datenintegritätsgefährdend. Für den Editor war bisher nur `ExternalEditor` (`pwsh.exe`, `NOT_STARTED`) fehlgeschlagen, während derselbe Produktbefehl mit `ExternalEditorNative` (`cmd.exe`) funktionierte. Damit war eine allgemeine Produktursache noch nicht nachgewiesen.
- **Implementierung:** Neuer `TryGetVerifiedAnsiShortDirectoryPath` in `src/common/win32_unicode_panel_name.h`: `GetShortPathNameW`, strikter ACP-Roundtrip, `CreateFileW`/Dateisystemidentität (Volumen + File-ID), Reparse-Point-Ablehnung. `src/fileswn2.cpp` verwendet diese Brücke ausschließlich bei fehlender exakter ANSI-Darstellung und ruft `ChangeLongPathToDisk` mit dem **originalen W-Pfad** auf. Fehlt ein echter 8.3-Alias, bleibt die vorherige Sperre erhalten. Neues `tools/tests/unicode_directory_panel_alias.cpp` und Registrierung in `tools/Manage-Salamander.ps1`.
- **Editor-Fixture:** `tools/release/tests/LegacyFind-GuiCases.ps1` verwendet jetzt bei originalem `pwsh.exe` den absoluten Scriptpfad in `-File` und keine Lockerung der PowerShell-Ausführungsrichtlinie. Der native Editorvergleich bleibt erhalten. `Test-LegacyFind-UiContract.ps1` schützt diese Voraussetzung. Keine Änderungen an der realen `EditFile`-Implementierung ohne nachgewiesene Ursache.
- **Commits:** `0f0f583c`, `1b4df0a2`, `cdafab9f`, `c6806765`, `89481d18`, `0efd0c43`, `15a99375`, `828114a7` auf `bugfix/v5.2`; anschließend diese gemeinsame Dokumentationsfortschreibung.
- **Verifikation:** GitHub-Dateien zurückgelesen und statisch auf W-Identität, ID-Vergleich, fail-closed, Testregistrierung, unveränderte Exec-Policy und erhaltene zwei Editorvarianten geprüft. **Keine neue MSVC-, PowerShell- oder GUI-Ausführung** dieser Änderungen. Der letzte tatsächlich grüne `--test`-SHA bleibt `a928794c`.
- **Restarbeit / Abnahmestatus:** Allgemeine native W-Panelnavigation **ohne vorhandene 8.3-Aliase** ist nicht umgesetzt. Historie/Anzeige und weitere Legacy-Grenzen beachten. Debug/Release `--test-gui-unicode-parent` sowie `--test-gui-legacy-find --debug/--release` ausführen; bei Editor-FAIL echte CreateProcess-/MSIX-Prozessstartdiagnose statt Testabschaltung. **Keine Gap-ID geschlossen, A0–A7 Release NO-GO.**

### J-20261124-08 — Separate PowerShell-Host-Preflight für Legacy Find

- **Befund / FIND-04, QA-03:** Der ursprüngliche `ExternalEditor`-GUI-Test hatte `NOT_STARTED` gemeldet; der native Vergleich funktionierte. Absolute Scriptpfadangabe allein beweist noch nicht, dass der konkrete MSIX-PowerShell-Host im aktuellen Benutzerkontext überhaupt starten darf.
- **Änderung:** `tools/release/tests/LegacyFind-GuiCases.ps1` enthält nun `Assert-TestPowerShellEditorHost`. Dieser startet ausschließlich den konfigurierten PowerShell-Host mit `ProcessStartInfo.ArgumentList`, dem absoluten GUID-eigenen Probe-Script und dem temporären Ziel; prüft Exitcode, Status `SAVED`, Original-/Ausgabebytes und erfasst stderr. Vor dem GUI-Befehl wird die Datei exakt zurückgesetzt und der Status entfernt. Der eigentliche Test folgt unverändert und darf den Preflight-Erfolg nicht als GUI-Erfolg werten.
- **Sicherheit:** Kein `ExecutionPolicy Bypass`; kein fremder Prozess wird beendet. Nur ein ausdrücklich gestarteter, dem Test gehörender Childprozess darf bei eigenem Timeout beendet werden. Keine Änderung des produktiven Editorstarts und keine Abschwächung der Dateiidentitäts-/Nachbarprüfungen.
- **Commit:** `95b5c5ed239f88de451040e7d42006e7d33694ac`; anschließend Aktualisierung von Tracker, Journal und Übergabestand.
- **Verifikation:** Quellcode und Registrierungsvertrag statisch geprüft; **Windows- und GUI-Ausführung ausstehend**. Der Preflight kann einen Umgebungs-/MSIX-/Policy-Fehler künftig vor der eigentlichen Produktuntersuchung eingrenzen; kein nachgewiesener Produktfix.

### J-20261124-09 — Statischer Vertrag für Editor-Preflight-Reset

- **Auftrag / IDs:** FIND-04, QA-03 – der unabhängige PowerShell-Testvorlauf darf das spätere GUI-Ergebnis nicht durch einen verbleibenden Erfolgsmarker verfälschen.
- **Änderung:** `tools/release/tests/Test-LegacyFind-UiContract.ps1` erzwingt nun sowohl den Aufruf von `Assert-TestPowerShellEditorHost` als auch das Löschen des Vorlauf-Statusmarkers vor dem tatsächlichen Legacy-Find-Edit-Befehl.
- **Commit:** `be853b5426ffdc5ee2c14106849769e3f1092033` plus diese Dokumentationsfortschreibung.
- **Verifikation:** Statischer Quelltextabgleich; kein neuer PowerShell-/MSVC-/GUI-Lauf. Letzter tatsächlich erfolgreicher `--test`-SHA bleibt `a928794c`. Die Unicode-Navigation ohne echten 8.3-Kurznamen und der Editorfehler bleiben offen bis zum echten Windows-Nachweis.

### J-20261124-10 — Delta-Build und native Tests grün, GUI-Läufe durch laufende Instanz blockiert

- **Benutzerbefund / IDs:** PowerShell-Ausgabe vom 24.11.2026 auf sauberem `bugfix/v5.2`-Checkout `9f524264af766cfc417b5b2b9870008e88b6e093`. Relevante Teilnachweise **BUILD-01, UP-04, UP-06, FIND-04, QA-03**.
- **Echter Windows-Nachweis:** `manage.cmd --build-delta --test` startete **14:32:47 CET**, endete erfolgreich vor 14:34:41. **MSBuild Debug x64 (Delta) PASS, Release x64 (Delta) PASS**; beide gebauten EXEs bestehen VERSIONINFO 5.2. HTML-Hilfe-Verarbeitung abgeschlossen. `--test` vollständig **PASS** einschließlich AST-Parser über 66 PowerShell-Skripte, 22 registrierter nativer C++-Regressionen und unverändertem Legacy-Find-Editor-Vertrag. Neuer `unicode_directory_panel_alias.cpp` **PASS** mit real vorhandenem, verifiziertem Windows-8.3-Alias.
- **Einschränkungen:** `long_path_io.cpp` markierte den optionalen echten **Cross-Volume-Move SKIP** (`OPENSAL_CROSS_VOLUME_TEST_DIR` fehlt). Normale `--test`-PASS-Verträge sind keine GUI-, Plugin-, Clean-/Vierfach- oder VM-Abnahme.
- **Drei nachfolgende Tests:** `--test-gui-unicode-parent --release` (14:34:41), `--debug` (14:34:43) und `--test-gui-legacy-find --debug` (14:34:45) beendeten sich mit Exit 1 **vor den eigentlichen GUI-Schritten**, weil bereits mindestens eine `salamand.exe`-Instanz lief. Die Preflight-Sperre ist absichtlicher Nutzerdatenschutz, **kein Produkt-PASS/FAIL**. Daher fehlen weiterhin GUI-Befunde zu Unicode-Elternnavigation und PowerShell-Editor.
- **Protokollbelege:** `manage-20261124-143247-926-e31128.log` (Build/Test PASS), `manage-20261124-143441-351-f441ec.log`, `manage-20261124-143443-659-54878a.log`, `manage-20261124-143445-886-a11170.log` (GUI BLOCKED), lokal in `.Build/logs`, nicht in Git. Benutzer-Paste ausgewertet, keine Logdatei mit persönlichen Pfaden eingecheckt.
- **Entscheidung / nächster Schritt:** Keine Produkt- oder Testvertragskorrektur aus einem reinen GUI-Umgebungsblocker ableiten. GUI-Sicherheitsprüfung **nicht** abschwächen, keine fremden laufenden Salamander-Prozesse automatisch beenden. Benutzer schließt reguläre Instanzen selbst, überprüft ausschließlich lesend `Get-Process salamand -ErrorAction SilentlyContinue` und führt die drei isolierten GUI-Befehle anschließend einzeln erneut aus. Danach tatsächliche Bugs auf dem neuen SHA bewerten; vollständige Unicode-W-Panelnavigation ohne 8.3 bleibt unabhängig davon offen.
- **Git-Änderung:** Ausschließlich nachweisgetriebene Aktualisierung von `Arbeitsstand-und-Uebergabe.md`, `Testluecken-und-Abnahmeplan-5.2.md` und diesem Journal. **Kein produktiver Code geändert.** Ein nachfolgender Dokumentationscommit hat selbst keinen zusätzlichen Windows-Testnachweis.

### J-20261124-11 — Automatisches Warten auf freie Salamander-GUI vor Teststart

- **Auftrag:** `manage.cmd` soll vor GUI-Tests prüfen, ob Salamander noch läuft, gegebenenfalls pausieren, zum regulären Schließen auffordern und nach Ende der letzten Instanz automatisch weiterlaufen. Anlass: drei am 24.11. 14:34 wegen bereits laufender `salamand.exe` blockierte GUI-Läufe. IDs: MGMT-02/03, QA-03.
- **Architekturentscheidung:** Die Wartefunktion liegt ausschließlich im Manager **vor dem ersten GUI-sensitiven Test**. Normales Bauen, `--test` ohne GUI, `--setup` und `--run` werden nicht aufgehalten. Der Wartevorgang nutzt ausschließlich eine lesende PID-Abfrage und `Start-Sleep` (1 s). Bei Nutzerabbruch wird keine Exception verschluckt. Bereits laufende Salamander-Fenster werden nicht automatisch geschlossen und nicht per globaler Eingabe beeinflusst.
- **Sicherheitsgrenze:** Das Warten wird nicht vor jedem isolierten GUI-Untertest wiederholt: ein von einem fehlerhaften GUI-Test zurückgelassener eigener Prozess muss in den bestehenden Sicherheitsprüfungen weiterhin als Fehler bzw. Skip erkannt werden, statt mit endlosem Warten oder gefährlichem Aufräumen verdeckt zu werden. Bei vorangehendem `--test-all`-GUI-Sicherheitsfehler wird nicht unnötig gewartet.
- **Änderungen:** Neues `tools/release/Wait-SalamanderGuiAvailability.ps1` mit `Test-RequiresGuiIdleGate` und `Wait-ForSalamanderGuiAvailability`, Manager-Bootstrap/Help/Startreihenfolge in `tools/Manage-Salamander.ps1`, neuer `tools/release/tests/Test-Manage-GuiWait.ps1`. Regressionen mit injizierter Prozessabfrage und Pause umfassen mehrere Prozesse, Warnung, Weiterlaufen, Null-Prozess-Sofortfall, explizite Cancellation sowie Abgrenzung der GUI-CLI-Modi. `manage.cmd` als unveränderter Aufrufer leitet wie bisher an den aktualisierten Manager weiter.
- **Verifikation:** Quelltexte aus GitHub erneut gelesen, strukturelle Prüfungen für Optionen, PID-Abfrage, unveränderte Sicherheitsgrenzen, Reihenfolge und Testregistrierung bestanden. **Kein PowerShell- oder Windows-Lauf nach dieser Änderung durchgeführt.** Der echte Produkt-Build/Test-PASS bleibt auf `9f524264`, der neue Commit ist ungetestet.
- **Nächste Aktion:** Zuerst `manage.cmd --test` mit der neuen Warte-Regression; anschließend GUI-Tests `--test-gui-unicode-parent --release`, `--debug`, `--test-gui-legacy-find --debug` nacheinander. Dabei darf Salamander anfangs geöffnet sein: Meldung muss erscheinen, nach regulärem Schließen soll der Test automatisch fortsetzen. Unicode-Elternverzeichnis ohne 8.3 bleibt unabhängig davon als Produktgap offen; PowerShell-ExternalEditor-GREEN steht aus.

### J-20261124-12 — Externer PowerShell-Editor reproduzierbar defekt; expliziter Win32-EXE-Start

- **Benutzerbeleg / IDs:** Neues vollständiges Transkript `manage-20261124-145926-376-de4931.log`, Windows NT 10.0.26300, PowerShell 7.7, Branch `bugfix/v5.2`, HEAD `3119af034cf5eb6d1a65b27880d891baa5258ca9`, sauberer Checkout, 24.11.2026 14:59:26–15:02:20 CET; **FIND-04, QA-03**.
- **Ausgeführtes Ergebnis:** `manage.cmd --test-gui-legacy-find --debug` endete **FAIL** mit **36 PASS, 1 FAIL, 0 SKIP**. Alle außer `ExternalEditor` bestanden, insbesondere Unicode-/lange Suchpfade, originale Advanced-Funktionen, Shell und `ExternalEditorNative`. Bei `ExternalEditor`: `NOT_STARTED` trotz korrekter Ergebnisdatei und **erfolgreichem unabhängigen Host-Preflight** `PASS: configured PowerShell editor runs independently; GUI launch is tested separately.` Datei nicht verändert; alle Folgeszenarien liefen weiter. Damit frühere Hypothese „PowerShell-Host startet allgemein nicht“ widerlegt; Launch-/Parameterweg in Salamander bleibt wahrscheinlich, aber noch nicht endgültig ursächlich belegt.
- **Analyse:** Produktpfad `src/finddlg1.cpp::OnEditFile` → `src/fileswnb.cpp::WM_USER_EDITFILE` → `src/fileswn5.cpp::CFilesWindow::EditFile`. Bisher `CreateProcess(NULL, cmdLine, ...)` mit zusammengesetztem Anwendungs- und Argumentstring. Anders als dieser Produktpfad übergibt der erfolgreiche .NET-Preflight den konkreten App-Namen separat. Die native cmd.exe-Gegenprobe schließt einen generellen Defekt aller Edit-Aktionen aus.
- **RED/GREEN-Änderung (noch nicht ausgeführt):** Neuer nativer Test `tools/tests/editor_process_launch.cpp` für absolute/relative/nicht vorhandene EXE-Auswahl und realen Child-Exitcode via `cmd.exe`; in `tools/Manage-Salamander.ps1` zu `--test` registriert. Neuer Header `src/common/win32_editor_process_launch.h` führt nur für nachweisbar existente **absolute `.exe`-Pfade** einen expliziten `lpApplicationName` bei `CreateProcessA`, ansonsten den alten `NULL`-Suchpfad. `src/fileswn5.cpp::EditFile` verwendet diesen Aufruf; der externe Viewer-Start bleibt unverändert. `Test-LegacyFind-UiContract.ps1` schützt den neuen Produkt- und Testvertrag. Kein PowerShell-Policy-Bypass und keine Abschwächung des GUI-Testvertrags.
- **Diagnose:** `LegacyFind-GuiCases.ps1` protokolliert bei einem weiteren ExternalEditor-Timeout künftig die Fenstertitel ausschließlich der isoliert gestarteten Salamander-Instanz; kein Retry, kein automatisches Dismiss/Stop, keine Dateiaktion außerhalb der Fixture.
- **Git / Nachweise:** Neue Test-, Header-, Produkt-, Manager-, Vertrags- und GUI-Diagnose-Commits im Branch nach `3119af03`; diese Journal-/Abnahmeplan-/Übergabeaktualisierung dokumentiert die genaue Kette. Die Implementierung wurde aus GitHub zurückgelesen und auf konservativen Fallback, Testregistrierung und unveränderte Altpfade **statisch überprüft**. **Weder MSVC- noch GUI-Ausführung des neuen Fixes liegt vor.**
- **Nächste Schritte:** `git pull --ff-only origin bugfix/v5.2`; `manage.cmd --build-delta --test`, anschließend `manage.cmd --test-gui-legacy-find --debug`. Nur bei erfolgreichem GUI-Lauf dieses konkrete Problem als verifiziert schließen; sonst diagnostische Titel/Fehler prüfen und weiter an tatsächlicher Ursache korrigieren. Unicode-Elternverzeichnis Debug/Release weiterhin separat offen.

### J-20261124-13 — MSVC-C2039 durch falsch verwendetes HANDLES-Makro korrigiert

- **Auftrag / Beleg / IDs:** Benutzerprotokoll vom **24.11.2026, 15:12 CET** auf sauberem `bugfix/v5.2`-Checkout bei `3820e63686d01eb4fcbde038533e95c05f7bfb7b`. Kombiniert `manage.cmd --build-delta --test`: **FAIL während Debug-x64-Build**. Anschließender `--test-gui-legacy-find --debug`-Aufruf: **FAIL während isolierter Debug-Kompilierung**, noch kein GUI-Test. Logs lokal: `manage-20261124-151235-015-5be57f.log` und `manage-20261124-151238-827-08f672.log`. Betroffen BUILD-01, FIND-04, QA-03.
- **Reproduzierbarer Fehler:** `src/fileswn5.cpp(1516,22): error C2039: "Salamander::CreateConfiguredEditorProcessA" ist kein Member von "C__Handles"`. `src/common/handles.h` definiert `HANDLES(function)` als Mitgliedsdispatch `__Handles.SetInfo(...).##function` (oder `::function` bei deaktiviertem Monitoring). `HANDLES(Salamander::CreateConfiguredEditorProcessA(...))` kann deshalb nicht kompilieren. Fehler wurde in der vorherigen Quelltextprüfung nicht erkannt.
- **Korrektur:** `src/fileswn5.cpp` verwendet `HANDLES(CreateProcess(Salamander::GetExplicitEditorApplicationName(expCommand), cmdLine, ...))`: vorhandene `C__Handles::CreateProcess`-Schnittstelle und Handle-Tracking bleiben erhalten, geprüfte absolute EXE-Identität wird als erster Parameter übergeben; relative Befehle bleiben beim `NULL`-Anwendungsnamen. Überflüssige, nur im falschen Makroaufruf verwendete `CreateConfiguredEditorProcessA`-Hilfsfunktion aus `src/common/win32_editor_process_launch.h` entfernt. Nativer Test `tools/tests/editor_process_launch.cpp` startet real über `CreateProcessA` und prüft den Exitcode; statischer Vertrag `Test-LegacyFind-UiContract.ps1` verbietet `HANDLES(Salamander::...)` und fordert korrektes `HANDLES(CreateProcess(...))` auch bei mehrzeiliger Formatierung.
- **Implementierungscommits:** `171af22d` (RED-Quellenvertrag), `5c7cc1dc` (Produktfix), `445bdef9` (unbenutzte Hilfsfunktion entfernt), `a6197266` (nativer Regressionstest aktualisiert), `76046555` und `e98adfc6` (Vertrag angepasst), danach gemeinsame Aktualisierung dieses Journals, Abnahmeplans und Übergabestands.
- **Verifikation:** GitHub-Quellen und die korrekte `C__Handles::CreateProcess`-Signatur gegengeprüft; statisch konsistent. **Kein Windows-MSVC- oder GUI-Test nach der Korrektur**. Letzter bestätigter Build/`--test`-PASS weiterhin `9f524264`, letzter echter Legacy-Find-GUI-Lauf `3119af03` mit 36 PASS/1 FAIL/0 SKIP. **FIND-04 ist weiterhin ein ungelöster Produkt-/Startpfadfehler**.
- **Nächste Aktion:** `git pull --ff-only origin bugfix/v5.2`, `manage.cmd --build-delta --test`, anschließend `manage.cmd --test-gui-legacy-find --debug`. C2039 muss verschwinden; erst nach positivem GUI-Gegenlauf mögliche Editorbehebung bestätigen. Unicode-Elternverzeichnis Debug/Release weiterhin separat offen.

## Vorlage für zukünftige Einträge

```markdown
### J-YYYYMMDD-NN — Kurzthema
- **Auftrag / Gap-IDs:** präzise Benutzeranweisung und betroffene IDs.
- **Ursache / Befund:** Reproduktion, Funktionsvertrag, Risikoklasse.
- **Entscheidung:** warum diese Lösung; bewahrte ABI/UI-/Sicherheitsgrenzen.
- **Änderungen:** Pfade, Branch, eindeutiger Commit/PR.
- **Verifikation:** tatsächlich ausgeführter Befehl, SHA, OS/Variante,
  PASS/FAIL/SKIP, relevanter Logname; oder ausdrücklich 'nicht ausgeführt'.
- **Restarbeit:** konkrete offene nächste Aktion, Verweis auf Tracker-ID.
```

**Pflegeregel:** Vor der nächsten Aufgabe [aktuellen Übergabestand](Arbeitsstand-und-Uebergabe.md)
und [Abnahmeplan](Testluecken-und-Abnahmeplan-5.2.md) lesen. Neue
Entscheidungen append-only ergänzen; korrigierte Befunde nicht aus
der Historie entfernen, sondern als neue datierte Korrektur markieren.
