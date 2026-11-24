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

### J-20261124-14 — Legacy Find Debug 34/3, C2039 behoben; GUI-Fehler differenziert

- **Beleg / Auftrag:** Nutzerlog `manage-20261124-152841-475-9a382e.log`, 24.11.2026 **15:28:41–15:32:06 CET**, sauberer `bugfix/v5.2`-Checkout bei `8a6de88c3eafe54cc874bdec85019ea67a5fdfcc`, Windows 10.0.26300, PowerShell 7.7.0. Auftrag bleibt Fehlerbehebung unter A0/A6, FIND-04, QA-03 und BUILD-01.
- **Tatsächlicher Build:** Isolierter Debug-x64-MSBuild von `salamand.exe` **PASS**. Der vorherige C2039-Makro-Compilerfehler ist nachweislich behoben. Im vorgelegten Protokoll **kein** separater `--build-delta --test`-Gesamtlauf.
- **GUI-Ergebnisse:** Legacy Find Debug: **34 PASS / 3 FAIL / 0 SKIP**. `AdvancedInputs` scheiterte bei `SelectLegacyFindRow(index=0,count=3,GetKeyState(VK_SHIFT)=0xFF81)` vor der Navigation. `ShellClipboard` scheiterte beim ersten **Copy**-Befehl: verlangte zwei CF_HDROP-Pfade und `Preferred DropEffect` wurden nicht im vorgegebenen Timeout nachgewiesen; der Cut-Fall wurde dadurch nicht erreicht. `ExternalEditor` bleibt nach bestandenem isoliertem PowerShell-Preflight `NOT_STARTED`, Nachbardatei unverändert, eigener `Open Salamander`-Dialog sichtbar; `ExternalEditorNative` PASS. Alle übrigen originalen Find-/Unicode-/Longpath-Szenarien PASS. Mehrfach musste die Testprozess-Fokussierung gegen eine fremde Vordergrundanwendung wiederhergestellt werden.
- **Analyse (keine behauptete Endursache):** `GetKeyState` fragt die Keyboard-Queue des Test-STA ab und kann nach einem Wechsel des Vordergrundfensters veraltet sein; der Test darf physisch gedrückte Modifikatoren dennoch niemals ignorieren. Beim Clipboard ist noch unklar, ob der Win32-Shell-Verb fehlgeschlagen ist, die Datenformate fehlen oder ein fremder Clipboard-Zugriff stört. Beim Editor muss erst die tatsächliche Dialogmeldung aus dem eigenen `Open Salamander`-Fenster ausgelesen werden, bevor weitere Änderungen an `EditFile` vertretbar sind.
- **Änderungen nach diesem Lauf:** `tools/release/tests/Test-SalamanderGui-LongPaths.ps1::SelectLegacyFindRow` prüft vor nichtdestruktiver ListView-Tastaturnavigation physische Shift/Ctrl/Alt-Zustände mittels `GetAsyncKeyState` und wartet bei gedrückter Taste maximal 2 s, sonst FAIL; keine künstlichen Key-up-Ereignisse und keine fremde Prozesssteuerung. `tools/release/tests/LegacyFind-GuiCases.ps1::Test-LegacyFindShellClipboard` bewahrt unveränderte exakte Dateiname-/Drop-Effekt-/Byte-Prüfungen, ergänzt aber Clipboard-Sequenz, Formate, Pfadanzahl, Effekt, Exceptions und PID-gebundene Fenster- sowie Foreground-Diagnostik beim Timeout; kein Retry. `Test-LegacyFindExternalEditor` protokolliert beschriftete Kindtexte **ausschließlich** sichtbarer Dialoge `Open Salamander` des GUID-isolierten eigenen Salamander-Prozesses, ohne diese zu schließen. `Test-LegacyFind-UiContract.ps1` schützt alle drei Verbesserungen einschließlich unveränderter fachlicher Assertions.
- **Verifikation:** Alle neuen Dateien aus GitHub gegengelesen und die neuen Vertragsanforderungen auf realen Quelltext geprüft; **keine Windows-/PowerShell-/GUI-Ausführung auf dem neuen Commit**. Kein Produktcode aufgrund unbewiesener Hypothesen verändert.
- **Nächste Schritte:** `manage.cmd --test` (Parser/Verträge), danach isoliertes `manage.cmd --test-gui-legacy-find --debug` in möglichst ungestörtem Desktop. Bei Fehlern die neue `Owned-error-dialog`-Fehlermeldung und die Clipboard-Metadaten auswerten; erst dann konkrete Produktursache korrigieren. Parallel `--test-gui-unicode-parent --debug/--release` unverändert offen; Release weiterhin NO-GO.

### J-20261124-15 — Verifizierte, begrenzte Kindtextdiagnose des Editor-Fehlerdialogs

- **Anlass / FIND-04, QA-03:** Im GUI-Lauf `8a6de88` war der Test-eigene Dialog mit dem Titel `Open Salamander` sichtbar, aber der tatsächliche Fehlermeldungstext fehlte. Fremdprozessuales `GetWindowTextW` gibt Texte von Child-Controls nicht zuverlässig zurück; daher wäre die bloße Wiederverwendung von `DescribeWindow` nicht aussagekräftig.
- **Änderung:** `tools/release/tests/Test-SalamanderGui-LongPaths.ps1` erhält `DescribeOwnedEditorErrorDialog`: es akzeptiert ausschließlich ein sichtbares Top-Level-`#32770` des isolierten Salamander-Test-PID mit Titel `Open Salamander` und liest maximal 11 zugehörige `Static`-Beschriftungen per `SendMessageTimeoutReadText(WM_GETTEXT, 750 ms)` aus. `LegacyFind-GuiCases.ps1` verwendet diese reine Leseoperation nur im bisherigen Fehlerbericht. `Test-LegacyFind-UiContract.ps1` prüft HWND-/PID-Eigentum, Klassen, Zeitbegrenzung und Integration statisch. Keine automatischen Dialogaktionen, kein Prozessstart-Retry, keine Abschwächung von `ExternalEditor`.
- **Verifikation:** Code aus GitHub gegengeprüft; **weder neue PowerShell-Vertragsprüfung noch GUI-Lauf auf diesen Commits ausgeführt**. Durch die zusätzliche Diagnose wird der vorherige Editor-Fail nicht als behoben ausgewiesen. Erst die tatsächliche Fehlermeldung kann eine kausal belegte Produktkorrektur begründen.

### J-20261124-16 — Automatische Erfassung der externen Editor-Startparameter

- **Auftrag / IDs:** FIND-04, QA-03; Benutzer fordert automatisierte Diagnose und ausdrücklich Commit auf `bugfix/v5.2`.
- **24.11.2026, 17:06–17:09 CET, `d93cb4d5`:** isolierter Debug-x64-Build PASS, Legacy Find **36 PASS / 1 FAIL / 0 SKIP**; `AdvancedInputs`, `ShellClipboard`, `ExternalEditorNative` PASS, `ExternalEditor` FAIL/NOT_STARTED, CreateProcess Win32 **5 (ERROR_ACCESS_DENIED)**. Log: `manage-20261124-170629-100-b3066a.log`. Gleiches Ergebnis im Lauf 15:57–16:01. Nutzer-Gegenproben: vier A/W-API-/ApplicationName-Kombinationen im PowerShell-Prozess PASS (Exit 7); absoluter MSIX-EXE-Start aus administrativer cmd.exe PASS (Exit 7); vollständige ursprüngliche Editor-Fixture aus cmd.exe PASS (Exit 0, SAVED). Allgemeine MSIX-Startblockade nicht belegt. Neue testbuild- und GUID-gesteuerte One-shot-Datei `process-temp/editor-launch.txt` erfasst vor CreateProcess expandierten Befehl, Argumente, Arbeitsverzeichnis, Commandline, ApplicationName, ACP und Startflags. GUI-Runner meldet sie bei FAIL mit dem vorhandenen Win32-Dialog; bei PASS verlangt er eine nichtleere Datei. **Kein Windows-Lauf auf dem neuen Diagnosecode; Produktfehler bleibt offen.**
- **Änderungen:** `src/fileswn5.cpp`, GUI-Driver, LegacyFind-GuiCases, UI-Contract, IsolatedLegacyFind-Runner und drei Wartungsdokumente. Optionaler `-EditorScenario ExternalEditor` ermöglicht fokussierten Build-/GUI-Gegenlauf; Standard-Suite, bestehende Editor- und Dateiintegritätsassertions und Managerregistrierung bleiben erhalten. Keine Änderung an MSIX-Berechtigungen, Ausführungsrichtlinie oder produktiver Startsemantik.
- **Restarbeit:** Windows-Build und GUI-Gegenlauf; tatsächliche Werte auswerten, dann Produktursache korrigieren und Debug/Release prüfen.

### J-20261124-17 — Fehlender Diagnose-Record: GUID-gebundener gemeinsamer Speicher

- **Auftrag / IDs:** FIND-04, QA-03, automatisierte Fehlerdiagnose fortsetzen.
- **24.11.2026, `b36a1233`:** fokussierter isolierter Debug-x64-Build PASS; `ExternalEditor` 0 PASS / 1 FAIL / 0 SKIP; CreateProcess weiterhin Win32 5/NOT_STARTED, neue Prelaunch-Datei fehlt (`Editor-launch=[<editor launch record missing or oversized>]`). Bericht `legacy-find-Debug-7a9434dab54c44229fe4f23134cd42a6.results.json`. Ursache der fehlenden Datei nicht nachgewiesen. Test-only-Transport auf vor Prozessstart durch den Treiber erzeugtes GUID-gebundenes `Local\\OpenSalamander.EditorTest.<id>`-Mapping (4096 Byte) umgestellt; keine Abhängigkeit von TEMP oder ANSI-Dateipfad beim Schreiben. Native Seite öffnet ausschließlich vorhandenes Mapping, schreibt NUL-terminierten Record vor CreateProcess und schließt ihre Handles. Treiber liest begrenzt, dekodiert per erfasster ACP, meldet konkrete Lesefehler und erhält Textkopie nur in eigener Fehlerfixture; Mapping wird im finally freigegeben. Zusätzlich tatsächliches Prozessarbeitsverzeichnis und GetFileAttributes-Resultat/Fehler des EXE-Pfads. Produktlaunch, Sicherheitsprüfung und fachliche Assertions unverändert. **Neuer Code nicht unter Windows ausgeführt; FIND-04/QA-03 offen.**
- **Nächster Schritt:** `git pull --ff-only origin bugfix/v5.2`; `pwsh -NoProfile -File tools/release/tests/Invoke-IsolatedLegacyFind.ps1 -Configuration Debug -EditorScenario ExternalEditor`. Erst gemessene Parameter begründen eine Produktänderung.

### J-20261124-18 — Startparameter korrekt; kontrollierte In-Process-Startmatrix

- **Auftrag / IDs:** FIND-04, QA-03, Editorfehler automatisiert eingrenzen.
- **24.11.2026, `370951fc`:** fokussierter Debug-x64-Build PASS, ExternalEditor FAIL (0/1/0), Bericht `legacy-find-Debug-053e9c642d9c48ba8d9e0189587fa117.results.json`. Shared-Memory-Diagnose PASS: vollständiger absoluter WindowsApps-PowerShell-EXE-Pfad, korrekte Argumente inklusive beider gequoteter Fixture-Pfade, korrekter InitDir und expliziter ApplicationName; ACP 1252, STARTF 0x7, CreationFlags 0x20, EXE-Attribute 0x20/Fehler 0, Prozess-CWD System32. CreateProcess weiterhin Win32 5. Keine erkennbare Abweichung in expandierten Parametern. Neue ausschließlich für den isolierten PowerShell-Editorfall aktivierte In-Process-Matrix startet nur exakt das vom Testtreiber konfigurierte pwsh.exe mit harmlosem `exit 7`, ohne Editorfixture-Zugriff: A/W, ApplicationName NULL/explizit, ursprüngliche/leere STARTUPINFO, neue Konsole/kein Konsolenfenster, expliziter unveränderter Unicode-Umgebungsblock, Job-/Threadtoken-Status. Begrenzte Waits, nur eigene Probehandles, bei Timeout keine weiteren Probes. Der reale Edit-Aufruf bleibt unverändert und wird nicht wiederholt; der Matrixbefund ist unabhängig vom tatsächlichen Editorerfolg. Keine Rechte-/Policy-Änderung. **Neuer Code noch nicht unter Windows ausgeführt; Fehlerursache und Produktfix offen.**
- **Nächster Schritt:** `git pull --ff-only origin bugfix/v5.2`; `pwsh -NoProfile -File tools/release/tests/Invoke-IsolatedLegacyFind.ps1 -Configuration Debug -EditorScenario ExternalEditor`; Matrixwerte und Originalfehler vergleichen. Kein manueller Debugger.

### J-20261124-19 — Editor-PASS mit geändertem PowerShell-Host; A8 verbindlich

- **Auftrag / IDs:** FIND-04, QA-03; Auswertung des Nutzerlogs und neuer A8.
- **24.11.2026, `447af3441741e9126a5273f396e3f28f73dc40f9`:** isolierter Debug-x64-Build PASS; fokussierter `ExternalEditor` **1 PASS / 0 FAIL / 0 SKIP** (5797 ms), Bericht `legacy-find-Debug-affb27784841402d8f84d4dcf56c67fb.results.json`. Alle acht In-Process-Probes starteten mit Fehler 0, Wait 0, Exit 7; echter Editor speicherte die exakte Fixture, Nachbar unverändert, Clipboard wiederhergestellt. **Geänderte Umgebung:** statt bisheriger WindowsApps/MSIX-PowerShell nun EXE außerhalb WindowsApps; daher nur für diesen Host bestanden. Job-Zugehörigkeit ja, kein Thread-Impersonationstoken (1008); kein Beweis einer Job- oder MSIX-Endursache. Gegenüber `fa3280b4` änderte `447af344` ausschließlich `Anforderungen.md` (neue A8: nachgewiesene Produktfehler ausschließlich im Produktcode beheben, Tests nur bei nachgewiesenem Testfehler korrigieren). Kein Produktfix zwischen MSIX-FAIL und diesem PASS; bisherige MSIX-Reproduktion bleibt offen. Neue A8 verbindlich berücksichtigen, keine Testabschwaechung. Nächster Schritt: wenn ursprünglicher MSIX-Host noch vorhanden, gezielter unveränderter GUI-Test mit explizitem Host aus dem gleichen administrativen VS-Kontext und bereits gebautem isolierten Binary; andernfalls MSIX-Fall als nicht erneut verifizierbar dokumentieren. Vollständige Legacy-Find-Debug-/Release-Suiten und `--test` weiterhin erforderlich; keine Release-Freigabe.
- **Änderung:** ausschließlich diese drei Wartungsdokumente; keine Produkt- oder Teständerung. Der frühere MSIX-Fehler wird nicht als behoben markiert.

### J-20261124-20 — Native Regression und vollständiger Legacy Find Debug PASS

- **Auftrag / IDs:** FIND-04, QA-03; Auswertung der beiden Nutzerlogs.
- **24.11.2026, `d5e5dfa129662b24b4634a0e2c70448eeee04964`, sauberer Checkout, Windows 10.0.26300, PowerShell 7.7.0 außerhalb WindowsApps:** `manage.cmd --test` 17:25:44–17:27:07 erfolgreich, 68 PowerShell-Skripte Parser-PASS, 23 native C++-Regressionsaufrufe erfolgreich, 18 Windows/.NET-Dateisystemassertions PASS; optionaler Cross-Volume-Unterfall mangels `OPENSAL_CROSS_VOLUME_TEST_DIR` SKIP. Log `manage-20261124-172544-668-cfc26a.log`. Danach `manage.cmd --test-gui-legacy-find --debug` 17:27:28–17:29:56, isolierter Debug-x64-Build PASS, **37 PASS / 0 FAIL / 0 SKIP**; beide Editorfälle, AdvancedInputs, ShellClipboard und alle acht In-Process-Startprobes PASS, unveränderte Nachbarfixture. Log `manage-20261124-172728-138-c6a62f.log`, Bericht `legacy-find-Debug-26d606a507584218a9c1c7fca5589afd.results.json`. Neue grüne Teilbaseline für diese konkrete Umgebung; MSIX-Fehler nicht behoben/nicht erneut getestet, Release-GUI noch nicht belegt, LongResult prüft weiterhin sichere Ablehnung und keine vollumfängliche Shell-Unterstützung. `--test` ist kein vollständiger Produktbuild, Plugin-/VM-Abnahme und UP-06 Unicode-Elternnavigation bleiben offen. Nächster Schritt: `manage.cmd --test-gui-legacy-find --release`, anschließend `manage.cmd --test-gui-unicode-parent --debug` und bei PASS `--release`. A8 unverändert; keine Produkt-/Teständerungen in diesem Nachweiscommit.
- **Änderung:** ausschließlich diese drei Wartungsdokumente, keine Produkt- oder Teständerung. Release 5.2 bleibt NO-GO.

### J-20261124-21 — Unicode-Parent-F2: W-Identität beim Refresh erhalten; ViewUnicode-Release offen

- **Auftrag / IDs:** A1/A2/A8, UP-04, UP-06, FIND-04, QA-03; Auswertung beider Nutzerlogs und Produktkorrektur.
- **24.11.2026, `9c43bec9df16356c2035259f266c3664454daaec`, sauberer Checkout:** Legacy Find Release 17:32:22–17:35:22, isolierter Release-x64-Build PASS, **36 PASS / 1 FAIL / 0 SKIP**. Einziger FAIL `ViewUnicode`: ClipboardSequenceChanged=False, ViewerStillMatches=True, eigener Viewer im Vordergrund, erwartete 21 UTF-16-Einheiten; keine Clipboard-Publikation nach Copy, Ursache offen. Beide ExternalEditor-Fälle und acht Startprobes mit nicht-MSIX-Host PASS. Log `manage-20261124-173222-928-1b92ac.log`, Bericht `legacy-find-Release-ea48776dba184c688a1cef40b428b9f9.results.json`. Unicode Parent Debug 17:35:38–17:35:49: Navigation nach einmaliger Wiederholung erfolgreich, exakter Unicode-Vollname vor F2 PASS; F2-Dateisystem-Postcondition (neuer Name/alte Datei entfernt) erreicht, anschließender Vollname FAIL (`F2 updated full name without ACP loss`). F5/F6 nicht erreicht. Log `manage-20261124-173538-413-23b040.log`. **Konkreter Produktcodefehler:** `RefreshDirectory` ruft `ChangePathToDisk(GetPath(), ..., isRefresh=TRUE)` auf; bei kurzem DOS-Alias waren beide Laengen unter MAX_PATH, somit ANSI-Pfad mit `SetPath(changedPath)` ohne originale W-Identität. `ChangePathToDisk` führt nun den Refresh des eigenen nicht exakt ANSI-identischen Pfads über `ChangeLongPathToDisk`, das den autoritativen W-Pfad kopiert und erneut W listet. Nach erfolgreicher nativer F2-Umbenennung erfolgt ein synchroner Panelrefresh, Fokus nur anhand exakter W-Zeilenidentität; bestehende no-overwrite-, Reparse- und Identitaetspruefungen sowie asynchrone Benachrichtigung anderer Verbraucher bleiben erhalten. Keine Teständerung. **Windows-Build/Gegenlauf auf neuem Code ausstehend**, keine behauptete Endursache für ViewUnicode/MSIX, keine Freigabe.
- **Änderungen:** `src/fileswn2.cpp`, `src/fileswn5.cpp` sowie drei Wartungsdokumente. Keine Testassertionen oder Testtreiber verändert.
- **Nächste Aktion:** `git pull --ff-only origin bugfix/v5.2`, `manage.cmd --build-delta --debug --test`, `manage.cmd --test-gui-unicode-parent --debug`; bei Erfolg Release-Build/Gegenlauf. ViewUnicode-Release nicht als behoben einstufen.

### J-20261124-22 — Unicode-Parent-F2/F5/F6 Debug und Delta-Build PASS

- **Auftrag / IDs:** A1/A2/A8, UP-04, UP-06, QA-03; Auswertung des Nutzerlogs.
- **24.11.2026, `5ca5bb322af1aaa09cff194fac6cc0e18b913087`, sauberer Checkout:** `manage.cmd --build-delta --debug --test` ab 17:38:16 erfolgreich (tatsächlich beide x64-Varianten Debug und Release gebaut, HTML-Hilfe, Parser-/Vertragsprüfungen, 23 native C++-Regressionsaufrufe und 18 Windows/.NET-Dateisystemassertions PASS; optionaler Cross-Volume-Unterfall SKIP). Log `manage-20261124-173816-147-6b14d3.log`. `manage.cmd --test-gui-unicode-parent --debug` ab 17:40:00 vollständig PASS: Original-Unicode-Elternpfad bei Navigation und Vollnamenskopie erhalten, F2 aktualisiert Vollname ohne ACP-Verlust, F5/F6 in beide getestete Richtungen mit exakter UTF-16-Identität und unveränderten Dateibytes erfolgreich. Log `manage-20261124-174000-534-09503a.log`. Der konkrete F2-Refresh-Fehler auf `9c43bec9` ist im unveränderten Debug-GUI-Test behoben; Release-Gegenlauf noch ausstehend. Keine Aussage zu Volumes ohne 8.3-Alias, vollständiger W-Panelmigration oder allen UP-04/UP-06-Fällen. Nächster Schritt `manage.cmd --test-gui-unicode-parent --release`, anschließend gezielte Untersuchung des Release-ViewUnicode-Clipboardfehlers. MSIX-Editorfehler und weitere Abnahme offen; keine Release-Freigabe.
- **Änderung:** ausschließlich diese drei Wartungsdokumente; Produktcode und Tests unverändert.

### J-20261124-23 — Unicode Parent Release PASS; Viewer-Clipboard robust gegen kurze Sperren

- **Auftrag / IDs:** A1/A2/A8, UP-04, UP-06, FIND-04, QA-03.
- **24.11.2026, `b65e3e272a2907941319bff54b92394c2a29fe0d`, sauberer Checkout:** `manage.cmd --test-gui-unicode-parent --release` 17:41:58–17:42:06 PASS; Original-W-Pfad, F2 exakter Vollname, F5/F6 in getesteten Quell-/Zielrichtungen PASS. Log `manage-20261124-174158-545-5db331.log`. Produktfix `5ca5bb32` damit in Debug und Release für die konkrete 8.3-gestützte Fixture verifiziert. UP-04/UP-06 nicht vollständig geschlossen (ohne 8.3, weitere Operationen, Cross-Volume usw.).
- **ViewUnicode (FIND-04/QA-03):** Release-FAIL `9c43bec9` zeigte unveränderte Clipboard-Sequenz trotz vorhandenem Viewer. Quellbefund: `CM_COPYTOCLIP` ruft `CopyHTextToClipboard` ohne HWND auf; einmaliger `OpenClipboard(NULL)`-Fehlschlag verwirft Copy still. Die ANSI-Clipboardfunktion nimmt jetzt den übergebenen Owner-HWND, der Viewer übergibt `HWindow`; maximal 20 Wiederholungen à 10 ms ausschließlich bei ERROR_ACCESS_DENIED und nur vor `EmptyClipboard` (kein Replay der Aktion oder Publikation). Bei fehlgeschlagener Unicode-Publikation wird der originale HGLOBAL nicht an Windows übertragen und danach vom Aufrufer freigegeben; zuvor konnte der Rückgabewert FALSE bei bereits übertragenem Handle zu falscher Freigabe führen. Kein Test verändert, keine Selektions-/Format-/UI-Änderung beabsichtigt. **Ob Clipboard-Konkurrenz tatsächlich den beobachteten Timeout verursachte, ist nicht nachgewiesen; Windows-Build und Release-Wiederholung ausstehend.** Bestehenden `Invoke-LegacyViewerReliability.ps1 -Configuration Release -Iterations 10` mit Checkout-lokalem `-OutputDirectory` ausführen, anschließend Legacy-Find Debug/Release. MSIX-Fehler separat offen, keine Freigabe.
- **Änderungen:** `src/salamdr4.cpp`, `src/viewer3.cpp` und drei Wartungsdokumente. Tests unverändert. Nächste Aktion: `git pull --ff-only origin bugfix/v5.2`; `manage.cmd --build-delta --test`; `pwsh -NoProfile -File tools/release/tests/Invoke-LegacyViewerReliability.ps1 -Configuration Release -Iterations 10 -OutputDirectory .Build/logs/legacy-viewer-reliability`.

### J-20261124-24 — Viewer-Korrektur: Release-Wiederholungsserie 10/10 PASS

- **Auftrag / IDs:** A8, FIND-04, QA-03; Auswertung des Nutzerlogs.
- **24.11.2026, `86fcf2b58c7c4badb42d3d3bd69a77648eb2e0a0`, sauberer Checkout:** `manage.cmd --build-delta --test` ab 17:45:04 PASS, Debug/Release x64, HTML-Hilfe, 68 PowerShell-Parserprüfungen, Vertragsprüfungen, 23 native C++-Regressionsaufrufe und 18 Windows/.NET-Dateisystemassertions erfolgreich; optionaler Cross-Volume-Unterfall SKIP. Log `manage-20261124-174504-566-5fa2e6.log`. Danach `Invoke-LegacyViewerReliability.ps1 -Configuration Release -Iterations 10 -OutputDirectory .Build/logs/legacy-viewer-reliability`: isolierter Release-x64-Build PASS, Binär-SHA256 `8F5F6DD07EA630C96A89957F736462B2F8EE48574F393B16260D75F675BB6D56`, **10/10 PASS**, 20 exakte Inhaltsvergleiche, Next/Previous und Clipboard-Restore jeweils PASS, 0 verbliebene Prozesse je Lauf, Dauer 2,98–3,31 s. Evidenz `viewunicode-20261124-174702-140a00c1/Summary.csv` und Einzellogs laut Nutzerkonsole. Der frühere Release-Timeout trat nach der Produktkorrektur in dieser Serie nicht mehr auf; die tatsächliche ursprüngliche Ursache und Verhalten unter gezielt erzwungener Clipboard-Sperre sind damit nicht abschließend nachgewiesen. Nächster Schritt vollständige Legacy-Find-Suiten Debug und Release auf produktgleichem Stand. FIND-04/QA-03 bleiben TEILBELEGT; MSIX-Editor, übrige Abnahme und Release-Freigabe offen. Keine Produkt-/Teständerung in diesem Nachweiscommit.
- **Änderung:** ausschließlich diese drei Wartungsdokumente. Nächster Schritt `manage.cmd --test-gui-legacy-find --debug` und `manage.cmd --test-gui-legacy-find --release`.

### J-20261124-25 — Vollständige Legacy-Find-Regression Debug/Release 74/74 PASS

- **Auftrag / IDs:** A6/A8, FIND-04, QA-03; Auswertung des Nutzerlogs.
- **24.11.2026, `2c689ca4a5248530febc0a7f65d7e32ab1f0b7b2`, sauberer Checkout:** vollständige isolierte Legacy-Find-GUI-Suite Debug x64 ab 17:49:27 und Release x64 ab 17:51:57, beide Builds PASS, jeweils **37 PASS / 0 FAIL / 0 SKIP**, zusammen 74/0/0. Logs `manage-20261124-174927-466-1d4c2a.log` und `manage-20261124-175157-778-3a392e.log`; Berichte `legacy-find-Debug-5a2dc9221bc34746a750dff62e794afd.results.json` und `legacy-find-Release-61a04c45d76f43c49d6e3876dbc59133.results.json`. ViewUnicode, ViewLong, ViewMixed, AdvancedInputs, ShellClipboard, ExternalEditor/ExternalEditorNative PASS in beiden Varianten; alle acht Editor-Startprobes mit nicht-MSIX-PowerShell PASS. Drei externe Fokusunterbrechungen in Release wurden durch die vorhandene sichere Fokuswiederherstellung abgefangen. Zusammen mit 10/10 isolierten Release-ViewUnicode-Läufen auf produktgleichem `86fcf2b5` und Unicode-Parent-Debug/Release PASS liegt eine neue grüne Teilbaseline vor. Der frühere MSIX-Editorfehler bleibt offen; kein Nachweis allgemeiner Flakiness-Freiheit, gezielt erzwungener Clipboard-Sperren oder vollständiger Shell-Unterstützung langer Pfade. LongResult PASS bedeutet sichere Ablehnung, nicht vollständige A1/A2-Unterstützung. FIND-04/QA-03 bleiben TEILBELEGT; übrige 35-Gap-Matrix, Plugin-/VM-Abnahme und Release-Freigabe offen. **Unmittelbar nächster Schritt:** `manage.cmd --test-all` ohne Modusfilter (beide x64-Varianten; bestehende Produktbuilds `86fcf2b5` sind produktgleich), maschinenlesbaren Bericht und etwaige FAIL/SKIP auswerten. Keine Produkt-/Teständerungen in diesem Nachweiscommit.
- **Änderung:** ausschließlich diese drei Wartungsdokumente. Nächster Schritt `manage.cmd --test-all` (beide x64-Varianten). Release 5.2 bleibt NO-GO.

### J-20261124-26 — Vollständiges Test-All 97/0/0

- **Auftrag / IDs:** A0–A8, UP-02/04/05/06/07, FIND-04, WIC-01/02, QA-03.
- **24.11.2026, `ae0a043afc2b74c176375036dd9992957841613e`, sauberer Checkout:** `manage.cmd --test-all` 17:55:57–18:08:42 **97 PASS / 0 FAIL / 0 SKIP auf Sammlungsebene**; 23 native C++-Regressionen, 18 Windows/.NET-Dateisystemassertions, Clipboard-Snapshot, je 35 Plugin-PE-Exporttabellen Debug/Release x64, PictView-WIC-Headless-/Fenstertests x86/x64 und 42 GUI-Sammlungen (21 je x64-Variante) einschließlich 74 Legacy-Find-Szenarien und acht 32-MiB-Copy-Fällen PASS. Unicode-Parent F2/F5/F6, Multiselect, Kollisionen, 32700 UTF-16-Einheiten (GUI lesend), SMB/UNC und beide Editorfälle PASS. Log `manage-20261124-175557-853-fded7d.log`, Bericht `manage-20261124-175557-853-fded7d.results.json`. Optionaler nativer Cross-Volume-Unterfall SKIP (fehlendes `OPENSAL_CROSS_VOLUME_TEST_DIR`), nicht im Sammlungsskip. Vorhandene produktgleiche Builds `86fcf2b5`, kein neuer Vierfach-Produktbuild. Native WIC-Tests belegen 13 Endungen, nicht den echten F3-Host; ABI ist kein Plugin-Funktionsnachweis. MSIX-Editor, fehlende 8.3-Aliase, Cross-Volume, Recycle-Restore, Plugin-Funktionsmatrix und VM-Abnahme offen. Nächster Schritt P0 WIC-02: `manage.cmd --test-pictview-host --release` (sechs echte F3-Formate). Keine Produkt-/Teständerung; Release NO-GO.
- **Änderung:** ausschließlich drei Wartungsdokumente; keine Gap-Vollabnahme aus Teilnachweisen.

### J-20261124-27 — PictView F3-Host Release 6/6 PASS

- **Auftrag / IDs:** A7/A8, WIC-02, UP-02; Auswertung des Nutzerprotokolls.
- **24.11.2026, `94f736b1981063bbc2dcca0328332efff38536fe`, sauberer Checkout:** `manage.cmd --test-pictview-host --release`, 18:15:40–18:15:50 CET, **6/6 PASS** (BMP, PNG, JPEG, GIF, TIFF, ICO), Windows 10.0.26300, PowerShell 7.7.0 außerhalb WindowsApps. Log `manage-20261124-181540-077-37d194.log`. Produktgleicher Release-x64-Build von `86fcf2b5`. Je Format eigener Salamander-Prozess, exakter geladener PictView-SPL-Pfad, echtes F3 und WIC-HWND statt internem Viewer, unveränderte SHA-256-Quelldatei vor dem Schließen, bestätigtes HWND-Schließen. WIC-02: vorgesehener F3-Smoke vollständig PASS; **TEILBELEGT** für weitergehende Abnahmekriterien, denn der Hosttreiber misst weder Bildabmessungen/Pixelanzeige noch Lock-Freigabe im realen Host explizit; native WIC-Fenster-/Pixeltests sind separate Nachweise. Keine Aussage über historische Codec-/Funktionsparität (WIC-06) oder vollständige A7-Erfüllung. **Nächster Schritt:** expliziter Opt-in `manage.cmd --test-plugin-load --release` ausschließlich mit vertrauenswürdigen installierten Plugins und geschlossenen übrigen Salamander-Instanzen; der Plugin-Manager initialisiert alle installierten Module, auch Drittanbieter, der Smoke prüft vier Zielplugins. Kein vollständiger Funktionsnachweis. Produkt und Tests unverändert; Release NO-GO.
- **Änderung:** ausschließlich drei Wartungsdokumente; keine Tests oder Produktcode verändert.

### J-20261124-28 — Plugin-Manager-Initialisierung Release: vier Zielmodule PASS

- **Auftrag / IDs:** A1/A2/A7/A8, UP-02, WIC-02, UP-06; Auswertung des Nutzerprotokolls.
- **24.11.2026, `ed878eb87fce1f66cc3bc2d061cc4efcde217f4a`, sauberer Checkout:** `manage.cmd --test-plugin-load --release`, 18:18:13–18:18:18 CET, PASS. Windows 10.0.26300, PowerShell 7.7.0 außerhalb WindowsApps. Log `manage-20261124-181813-916-8518d0.log`. PictView BMP-F3-Vorprüfung PASS; anschließend echter Plug-in Manager Test All, vier exakt erwartete SPL-Pfade von 7zip, checksum, filecomp, renamer im eigenen Release-x64-Prozess geladen und resident, Unicode-Quellfixture byteidentisch. Der Treiber beendet die Beobachtung, sobald die vier Zielmodule resident sind; daraus folgt kein vollständiger Abschluss-/Initialisierungsnachweis für alle 35 Plugins und keine Funktions-, Unicode- oder Langpfadabnahme. UP-02 bleibt BLOCKIERT/TEILBELEGT. Nächster Schritt: kontrollierter Opt-in `manage.cmd --test-recycle-restore --release` auf Wegwerf-Fixture bei geschlossenen übrigen Salamander-Instanzen (UP-06/QA-01); anschließend Debug-Gegenlauf bei PASS. Keine Produkt-/Teständerung; Release NO-GO.
- **Änderung:** ausschließlich drei Wartungsdokumente.

### J-20261124-29 — Unicode-Papierkorb-Restore Debug/Release PASS; Clipboard-Cleanup-Korrektur

- **Auftrag / IDs:** A1/A8, UP-06, QA-01, QA-03; Auswertung der beiden Nutzerlogs.
- **24.11.2026, `e2e5fd2fbb34a47f9b6170f4f7b9fde926a63ef3`, sauberer Checkout:** `manage.cmd --test-recycle-restore --release` ab 18:20:16 und `--debug` ab 18:20:29: echte Unicode-F8-Papierkorb-Rundreise beide PASS; exakter UTF-16-Name und Originalverzeichnis im Papierkorb, restaurierte UTF-8-Dateibytes identisch. Logs `manage-20261124-182016-338-d0651a.log`, `manage-20261124-182029-571-8c05e5.log`. Debug zusätzlich `Clipboard owner STA did not stop within five seconds` aus `SalamanderGuiClipboardOwner.Dispose` des Testtreibers; Manager meldete trotz Cleanup-Warnung Erfolg. Produkt-F8-Verhalten PASS, Testinfrastruktur-Cleanup nicht vollständig PASS. Konkrete Treiberlücke: `Publish` pumpt Nachrichten der aufrufenden STA, `Dispose` wartet bisher nur per `Join(5000)`. A8-konforme Korrektur ausschließlich dieses nachweislich fehlerhaften Cleanup-Pfads: kurze Join-Intervalle mit bestehendem `PumpCallerMessages`, monotone 5-s-Frist, expliziter Shutdown-PASS erst nach erfolgreichem Join; verbleibender Shutdownfehler führt nach sonstigem Erfolg zu FAIL (primäre GUI-Fehler bleiben erhalten). Keine Produktänderung, keine F8-/Restore-Assertion oder Timeout-Grenze abgeschwächt. Zusammenhang mit STA-Callbacks plausibel, ursprüngliche konkrete Blockade nicht gemessen. Windows-Gegenlauf ausstehend. Nächster Schritt: `manage.cmd --test-recycle-restore --debug`, bei PASS `--release`, danach vollständiges `--test-all` wegen gemeinsamem GUI-Treiber. UP-06/QA-01/QA-03 bleiben offen/teilbelegt, Release NO-GO.
- **Änderungen:** `tools/release/tests/Test-SalamanderGui-LongPaths.ps1` ausschließlich Testinfrastruktur-Cleanup, drei Wartungsdokumente. Produktcode unverändert.

### J-20261124-30 — Papierkorb-Restore und STA-Shutdown Debug/Release PASS

- **Auftrag / IDs:** A1/A8, UP-06, QA-01, QA-03; Auswertung der beiden Nutzerprotokolle.
- **24.11.2026, `4f59f0358241ad37fc1f81679c63319c15e4c1cd`, sauberer Checkout:** `manage.cmd --test-recycle-restore --debug` ab 18:23:10 und `--release` ab 18:23:15, beide PASS einschließlich explizitem `PASS: Clipboard owner STA stopped`. Exakter Unicode-Name und Originalverzeichnis im Papierkorb, identische restaurierte UTF-8-Dateibytes. Logs `manage-20261124-182310-093-132e2c.log` und `manage-20261124-182315-177-39f76a.log`. Der frühere Cleanup-Timeout trat in beiden Gegenläufen nicht auf; die konkrete ursprüngliche STA-Blockade ist nicht gemessen. Debug: lesender Clipboard-Befehl 710 publizierte beim ersten Versuch keine neuen Daten (Sequenz unverändert, Fokus im verifizierten ItemsBox desselben Prozesses), zweiter Versuch ohne Selektionsänderung erfolgreich. QA-03 bleibt wegen sporadischer Clipboard-Auffälligkeit und ausstehender Gesamtregression TEILBELEGT. Kein Replay von F8/Restore. UP-06/QA-01 bleiben wegen weiterer offener Fälle offen. Nächster Schritt `manage.cmd --test-all` ohne Modusfilter (Debug/Release x64), da `4f59f035` den gemeinsamen GUI-Testtreiber geändert hat. Kein Produktbuild erforderlich bei unveränderten produktgleichen Binaries. Keine Produkt-/Teständerung in diesem Nachweiscommit; Release NO-GO.
- **Änderung:** ausschließlich drei Wartungsdokumente.

### J-20261124-31 — Audit der Test-All-Registrierung und Ausschlüsse

- **Auftrag / IDs:** A4/A8, MGMT-03; Nutzerfrage, ob alle Tests in Test-All enthalten sind.
- **24.11.2026, Registry-Audit auf Git-HEAD `8078889fd24f256d7dca7c2519c7782a25251942` (MGMT-03):** Verzeichnisinventar `tools/tests` und `tools/release/tests` mit `Manage-Salamander.ps1`, `Invoke-PictViewTests.ps1`, `Invoke-IsolatedLegacyFind.ps1`, Paketregressionen und ausgewählten CI-Aufrufen verglichen. Alle 31 C++-Testquellen in `tools/tests` sind registriert (23 allgemeine + 8 WIC). `Expand-AutomatedTestActions` aktiviert `--test`, WIC inkl. Fenster, Plugin-Exporte, Clipboard-Snapshot sowie alle `--test-gui*` außer `--test-gui-manual`; standardmäßig Release/Debug x64. Bewusst ausgeschlossen gemäß AGENTS.md: `--test-recycle-restore`, `--test-plugin-load`, `--test-pictview-host`. Legacy Find: 37 automatische Fälle je Variante, drei explizite Opt-ins `EncryptedFixture`, `NearLimit`, `RecycleRestore`. Nativer Cross-Volume-Fall bedingt durch `OPENSAL_CROSS_VOLUME_TEST_DIR`. `tools/tests/Test-LongPaths.ps1` ist ein zusätzlicher CI-Dateisystemtest (pr-long-path.yml), nicht im Manager registriert; verwandte, nicht identische Prüfungen durch `Test-FilenamesAndPaths.ps1`. Wiederholungs-/WER-Diagnoseläufe, echter Installer-/Paketnachweis auf erzeugten Artefakten, manuelle und VM-Abnahme sind nicht vollständig Bestandteil von Test-All; synthetische Paketregressionen dagegen schon. Keine vollständige rekursive Repo-/CI-Inventur oder neue Windows-Ausführung erfolgt. Help-Text 'Alle automatisierten Tests' ist zu weit gefasst. Empfehlung: vollständige explizite Registry mit Kategorien, dokumentierten Voraussetzungen/Ausschlüssen und Drift-Gate; sichere zusätzliche Fälle integrieren und systemwirksame Opt-ins nur ausdrücklich freigeben. Keine Änderung an Manager, Tests oder Produkt ohne neuen Auftrag; bisheriger nächster Schritt `manage.cmd --test-all` zur Verifikation von `4f59f035` bleibt. MGMT-03 OFFEN; Release NO-GO.
- **Änderung:** ausschließlich drei Wartungsdokumente; keine Ausführungssemantik geändert.

### J-20261124-32 — Test-Registry und erweiterter Standardlauf

- **Auftrag / IDs:** A4/A8, MGMT-03, QA-03; Nutzerauftrag zur Integration aller sicher automatisierbaren Tests.
- **24.11.2026, MGMT-03/A4/A8 – Nutzerauftrag vollständige Testinfrastruktur:** rekursiver Git-Baum auf `4f79284e` vollständig (5465 Einträge), projektinterne Testquellen unter `tools/tests`, `tools/release/tests`, `src/vcxproj/tests` klassifiziert. `Test-Registry.json` dokumentiert Ausführungseigentümer und Scope, neuer `Test-TestRegistry.ps1` prüft Inventardrift (fehlend/neu/doppelt), AST-Quellverweise, CLI-Dispatch, Auswahl und SKIP-Semantik. Standardlauf ergänzt um CI-LongPaths, VS2026-CMD-Resolver, isolierte Langpfadhistorie/CF_HDROP, vier 32-MiB-Fälle mit Unicode-Eltern je Variante, fünf ViewUnicode-Wiederholungen je Variante und vier isolierte WER-Core-Builds. Bestehende Fachassertions unverändert. Explizite Opt-ins für EFS (eigene Datei per OPENSAL_EFS_TEST_FILE), NearLimit, Recycle-Restore (kurze Datei, lange Datei/langer Ordner und Legacy Find), Plugin-Load und PictView-Host werden beim Kombinieren mit Test-All gesammelt und in beiden gewählten x64-Varianten ausgeführt. A/B-Diagnose, WER-GUI-Follow-up, manuelle/VM- und echte Artefaktabnahme bleiben begründete Scope-SKIPs; native Unter-SKIPs aus tatsächlicher Ausgabe werden separat erfasst; direkte GUI-SKIPs sind erforderliche SKIPs statt falscher PASS, Opt-in-Einzelszenarien werden je gewählter Variante ausgewiesen. Geplante Ausschlüsse sind SKIP mit PlannedExclusion=true, nicht PASS, und blockieren den Standardlauf nicht; FAIL und erforderliche SKIP weiterhin Exit 1. Keine Produktänderung, keine bestehenden Assertions abgeschwächt. Windows-Parser/Vertrag und erweiterter Test-All noch nicht ausgeführt, MGMT-03 TEILBELEGT, Release NO-GO. Nächster Schritt `manage.cmd --test`, danach `manage.cmd --test-all`.
- **Änderungen:** Management, Collector, Registry/Vertragstest, isolierte Runner, AGENTS und drei Wartungsdokumente. Produktcode unverändert.

### J-20261124-33 — Erster erweiterter Test-All: Registry bestätigt, sechs Fehler in drei neuen Szenarien

- **Auftrag / IDs:** A1/A2/A4/A8, MGMT-03, UP-04/05/06, QA-03; Auswertung der zwei Windows-Protokolle.
- **24.11.2026, Windows auf `0f9d16324394bff182cdb11666df122387ef11c0`, sauber:** `--test` 18:48:01 PASS (70 PS-Skripte, 89 Registry-Quellen, 23 native Aufrufe, 18 + 9 Dateisystemassertions, VS-Resolver); `--test-all` 18:51:07–19:05:11 **103 PASS / 6 FAIL / 32 geplante SKIP / 0 erforderliche SKIP**. Logs `manage-20261124-184801-225-29bc4f.log`, `manage-20261124-185107-963-850c3f.log`, zugehöriges `.results.json`. WER-Core-Buildmatrix 4/4, PictView x86/x64 mit HWND, ABI 35 Plugins je x64-Konfiguration, Legacy Find 37/37 und ViewUnicode 5/5 je Debug/Release, bestehende ASCII-Eltern-32-MiB-Fälle 4/4 je Variante PASS. Clipboard 710 sporadische read-only Wiederholungen bleiben QA-03; kein neuer STA-Shutdownfehler belegt. Cross-Volume und 31 Scope-SKIPs korrekt sichtbar. MGMT-03: Registry und Aggregation zur Laufzeit bestätigt, Gesamtintegration noch nicht vollständig. Vier neue Runner-FAILs vor GUI: `Build-IsolatedGuiTest.ps1`-ValidateSet fehlte `isolated-long-paths`; ausschließlich diese nachgewiesene Infrastrukturinkonsistenz korrigiert. Zwei neue Produkt-FAILs: Unicode-Eltern-32-MiB-Copy Debug/Release vor F5 mit Error Changing Directory (123) bei isoliertem Start. Quellbefund: WinMain ANSI-Kommandozeile verliert W-Identität; bisheriger DOS-Alias-Helfer lehnt W-Eltern ab MAX_PATH-2 pauschal ab. Produktkorrektur: ursprüngliche W-Argumente mit derselben Tokenisierungsgrammatik, Prozess-lokale native absolute Diskpfade für -l/-r/-a in LoadConfig/Apply; keine lossy Tasklist-Weiterleitung, unveränderte Shared-Memory-Struktur. Verifizierte DOS-Aliase bei langen W-Verzeichnissen über GetShortPathNameW und Identitätsprüfung mit Extended-Pfad, Legacy-Alias bleibt kurz. Ohne verifizierten Alias weiterhin sichere Ablehnung; Unicode-relative/Plugin/Archiv-Syntax und W-Weiterleitung an laufende Instanz nicht vollständig unterstützt, explizite Ablehnung statt Datenverlust. Keine fachliche Testassertion verändert. Windows-Build/Gegenlauf offen; MGMT-03/UP-04/UP-05/UP-06/QA-03 nicht schließen. Nächster Schritt `manage.cmd --build-delta --test`, dann gezielte drei GUI-Modi Debug und Release, anschließend `--test-all`. Release NO-GO.
- **Änderung:** Produkt-Startup/Panelpfade und verifizierter Alias-Helfer, isolierter Build-Runner (fehlende Allowlist), drei Wartungsdokumente.

### J-20261124-34 — Gezielter Gegenlauf: Unicode-Elternpfade bestätigt, Release-Clipboard-Timeout

- **Auftrag / Gap-IDs:** Fortsetzung nach Chatwechsel, UP-04/05/06, MGMT-03, QA-03; unveränderte A8-Testverträge.
- **24.11.2026, 19:18 CET, Windows x64, sauberer Source-HEAD `93c1a1d9bb54f0070aab523916aa0769ccf4f5a4`:** `manage.cmd --test-gui-large-unicode-parent-copy --test-gui-long-history --test-gui-long-clipboard --debug` PASS, derselbe Aufruf mit `--release` FAIL. Isolierte Builds PASS; Unicode-Eltern-32-MiB-Copy/Cancel/Collision/LockedSource je 4/4 PASS inklusive Bytes, Zeit, Read-only, ADS und Pause/Resume; History je PASS (411 UTF-16-Einheiten). Clipboard Debug PASS (Multi-Move, rekursive Kopie, Long-to-short); Release FAIL beim ersten Multi-Move, nach erfolgreicher 411er-Navigation und WM_COMMAND 775 ohne gemeldeten SendMessageTimeout oder Fehlerdialog; Timeout der unveränderten Dateisystemassertion. Folgefälle Release nicht ausgeführt. Clipboard-Snapshot und STA-Shutdown jeweils PASS. Logs `manage-20261124-191803-981-cbaf83.log`, `manage-20261124-191842-475-d468d1.log`. Kein neuer `--test` oder `--test-all` belegt. UP-04/UP-05/UP-06/MGMT-03/QA-03 bleiben offen bzw. teilbelegt; Release NO-GO.
- **Befund / Entscheidung:** Quellprüfung `src/fileswn9.cpp::ClipboardPaste`: `OleGetClipboard`-Fehler kann ohne Dialog FALSE zurückgeben; natives CF_HDROP-Fallback greift bisher nur nach ERROR_BAD_FORMAT. Das ist eine mögliche, nicht belegte Ursache; keine Produkt- oder Teständerung auf Verdacht. Erhaltene GUID-Fixture und Screenshot des Release-Fehlers auswerten: Quell-/Ziel-Existenz und SHA-256 beider Dateien, sichtbarer Panelzustand; dann `manage.cmd --test-gui-long-clipboard --release` isoliert wiederholen, bei geklärter Ursache Produktfix und beide Varianten, danach `--build-delta --test` und `--test-all`. Keine Timeout-/Assertion-Abschwächung.
- **Änderungen:** ausschließlich Nachführung der drei Wartungsdokumente; keine Produkt-/Teständerung, keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-35 — Release-Clipboard isoliert PASS, sporadischer Fehler nicht geklärt

- **Auftrag / Gap-IDs:** Auswertung der erhaltenen Fixture und des isolierten Gegenlaufs, UP-06/MGMT-03/QA-03.
- **24.11.2026, 19:34:08–19:34:12 CET, Windows NT 10.0.26300 / PowerShell 7.7.0, sauberer HEAD `007f2109f5d6859c363971dd8f9c5930415c90bf`:** isoliertes `manage.cmd --test-gui-long-clipboard --release` PASS (Build, 411er Navigation, Multi-Move, rekursive Kopie, Long-to-short, Clipboard-Restore und STA-Shutdown). Log `manage-20261124-193408-961-808074.log`. In der erhaltenen Fehlfixture vom 19:18 waren beide `cut-*.txt` noch im Quellverzeichnis, je 29.696 Bytes und übereinstimmender sichtbarer SHA-256-Präfix; keine entsprechenden Ziele in der gelieferten Dateiliste. Vollständige Hashes und Screenshot nicht vorgelegt. Zwischen den Läufen nur Dokumentation geändert: Fehler nicht reproduziert, nicht behoben; unterschiedliche Testreihenfolge (kombiniert vs. isoliert) und sporadischer Clipboard-/GUI-Zustand bleiben mögliche Einflussfaktoren. Kein bestätigter Fehlermechanismus. Keine Produkt-/Teständerung, keine Timeouterhöhung. Nächster Schritt: fünf unabhängige Wiederholungen des ursprünglichen kombinierten Release-Aufrufs (Unicode-Eltern-Copy, History, Clipboard), bei erstem FAIL anhalten und neue Fixture/Screenshot/Log sichern; bei PASS `manage.cmd --build-delta --test`, danach `manage.cmd --test-all`. UP-06, QA-03 und MGMT-03 bleiben offen/teilbelegt, Release NO-GO.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine neuen lokalen Windows-Tests durch den Agenten.

### J-20261124-36 — Release-Clipboard erneut FAIL (ERROR_INVALID_DATA), nativer Fallback erweitert

- **Auftrag / Gap-IDs:** Fehlerbehebung nach unverändertem kombiniertem Regressionstest; UP-06/QA-03/MGMT-03, A8.
- **24.11.2026, ab 19:35:38 CET, sauberer Windows-HEAD `6a6a6b7a0b6b92f1e118eb99d8d99a016fc42e7a`:** erster von fünf vorgesehenen kombinierten Release-x64-Läufen (`manage.cmd --test-gui-large-unicode-parent-copy --test-gui-long-history --test-gui-long-clipboard --release`) FAIL; weitere vier nicht ausgeführt. Build, Unicode-Eltern-Copy/Cancel/Collision/LockedSource 4/4 und History PASS. Clipboard: WM_COMMAND 775 nach 411er Navigation, Fehlerdialog `Transferred 0 items (Win32 error 13)` (ERROR_INVALID_DATA), SendMessageTimeout 1460 nach 5001 ms, IsHungAppWindow=False, keine Wait-Chain-Zyklen. Clipboard-Snapshot und STA-Shutdown PASS. Log `manage-20261124-193538-718-c7edcb.log`; GUID-Fixture und Screenshot lokal erhalten. Vorheriger isolierter PASS auf `007f2109` bleibt gültig, sporadischer Fehler erneut belegt.
- **Produktkorrektur:** `src/fileswn9.cpp::ClipboardPaste` verwendete bei OLE-Lesefehlern bisher ausschließlich für ERROR_BAD_FORMAT den nativen Fallback, obwohl `ReadUnicodeClipboardFiles` auch bei fehlerhaftem Preferred DropEffect/CF_HDROP ERROR_INVALID_DATA zurückgibt. Jetzt auch bei ERROR_INVALID_DATA einmalig die vorhandene native Lesefunktion verwenden, sofern regulärer CF_HDROP-Transfer zulässig ist. Diese liest Effekt und Dateiliste unter derselben Clipboard-Sperre, verifiziert die ursprüngliche Sequenz und validiert UTF-16-Pfade und Transfer-Effekt weiterhin strikt. Keine Wiederholung einer Dateioperation, keine Änderung der Transfer-/Overwrite-/Rollback-Semantik und keine Lockerung des Parsers oder virtueller Payload-Grenzen. Fehler 13 könnte auch aus dem Transfer selbst stammen; die konkrete Fehlerquelle ist nicht abschließend belegt. Keine Tests, Assertions oder Timeouts geändert. Windows-Build/GREEN ausstehend. Nächster Schritt: `manage.cmd --build-delta --test`, dann unveränderter kombinierter Release-Aufruf fünfmal (bei FAIL stoppen), Debug-Gegenlauf, danach `--test-all`. UP-06/QA-03/MGMT-03 offen bzw. teilbelegt, Release NO-GO.
- **Änderungen:** `src/fileswn9.cpp`, drei Wartungsdokumente. Keine Teständerung; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-37 — Clipboard-Fallback: Delta-Build und fünf kombinierte Release-Gegenläufe PASS

- **Auftrag / Gap-IDs:** Verifikation der Produktkorrektur aus J-20261124-36; UP-04/05/06, QA-03, MGMT-03, BUILD-01.
- **24.11.2026, 20:09–20:29 CET, sauberer Windows-HEAD `6839ef3e7caaae57cd261061821436f12e556d8d`:** `manage.cmd --build-delta --test` PASS (Debug/Release x64, MSBuild 18.12.3, HTML-Hilfe, 70 PS-Skripte, 89 klassifizierte Testquellen, 23 native C++-Regressionen, 18 + 9 Dateisystemassertions; physischer Cross-Volume-Move SKIP mangels `OPENSAL_CROSS_VOLUME_TEST_DIR`). Log `manage-20261124-200912-345-3c50c8.log`. Fünf kombinierte `manage.cmd --test-gui-large-unicode-parent-copy --test-gui-long-history --test-gui-long-clipboard --release` vollständig PASS: 30/30 isolierte Szenarien, Copy/Cancel/Collision/LockedSource je 5/5, History und Clipboard je 5/5, inklusive Multi-Move, rekursiver Kopie und Long-to-short, Snapshot-Restore/STA-Shutdown 30/30. Logs `manage-20261124-201057-694-62b721.log`, `manage-20261124-202806-138-f6a050.log`, `manage-20261124-202830-399-c8030f.log`, `manage-20261124-202852-522-e8ad8b.log`, `manage-20261124-202914-707-7191f3.log`. Fehler 13 nach Erweiterung des nativen Fallbacks nicht erneut aufgetreten; tatsächliche Nutzung des Fallback-Zweigs nicht separat instrumentiert, exakter früherer Fehlermechanismus nicht bewiesen. Im fünften Lauf je ein read-only Retry bei 709 (Sentinel) und 710 (Sequenz unverändert), danach PASS; QA-03 weiter teilbelegt. Kein neuer Debug-GUI-Gegenlauf bzw. vollständiger Test-All auf dieser SHA. Nächster Schritt: `manage.cmd --test-gui-large-unicode-parent-copy --test-gui-long-history --test-gui-long-clipboard --debug`, bei PASS `manage.cmd --test-all`. UP-04/05/06, QA-03, MGMT-03 und BUILD-01 bleiben offen bzw. teilbelegt; Release NO-GO. Keine Produkt- oder Teständerung.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-38 — Debug-Clipboard erneut FAIL; direkte native Dateiliste vor OLE

- **Auftrag / Gap-IDs:** Fehlerbehebung nach Debug-Gegenlauf; UP-06/QA-03/MGMT-03, A8.
- **24.11.2026, 20:34:40–20:35:31 CET, sauberer Windows-HEAD `6dd03835551ae6a345a7146bcb6bf0704d6c43cf`:** kombinierter `manage.cmd --test-gui-large-unicode-parent-copy --test-gui-long-history --test-gui-long-clipboard --debug` FAIL: isolierte Builds, Unicode-Eltern-Copy/Cancel/Collision/LockedSource 4/4 und History PASS; Clipboard nach erfolgreicher 411er Navigation und WM_COMMAND 775 wieder Timeout der ersten Multi-Move-Dateisystemassertion, kein gemeldeter Fehlerdialog/SendMessageTimeout. Snapshot-Restore/STA-Shutdown 6/6 PASS, weitere Clipboard-Teilfälle nicht ausgeführt. Log `manage-20261124-203440-571-4e4aac.log`; GUID-Fixture und Screenshot lokal erhalten. Neuer Volltest nicht ausgeführt. Fünf Release-PASS auf `6839ef3e` bleiben gültig, sporadischer Fehler besteht auf gleichem Produktstand.
- **Produktkorrektur:** `src/fileswn9.cpp::ClipboardPaste` konnte weiterhin vor dem Fallback bei fehlgeschlagenem `OleGetClipboard` oder nicht erkanntem OLE-Dateiformat FALSE liefern und anschließend Textpfadnavigation versuchen. Einfache native CF_HDROP-Pakete (ausschließlich CF_HDROP und optional Preferred DropEffect, vollständige Formatenumeration unter derselben Clipboard-Sperre) werden jetzt bei realer Langpfad-Dateioperation direkt ohne OLE-Wrapper gelesen; unbekannte/zusätzliche Formate behalten den bisherigen IDataObject-Pfad einschließlich Virtual-/Plugin-Schutz. Native Snapshot-Lesefunktion prüft nichtnull Sequenz, validiert Pfade/Effekt unverändert und wiederholt nur ERROR_ACCESS_DENIED beim Öffnen der Lesesperre begrenzt (max. vier Versuche, drei mal 10 ms); Sequenzwechsel vor direktem Lesen führt bei erkanntem nativen Dateiformat zum Abbruch. Wenn ein Dateiformat angezeigt wird, aber OLE keinen lesbaren Payload liefert, wird Fehler gemeldet statt stiller Textnavigation. Keine Wiederholung der Dateioperation, keine Parser-/Transfer-/Rollback-Lockerung; keine Tests oder Testtimeouts geändert. Quellvertrag zur Trennung Text-/Dateipaste beibehalten. Konkreter Auslöser des neuen Timeouts mangels Produktdiagnose und Screenshot nicht abschließend bewiesen; Windows-Build und GREEN offen. Nächster Schritt: `manage.cmd --build-delta --test`, dann fünf kombinierte Debug-Gegenläufe, bei PASS fünf Release-Gegenläufe, danach `--test-all`. UP-06/QA-03/MGMT-03 offen, Release NO-GO.
- **Änderungen:** `src/fileswn9.cpp` und drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-39 — Debug-History-Timeout; begrenzte Clipboard-Lesesperre auch für Textpfade

- **Auftrag / Gap-IDs:** Auswertung der Regression nach nativer CF_HDROP-Korrektur; UP-05/UP-06/QA-03/MGMT-03, A8.
- **24.11.2026, ab 20:38:47 CET, sauberer Windows-HEAD `fe6d9e2eb0d171a3ecda397e8dfa66834d0fa126`:** `manage.cmd --build-delta --test` PASS (Debug/Release x64, HTML-Hilfe, 70 PS-Skripte, 89 Testquellen, 23 native C++-Regressionen, 18 + 9 Dateisystemassertions; Cross-Volume SKIP). Kombinierte Debug-GUI: Läufe 1/2 vollständig PASS, Lauf 3 Copy/Cancel/Collision/LockedSource PASS, History FAIL vor Clipboard-Szenario; insgesamt 16 PASS / 1 FAIL in 17 gestarteten isolierten GUI-Szenarien. Weitere Debug- und alle Release-Läufe nicht ausgeführt. History-Fehler: nach verifiziertem CF_UNICODETEXT und WM_COMMAND 775 keine Navigation zum 411er Pfad, zuletzt unverändertes source-Panel, kein Dialog, Prozess lebt, Vordergrund PrimeVideo. `Go-ToPath -NoForeground` ist in History absichtlich hintergrundfähig (HWND-basierte Befehle); externer Vordergrund allein beweist keine Ursache. Clipboard-Snapshot/STA-Shutdown auch bei FAIL PASS; ein read-only Retry 710 im zweiten Lauf erfolgreich. Logs `manage-20261124-203847-717-00e303.log`, `manage-20261124-204034-159-378055.log`, `manage-20261124-204059-987-b9fc60.log`, `manage-20261124-204124-635-053b89.log`. Kein erneuter CF_HDROP-Fehler in zwei ausgeführten Clipboard-Szenarien, aber Verifikation unvollständig.
- **Produktkorrektur:** `ClipboardPastePath()` hatte einen einzigen `OpenClipboard`-Versuch und kehrte bei transientem ERROR_ACCESS_DENIED ohne Navigation zurück; dieselbe Zugriffskonkurrenz war zuvor bereits bei Datei-Snapshots berücksichtigt. Gemeinsamen lokalen `OpenClipboardForRead`-Helfer aus der vorhandenen bounded retry-Schleife extrahiert und auch für Textpfad-Paste eingesetzt. Maximal vier Versuche, drei mal 10 ms ausschließlich bei ERROR_ACCESS_DENIED, tatsächlicher Win32-Fehler bei Fehlschlag im bestehenden Trace; keine Wiederholung von WM_COMMAND oder Navigation, keine Änderung der Pfad-/Formatvalidierung, OLE-/Plugin-Transferlogik oder Testassertions. Konkreter Auslöser des History-Timeouts mangels Produkttrace nicht nachgewiesen; Korrektur adressiert einen nachweisbaren stillen Abbruchpfad. Windows-Build/GREEN offen. Nächster Schritt: `manage.cmd --build-delta --test`, dann isolierte History Debug-Wiederholungen unter ungestörtem Desktop (fünf, bei FAIL stoppen), danach fünf kombinierte Debug- und fünf Release-Läufe, anschließend `--test-all`. UP-05/UP-06/QA-03/MGMT-03 weiter offen bzw. teilbelegt; Release NO-GO.
- **Änderungen:** `src/fileswn9.cpp` und drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-40 — Kombinierter Release-Gegenlauf nach Clipboard-Lesekorrektur PASS

- **Auftrag / Gap-IDs:** Auswertung der übermittelten Release-Regression; UP-05/UP-06/QA-03/MGMT-03.
- **24.11.2026, 20:49:28–20:49:51 CET, sauberer Windows-HEAD `0ec07a95d376a3048a5e9c263210d97c5b5547a6`:** kombinierter `manage.cmd --test-gui-large-unicode-parent-copy --test-gui-long-history --test-gui-long-clipboard --release` PASS, 6/6 isolierte GUI-Szenarien (Copy/Cancel/Collision/LockedSource, History, Clipboard), isolierte Release-Builds PASS, Snapshot-Restore/STA-Shutdown 6/6 PASS. 411er Navigation, Multi-Move, rekursive Kopie und Long-to-short erfolgreich. Ein read-only Retry bei 709 (Sequenz 58818 unverändert, verifizierter Fokus) danach PASS; QA-03 bleibt offen. Log `manage-20261124-204928-589-6e1633.log`. Übermittelt wurde ausschließlich dieser einzelne Release-Transcript; Delta-Build/`--test`, fünf Debug- und insgesamt fünf Release-Gegenläufe auf diesem Produktstand noch nicht vollständig belegt. Kein neuer Volltest. Konkreter früherer Fehlermechanismus weiterhin unbewiesen. Keine Produkt- oder Teständerung. Nächster Schritt: fehlende Nachweise übermitteln, soweit bereits ausgeführt, sonst `manage.cmd --build-delta --test`, fünf kombinierte Debug- und vier weitere kombinierte Release-Gegenläufe (bei FAIL stoppen), danach `manage.cmd --test-all`. UP-05/UP-06/QA-03/MGMT-03 weiter offen bzw. teilbelegt; Release NO-GO.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-41 — Delta-Build und zehn kombinierte GUI-Gegenläufe PASS

- **Auftrag / Gap-IDs:** Verifikation der Produktkorrekturen für History und Clipboard; UP-04/05/06, QA-03, MGMT-03, BUILD-01.
- **24.11.2026, ab 21:00:14 CET, letzter Lauf ab 21:05:00 CET, sauberer Windows-HEAD `bb4443e645d74f5837d2b5cd8715f99ab617bb4a`:** `manage.cmd --build-delta --test` PASS (Debug/Release x64, HTML-Hilfe, 70 PS-Skripte, 89 klassifizierte Testquellen, 23 native C++-Regressionen, 18 + 9 Dateisystemassertions; physischer Cross-Volume-Move SKIP mangels `OPENSAL_CROSS_VOLUME_TEST_DIR`). Fünf kombinierte Debug- und vier kombinierte Release-Läufe (`--test-gui-large-unicode-parent-copy --test-gui-long-history --test-gui-long-clipboard`) vollständig PASS: 54/54 isolierte Szenarien und Snapshot-Restore/STA-Shutdown 54/54. Zusammen mit dem Release-PASS auf `0ec07a95` (nur Dokumentation dazwischen) 60/60 Szenarien, je 5/5 Debug und Release für Copy/Cancel/Collision/LockedSource/History/Clipboard. 32-MiB-Kopie inklusive Bytes, Zeit, Read-only, ADS und Pause/Resume; 411er History und alle drei Clipboard-Transfers erfolgreich. Kein erneuter Transfer- oder Navigationstimeout. QA-03: zweimal read-only Retry 710 (Debug 2, Release 1), einmal Clipboard-Verifikation vor Navigation (Release 2: zunächst 0 statt 411 UTF-16-Einheiten, nur Clipboard-Schreibwiederholung), jeweils PASS; früherer Retry 709 auf `0ec07a95` bleibt dokumentiert. Konkreter ursprünglicher Fehlermechanismus und Nutzung der korrigierten Zweige nicht separat instrumentiert; begrenzte Gegenläufe sind kein Beweis vollständiger Fehlerfreiheit. Logs `manage-20261124-210014-312-253ed1.log`, `manage-20261124-210149-223-2e0294.log`, `manage-20261124-210214-046-8db747.log`, `manage-20261124-210240-042-ad1ecd.log`, `manage-20261124-210303-741-e9145b.log`, `manage-20261124-210327-667-c62fcb.log`, `manage-20261124-210351-717-8626a2.log`, `manage-20261124-210415-150-842145.log`, `manage-20261124-210437-880-2875bf.log`, `manage-20261124-210500-219-dba175.log`. Nächster Schritt: `manage.cmd --test-all` (vollständiger neuer Lauf ausstehend). UP-04/05/06, QA-03, MGMT-03, BUILD-01 weiterhin offen bzw. teilbelegt; Release NO-GO. Keine Produkt-/Teständerung.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-42 — Gesamtlaufzeit im manage.cmd-Protokoll

- **Auftrag / Gap-IDs:** A4, MGMT-01/MGMT-02.
- **24.11.2026, Nutzerauftrag (A4 / MGMT-01, MGMT-02):** Gesamtlaufzeit eines `manage.cmd`-Aufrufs am Ende ausgeben. In `tools/Manage-Salamander.ps1` startet eine monotone `System.Diagnostics.Stopwatch` am Skripteinstieg; der bestehende `finally`-Block gibt vor `Stop-Transcript` die Laufzeit als `Gesamtlaufzeit: HH:mm:ss.fff` (Gesamtstunden auch über 24 h) aus, auch bei regulär abgefangenen Fehlern und Hilfe. Die Zeit umfasst alle angeforderten Schritte einschließlich Wartezeiten, nicht den nachgelagerten Transcript-Abschluss/Clipboard-Export oder den Prozessstart des CMD-Wrappers. Exitcodes, bestehende Protokollierung und Clipboard-Verhalten unverändert. Keine Testdateien geändert (A8), kein neuer Windows-Lauf belegt. Nächster Schritt: `manage.cmd --help` (Exit 0), `manage.cmd --invalid-option` (Exit 1), jeweils Laufzeit im Terminal/Log prüfen; anschließend der noch ausstehende `manage.cmd --test-all`. Release NO-GO unverändert.
- **Änderungen:** `tools/Manage-Salamander.ps1` und drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-43 — Vollständiger Standard-Regressionslauf 109 PASS / 0 FAIL / 32 geplante SKIP

- **Auftrag / Gap-IDs:** Auswertung Volltest und Laufzeitausgabe; A4, MGMT-01/02/03, BUILD-01, UP-01/04/05/06/07, FIND-04, QA-03, WIC-01/02/05, PKG-01/02.
- **24.11.2026, 21:23:27–21:39:19 CET, sauberer Windows-HEAD `aae7e76c2a5b73b2ff2fff4e65570a2a660be92e`:** `manage.cmd --test-all` erfolgreich abgeschlossen: **109 PASS / 0 FAIL / 32 geplante SKIP / 0 erforderliche SKIP**, Gesamtlaufzeit `00:15:51.958` im Transcript bestätigt (A4; Fehler-/Help-Ausgabe noch nicht real belegt). Log `manage-20261124-212327-502-ccc951.log`, gleichnamiger `.results.json`-Bericht laut Transcript erzeugt. 70 PS-Skripte, 89 klassifizierte Testquellen, 23 native C++-Regressionen, 18+9 Dateisystemassertions, WER-Core-Buildmatrix 4/4, Plugin-ABI 35/35 je Debug/Release x64, PictView native x86/x64 inkl. HWND, Legacy Find je 37/37, ViewUnicode je 5/5, je vier ASCII- und Unicode-Eltern-32-MiB-Fälle, History, Clipboard, alle registrierten GUI-Standardfälle einschließlich 32700er GUI-Grenzwert PASS. Alle sechs zuvor fehlgeschlagenen Sammlungseinträge auf `0f9d1632` jetzt PASS; keine neue Produkt-/Teständerung. QA-03: sieben erfolgreiche read-only Retries (709 viermal, 710 dreimal; davon drei Sentinel-Fehler vor Kommandoversand); keine erneuten Transfer-/Navigationstimeouts, keine behauptete vollständige Fehlerfreiheit. 32 geplante Ausschlüsse: Cross-Volume 1, Recycle-Restore 8, Plugin-Initialisierung 2, PictView-F3-Host 12, EFS/NearLimit 4, manuelle GUI/A-B/WER-Follow-up/Paket-/VM-Abnahme 5. Kein Nachweis einer vollständigen Plugin-Funktionsmatrix, Clean-Solution-Vierfachmatrix, echter Release-Pakete oder sauberer VM. Nächster Schritt nach grünem Standardlauf: `manage.cmd --build-clean --test --setup` für frischen Debug/Release-x64-Solution-Build, Regressionen und reale 7z-/Setup-Artefakte (kein Installieren); danach Artefakt- und VM-Abnahme, separate Opt-ins nach Autorisierung und Voraussetzungen. MGMT-03 Standardregistry-/Dispatch-/Drift-Nachweis grün; übrige Gap-Kriterien bleiben offen bzw. teilbelegt. Release NO-GO.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-44 — Clean-Solution-Build x64, Regressionen und reale Paketgenerierung PASS

- **Auftrag / Gap-IDs:** A3/A4/A5, BUILD-01, MGMT-01/02, UP-01, PKG-01/02/03/04/05.
- **24.11.2026, 21:54:48–22:00:07 CET, sauberer Windows-HEAD `28c18a48d1615ce68e38277047cf24d52ac93374`:** `manage.cmd --build-clean --test --setup` PASS, Gesamtlaufzeit `00:05:18.722`, Log `manage-20261124-215448-380-d3341c.log`. Tatsächlicher Clean-Solution-Build Debug/Release x64 mit MSBuild 18.12.3, VERSIONINFO 5.2, 34 HTML-Help-Projekte, `--test` (70 PS-Skripte, 89 Testquellen, 23 native C++-Regressionen, 18+9 Dateisystemassertions; physischer Cross-Volume-Fall weiterhin SKIP). Je Paketvariante 35/35 Solution-SPLs und 40/40 kompilierte Plugin-Sidecars SHA-256-identisch zu Build; fünf Pflichtmodule vorhanden, keine nicht deklarierten SPLs. Inventar 36 Module/432 Operationsslots, WinSCP source-only/NOT_SHIPPED; Funktionsstatus NOT_ASSESSED, kein Funktions-PASS. Debug 63 PE/422 Paketdateien, Release 52 PE/286 Paketdateien, jeweils zusätzlich internes Manifest (423 bzw. 287 Dateien im Archiv). 7-Zip 26.06 Integrität beider Archive PASS; Inno Setup 6.7.4 kompiliert beide Installer. `.Build/dist`: Debug-7z 30.867.119 Bytes, Debug-Setup 35.551.302 Bytes, Release-7z 5.304.329 Bytes, Release-Setup 7.342.543 Bytes. Die 287 protokollierten Release-Payload-Dateien enthalten keine der verbotenen Build-Endungen .pdb/.lib/.exp/.obj/.pch/.idb/.ilk/.tlog/.lastbuildstate oder erkennbaren Debug-CRT-DLLs; Debug-Pakete enthalten diese absichtlich und bleiben privat. Inno-Compiler meldet Non-commercial use only; Lizenz-/Redistributionsentscheidung offen. Lokales Protokoll belegt Staging, Archivtest und Installer-Kompilierung, nicht unabhängige Inhaltsprüfung des finalen Archivs, Hashes der finalen Artefakte, tatsächliche Installation/Deinstallation oder VM-Lauffähigkeit. Vorheriger Volltest `aae7e76c` 109/0/32 bleibt gültiger produktgleicher Standardnachweis; kein neuer GUI-Volltest. **Nächster Schritt:** lokale Release-Manifestprüfung `pwsh -NoProfile -File tools/release/tests/Test-ReleaseChecksumManifest.ps1 -DistributionDirectory .Build/dist` und Hashes dokumentieren; Release-7z in frisches Verzeichnis entpacken und `Test-PortableManifest.ps1 -ExtractedDirectory <Verzeichnis>` ausführen. Anschließend in sauberer Windows-11-x64-Test-VM (keine Entwicklerwerkzeuge/zusätzliches VC++-Redist) Portable-Start, F1/F3, Plugin-/Unicode-/Langpfad-Smoke; separater Snapshot für Installer mit `Test-InstalledPayload.ps1 -PortableDirectory <Portable> -InstalledDirectory <Installation>` vor Erststart, Start/Deinstallation und separater 5.0-Upgrade-Test gemäß Release-5.2-Gates.md. Keine Veröffentlichung. PKG-01 reale Staging-Abnahme belegt, endgültiger Paket-/Installationsnachweis offen; PKG-02/03/04/05, BUILD-01 (Win32-Solution), MGMT-01 (autorisierter kombinierter Update-Ablauf) bleiben offen/teilbelegt; Release NO-GO. Keine Produkt- oder Teständerung.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-45 — Priorisierte Unicode-/Langpfad-Migrationsanalyse aller Plugins

- **Auftrag / Gap-IDs:** Nutzer fragt nach Komplexitätsranking aller Plugins; A1/A2, UP-01/02/03, WIC-07, QA-01.
- **24.11.2026 – Plugin-Migrationsaufwandsanalyse (A1/A2, UP-01/02/03, WIC-07, QA-01):** auf Quell-HEAD `320b26f376ef07fce71fc265f7f263471c675ed6` vollständiges Plugin-Bauminventar plus gezielte Quellstichproben pro Modul und SDK-Grenzen ausgewertet. [Migrationspriorität aller Plugins](Plugin-Migrationsprioritaet-5.2.md): 35 gebaute Module gerankt, WinSCP separat (source-only), relative Aufwandsskala, Risiken, Codeumfang, Migrationsschwerpunkte und Testfälle. FTP/ZIP/Automation/7zip/renamer/undelete mit größtem geschätztem Restaufwand; UnRAR/RAPI/WinSCP mit gesonderten Abhängigkeitsrisiken. Gemeinsame kompatible W-SDK-/SafeFile-Identitätsvorleistung und risikoarme Pilotmodule empfohlen. Keine vollständige Call-Graph-/Codeprüfung, keine Zeitmessung, keine Produkt-/Teständerung oder neue Windows-Ausführung, keine Abnahme-ID geschlossen. Aktueller operativer nächster Schritt bleibt Paket-/Manifest-/VM-Validierung.
- **Änderungen:** Planungsdokument und drei Wartungsdokumente; kein Produktcode, keine Tests.

### J-20261124-46 — Stabiler Meilenstein und autorisierte Entfernung zweier Demo-Plugins

- **Auftrag:** DemoMenu/DemoPlug entfernen, danach kompatibles Unicode-SDK und vier priorisierte Plugin-Regressionssuiten.
- **24.11.2026 – ausdrücklicher Nutzerauftrag (A0-Ausnahme ausschließlich für DemoMenu/DemoPlug, A1/A2/A4, UP-01/02/03, WIC-07):** stabilen Referenzbranch `baseline/v5.2-stable-2026-11-24` auf unverändertem Quellstand `4b2631a797cafa290d50822cb6c4b9f350c415fc` gesichert (produktgleicher letzter Volltest 109/0/32 und Clean-Build/Setup PASS; kein öffentlicher Release/Tag). DemoMenu und DemoPlug vollständig aus Quellbaum und Solution einschließlich Sprachprojekten und GUID-Konfigurationszuordnungen entfernt. DemoView bleibt. Aktive Soll-Inventarliste nun 33 Projekte, 34 Quellordner inkl. WinSCP; zwei feste 35er Testanzahl-Assertions sind nach ausdrücklicher Soll-Bestandsänderung sachlich veraltet und werden exakt auf 33 angepasst, alle eigentlichen Export-/Build-/Drift-/Negativassertions unverändert. Keine Windows-Verifikation und kein neuer Paketnachweis. Bereits vorhandene lokale alte Build-/Installationsdateien werden nicht selbständig gelöscht; frischer Clean-Build und neues Staging erforderlich. Danach kompatible UTF-16-SDK-Erweiterung mit unverändertem SDK-103-Vertrag und separaten neuen Schnittstellen, bevorzugte Plugin-Regressionssuiten PictView, ZIP, 7-Zip, Renamer jeweils mit Unit-/GUI-Nachweis des unveränderten Verhaltens vor der jeweiligen Migration. Vorgesehene CLI: `--test-plugin-pictview`, `--test-plugin-zip`, `--test-plugin-7z`, `--test-plugin-renamer`. Keine Plugin-Migration vor grüner Altfunktionsbaseline. Aktueller nächster Schritt `manage.cmd --build-clean --test`; keine Tests stillschweigend abschwächen. Release NO-GO.
- **Änderungen:** Quellbaum, Solution, Soll-Inventar und zwei explizite Bestandszahl-Assertions; drei Wartungsdokumente.

### J-20261124-47 — Optionale UTF-16-Viewer-SDK-Grundlage und PictView-Testgruppe

- **Auftrag / Gap-IDs:** A1/A2/A4, UP-02, WIC-02/07, MGMT-03.
- **24.11.2026 – SDK-W-Grundlage, erster Viewer-Schnitt (A1/A2/A4, UP-02, WIC-07, MGMT-03):** separates `src/plugins/shared/spl_unicode.h` mit optionalem, explizit versioniertem Export `SalamanderPluginQueryUnicodeViewer`, caller-owned Tabelle Size/Version/CanViewFileW/ViewFileW, exakter UTF-16-Name ohne ACP-/MAX_PATH-Puffer, keine neue Methode in alten SDK-VTables, SDK-103 unverändert. Host `CPluginData::TryCanViewFileW/TryViewFileW` fragt Export nur bei geladenem Plugin ab, trennt nicht unterstützte Schnittstelle von fachlichem FALSE, hält Enter/LeavePlugin und Viewer-Lock-Vertrag ein. Neue native Regression `plugin_unicode_sdk.cpp` registriert in `--test` und Registry: kein Export, FALSE, falsche Größe/Version, fehlende Callbacks, kein stale Pointer, >260 UTF-16 mit nicht-ACP/Supplementary-Zeichen. Dies ist eine erste Implementierung der Viewer-Negotiation, noch ohne produktiven Panel-/Find-Aufrufpfad und ohne Plugin-Implementierung; kein vollständiges SDK-W für Archive/FS/SafeFile/Menüs. Keine vorhandene Plugin-Funktion umgebaut. `--test-plugin-pictview` gruppiert vorhandene native WIC-Tests einschließlich HWND und sechs explizite F3-Hosttests; bisherige Host-Opt-in-Regel bleibt, Alias als geplante Gruppenauslassung in Registry, keine neuen PictView-Funktionsassertions. ZIP/7-Zip/Renamer benötigen erst neue echte Unit-/GUI-Funktionsbaselines und getrennte CLI-Dispatches, nicht als Ladesmoke oder leere PASS-Option ausgegeben. Windows-Build/GREEN ausstehend. Nächster Schritt `manage.cmd --build-clean --test`, dann `manage.cmd --test-plugin-pictview --debug` und `--release`; erst nach grünen Funktionsbaselines die jeweiligen Plugin-Migrationen. Release NO-GO.
- **Änderungen:** neuer SDK-Header, Host-Methoden, neue native Regression, Manager/Registry, drei Wartungsdokumente. Bestehende Plugin-Quellen unverändert.

### J-20261124-48 — Clean-Build nach Demo-Entfernung PASS, lokaler Quellinventardrift

- **Gap-IDs:** UP-01/02, BUILD-01, MGMT-03.
- **24.11.2026, 22:55:14–22:57:35 CET, sauberer tracked Windows-HEAD `b43a219150df78ec9845e910bd116bdf6dae5e77`:** `manage.cmd --build-clean --test` teilweise PASS, insgesamt Exit 1 (00:02:21.328; Log `manage-20261124-225514-444-9d7a73.log`). Clean-Solution Debug/Release x64, 32 HTML-Help-Projekte, 70 PS-Skripte, 90 Testquellen, 85 aktive C++-Projekte und 33 Plugin-Buildmatrix-Einträge PASS. Originale 107 Dialogressourcen/89 Tastaturbelegungen PASS. Abbruch in `Test-PluginCoverageInventory.ps1:18`: lokales Dateisysteminventar enthält weiterhin `src/plugins/demomenu` und `src/plugins/demoplug` zusätzlich zu 34 erwarteten Quellordnern. Rekursiver vollständiger Git-Baum desselben Remote-HEAD enthält keinerlei Einträge unter diesen beiden Pfaden; der Test zählt bewusst physische Ordner, auch unversionierte. Vermutete lokale unversionierte/ignorierte Reste (Inhalt nicht belegt), kein nachgewiesener Produkt- oder Testfehler. Keine Teständerung und kein automatisches Löschen. Nächster Schritt: `git ls-files -- src/plugins/demomenu src/plugins/demoplug`, `git clean -ndx -- src/plugins/demomenu src/plugins/demoplug`, lokale Ordner nach Prüfung außerhalb des Repositorys sichern/verschieben; danach `manage.cmd --test` auf bereits gebautem Stand, dann bei Erfolg `manage.cmd --test-plugin-pictview --debug` und `--release`. Neue native SDK-Regression und weitere nachgelagerte Tests nicht erreicht; keine neuen GUI-/Paketnachweise. ZIP/7-Zip/Renamer-Baselines weiterhin offen; keine Plugin-Migration vor grünem Nachweis. Release NO-GO.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine Windows-Ausführung durch den Agenten.

### J-20261124-49 — Native PictView-Baseline PASS; Startmigration für entfernte Demo-Plugins

- **Gap-IDs:** A0-02, UP-01/02, WIC-02/07, QA-03.
- **24.11.2026, 23:09:19–23:10:24 CET, sauberer Windows-HEAD `da48e6e594ee1749de91ecd95464c9e4b7b7ea64`:** `manage.cmd --test-plugin-pictview --debug` Exit 1, 00:01:05.636, Log `manage-20261124-230919-016-b6d3e1.log`. Native WIC 8/8 x64 und 8/8 x86 PASS inkl. 13 Endungen, Unicode/Langpfad-PNG, Pfadgrenze, GDI, Transformation, Export, Clipboard, HWND/Lock. Erster F3-Hosttest BMP scheitert vor F3 während Start: Debug-HANDLE-Dialog LoadLibraryW Win32 126 (`plugins1.cpp:2193`, `handles.cpp:792`); tatsächliches Modul bisher nicht angegeben, fünf übrige Formate und Release nicht erreicht. `--test`-Transcript nach lokaler Ordnerbereinigung nicht vorgelegt; kein nachgewiesener vollständiger PASS. **Produktkorrektur:** vorhandene Startmigration bereinigte fehlende Plugins nur bei Config-Versionswechsel/Import/plugins.ver, nicht beim gleichversionigen Build. Vor Import-/Autoinstall-/LoadOnStart-Pfaden gezielte Bereinigung für genau die fehlenden relativen Standardmodule `demomenu\\demomenu.spl` und `demoplug\\demoplug.spl` mit vorhandener W-Presence-Prüfung und `CPlugins::Remove(..., FALSE)` (Index-/Viewer-/Archiver-Referenzen korrigiert, private RegKey nicht gelöscht, SaveConfig bei tatsächlicher Änderung). Keine Entfernung anderer oder vorhandener Module, kein Eingriff bei Unknown; kein Unterdrücken der Debug-Fehlermeldung. `C__Handles::LoadLibraryW` zeigt nun den realen W-Modulpfad (bei sehr langen Pfaden begrenztes Ende) statt generischem Text, behält LastError und Tracking bei. Konkrete Ursache des beobachteten 126 bleibt bis erneuter Ausführung ungeklärt (auch fehlende DLL-Abhängigkeit möglich). Keine Tests geändert. Nächster Schritt `manage.cmd --build-delta --test`, bei Erfolg `--test-plugin-pictview --debug` und `--release`. Keine Plugin-Migration vor grüner Baseline. Release NO-GO.
- **Änderungen:** Produktcode und drei Wartungsdokumente, keine Teständerung; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-50 — PictView Release-Baseline: native Tests und sechs F3-Hostfälle PASS

- **Gap-IDs:** A0-02, UP-02, WIC-02/07, QA-03, MGMT-03.
- **24.11.2026, 23:23:23–23:24:37 CET, sauberer Windows-HEAD `66187c7e6b9ed4bb03c53de933bfda003695b995`:** `manage.cmd --test-plugin-pictview --release` PASS, Laufzeit `00:01:13.754`, Log `manage-20261124-232323-525-79e959.log`. Native WIC-Tests je 8/8 x64 und x86 (16/16) PASS; 13 Endungen, Unicode-/Langpfad-PNG, SDK-Pfadgrenze, GDI, Transformation, Export, DIB-Clipboard und HWND/Lock-Vertrag. Reale Release-x64-F3-Hosttests BMP/PNG/JPEG/GIF/TIFF/ICO 6/6 PASS: jeweils eigener Prozess, geladenes PictView-SPL, WIC-Viewer geöffnet/geschlossen, Bild unverändert. Kein Fehler 126 in diesem Lauf; vorheriger Fehler betraf jedoch Debug. Konkretes zuvor fehlendes Modul und tatsächliche Ausführung der gezielten Demo-Migration weiterhin nicht nachgewiesen. Nur Release-Transcript übermittelt; `--build-delta --test` (inkl. SDK-Negotiation und Quellinventar) und Debug-F3-Gegenlauf nach Korrektur noch nicht separat belegt. Wenn bereits ausgeführt, deren Logs nachreichen, sonst fehlende Gegenläufe ausführen. PictView-Baseline für getestete Release-Funktionen grün, vollständige Funktionsparität und Unicode-/Langpfad-Hostintegration offen. ZIP/7-Zip/Renamer-Unit-/GUI-Baselines und getrennte CLI-Optionen weiterhin offen. Keine Produkt- oder Teständerung; Release NO-GO.
- **Änderungen:** ausschließlich drei Wartungsdokumente; keine lokale Windows-Ausführung durch den Agenten.

### J-20261124-51 — PictView-Baseline grün und zusätzlicher F3-UTF-16-Langpfad-Regressionstest

- **Gap-IDs:** UP-01/02, WIC-02/07, QA-03, MGMT-03, BUILD-01.
- **24.11.2026, 23:30:53–23:33:48 CET, sauberer Windows-HEAD `3e083068fc0b660dc490f833f415400f89fea6c7`:** `--build-delta --test` PASS (00:01:35.632, Log `manage-20261124-233053-440-083022.log`): Debug/Release x64, 32 HTML-Hilfen, 70 PS-Skripte, 90 Registry-Testquellen, 85 aktive C++-Projekte, 33/34 Plugin-Projekt-/Quellordner, 24 native C++-Regressionsaufrufe inkl. optionaler Unicode-Viewer-SDK-Negotiation und exakter langer UTF-16-Callback-Identität. Physischer Cross-Volume-Test weiterhin SKIP. `--test-plugin-pictview --debug` PASS (00:01:19.315, Log `manage-20261124-233229-529-2a7212.log`), native x86/x64 16/16 und reale F3-Hosttests 6/6 PASS. Zusammen mit Release auf produktgleichem `66187c7` ist die vorhandene PictView-Baseline für die getesteten Funktionen grün. Frühere Start-126-/Inventarfehler nicht reproduziert; konkretes damals fehlendes Modul/ausgeführte Demo-Migration nicht nachgewiesen. **Nächste TDD-Stufe:** zusätzlicher expliziter CLI-Opt-in `--test-plugin-pictview-unicode` (Debug/Release wählbar), neue Variante `-UnicodeLongPath` im bestehenden Hosttest: PNG-Bytes aus MemoryStream, ein GUID-eigenes Verzeichnis >MAX_PATH mit eindeutigem ASCII-Endsegment, Unicode-Bildname mit CJK und Supplementary-Zeichen, tatsächlicher Prozess-/SPL-/WIC-HWND-Nachweis, exakter vollständiger WIC-Fenstertitel (normaler oder erweiterter DOS-Pfad), SHA-256 unverändert. Bestehende sechs Formatfälle und Assertions unverändert, neuer Fall separat vom grünen Standard-/Plugin-Baseline-Lauf und in Registry als Opt-in sichtbar, mit bestehendem GUI-Wartegate. Kein neuer Produktcode, noch kein RED-/GREEN-Lauf des Zusatzfalls. Zunächst `manage.cmd --test`, dann `manage.cmd --test-plugin-pictview-unicode --debug`; bei Fehler Protokoll auswerten und tatsächlichen Host-/SDK-Aufrufpfad im Produktcode korrigieren, nicht den neuen Test auf ANSI/Alias abschwächen. Test läuft wie bestehender F3-Hosttest mit Benutzerprofil, isolierten Fixture-/TEMP-Dateien und eigenem Prozess; vollständige isolierte Profilabnahme weiterhin offen. ZIP/7-Zip/Renamer-Baselines und vollständige SDK-Erweiterung offen. Release NO-GO.
- **Änderungen:** additive neue Hosttestvariante, Manager/GUI-Gate/Registry und drei Wartungsdokumente; keine lokalen Windows-Tests durch den Agenten.

### J-20261124-52 — PictView Langpfadtest: nachgewiesenen Titel-Beobachtungsfehler korrigiert

- **Gap-IDs:** UP-02/05, WIC-02/07, QA-03, MGMT-03.
- **24.11.2026, 23:38:17–23:38:44 CET, sauberer Windows-HEAD `a294370d67a527fc691d55d95146a1bd5858f0b6`:** `--test-plugin-pictview-unicode --debug` FAIL, Exit 1, 00:00:27.477, Log `manage-20261124-233817-307-cdec6d.log`. PNG-Fixture 399 UTF-16-Einheiten erzeugt; Timeout beim Warten auf Verzeichnisnamen im Main-HWND-Titel (`Test-PictView-Host.ps1:456`), tatsächlicher Titel `Open Salamander`, kein F3 versandt. **Nachgewiesener Testfehler gemäß A8:** `CMainWindow::SetWindowTitle` (`src/mainwnd1.cpp:1860ff.`) setzt für `HasLongDiskPath()` absichtlich den konstanten MAINWINDOW_NAME, um Legacy-Pufferüberläufe zu verhindern. Der neue Test erwartet dagegen einen Pfadbestandteil in diesem Titel. Daraus ist weder ein Navigationsfehler noch ein SDK-RED nachgewiesen. Nur neue UnicodeLongPath-Variante korrigiert: vorhandene native Clipboard-Snapshot-Klasse vor dem ersten Lese-Kommando nutzen, über verifiziertes eigenes Main-HWND synchron WM_COMMAND 711 (CopyCurrentPathToClipboard, nicht Navigation) ausführen, frische stabile Clipboard-Sequenz und vollständigen ordinal gleichen Verzeichnispfad verlangen, Snapshot auch bei Fehler wiederherstellen und bei fehlgeschlagener Wiederherstellung hart fehlschlagen. Keine Pfad-/F3-/SPL-/Viewer-Titel-/SHA256-Assertion abgeschwächt, sechs bisherige Formatfälle unverändert, kein Produktcode geändert. Vollständiger neuer `--test`-Lauf auf `a294370` nicht im übermittelten Transcript belegt. Nächster Schritt `manage.cmd --test`, danach `manage.cmd --test-plugin-pictview-unicode --debug`; erst bei nachgewiesenem Produkt-RED die SDK-/Viewer-Anbindung korrigieren. Release NO-GO.
- **Änderungen:** ausschließlich nachweislich fehlerhafte neue Hosttest-Beobachtung und drei Wartungsdokumente. Keine lokale Windows-Ausführung durch den Agenten.

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

### J-20261124-53 — PictView F3: Produkt-RED und native Viewer-SDK-Anbindung

- **24.11.2026, 23:41:44–23:41:46 CET, sauberer Windows-HEAD `9cbe573188524ea36f93c1233bbc9ec7d9a71b15`:** `--test-plugin-pictview-unicode --debug` FAIL, Exit 1, 00:00:02.161, Log `manage-20261124-234144-039-4bc356.log`. 399 UTF-16-Einheiten Fixture, exakter aktiver 383er Panelpfad und Clipboard-Restore PASS. F3: `Cannot finish operation because of too long name`; SPL nicht resident. **Produkt-RED nachgewiesen:** `CFilesWindow::ViewFile` baut vor Viewer-Auswahl einen MAX_PATH-ANSI-Pfad; der SDK-W-Dispatch war bisher nicht verbunden. Produktkorrektur (A1/A2/A7/A8, UP-02/UP-06/WIC-07): native Disk-Panel-F3-Verzweigung vor diesem Puffer mit exakter W-Zeilenidentität bzw. verifiziertem eindeutigem Cache-/Live-Namen, Extended-Pfad und Existenzprüfung; konfigurierter Viewer/Handler, optionale `TryCanViewFileW`/`TryViewFileW`, PictView-Version-1-Export mit unveränderten SDK-103-VTables und Legacy-Exports, eigene W-Namenskopie im bestehenden Viewerthread und gemeinsamer WIC/HWND-/Lock-Pfad. Kein ANSI-Retry für nicht sicher darstellbare Pfade; nicht migrierte externe/Legacy-Viewer bleiben hierfür gesperrt, W-Dateihistorie und Find-/View-With-Menüintegration nicht vollständig migriert. Normale sichere Legacy-Aufrufe behalten ihren bisherigen Aufrufpfad. Keine Testdatei verändert. Windows-Build und GREEN noch offen, vollständige Plugin-/WIC-Parität offen. Nächster Schritt `manage.cmd --build-delta --test`, anschließend `--test-plugin-pictview-unicode --debug` und bei PASS `--release`; danach reguläre PictView-Baselines Debug/Release. Release NO-GO.

### J-20261124-54 — PictView F3: Folge-RED mit residentem SPL; differenzierte Produktdiagnose

- **24.11.2026, 23:46:18–23:46:20 CET, sauberer Windows-HEAD `d0d8399b9fb14d9d69a341e44deeb05f49e0e4ec`:** `--test-plugin-pictview-unicode --debug` FAIL, Exit 1, 00:00:02.472, Log `manage-20261124-234618-429-bd9595.log`. Fixture 399 UTF-16-Einheiten, Clipboard-Restore und exakter 383er Panelpfad PASS; erwartetes PictView-SPL resident, kein WIC-HWND; Fehlerdialog `Source path cannot be translated from Unicode to multibyte`. Vorheriger MAX_PATH-Dialog nicht mehr aufgetreten. Keine eindeutige Ursache für den neuen Fehler: bisher identische Meldung bei fehlender SDK-Negotiation, negativer CanView-Prüfung oder nicht geeignetem Handler. Native WIC-Langpfadtests auf früherer Baseline PASS, deshalb keine unbelegte Decoderänderung. Vollständiges Build-/`--test`-Protokoll auf `d0d8399b` nicht vorgelegt; geladener SPL-Export und Binäridentität zur Quelle nicht belegt. **Produktdiagnose:** fehlenden Export (127), abgelehnte Tabelle/Version (1306), sonstige Dispatchfehler, CanViewFileW-FALSE mit optionalem rohem Callback-Diagnosewert (PictView COM-/WIC-HRESULT vor Rückkehr) und ViewFileW-FALSE getrennt melden; konkreten Plugin-Modulnamen ausgeben, keine ANSI-Wiederholung, Viewer-Reihenfolge beibehalten. SDK-V1-Layout und SDK-103-ABI unverändert; optionaler LastError-Diagnosevertrag ändert keine BOOL-Semantik. Keine Tests geändert. Keine behauptete GREEN-Korrektur; Windows-Build und Gegenlauf offen. Nächster Schritt `manage.cmd --build-delta --test` mit vollständigem Transcript, dann `--test-plugin-pictview-unicode --debug`; neue Fehlerdetails auswerten, bei PASS Release und alte PictView-Baselines. UP-02/UP-06/WIC-07/QA-03 offen; Release NO-GO.

### J-20261124-55 — PictView F3: fehlender PE-Export (127); Build-Artefaktgate

- **24.11.2026, 23:48:41–23:48:43 CET, sauberer Windows-HEAD `4ce5f56e49f388962044181fbf57c18318692d00`:** `--test-plugin-pictview-unicode --debug` FAIL, Exit 1, 00:00:02.465, Log `manage-20261124-234841-521-e40991.log`. Exakter 383er Panelpfad, Clipboard-Restore und residenter PictView-SPL bestätigt; neuer Produktdialog `Unicode viewer SDK: export missing; plug-in: pictview\pictview.spl; status: 127 (0x0000007F)`. GetProcAddress findet den exakten Export nicht; WIC-Callback noch nicht erreicht. Quellprüfung: `pictview.cpp` definiert die unbedingte extern-C-WINAPI-Funktion, `pictview.def` deklariert sie, `plugin_base.props` verwendet die .def, Solution aktiviert PictView für Debug/Release x64 und Win32. Kein Beleg für einen konkreten Compiler-/Linkerfehler versus veraltete SPL-Datei; vollständiger Build-Transcript fehlt erneut. **Build-Gate** in `tools/Manage-Salamander.ps1`: nach jedem Solution-Build für Debug und Release das exakte PictView-SPL mit Pfad, UTC-Dateizeit, SHA256, x64-Machine und allen drei erforderlichen PE-Exporten per vorhandenem dumpbin-Parser prüfen; fehlende Exporte führen zu hartem Fehler mit tatsächlichen Exportzeilen, ohne Plugin-Code zu laden. Keine Tests oder SDK-/WIC-Produktlogik geändert; kein unbewiesener Linkerfix. Nächster Schritt frischer `manage.cmd --build-clean --test` (reguläre Build-Ausgabeverzeichnisse werden neu erzeugt), vollständiges Buildprotokoll inkl. PE-Gate sichern, nur bei PASS `--test-plugin-pictview-unicode --debug`, dann Release. UP-02/WIC-07/MGMT-03/QA-03 weiterhin offen; Release NO-GO.

### J-20261124-56 — PictView Clean-Build RED: zwei falsche Wrapper-Argumentnamen

- **24.11.2026, 23:50:38–23:51:25 CET, sauberer Windows-HEAD `029345e37f4d7df13c5e9ebf326b92c20de5d3d6`:** `--build-clean --test` FAIL, Exit 1, 00:00:47.217, Log `manage-20261124-235038-219-180157.log`; MSBuild 18.12.3. Debug-x64-Hauptprogramm gelinkt, PictView-Kompilierung scheitert mit C2065 in `WicNativeViewer.cpp:548,560`: beide Wrapper `RunNativeViewer` und `RunNativeViewerW` deklarieren `UINT showCommand`, übergeben aber den nicht deklarierten Namen `showCmd` an `RunNativeViewerImpl`. Fehler eingeführt in `d0d8399b`. **Minimaler Produktfix:** ausschließlich die zwei fehlerhaften Argumentnamen auf `showCommand` korrigiert; Signaturen, SDK-ABI, Exportdefinitionen, Viewersemantik und Tests unverändert. Damit ist ein konkretes Hindernis für die Erstellung des neuen SPL belegt; ob die früheren 127-Fehler tatsächlich auf ein altes SPL zurückgingen, bleibt bis zum erfolgreichen Build-/Export-/GUI-Gegenlauf offen. Release-Build, neues PE-Gate und `--test` wurden nicht erreicht. Statische Quellprüfung PASS, Windows-GREEN nicht ausgeführt. Nächster Schritt `manage.cmd --build-delta --test` (Debug bereits frisch begonnen, übrige Artefakte inkrementell vervollständigen; kein weiterer Clean erforderlich für diesen Zweizeilenfix), danach nur bei PASS `--test-plugin-pictview-unicode --debug`, dann Release. UP-02/WIC-07/MGMT-03/QA-03 offen; Release NO-GO.

### J-20261124-57 — PictView SDK-Build GREEN; WIC-Fenstertitel RED

- **24.11.2026, sauberer Windows-HEAD `6c043a6b54f01a395b9bf243861edfe1ad88a2a5`:** 23:53:03–23:55:12 CET `--build-delta --test` PASS (00:02:09.159, Log `manage-20261124-235303-148-09138f.log`). Debug/Release x64 gelinkt, je alle drei PictView-PE-Exporte PASS (Debug SHA256 `5DFDCD22F9E1FDF21A998A684100C8A6F6E160E7090B116B10CC00BF1F5D31B0`, Release `CEE06BEF64C1DC9D15A00749914C1A0AF5774EAF4377A75E1E1E5672ECD87F58`), 32 HTML-Hilfen, 70 PowerShell-Parserprüfungen, 90 Registry-Testquellen, 24 native Regressionen und 18 Dateisystemassertions PASS; physischer Cross-Volume-Unterfall weiterhin SKIP. Zwei Transcript-Meldungen `The pipeline has been stopped` vor den erfolgreichen Exportprüfungen, keine abschließende Buildfehlermeldung; Ursache dieser Zwischenmeldungen nicht untersucht. 23:55:30–23:55:33 CET `--test-plugin-pictview-unicode --debug` FAIL (00:00:02.498, Log `manage-20261124-235530-567-e5f28e.log`): exakter 383er Panelpfad, Clipboard-Restore, residenter SPL und echtes WIC-HWND PASS; 399er UTF-16-Pfad, erwarteter Titel aber leer (`Test-PictView-Host.ps1:633`), Hash-/Close-Assertions noch nicht erreicht. Exportfehler 127 und vorherige Compilerfehler im konkreten Gegenlauf nicht mehr aufgetreten. **Produktbefund:** `ViewerProc` in `src/plugins/pictview/WicNativeViewer.cpp` setzt bei WM_NCCREATE GWLP_USERDATA, liefert dann direkt TRUE und überspringt die Standardinitialisierung des Fenstertitels durch DefWindowProcW; CreateWindowExW erhält bereits den exakten W-Pfad. Minimaler Fix: nach unverändertem State-Setup WM_NCCREATE an DefWindowProcW weiterreichen, dessen Rückgabewert respektieren. Keine Änderung an Pfad, SDK, Decoder, Test oder Assertions. Windows-GREEN auf Folgecommit noch offen. Nächster Schritt `manage.cmd --build-delta --test`, dann `--test-plugin-pictview-unicode --debug`, bei PASS Release und beide regulären PictView-Suiten. UP-02/UP-06/WIC-07/MGMT-03/QA-03 bleiben offen; Release NO-GO.

### J-20261125-01 — PictView Unicode-Langpfad-F3 GREEN und reguläre Debug-/Release-Regressionen

- **24./25.11.2026, sauberer Windows-Quell-HEAD `cc0b8abfc299e1d34ad0170d0412649da94940d4`: TDD-GREEN für nativen PictView-F3-Unicode-Langpfad.** `--test-plugin-pictview-unicode --debug` 24.11. 23:58:36, PASS 00:00:02.412, Log `manage-20261124-235836-543-66a6f2.log`; `--release` 23:58:54, PASS 00:00:02.371, Log `manage-20261124-235854-043-df6d0b.log`. Jeweils 399 UTF-16-Einheiten Dateipfad (CJK/Supplementary), 383er exakter aktiver Panelpfad, Clipboard-Restore, exakt gleicher WIC-Fenstertitel (DOS oder Extended), erwarteter residenter SPL, eigenes WIC-HWND geöffnet/geschlossen und unveränderte SHA-256-Bildbytes PASS. RED auf `6c043a6` (leerer Titel) ist damit für diesen Fall nach dem WM_NCCREATE-Fix nicht mehr reproduziert. Reguläre `--test-plugin-pictview --debug` ab 23:58:56 PASS 00:01:15.618, Log `manage-20261124-235856-862-763b43.log`; `--release` ab 25.11. 00:00:13 PASS 00:01:20.240, Log `manage-20261125-000013-938-dd66b0.log`. Pro Suite 8/8 native x64 und 8/8 native x86, 6/6 echte x64-F3-Hostfälle BMP/PNG/JPEG/GIF/TIFF/ICO; insgesamt 32 native Testausführungen und 14 Hostfälle über vier CLI-Läufe PASS. 13 beworbene Endungen inklusive JPEG XR, Unicode-/Langpfad-PNG, Decoder-Negativfälle, GDI, Transformationen, PNG-Export, DIB-Clipboard und nativer HWND-/Lock-Vertrag auf diesem Rechner nachgewiesen. Keine Produkt- oder Teständerung in dieser Dokumentationsfortschreibung. Standard-/Build-/PE-Gate-Protokoll auf `cc0b8ab` nicht übermittelt; letzter separat belegter `--build-delta --test` ist `6c043a6`, physischer Cross-Volume-Unterfall SKIP. Native x86-Tests sind kein Win32-Solution-/Hostbuild-Nachweis. WIC-01/02/07, UP-02/06 und QA-03 durch konkrete Teilnachweise fortgeschritten, keine pauschale Schließung: historische Funktionsparität, Thumbnails/Animation, weitere SDK-Grenzen, Find-/View-With/History, UNC/Maximalpfade, Host-Pixel-/Lock-Nachweis, Wiederholbarkeit und andere Systemcodec-/VM-Umgebungen offen. MGMT-03: registrierter Unicode-F3-Opt-in ausgeführt; neuer Volltest offen. **Nächster Schritt:** `manage.cmd --build-delta --test-all` auf aktuellem Stand; geplante Opt-in-SKIPs nicht als PASS zählen. Danach ZIP/7-Zip/Renamer-Funktionsbaselines und getrennte CLI-Suiten vor Migration vorbereiten. Release NO-GO.

### J-20261125-02 — Vollregression 108/2/35; zwei modale Testtreiberabbrüche

- **25.11.2026, 00:03:29–00:19:21 CET, sauberer Windows-HEAD `8b9a31b379fa0fb52a3a7f27cf98c668d18804a9`:** `--build-delta --test-all` insgesamt FAIL (00:15:52.349), 108 PASS / 2 FAIL / 35 SKIP auf Sammlungsebene. Log `manage-20261125-000329-561-b07357.log`, JSON `manage-20261125-000329-561-b07357.results.json` lokal. Debug/Release x64 Solution-Delta und beide PictView-Exportgates PASS; isolierte WER-Core-Buildmatrix 4/4, 33 gebaute x64-Plugin-PE-Tabellen pro Konfiguration (66/66), 70 PS-Parser, 90 Registry-Testquellen, 24 native C++-Regressionsaufrufe, PictView headless und interaktive HWND-Tests, Legacy Find 37/37 je Debug/Release und ViewUnicode 5/5 je Debug/Release PASS. Vollständige Win32-Plugin-Solution und reale Plugin-Funktionen nicht aus ABI-/Core-Builds ableiten. PictView-F3-Opt-ins bewusst SKIP; deren separate GREEN-Belege auf produktgleichem `cc0b8ab` bleiben gültig. Physischer Cross-Volume-Fall, EFS, NearLimit, weitere Opt-ins/VM offen. Zusammenfassung meldet 35 Scope-SKIPs, Fehlertext dagegen 0 übersprungen (keine Aussage, dass 35 Tests ausgeführt wurden); zwei Zwischenmeldungen `The pipeline has been stopped` unmittelbar vor erfolgreichen PE-Gates erneut sichtbar, nicht weiter untersucht.
- **Nachgewiesener Testtreiberfehler (A8, QA-03):** Release `--test-gui-unsafe-unicode-operations` nach F2-Sicherheitsrefusal PASS beim Bestätigen des erwarteten Error-MB_OK (Log Zeilen 2817–2833) und Release `--test-gui` nach F5 beim erwarteten Unicode-copy-MB_OKCANCEL für `short-to-long.txt` in 411er Panelpfad (3350–3374) abgebrochen. Beide Exception `Test-SalamanderGui-LongPaths.ps1:2774`: `Send-Keys` verweigert korrekt globale Eingabe bei fremdem Vordergrund und vorhandenem Modal. Kein Nachweis einer fehlerhaften Produktoperation; der erste Fall hat die Ablehnung bereits beobachtet, der zweite noch kein OK gesendet. Entsprechende Debug-Gesamttests PASS. Produktvertrag in `fileswn5.cpp:2816` und `fileswn8.cpp:784–795,1572` geprüft: identischer Refusaltext/MB_OK und synchroner F5-Prompt mit exaktem Namen, Ziel und Nichtüberschreibhinweis. Ausschließlich die beiden betroffenen Testtreiberstellen korrigiert: exakte vollständige Static-Nachricht über bounded WM_GETTEXT (4096 Zeichen, 1000 ms je Control), PID, Main-HWND-Klasse, sichtbares/aktiviertes #32770, Owner-Beziehung, exakte Caption, eindeutiges Dialog-HWND und verifiziertes IDOK; unmittelbar vor einmaligem PostOwnedCopyDialogButton erneut prüfen. Beim Refusal vollständiges Schließen und Main-Enablement abwarten; bei F5 feste Pause/globalen Enter durch exakt gebundene Bestätigung ersetzen. F2/F5/F6/F8-Auslösung, bestehende Daten-/Kollisions-/No-write-Assertions, allgemeine Foreground-Schutzlogik und Produktcode unverändert. Keine globale Eingabewiederholung und keine Timeout-Erhöhung. Neue Treiberkorrektur statisch geprüft, Windows-GREEN offen; andere globale Modal-Bestätigungen nicht vorsorglich umgebaut. Nächster Schritt `manage.cmd --test`, dann `manage.cmd --test-gui-unsafe-unicode-operations --release`, `manage.cmd --test-gui --release`, bei Erfolg beide Debug-Gegenläufe und `manage.cmd --test-all`; bei FAIL zuerst den neuen konkreten Befund auswerten. Release NO-GO.

### J-20261125-03 — Beide Release-GUI-Gegenläufe GREEN; veralteter Metatest RED

- **25.11.2026, 00:22–00:23 CET, sauberer Windows-HEAD `e7712c9a3cf97c79fdd43f65b85301500d835d15`:** `--test` FAIL nach 00:00:27.954, Log `manage-20261125-002222-650-512f03.log`, `Test-Package-Helpers.ps1:365`: `Unicode unsafe-operation GUI test must restore verified app focus after modal refusal and validate source panel.` 70 PS-Parserprüfungen, 90 Registry-Testquellen und vorherige GUI-Vertragsprüfungen PASS; restlicher Standardlauf nicht erreicht. Beide zuvor auf `8b9a31b` fehlgeschlagenen Release-GUI-Suiten sind auf `e7712c9` GREEN: `--test-gui-unsafe-unicode-operations --release` PASS 00:00:05.575, Log `manage-20261125-002251-035-556dbe.log` (alle vier Refusals F2/F5/F6/F8, exakte Quellzeilen, unveränderte Originalbytes, keine Zieldateien); `--test-gui --release` PASS 00:00:21.492, Log `manage-20261125-002257-046-407471.log` (Short-to-long-F5 beidseitige Byteintegrität, Target-leaf-Overflow F5/F6, 255er Komponenten, 564er Navigation, SMB-UNC, F2/F5/F6/F8). **Nachgewiesener Metatestfehler (A8):** alter Regex in `Test-Package-Helpers.ps1` verlangt ausdrücklich globales ESC unmittelbar vor Dialog-Wartebedingung und Focus-TestProcess, obwohl der Testtreiber seit `e7712c9` den erwarteten MB_OK-Dialog über verifiziertes eigenes HWND bestätigt. Fokuswiederherstellung, Panelprüfung und Fremdprozess-Eingabeschutz bestehen unverändert. Ausschließlich diesen fehlgeschlagenen statischen Vertrag aktualisiert: fordert FindVerifiedRegressionPrompt mit Main-HWND/PID/Caption/Text, ConfirmVerifiedRegressionPrompt mit identischem Kontext und gespeichertem HWND, anschließend tatsächliches Verschwinden des Dialog-HWND, Enablement des Main-HWND, Abwesenheit blockierender Dialoge und Focus-TestProcess in dieser Reihenfolge; vorherige Panel-/Fremdprozess-Assertions bleiben. Statischer Regex-Gegencheck (JS, nicht PowerShell): bisherige Regel lehnt aktuellen Treiber ab, neue akzeptiert ihn und verwirft Varianten ohne Lookup, Fokus, HWND-Schließung, Main-Enablement oder korrekten Bestätigungs-PID. Kein Produktcode und kein GUI-Treiber geändert. Windows-Ausführung des korrigierten Metatests offen. Nächster Schritt `manage.cmd --test`, bei PASS beide betroffenen Debug-Gegenläufe und `manage.cmd --test-all`. Kein erneuter Produktbuild erforderlich. Letzte vollständige Regression weiterhin 108 PASS / 2 FAIL / 35 SKIP auf `8b9a31b`; nicht nachträglich als Gesamt-GREEN deklarieren. Release NO-GO.

### J-20261125-04 — Standard-/GUI-Gegenläufe GREEN; Vollregression durch Fokusabbrüche blockiert

- **25.11.2026, 00:26–00:43 CET, sauberer Windows-HEAD `2ecd4729cd16a86b56de5b9da71f9e7c6684d99f`:** `--test` PASS 00:01:30.979, Log `manage-20261125-002622-956-ec0965.log` (70 PS-Parserprüfungen, 90 Registry-Testquellen, 24 native C++-Regressionen, 18 Dateisystemassertions; physischer Cross-Volume-Unterfall SKIP). Statischer ESC-Metatest aus J-20261125-03 damit GREEN. `--test-gui-unsafe-unicode-operations --debug` PASS 00:00:05.620, Log `manage-20261125-002805-607-8ae26e.log`; `--test-gui --debug` PASS 00:00:22.995, Log `manage-20261125-002811-676-fee240.log`. Vorige Release-GREEN-Nachweise auf `e7712c9` bestätigt durch beide entsprechenden Release-Suiten im neuen Volltest; keine Produktcodeänderung seit `cc0b8ab`. `--test-all` FAIL nach 00:15:01.897, 105 PASS / 5 FAIL / 35 SKIP (Sammlungsebene), Log `manage-20261125-002835-133-ea9994.log`, JSON `manage-20261125-002835-133-ea9994.results.json`. WER-Core-Buildmatrix 4/4, 66/66 x64-Plugin-PE-Exporttabellen, native PictView x86/x64 inkl. HWND-/Lock-Test, beide ViewUnicode-Wiederholungsserien je 5/5, alle Debug-GUI-Suiten PASS. Legacy Find Release 36/37, Debug 37/37. PictView-F3-Opt-ins, Cross-Volume, EFS/NearLimit und andere 35 Scope-Ausschlüsse nicht als PASS werten. Kein neuer vollständiger Solution-Build in diesem Lauf; vorheriger x64-Build-/Exportnachweis auf produktgleichem `8b9a31b` bleibt Referenz.
- **Fünf Release-GUI-Abbrüche (QA-03; A8):** `--test-gui-legacy-find` ausschließlich UnicodeFindShortcut vor tatsächlicher Shortcut-Prüfung, Restore-FilePanelFocus:2767, active/focus=0, kein Dialog (Log Z. 2322–2385); `--test-gui-operations-baseline` erwarteter ASCII-Copy-Dialog nach F5, Send-Keys:2841 vor Enter (Z. 2548–2574); `--test-gui-unicode-transfer` erwarteter Unicode-copy-Dialog nach F5 vor Enter, gleicher Guard (Z. 2718–2742); `--test-gui-unicode-rename` erwarteter Rename-Unicode-item-Dialog vor Ctrl+A/Ctrl+V/Enter, gleicher Guard (Z. 2743–2764); `--test-gui-unicode-multiselect` nach verifiziertem F6-Quellpanel explizit GUI_ENVIRONMENT_BLOCKED:2596, sechs begrenzte Aktivierungsversuche, fremder Vordergrund `PrimeVideo` PID 7900, keine Tasten gesendet (Z. 2835–2854). Dasselbe fremde Fenster wurde vor den ASCII-Copy-/Unicode-copy-Abbrüchen in der Fokuswiederherstellung protokolliert (Z. 2558,2724). Damit ist eine konkurrierende Desktop-Anwendung nachgewiesen, jedoch nicht ihr kausaler Anteil an jedem einzelnen Abbruch. Quellprüfung: Restore-FilePanelFocus und Send-Keys verweigern Eingaben bei fehlendem verifiziertem Vordergrund bzw. offenen Modalen absichtlich; Focus-TestProcess hat begrenzte Aktivierung und explizite Umweltblockade. Drei erwartete Produktdialoge wurden beobachtet, deren Folgeassertions aber nicht erreicht; kein nachgewiesener neuer Produktfehler. Keine Produkt-/Teständerung, keine Abschwächung oder Umdeklaration der fünf FAILs. Entscheidung: vor weiterem Testtreiberumbau isolierter Gegenlauf mit geschlossenen konkurrierenden Desktop-Anwendungen (insbesondere PrimeVideo), keine Benutzerinteraktion während des GUI-Laufs, Desktop entsperrt, gleicher Integritätslevel. `manage.cmd --test-gui-legacy-find --release`, `--test-gui-operations-baseline --release`, `--test-gui-unicode-transfer --release`, `--test-gui-unicode-rename --release`, `--test-gui-unicode-multiselect --release`; bei PASS `--test-all`, bei reproduziertem FAIL gezielt analysieren. Kein Build erforderlich. Release NO-GO.
