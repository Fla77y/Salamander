# Salamander 5.2 – Testlücken, Nachweise und Abnahmeplan

> **Verbindlicher Arbeitskatalog für offene Qualitäts- und Release-Nachweise**
>
> Stand: **24. November 2026** (Fortschreibung des historischen
> Arbeitskatalogs vom 23.11.). Ursprüngliche grüne Referenz
> `a7ab5b40d859509ffe5fead2d8f00739399a5067`; zuletzt
> zuletzt unter Windows ausgewerteter **GUI-Quellstand** `8a6de88c3eafe54cc874bdec85019ea67a5fdfcc` (`--test-gui-legacy-find --debug`: Build PASS, 34 PASS / 3 FAIL / 0 SKIP am 24.11.2026 15:28–15:32 CET). Letzter **vollständiger** `--build-delta --test`-PASS: `9f524264`, 14:32–14:34 CET.
> Die Dokumentationscommits danach sind **keine** neue grüne Testbaseline.
> **Keine vollständige Anforderungsabdeckung und keine Release-Freigabe behauptet.**
>
> **Arbeitsregel:** Vor jeder anforderungsrelevanten Änderung diesen Katalog,
> `AGENTS.md`, `Anforderungen.md` (falls im Checkout vorhanden), die
> Projektquelle `Master-Prompt.odt` sowie die betroffenen Tests/Quellen
> prüfen. Nach Änderungen IDs, Status und Testbelege aktualisieren.

## 1. Zweck und Geltungsbereich

Dieses Dokument ist die **fortlaufend zu pflegende, zentrale Arbeitsliste**
für die Anforderungen **A0–A7** aus `Anforderungen.md`. Es ergänzt, ersetzt
aber nicht die verbindlichen Produktanforderungen oder die Release-Gates.

**Quellen im Repository:** [verbindliche Originalanforderungen](../../Anforderungen.md),
[aktueller Übergabestand](Arbeitsstand-und-Uebergabe.md),
[append-only Entwicklungsjournal](Entwicklungsjournal.md),
`AGENTS.md`;
`docs/maintenance/test-coverage-audit-2026-11-23.md` (historischer Audit);
`docs/maintenance/Legacy-Find-UTF16-Migration.md`;
`docs/pictview-wic-migration.md`;
`tools/release/Release-5.2-Gates.md`;
`tools/Manage-Salamander.ps1`;
`tools/tests/`, `tools/release/tests/`, `.github/workflows/`.
Der `Master-Prompt.odt` liegt als Projektquelle vor; die Repository-Datei
`AGENTS.md` konsolidiert die für Salamander relevanten Arbeitsregeln.
Bei Abweichungen hat die verbindliche Anforderung Vorrang; Unterschiede
werden ausdrücklich dokumentiert, nicht stillschweigend umdefiniert.

**Abgrenzung:** Eine grüne `--test-all`-Suite beweist ihre ausgeführten
Szenarien, aber weder 100 % Branch-Coverage noch vollständig implementierte
Funktionen, noch eine saubere Endnutzer-VM. Eine Datei mit einem Testnamen
beweist nicht, dass dieser Test auf dem aktuellen Commit ausgeführt wurde.

### 1.1 Nachgewiesene Ausgangsbasis

| Bezug | Stand / Beleg | Bewertung |
| --- | --- | --- |
| Vorheriger Referenzstand | `baseline/test-all-pass-2026-11-23` → `37a5cc595e45c37b32ad8460148717d975bc600b`; protokollierter Windows-`--test-all`-Lauf vom 23.11.2026 | Historisch grün |
| Aktueller Referenzstand | `baseline/test-all-pass-2026-11-23-f5-f6` → `a7ab5b40d859509ffe5fead2d8f00739399a5067`; Benutzerprotokoll `manage-20261123-181433-866-c973b8.log`, 18:14:33–18:26:22 CET (nicht im Git versioniert) | Tatsächlich erfolgreicher `--test-all`-Stand mit Windows-Testausgabe |
| Verifizierte Teilbereiche | 36 isolierte Legacy-Find-GUI-Szenarien je Release/Debug x64 (72); native Unicode-/WIC-Tests; F2/F5/F6/F8; 263-UTF-16-Pfad und F6-Datei >17 MiB mit SHA-256; umfangreiche Max-Pfad-/GUI-Tests | **Nur** die konkret ausgeführten Szenarien |
| Ausstehende Erweiterungen | [Draft-PR #14](https://github.com/Fla77y/Salamander/pull/14) (`test/coverage-validation-2026-11-23`, zuletzt `bbf2c39e158acbc38e5192b5efc3e0e07c394f01`) | Nicht in `a7ab5b40` enthalten; Tests/CI auf finalem Merge-Stand nachzuholen |
| Endnutzer-Release | `tools/release/Release-5.2-Gates.md` enthält offene Prüf- und Entscheidungspunkte | **NO-GO** bis alle zutreffenden Gates belegt |

Die genauen Benutzerprotokolle sind nicht automatisch im Git-Repository
versioniert. Für einen Statuswechsel immer **Commit-SHA + Testbefehl +
OS/Toolchain + Ergebnis + Protokoll/Artefakthash** hinterlegen.

### 1.2 Status- und Prioritätsregeln

- **OFFEN:** Testfall/Nachweis fehlt oder ist auf dem aktuellen Stand nicht belegt.
- **VORBEREITET:** Test liegt in einem nicht gemergten PR oder ist nur statisch geprüft.
- **BLOCKIERT:** Benötigte Umgebung, Voraussetzung, ABI- oder Produktentscheidung fehlt.
- **TEILBELEGT:** Einzelne Fälle sind ausgeführt; das Abnahmekriterium insgesamt fehlt.
- **BESTANDEN:** Alle für die ID definierten Fälle auf der angegebenen SHA,
  Konfiguration und Umgebung ausgeführt; Negativfälle und Nachweise dokumentiert.
- **P0:** Datenverlust, grundlegender Vertragsbruch oder Release-Blocker.
  **P1:** hoher Funktions-/Kompatibilitätsbedarf. **P2:** weitere Robustheit/Diagnostik.

Alle nachfolgenden Checkboxen sind **offen**, soweit nicht explizit anders
markiert. Ein vorbereiteter Test wird **nicht** allein durch Merge oder
erfolgreichen Build zu BESTANDEN. Testumgebungsfehler sind BLOCKIERT/FAIL,
nicht SKIP=PASS.

## 2. Querschnittsmatrix und Testdaten

Für jede relevante Dateioperation den jeweils anwendbaren Satz ausführen:

| Dimension | Minimale Testfälle |
| --- | --- |
| Zeichen / Identität | ASCII; CP1252 mit Umlaut; `東京`; nicht-ACP-Zeichen/Emoji; gleich aussehende oder durch ANSI-Best-Fit kollidierende Namen; kombinierende Zeichen; exakte UTF-16-Identität |
| Pfadlänge | Kurz; Gesamtpfad 259/260/263; kurzer Ordner + langer Dateiname; 255 UTF-16-Einheiten im einzelnen Namen; >260; 32.700 UTF-16-Einheiten, **wenn das Dateisystem/OS die Fixture zulässt** |
| Pfadart | Laufwerk, `\\?`-Laufwerkpfad, gültiger UNC-/SMB-Pfad, `\\?\UNC`-Pfad, unterschiedliche Laufwerke, Reparse Point/Junction; ungültige Device-/Dot-Segmente ablehnen |
| Inhalt / Größe | 0 B; 1 B; 16-/32-MiB-Grenzen; große Datei; binärer Inhalt/ADS, soweit vom konkreten Dateisystem unterstützt |
| Operation | Öffnen/Lesen, Anzeigen, Kopieren, Verschieben, Umbenennen, Löschen/Papierkorb, Suchen, Archivieren/Extrahieren, Clipboard/Editor/Shell, **je nach Modulvertrag** |
| Fehler | Bereits vorhandenes Ziel; Access Denied; gesperrte/geänderte Quelle; Abbruch; volles Volume; Offline-Netzwerk; fehlender Codec/Plugin; kaputtes Archiv/Bild; ungültige Namen |
| Korrektheit | Quell-/Ziel-SHA-256, Größe, Name, vollständiger Pfad, keine stille Trunkierung, keine Überschreibung ohne Zustimmung, unveränderte Nachbar-/Originaldateien; kontrollierter Cleanup |
| Laufzeit | Release/Debug und Win32/x64 **soweit unterstützt**; Windows-Codepage/Locale, LongPathsEnabled; realer GUI-Host, wo die Funktion GUI-/Plugin-gebunden ist |

**Sicherheit:** Ausschließlich GUID-eigene Wegwerf-Fixtures einsetzen.
Vor destruktiven Aktionen Eigentümerschaft, Pfad und unveränderte
Dateiidentität prüfen. Fremde Salamander-Prozesse nie automatisch beenden.
EFS, Papierkorb-Wiederherstellung, Netzlaufwerke, Plugin-Load, Installer und
VM-Snapshots bleiben ausdrücklich kontrollierte **Opt-in**-Prüfungen.
Bei nicht erstellbarer 32.700er-Fixture den Win32-Fehler protokollieren;
eine kürzere Fixture erfüllt den Grenzfall **nicht**.

## Arbeitsfortschritt M1 – nachgeführter Windows-Stand (24. November 2026)

**Neuer belegter Windows-GUI-Stand 24.11.2026, 15:28–15:32, Quell-SHA `8a6de88`:** isolierter Debug-x64-Build PASS, MSVC-C2039 somit behoben; Legacy-Find-Suite **34 PASS / 3 FAIL / 0 SKIP**. `AdvancedInputs` verweigert Auswahl mit Shift-KeyState `0xFF81`, `ShellClipboard` wartet vergeblich auf Copy-Dateiliste und Drop-Effekt, `ExternalEditor` unverändert `NOT_STARTED` trotz separatem PowerShell-Preflight-PASS und sichtbarem test-eigenem `Open Salamander`-Dialog. Nachfolgend eingecheckte Änderungen betreffen nur Treiberdiagnosen und sichere physische Modifikatorbereitschaft, **noch kein Windows-GREEN**. Kein erfolgreiches neues `--test` auf `8a6de88`, kein vollständiger GUI-PASS. Beleg: Benutzerlog `manage-20261124-152841-475-9a382e.log`; Originalprotokoll privat, nicht in Git.


**Windows-Gegenlauf 24.11.2026, 15:12 / SHA `3820e636...`:** `--build-delta --test` **FAIL** im Debug-C++-Build, `src/fileswn5.cpp:1516` C2039 (ungültige `HANDLES(Salamander::CreateConfiguredEditorProcessA(...))`-Expansion). Direkt danach `--test-gui-legacy-find --debug` **FAIL ebenfalls im isolierten Debug-Build**, keinerlei GUI-Szenario ausgeführt. In Folgecommits durch vorhandene `C__Handles::CreateProcess`-Schnittstelle als `HANDLES(CreateProcess(...))` behoben; überflüssige Wrapperfunktion entfernt, native Regression und statischer Vertrag angepasst. **MSVC-/PowerShell-/GUI-GREEN ausstehend**. Diese Quellcodeänderung stellt noch keine neue grüne Baseline dar.


**Neuer Debug-Legacy-Find-Nachweis am 24.11.2026, 14:59–15:02 (Quell-SHA `3119af034cf5eb6d1a65b27880d891baa5258ca9`):** 36 PASS, 1 FAIL, 0 SKIP.
`ExternalEditorNative` und PowerShell-Host-Preflight beide **PASS**; ausschließlich tatsächliches Legacy-Find-`ExternalEditor` bleibt `NOT_STARTED` / FAIL. Dagegen sind die 36 anderen Szenarien erfolgreich.
**Nachfolgende ungetestete Produktkorrektur:** Für vorhandene absolute `.exe`-Editoren wird dem Win32-`CreateProcessA` der Anwendungsname explizit übergeben, für andere Editorbefehle bleibt Legacy-Verhalten erhalten. Neuer nativer Editor-Prozessstarttest und statische Vertragsprüfung hinzugefügt.
**Kein neuer `--test`-/GUI-PASS** auf den neueren Quell-SHAs; FIND-04/QA-03 ausdrücklich weiter offen.
Beleg des realen Fehlers: lokales `manage-20261124-145926-376-de4931.log`, im Git nicht abgelegt.


**Windows-Nachweis 24.11.2026, 14:32–14:34 auf `9f524264`:** Debug/Release-x64-Delta-Build und `--test` **PASS**. Neuer nativer 8.3-Verzeichnisalias-Test **positiv PASS**; 22 registrierte native C++-Regressionen, 66 PS-Skripte. **GUI nicht ausgeführt:** Unicode-Elternverzeichnis Release/Debug und Legacy-Find Debug um 14:34 jeweils durch eine bereits laufende Salamander-Instanz **vor dem eigentlichen Produkttest blockiert** (kein neuer Produkt-PASS/-FAIL). Nicht-8.3-Volumes, echte Debug-/Release-GUI-Verzeichnisnavigation und externer Editor weiterhin offen. Vor erneuter GUI-Prüfung alle regulären Salamander-Instanzen geordnet schließen; niemals automatisch fremde Prozesse beenden.

**Beleg- und Umfangsgrenze:** User-Transkripte, nicht in Git gespeicherte
Logdateien. Der letzte **tatsächlich** geprüfte aktuelle Code-Stand ist
`bugfix/v5.2` bei `9f524264af766cfc417b5b2b9870008e88b6e093`
(`manage.cmd --build-delta --test` **PASS**, 24.11.2026, 14:32–14:34 CET).
Ein darauf folgender **Dokumentationscommit** gilt nicht als neu getesteter
Produktcode. Detailgeschichte und Folgeaufträge:
[Entwicklungsjournal](Entwicklungsjournal.md), aktueller
[Übergabestand](Arbeitsstand-und-Uebergabe.md).

| Gap-IDs / Thema | Tatsächlich umgesetzt bzw. bestätigt | Noch ausstehend / Status |
| --- | --- | --- |
| **A0-01 / About** | Zusatzzeile für EXE-Zeitstempel, Debug/Release, x86/x64; `about_build_info.cpp` im am 24.11. 12:59 gelaufenen `--test` PASS | Echter About-GUI-/Layout-/Lokalisierungstest; **TEILBELEGT**, keine 5.0-A/B-Vollparität |
| **UP-04 / F5/F6** | `--test-gui-unicode-multiselect --release` am 24.11. 02:54 PASS, einschließlich synchroner und 17-MiB-Worker-Fälle; native Worker-/Identitätsprüfungen im 12:59-`--test` PASS | Cross-Volume-Nativtest mangels `OPENSAL_CROSS_VOLUME_TEST_DIR` **SKIP**; gemischte Ordner-/Dateibatches, alle Volumes/ADS offen; **TEILBELEGT** |
| **UP-06 / Unicode-Elternverzeichnis** | Identischer, reproduzierbarer Fehler in Release/Debug am 24.11. 03:00/03:01: `ChangeUnicodePathToDisk` verweigert nicht-ACP-Pfade mit Modal-Dialog, `WM_COMMAND 775` timeout | **OFFENER PRODUKTFEHLER**; keine unsichere ANSI-Umgehung; vollständige W-Panelnavigation fehlt |
| **FIND-04 / QA-03** | **24.11. 15:02, `3119af03`: 36 PASS, 1 FAIL, 0 SKIP**; unabhängig gestartetes PowerShell erfolgreich, nativer cmd-Editor PASS, Unicode-/Find-Ergebnisaktionen PASS | Original-`ExternalEditor` über Salamander: weiterhin `NOT_STARTED` / FAIL. Nachfolgende explizite `CreateProcessA`-EXE-Identität und nativer Test **noch nicht unter Windows verifiziert**; Release-Variante offen. |
| **BUILD-01 / A3** | Debug/Release-x64-Delta-Build nach Umzug unter `.Build/` PASS, zunächst ca. 122 s, danach ca. 8 s | Komplette Vierfachmatrix und neuer Clean-/Setup-Lauf auf HEAD offen |
| **MGMT-01/02/03** | `.Build/` gitignoriert und als Buildroot; `--test-all` sammelt unabhängige Testfehler in JSON und liefert insgesamt nonzero; eigenständiger Sammlertest am 24.11. 12:59 PASS | Vollständige Update-/Build-/Test-/Setup-Matrix, defekte Voraussetzungen/Unterbrechung und automatisierte Lückenregistrierung weiter **TEILBELEGT/OFFEN** |
| **QA-01 / A0-02** | Native F6-Dateiidentitäts-, Binär- und Registry-Canary-Verträge im `--test` PASS | Echte Benutzer-5.0-Upgrade-/Rollback-VM und alle Fehler-/Nebenläufigkeitsfälle offen |
| **UP-03 / A1–A2** | Kein neuer positiver Beleg für sämtliche Plugins/Archive | **UnRAR-Ersatz aus Chat 09 bleibt ausdrücklich offen**; Archiv-/Plugin-ABI/Unicode/Longpath-Matrix fehlt |
| **A5 / A7** | Bestehende WIC-/Release-Vertragstests in `--test` PASS | Realer WIC-Host/Codec-Parität, Installer, saubere VM und Public-Gates nicht erledigt; **NO-GO** |

**Verifikation am 24.11., 12:59–13:00 CET:**
`manage-20261124-125928-575-54f5eb.log` (`--test`, PASS);
`manage-20261124-130047-583-958536.log`
(`--test-gui-legacy-find --debug`, EXIT 1, 36/1/0).
Die Logs liegen ausschließlich im lokalen `.Build/logs/`.
Der vorhandene historische Gesamtgrünstand vom 23.11. wird dadurch
**nicht** für den aktuellen Branch fortgeschrieben.

**Neues Sitzungs-/Agent-Übergabeprotokoll:** Das Repository enthält nun
`Anforderungen.md`, `Entwicklungsjournal.md`,
`Arbeitsstand-und-Uebergabe.md` und eine Bootstrap-Pflicht in `AGENTS.md`.
`Test-DevelopmentContinuity.ps1` schützt strukturelle Verlinkung;
das ersetzt **nicht** die fachliche Prüfung, ob der Text noch aktuell ist.
Bei jedem künftigen autorisierten Code-Commit die betroffenen Gap-Sektionen
und Journal/Handoff nachziehen (A4 / MGMT-03).

**24.11.2026, 14:02–14:03 CET – PowerShell-Parserfix unter Windows verifiziert:**
`manage.cmd --test` wurde auf dem sauberen Checkout
`a928794c7e4072777246d959ee9dd77c129e2d89`
(Windows NT 10.0.26300, PowerShell 7.7.0) vollständig ausgeführt:
**Gesamtergebnis PASS**. Der neue AST-Parser prüfte **alle 66**
Repository-PowerShell-Skripte erfolgreich; die bewusst fehlerhafte
`$id:`-Negativfixture wurde erkannt. Die Test-Fehleraggregation,
die Dokumentations-Kontinuitätsprüfung und die 21 registrierten
nativen C++-Regressionen liefen erfolgreich. **Physischer Cross-Volume-
Move SKIP** mangels `OPENSAL_CROSS_VOLUME_TEST_DIR`. Die Plugin-Inventar-
Fixtures `alpha`, `beta` und `rogue` sind synthetisch; sie ersetzen
keine echte Plugin-Abnahme.
**Beleg:** `manage-20261124-140223-783-8d6f75.log`
(Benutzertranskript, lokal unter `.Build/logs/`, nicht in Git).
Die um 13:56 dokumentierte Parserregression ist damit **behoben**;
die allgemeinen MGMT-02-/MGMT-03-Gates und das Release bleiben
**TEILBELEGT/OFFEN beziehungsweise NO-GO**. Dokumentationscommits
nach dem getesteten SHA stellen keine neue automatische Testfreigabe dar.

**24.11.2026, 13:56 CET – Regression im neu integrierten Kontinuitätstest:**
`manage.cmd --test` auf `8a5cb99da350a494f94fdb57087c7b7f8221c336`
**FAIL** nach bestandenem Sammlertest:
`Test-DevelopmentContinuity.ps1:37` hatte den PowerShell-Parserfehler
`$id:` in einer String-Interpolation. Kein Produktfehler, die
übrigen Skript-/C++-Tests liefen in diesem Durchlauf **nicht**.
Die Korrektur `${id}:` sowie eine echte AST-Parser-Vorprüfung
aller Repository-`.ps1`-Skripte sind im Branch implementiert.
Die Vorprüfung läuft als erster `--test`-/`--test-all`-Schritt,
um weitere syntaktische Defekte übergreifend vor dem Teststart zu
finden. **Neuer Windows-Lauf auf dem Korrektur-Commit steht aus.**
Beleg: Nutzerprotokoll `manage-20261124-135629-299-b89d1f.log`.
Das ist **kein** neuer grüner Baseline-SHA.

## Arbeitsfortschritt M0 – erste Teilaufgaben (23. November 2026)

**Arbeitsbranch:** work/test-gap-m0-a0-up01 (auf bugfix/v5.2).
Dies ist **kein** neuer grüner Testreferenzstand.
Es wurden keine GUI-/Win32-Tests für diese neuen Dateien ausgeführt.

- **A0-01, statischer Originalquellenvergleich:** Das ursprüngliche
  5.0-GitHub-Commit `3945ecf7a655b2dbb0a50e189a2682e1e336352e`
  wurde unabhängig vom 5.2-Referenzstand geprüft. Alle **107**
  ursprünglichen Win32-Dialogdefinitionen in `src/lang/lang.rc`
  sind bis auf das neue UTF-8-BOM unverändert; `lang.rh` ist
  identisch. Sämtliche **89** ursprünglichen Haupt-Acceleratorzeilen
  sind erhalten, ergänzt wurde nur `Alt+Shift+F7` für die separate
  Unicode-Suche. `pictview.rc`/`.rh` sind identisch, **nicht**
  die PictView-Funktionalität. 89 Legacy-Shortcuts wurden
  dem maschinenlesbaren UI-Quellbaseline hinzugefügt und werden
  durch eine Negativregression gegen F5-Binding-Entfernung
  geschützt. **Kein** Windows-/PowerShell- oder echter
  Original-5.0-GUI-Lauf wurde dadurch ersetzt.

- **A0-01, TEILBELEGT:** Neues
  [Legacy-Verhaltens-/Konfigurationsinventar](Legacy-Verhalten-und-Konfiguration-5.2.md)
  ordnet die bestehenden F2/F3/F5/F6/F8-, Ctrl+F-, Plugin- und
  Konfigurationsbelege zu. Eine eigenständige Source-Regression
  (**Test-LegacyUiSurfaceInventory.ps1**) schützt die derzeit **107**
  expliziten Win32-Dialogressourcen und **4** Acceleratorgruppen
  sowie kritische F2–F8-/Find-Kommandos gegen unbemerkten Wegfall.
  Die Referenz ist der *grüne 5.2-Quellstand*, **nicht** eine
  Original-5.0-UI-Vergleichsmessung; A0 bleibt offen.
- **A0-02, Importpfad weiterhin blockierend:** Die vorhandenen
  Produktpfade `FindLatestConfiguration` und
  `CMainWindow::DeleteOldConfigurations` (Aufruf in
  `src/salamdr1.cpp`) können eine ältere Konfiguration nach
  ausdrücklicher Import-/Löschentscheidung entfernen.
  Der neue Canary prüft nur die vorhandene 5.2-Config0, **nicht**
  diesen Pfad. Für die Release-Gate-Vorgabe „5.0-Registry erhalten“
  ist ein separater, echter 5.0→5.2-VM-Import- und Rollbacktest
  einschließlich beider Dialogentscheidungen notwendig.

- **A0-02, neue Regression vorbereitet:** Ein echtes Registry-
  Negativtestskript `Test-LegacyConfig-Canary.ps1` erstellt ausschließlich
  eigene GUID-Schlüssel und erkennt geänderte Unicode-/Binärwerte,
  zusätzliche Schlüssel und falsche Versionsnummern.
  Der bestehende **isolierte Legacy-Find-Baseline-GUI-Test** seedet vor
  dem 5.2-Prozessstart eine synthetische 5.0-Config1 mit Version 104
  und prüft nach der GUI-Initialisierung den vollständigen
  Registry-SHA-256 sowie die neue Config0-Version 105.
  Beide neuen Prüfungen sind unter `--test` bzw. `--test-all`
  registriert, aber **auf diesem Commit noch nicht unter Windows
  ausgeführt**. Der echte 5.0-Import samt Rollback bleibt offen.

- **A0-02, TEILBELEGT:** Die nachgewiesenen 5.2-/5.0-Registry-Wurzeln,
  Versionsmigration 105, vorhandenen Quell-/GUI-Tests und die noch
  erforderlichen isolierten 5.0→5.2→5.0-Snapshots sind im
  [Legacy-Verhaltensinventar](Legacy-Verhalten-und-Konfiguration-5.2.md)
  einzeln erfasst. **Kein** echter VM-/Rollback-Test neu ausgeführt.
- **UP-01 / PKG-01, SHA-256-Gate vorbereitet:** Der neue SPL-
  Inventarreport vergleicht bei ausdrücklich bereitgestellten
  Build- und Staging-Verzeichnissen die tatsächlich enthaltenen
  SPL-Bytes per SHA-256. `-RequireMatchingPayloads` lehnt fehlende,
  zusätzliche und veränderte SPLs ab. Die synthetischen Regressionen
  simulieren `HASH_MISMATCH`, `MISSING_BUILT`, `MISSING_STAGED`
  und ein bewusst nicht ausgeliefertes Quellmodul (`NOT_SHIPPED`).
  Noch kein echter Build-/Staging-/Release-Artefaktvergleich oder
  Windows-Testlauf für diese Änderungen erfolgt.

- **UP-01, TEILBELEGT:** Die tatsächliche Solution enthält **35**
  gleichnamige Top-Level-Plugin-Projekte; unter src/plugins liegen
  **36** Plugin-Quellordner (ohne shared). **winscp** ist derzeit
  nur als Quellordner gefunden, nicht als Projekt in der Lösung.
  [Inventar und Abnahmematrix](Plugin-Inventar-und-Testmatrix-5.2.md),
  machine-readable **plugin-source-inventory-baseline.json**,
  read-only Build-/Staging-Report und **12 Operationsslots je Modul**
  wurden ergänzt. **Test-PluginCoverageInventory.ps1** prüft
  Quellvollständigkeit, falsche SPL-Pfade, doppelte Solution-Plugins
  und den Report mit test-eigenen Dateien. Build-/Releasebestand und
  reale Plugin-Funktionen sind **noch nicht nachgewiesen**.
- Beide neuen PowerShell-Regressionsskripte sind für
  **manage.cmd --test / --test-all** registriert. Sie sind statisch
  integriert, **noch nicht tatsächlich unter Windows ausgeführt**.

- **MGMT-03, VORBEREITET:** Der neue
  **Test-TestGapTracker.ps1** gleicht alle **35** stabilen IDs mit
  **test-gap-ids-baseline.json** ab. Er fordert weiterhin die zentralen
  Links in AGENTS.md und README.md, weist simuliert entfernte IDs und
  unbelegte [x]-Abschlüsse zurück. Er läuft künftig in manage.cmd --test;
  ein echter Windows-Lauf steht noch aus.

**A0-02 – Registry-Canary-Negativregression (23.11.2026, vorbereitet):**
Eine ergänzte synthetische Probe prüft Wertnamen mit `|` und Zeilenumbruch,
damit die SHA-256-Snapshot-Serialisierung keine mehrdeutigen Datensätze
bildet. Eine zweite Probe verwirft `REG_SZ "105"` als Ersatz für die
erforderliche `REG_DWORD`-Versionsnummer 105. Der Canary kodiert nun
Registry-Schlüssel- und Wertnamen vor der Digest-Bildung als UTF-16-Base64
und prüft den Registry-Werttyp explizit.
Teständerung `7378e5e70abb979d9f7197efe40c6dd6f28a0f6b`;
Implementierung `10dca3ebc467ca3ede0c56edd6f52f1a7fdfd8bb`; Testpfad-Korrektur `84658d99776aa05597181f3eed08ad6e0be36169`.
**Statisch geprüft, Windows-/PowerShell-Ausführung ausstehend; kein PASS.**
Die reale 5.0-Import-/Löschsemantik bleibt ausdrücklich offen.

**UP-01 / PKG-01 – Integritäts-Gate verschärft (23.11.2026,
VORBEREITET):** Der Aufruf `Invoke-PluginCoverageInventory.ps1
-RequireMatchingPayloads` lehnt jetzt den vorher zulässigen
Fehlzustand "Build und Stage enthalten keine SPL-Datei" ab.
Mit `-RequiredShippedModules` ist ein namentlicher Mindestbestand
prüfbar; fehlende oder falsch typisierte Namen werden nicht stillschweigend
als `NOT_SHIPPED` akzeptiert. Synthetische Negativfälle liegen in
`Test-PluginCoverageInventory.ps1` vor. Der Paketaufbau vergleicht
vor Erstellung der Debug-/Release-Archive und Installer die Byte-Hashes
und verlangt derzeit die fünf über vorhandene Exporttests belegten
Pflichtmodule 7zip, checksum, filecomp, renamer und pictview.
**Nicht belegt:** vollständige Produkt-/Plugin-Positivliste, reale
Windows-Ausführung, alle 35 Moduloperationen, finale Paketinhaltstests.
Code: `fbf71c384b0156d1871e3ad0534b0ec355e15211`,
`0588db60722e7e3479b21793c7d1b0b01f63a353`,
`b708605f045c5d10ef67f7e5fa233a674597b4be`,
`c979aa6a505ae479c8d341abc248c5f758c37788`.

**BUILD-02 / MGMT-03 – Windows-CI-Vorprüfung vorbereitet:**
Das branchgebundene Workflow-Skript
`.github/workflows/pr-test-gap-preflight.yml`
(Commit `ea23d4aefe03db8d85aaa0643a563ee9ca521dc5`)
führt sechs isolierte Quell-/Registry-Vertragstests auf einem
Windows-Runner aus. **Zum Zeitpunkt dieser Eintragung existiert
kein abrufbarer Erfolgsnachweis für den aktuellen Commit.**
Die vollständigen Visual-Studio-2026-, GUI-, Plugin-Host- und
VM-Abnahmeprüfungen werden hierdurch nicht ersetzt.

**UP-01 – Projektdatei-Existenz geprüft:** Ein weiteres
synthetisches Fehlerszenario verhindert, dass ein verwaister
`.sln`-Eintrag ohne Haupt-`.vcxproj` als tatsächlich
vorhandenes Projekt gezählt wird. Test-Commit
`9d468b454943ea329756a87b95335d3a88f3ff11`, Quellkorrektur
`4de015f7117f92fa5da9d1bf8f75753cb17da5fb`.
Alle 35 erwarteten Hauptprojektdateien wurden in der GitHub-Quelle
einzeln gefunden. **Nur statische Dateiexistenz, noch keine Windows-
PowerShell-/MSBuild-Ausführung auf diesem Stand.**

**BUILD-01 – Vierfach-Solution-Abdeckung statisch gesichert:**
Im aktuellen `src/vcxproj/salamand.sln` enthalten alle 35
Plugin-Hauptprojekte jeweils eine zugehörige `Build.0`-Zuordnung
für `Debug|Win32`, `Debug|x64`, `Release|Win32` und
`Release|x64` (zusammen 140 geprüfte Deklarationen).
`Test-VS2026-ProjectMetadata.ps1` prüft nun zusätzlich diesen
Vertrag gegen die versionierte Liste und simuliert fehlende und
falsch umgeleitete Build-Zuordnungen. Commit
`6975cd5aee072efbfe2e3d39163750837d3434df`;
Windows-CI-Einbindung `17fe8218ade9f3c35ce42898e515dbf4e163b0ee`.
Dies ist **ausschließlich ein statischer Lösungs-/Konfigurationsnachweis**,
kein absolvierter MSBuild-Vierfach-Build; BUILD-01 bleibt offen.

**UP-02 – SDK-Exportdeklarationen erweitert (VORBEREITET):**
35/35 Solution-Module besitzen eine .def-Quellbeschreibung;
für diskmap liegt sie in einem Unterordner. Der erweiterte
DEF-Parser und die Regressionen wurden in den bestehenden
Pakettest sowie die Windows-Vorprüfung aufgenommen.
Test 8b48d958b3682626644812d7b83e1b55293f9c84,
Parser ccf191b441d9895f317e85c004e983420cf18248,
Binärtest-Wiederverwendung
0d66e9c28822dccce96921ee11929ae11b54485f.
**Quellprüfung, noch keine ausgeführte Windows-/PE-Verifikation
für sämtliche Module.** SDK-Binärkompatibilität, alle
Unicode-/Langpfad-Operationen und Plugin-Host-Interaktionen bleiben offen.

**UP-02 – Binär-ABI-Test über alle tatsächlich gebauten Module
erweitert (VORBEREITET):** Die x64-dumpbin-Prüfung nutzt jetzt
Get-SalamanderPluginInventory statt einer auf fünf Module begrenzten
Schleife. Alle gefundenen BuiltPath-SPLs werden gegen die jeweiligen
.def-Namen und PE-Exporttabellen geprüft; die fünf bisherigen
Pflichtmodule bleiben zwingend und nicht deklarierte Build-SPLs werden
abgewiesen. Quell-Regressionsschutz a1dac23561d6bf7e4f618700f09191dfda2241e0,
Implementierung ad50f2a85924f9386da3b86fda6e6e2211300bd5.
Alle 35 .def-Dateien wurden separat aus GitHub gelesen und enthielten
die beiden deklarierten SDK-Exportnamen.
**Keine ausgeführte x64-Binärprüfung und kein Unicode-/Langpfad-
End-to-End-Nachweis auf diesem HEAD.**

**Neue lokale Ausführungsevidenz (23.11.2026, 20:58–21:12 Uhr):**
Der bereitgestellte PowerShell-Transkriptlauf
`manage.cmd --build-clean --test-all` meldet auf dem **getesteten**
Commit `2be91b27032a2f4cb4619a606b42b0af7c8ea6c1`
einen sauberen Git-Working-Tree und den vollständigen Abschluss
`Alle angeforderten Schritte erfolgreich abgeschlossen.`.
Der Text nennt `D:\Build\OpenSal\logs\manage-20261123-205829-483-5c3b7f.log`
als lokales Originalprotokoll. Im bereitgestellten Text erscheinen für
beide Konfigurationen **je 35** verschiedene Solution-`.spl`-Buildausgaben
(Debug x64 und Release x64). Ebenso meldet er den erfolgreichen nativen
und GUI-Testabschluss einschließlich Legacy Find, Unicode, Langpfaden,
F2/F5/F6/F8 und PictView/WIC. Die damalige ABI-Prüfung prüfte nur
die fünf vordefinierten Module. Die späteren PR-Änderungen sind
**nicht durch diesen Lauf gedeckt**; eine finale Paketierung (`--setup`)
war **nicht** Teil des Befehls. Daher bleiben alle separaten
Abnahme- und Clean-VM-Gates offen.

**PKG-01 – korrigierte Quelltools und vollständiges Solution-Gate
(nicht auf HEAD getestet):** Ein statisch entdeckter
PowerShell-Quellbruch in `Plugin-CoverageInventory.ps1` und
`Invoke-PluginCoverageInventory.ps1` wurde aus der letzten
unbeschädigten Fassung rekonstruiert. Der zentrale
`Test-Package-Helpers.ps1` überprüft nun deren Parser-Syntax
vor weiterer Prüfung. `-RequireSolutionPluginPayloads` sichert
in der Paketpipeline zusätzlich zu SHA-256 die Existenz aller
Solution-Projekt-SPLs in Build und Stage und verwirft
nicht deklarierte gestagte Module. Neu: Negativtests für auf
beiden Seiten fehlende Solution-SPLs und unbekannte Stage-SPLs.
Neu: Auch tatsächlich gebaute Plugin-Hilfsdateien mit den Erweiterungen
`.dll`, `.exe`, `.slg` und `.chm` werden im strengen Release-Gate
auf identischen Inhalt im Stage-Baum geprüft. Regressionsfälle
verwerfen eine fehlende Sprachdatei und eine manipulierte Hilfs-DLL.
Die ABI-Prüfung fordert nun außerdem **alle** Solution-Plugin-SPLs
im Build, bevor sie die vorhandenen x64-PE-Exporte inspiziert.
Nicht gelöst: weitere Repository-Ressourcen und Release-Hinweise,
Signaturen, vollständige externe Runtime-Abhängigkeiten, die
Setup-/Uninstall-Clean-VM-Abnahme sowie die Ausführung dieser Änderungen.
Diese Prüfungen sind trotz grünem Alt-SHA **nicht als PASS markiert**.

Wesentliche neue Commits: Syntax- und Strukturreparatur
`083a601343202051b49bd3495a8f9a84b4b497a4` /
`3d15d19fd70be62dbbf6255c56562c7f79976a8c`;
Pflichtmodule `1261104ee210f51609d972c8dbca3c65965c741f`,
Paketintegration `680615300407e66b58fb970819511bbba2d1d314`,
Sidecar-Abgleich `46b18fe15004ec24b2f58506382ce6e8167a7872`,
ABI-Vollständigkeit `6a17556190825538faacd2ed22e202acdfd7c651`.

**PKG-01 – versteckte Plugin-Payloads (zusätzlicher Negativfall):**
Der SPL-Scanner und der Vergleich der gebauten Laufzeitbegleitdateien
berücksichtigen jetzt ausdrücklich auch Dateien mit `Hidden`-Attribut
(`Get-ChildItem -Force`). Ein synthetisch verstecktes Stage-SPL
muss in der Inventarliste als `MISSING_BUILT` erscheinen und darf
nicht unbemerkt den Paketvertrag passieren. Die Registry-Canary-
Skripte wurden ebenfalls in die zentrale PowerShell-Parserprüfung
aufgenommen. **Nur statisch kontrolliert, Windows-Test ausstehend.**
Commits `3033bf3eabbe380137fcb773ffcd579f88f2f2e4`,
`b334aed524174a39110da4146408744871faa740`,
`9489c961c9152cc3a6fad80a51b5554f611cae98`.

**UP-01 / PKG-01 – tatsächlicher kombinierter Windows-Testlauf
(23.11.2026, FAIL in synthetischem Fixture):**
`manage.cmd --build-clean --test-all --setup` wurde auf sauberem
Checkout `2be48a3b7cc0a5817d0706433c885dc3b21d1125`
ausgeführt. Log:
`D:\Build\OpenSal\logs\manage-20261123-222759-498-541926.log`,
22:27:59 bis 22:30:48 Uhr. Debug und Release x64 wurden
sauber gebaut, alle 35 Solution-Plugin-SPLs je Konfiguration
ausgegeben und die HTML-Hilfe kompiliert. Die vor dem
Fehler ausgeführten statischen und Managementtests meldeten PASS,
unter anderem VS2026-Projekt-/Matrixverträge, PictView-WIC-Quellvertrag,
Legacy-Dialog-/Find-Verträge und die 35 inventarisierten Gap-IDs.
Der Ablauf brach in
`tools/release/tests/Test-PluginCoverageInventory.ps1:214`
ab: `File.WriteAllBytes` konnte die synthetische
`build\plugins\beta\beta.spl` nicht erstellen, weil das
Elternverzeichnis im Test-Fixture fehlte. Kein produktiver
Build- oder Unicode-/Viewer-Fehler. **Nachfolgende Tests,
reale Paketierung und Setup liefen nicht; kein Gesamt-PASS.**

Der Test initialisiert nun auch das leere
`build\plugins\beta`-Verzeichnis vor seinem bewusst
zunächst fehlenden Beta-Binärtest (Fix
`73323465111158e88be31524821e2a0db20f9e9b`).
Die beiden auf PowerShell 7.7 als veraltet gemeldeten
`Export-Csv -NoTypeInformation`-Schalter wurden entfernt
(Fix `844236183e2906b80640c6b4287a8085bd09a856`).
**Fix noch nicht auf Windows ausgeführt.**
Vor der nächsten vollständigen Abnahme zuerst isoliert
`Test-PluginCoverageInventory.ps1` und anschließend
`manage.cmd --build-clean --test-all --setup` auf demselben
neuen Source-SHA ausführen.

**Nächster Schritt nach dieser Quellbasis:** Neue Regressionen auf
Windows ausführen; anschließend tatsächliche Built-/Staged-/Shipped-SPLs
auf dem **selben** Commit nachweisen, pro Modul Funktionen
und Unicode-/Langpfad-Grenzen klassifizieren.

## 3. A0 – Unveränderte Originalfunktionen und Benutzeroberfläche

### [ ] A0-01 – Vollständiger Legacy-Verhaltenskatalog (**P0**, TEILBELEGT)
- **24.11.2026:** About-Buildinformation in `src/logo.cpp` ergänzt, ursprüngliche Dialog-Ressource unverändert. Native Formatprüfung am 24.11. 12:59 PASS; echte GUI-/Original-UI-Parität weiter offen.

- **Lücke:** Bisherige GUI-Szenarien beweisen nicht die Funktionsparität aller
  Menüs, Kommandos, Einstellungen, Tastenkombinationen und Plugins.
- **Arbeit:** Version 5.0/Altverhalten gegen 5.2 inventarisieren;
  Charakterisierungstests je tatsächlich vorhandener Funktion; UI-Struktur,
  Dialogtexte und Tastaturbedienung nicht stillschweigend ändern.
- **Abnahme:** Jede relevante Alt-Funktion ist als erhalten und geprüft
  dokumentiert oder mit konkretem Defekt/Entscheidungsbedarf vermerkt.
  Beleg: Testfälle, Screenshots/Bedienprotokolle, Ausgangs- und Zielversion.
- **Quellen:** `AGENTS.md` A0, `tools/release/tests/`,
  `docs/pictview-wic-migration.md`. **Abhängig von:** A7-06.

**A0-02 – kombinierter Windows-Lauf (23.11.2026, neue Test-Failure):**
Der Nutzer hat `manage.cmd --build-clean --test-all --setup` auf
sauberem Source-SHA
`3b79ffc65b836bf74fb7bfe7003a2766233e41f3`
ausgeführt. Lokales Protokoll:
`D:\Build\OpenSal\logs\manage-20261123-223541-643-67dd32.log`
(22:35:41–22:38:37 Uhr). Debug/Release x64, HTML-Hilfe,
die zuvor fehlgeschlagene komplette Plugin-Inventarregression
einschließlich leerem/fehlendem Modul und SHA-256-Negativfällen,
Plugin-Binärinventar und Loader-Quellverträge wurden erfolgreich
abgeschlossen. Danach brach der Lauf in
`LegacyConfig-Canary.ps1:108` beim ersten
`Get-IsolatedLegacyConfigDigest` mit PowerShell-Parameterbindung
`Cannot bind argument to parameter 'Entries' because it is an empty collection`
ab. Die Hilfsfunktion `Add-RegistryCanarySnapshot` verwendete
`[Parameter(Mandatory)]` auf einer zunächst
**absichtlich leeren** `List[string]`; die Listenbefüllung wurde
noch gar nicht erreicht. **Kein produktiver Registry- oder
GUI-Fehler belegt; nachfolgende Tests und Setup nicht erreicht.**

Korrektur auf **demselben Branch `bugfix/v5.2`**:
`[AllowEmptyCollection()]` am obligatorischen
`Entries`-Parameter (Commit
`6f632433db959006ea7d693a385e7e5b34e41622`).
Ein zusätzlicher Negativ-/Positivkontrakt auf einer ausschließlich
GUID-eigenen `HKCU\\Software\\Open Salamander\\CodexTests`-
Fixture prüft den anfänglich leeren Sammler, den ersten
kanonischen KEY-Datensatz und die stabile SHA-256-Prüfsumme
(Commit `1ca107cc36c70d582768b6fb2acb27d0325fc3ee`).
**Die neuen Änderungen sind noch nicht auf Windows ausgeführt.**
Zuerst isoliert
`pwsh -NoProfile -File .\\tools\\release\\tests\\Test-LegacyConfig-Canary.ps1`
prüfen, danach den kompletten `--build-clean --test-all --setup`-
Lauf auf demselben aktuellen SHA wiederholen. A0-02 und
die vollständige Registry-/Upgrade-Abnahme bleiben offen.

**A0-02 – PowerShell-Parserregression nach Canary-Erweiterung
(23.11.2026, behoben im Quelltext):**
Beim gezielten Windows-Aufruf des Registry-Canary-Tests auf
`7b4d80ac63c89c2e7ec9cc8dbb6b1564db77d9d0`
meldete PowerShell einen `ParserError` in
`Test-LegacyConfig-Canary.ps1:50`. Der zuvor eingefügte
Regressionstest hatte versehentlich den Quelltext beschädigt:
Die Regex `'^[0-9A-F]{64}$'` wurde abgeschnitten und
nachfolgende Skriptabschnitte dupliziert. **Dieser Parserfehler
entstand vor jedem Registry-Test; keine neue Aussage über die
Produktfunktion.** Der Test wurde aus dem letzten intakten
194-Zeilen-Stand rekonstruiert und um einen kontrollierten
20-Zeilen-Test ergänzt. Der komplette Originalinhalt
bleibt abgesehen von der gezielten Einfügung unverändert.
Reparatur-Commit `d4cc3d5bfbb50d646af2dbe9e27e808945bb3895`.
Die Datei ist jetzt 214 Zeilen lang; Regex,
Setup des GUID-eigenen `Config1` und Cleanup sind
quellseitig geprüft. Der Parser wurde in dieser
Ausführungsumgebung **nicht tatsächlich ausgeführt**.
Nächste Prüfung: PowerShell-AST-Parser, dann isolierter
`Test-LegacyConfig-Canary.ps1`. A0-02 bleibt offen.

### [ ] A0-02 – Einstellungen, Upgrade und persistierte Daten (**P1**, TEILBELEGT)
- **Lücke:** Registry-/Konfigurationsregressionen existieren; komplette
  5.0→5.2→5.0-Kompatibilität ist nicht als End-to-End-Matrix belegt.
- **Fälle:** Gesicherte 5.0-Konfiguration; Unicode-Historien/Pfade;
  Suchfilter; Plugin-Einstellungen; Abbruch der Migration; Wiederstart und
  Rollback; 5.0-Daten bleiben unverändert.
- **Abnahme:** Alle definierten Einstellungen identisch oder verlustfrei
  migriert, keine alte Registry überschrieben; VM-Nachweis je Scenario.
- **Quellen:** `tools/release/Release-5.2-Gates.md`, A5-04.

## 4. A1/A2 – Unicode und lange Pfade im gesamten Produkt

### [ ] UP-01 – Vollständiges Produktions-/Plugin-Inventar (**P0**, TEILBELEGT)
- **Lücke:** Keine lückenlose Prüfung jedes tatsächlich ausgelieferten
  Plugins und jedes UTF-16-/ANSI-Übergangs.
- **Arbeit:** Aus Solution/Projektdateien, gebauter `.spl`-Liste und
  Release-Manifest für **jedes** Modul Rolle, SDK-Schnittstelle,
  Dateisystem-/Archiv-/Viewer-Funktionen und benötigte Matrix erfassen;
  Quellverzeichnis allein ist kein Beweis für ein ausgeliefertes Plugin.
- **Inventar zu klassifizieren:** `7zip, automation, checksum, checkver,
  dbviewer, demomenu, demoplug, demoview, diskmap, filecomp, folders, ftp,
  ieviewer, mmviewer, nethood, pak, peviewer, pictview, portables, regedt,
  renamer, splitcbn, tar, unarj, uncab, unchm, undelete, unfat, uniso,
  unlha, unmime, unole, unrar, winscp, wmobile, zip`; `shared` ist SDK,
  keine eigenständige auszuliefernde `.spl`.
- **Abnahme:** Versionierte Matrix `Modul → Operationen → Fälle → Testergebnis
  → SHA/Log`; jedes ausgelieferte Modul erscheint darin, nicht anwendbare
  Operationen begründet. Kein reiner Export-/ABI-Test als End-to-End-PASS.

### [ ] UP-02 – Unicode-Plugin-/SDK-Grenzen (**P0**, BLOCKIERT/TEILBELEGT)
- **Lücke:** Legacy-SDK kann ANSI-Zeiger verwenden; strenger ACP-Roundtrip
  vermeidet Datenverlust, stellt aber noch keine vollständige UTF-16-Funktion
  für alle Plugins bereit. ABI darf nicht stillschweigend geändert werden.
- **Fälle:** Nicht-ACP-Namen und Best-Fit-Kollisionen in List/Fokus/Öffnen/
  Copy/Move/Rename/Delete; valide Unicode-Namen durch Plugin-Roundtrips,
  auch bei gleichnamigen ANSI-Aliasen.
- **Abnahme:** Eindeutige UTF-16-Identität über den gesamten Aufrufweg oder
  nachweislich sichere, explizite Ablehnung **als noch offene A1-Abweichung**;
  für vollständige A1-Erfüllung ist eine kompatible Produktlösung plus
  positiver End-to-End-Test nötig. ABI- und Regressionstests ergänzen.
- **Quellen:** `src/plugins/shared/`, `docs/pictview-wic-migration.md`.

### [ ] UP-03 – Archive und externe/virtuelle Dateisysteme (**P0**, OFFEN)
- **24.11.2026:** Benutzerauftrag aus Chat 09 zu einem funktionierenden **UnRAR-Ersatz** bleibt bestehen und ist durch die bisherigen WIC-/Viewer-Fixes weder ersetzt noch als erfüllt belegt.

- **Fälle:** Für jedes betroffene Archiv-/VFS-Plugin Dateien mit Unicode/
  langen Pfaden auflisten, öffnen, packen, entpacken, umbenennen und löschen;
  verschachtelte Archivpfade, Kollisionen, beschädigte Archive, Dateirechte,
  Cancel und Quellwechsel prüfen; Remote-Plugins zusätzlich Offline/Timeout.
- **Abnahme:** Byte-/Namensgleichheit beim Roundtrip, keine Trunkierung,
  keine Fehlzuordnung, keine ungefragte Zielüberschreibung; pro Plugin und
  Operation unabhängige reproduzierbare Protokolle. **Abhängig von:** UP-01.

**Neuer Produktcode auf `bugfix/v5.2` (23.11.2026, noch nicht
Windows-getestet):** Eine einzelne gewöhnliche Unicode-Datei kann
bei F6 nach dem nachgewiesenen Win32-Fehler
`ERROR_NOT_SAME_DEVICE` jetzt über die bereits vorhandene
UTF-16-Zwischenablage-Transaktion (`TryTransferUnicodeClipboardFiles`)
bewegt werden. Diese prüft eindeutige Dateihandles und Byte-
Kopierveröffentlichung ohne Zielüberschreibung, bevor die ursprüngliche
Datei gelöscht wird. Bei einer fehlgeschlagenen Quelllöschung
bleibt die Zielkopie absichtlich erhalten und wird dem Benutzer
als **möglicher Teiltransfer** gemeldet. Für einen synchronen Aufruf
gelten weiterhin höchstens 16 MiB, um den GUI-Thread nicht
unbegrenzt zu blockieren. Größere volumeübergreifende F6-Dateien,
mehrere Dateien/Verzeichnisse sowie der vollständige Worker-
/Overwrite-/ACL-/ADS-Vertrag **sind nicht fertig**; für diese
Fälle ist der asynchrone UTF-16-Move-Worker erforderlich.
Produkt-Commits:
`9983c51b8c7c9cce2a8a8fdceced7e05e01207bc`,
`a964a9086f750b8d2499c0a22bb4d63b0d8d1b2f`.

Ein zusätzlicher nativer Win32-Regressionstest in
`tools/tests/long_path_io.cpp` (Commit
`f791a04a289e73e03ebae81ec2e1d35b88d819f4`)
wird nur ausgeführt, wenn
`OPENSAL_CROSS_VOLUME_TEST_DIR` ausdrücklich auf einen
**vorhandenen, eigens für Tests bereitgestellten Ordner auf
einem zweiten Volume** zeigt. Er verlangt echten Device-
Unterschied und prüft originalgetreue Bytes, erfolgreiche
Quellentfernung sowie Zielkollision ohne Überschreibung.
Fehlt das zweite Volume, meldet er `SKIP`, nicht `PASS`.
**Ausführung unter Windows noch offen.**

**Weitere C++-Implementierung (23.11.2026, noch ohne Windows-Build):**
`TryUnicodeSingleDirectoryCopy` führt einen eindeutig über die
UTF-16-Verzeichnisliste identifizierten Einzelordner durch die
bereits vorhandene stagingbasierte `TryTransferUnicodeClipboardFiles`-
Routine. Nur Unicode-/Langpfadfälle werden umgeleitet; gewöhnliche
kurze ANSI-Verzeichnisoperationen behalten den ursprünglichen Dialog
und die vollständige Altlogik. Der synchrone Weg bleibt auf
16 MiB Dateiinhalte und maximal 1.024 Verzeichniseinträge begrenzt;
nicht veröffentlichte Temp-Verzeichnisse müssen bei Fehlern
gegebenenfalls geprüft werden. Ein eindeutig auflösbares,
im ANSI-Panel nicht exakt darstellbares Unicode-Verzeichnis kann
nun auch per F6 auf demselben Volume verschoben werden; die
individuelle W-Verifikation der Identität bleibt erforderlich.
GUI-Regression: der bestehende isolierte
`-ShortUnicodeDirectoryRenameOnly`-Fall führt jetzt F2,
native F5-Verzeichniskopie und F6-Verzeichnisverschiebung aus.
Produkt-Commit `070f480d5370ff68711693d13882a4207aa69a4a`.

Bei bis zu 16 vorab geprüften regulären Dateien und insgesamt
maximal 16 MiB kann Unicode-F6 im Mehrfachtransfer den
Copy-and-Delete-Fallback für verschiedene Volumes verwenden,
mit expliziter Teiltransferdiagnose. Ein optionaler echter
Zwei-Volume-Nativtest prüft zwei Dateien, identische Bytes und
die vollständige Batch-Zielkollisionsprüfung.
Produkt-Commit `3526dfc7d44b72cb2da5fd3932a4df24a7dcf503`,
Test-Commit `e9cc1610c72861313495026cc401fa5a8f82cd8e`.

**Seither erweitert:** Für größere reguläre Unicode-Einzeldateien und
Mehrfachauswahlen ist der bestehende Hintergrund-Worker jetzt
verdrahtet (siehe folgenden Nachweisblock). Die vorherige
16-MiB-Grenze gilt weiterhin für synchrone Transfers und die
Verzeichnisbaum-Kopierhilfe, nicht für die neuen Workerpfade.
**Offen bleiben** große Verzeichnisbäume, alle erweiterten
Masken-/Advanced-, ACL-/EFS-/ADS-/UNC-Grenzfälle und die
Windows-Build-/GUI-Ausführung. UP-04 bleibt TEILBELEGT.

**UP-04 – neue asynchrone UTF-16-Kernimplementierung (24.11.2026;
NICHT UNTER WINDOWS VERIFIZIERT):**
Der bereits vorhandene Salamander-Copy-Worker (`ocCopyFile`,
`DoCopyFile`, `StartProgressDialog`) wird nun für
**laufwerksübergreifendes F6 bei großen regulären Dateien**
weiterverwendet. Bei `ERROR_NOT_SAME_DEVICE` bleibt der
Same-Volume-Rename unverändert, während Dateien über 16 MiB
die Hintergrundkopie mit vorhandenem Fortschritt, Pause,
Abbruch und Fehlerdialog verwenden. Für F6 markiert
`OPFL_UTF16_MOVE_AFTER_COPY` einen expliziten Copy-then-Delete-
Vertrag; der Worker prüft `!Error`, `!skipped`,
`!CancelWorker`, den Pause-/Resume-Zustand und die
tatsächlich geöffneten Unicode-Dateiidentitäten von **Quelle
und Ziel**. `TryCompleteUnicodeMoveAfterCopy` öffnet die
Zieldatei erneut, prüft die bekannte Volume-/File-ID und
Dateigröße und entfernt die Originalquelle ausschließlich
über `TryDeleteUnicodeFileWithIdentity`. Misslingt die
Quellentfernung, verbleibt die Kopie und der Benutzer
erhält eine explizite Teiltransferwarnung; es wird nicht
blind zurückgerollt oder eine fremde Datei gelöscht.
Der erste schreibende Zielzugriff verwendet `CREATE_NEW`,
um eine nach dem GUI-Preflight von Dritten angelegte
Zieldatei nicht zu überschreiben.

**Mehrfachauswahlen:** `PrepareUnicodeFileCopy` kann
mehrere unabhängig gespeicherte UTF-16-Dateipfade in
demselben `COperations`-Skript vorbereiten. Die Größen,
Dateizahl und Warteschlangeninformationen werden konsistent
verwaltet. Auswahlgrößen über 16 Dateien bzw. 16 MiB
nutzen den bestehenden Worker statt einer synchronen
GUI-Kopie; kleine Dateien behalten den bisherigen Ablauf.
Ein erweiterter GUI-Regressionstest prüft eine 17-MiB-
Zweitdatei mit SHA-256, Fortschrittsabschluss und F5-/F6-
Quell-/Zielintegrität. Ein nativer Identitätstest simuliert
das Ersetzen von Quell- und Zieldatei zwischen Kopie und
Löschung. Statische Quellverträge sichern das Skip-/Cancel-,
Datei-ID- und `CREATE_NEW`-Verhalten.

**Keine abgeschlossene Abnahme:** Die neuen Quellpfade
wurden statisch auf Symbolreferenzen und Klammerstruktur
geprüft, aber nicht mit MSVC gebaut. Der große Cross-Volume-
F6-Fall benötigt einen tatsächlichen Zwei-Volume-GUI-Test
auf Windows; das derzeitige 17-MiB-GUI-Batchszenario
nutzt zwei Verzeichnisse auf demselben Volume. Noch
ungeklärt sind erweiterte Copy-Masks/Advanced-Regeln,
allgemeine Verzeichnisbaum-Operationen, gemischte Ordner-/
Dateiauswahlen, tatsächlicher ADS-/ACL-/EFS-Support und
Abbruch-/Fehlerpfade auf realen Volumes. **Keine
Freigabe und kein formaler Abschluss von UP-04.**

**Sicherheitsnachtrag zum asynchronen F6 (24.11.2026; nicht
Windows-verifiziert):** Die Dateiauswahl wird vor dem modalen
Bestätigungsdialog über `TryReadUnicodeRegularFileIdentity`
an die Win32-Volume-/File-ID gebunden. Dieselbe Identität
gilt für Einzeldateien und Mehrfachauswahlen, für den
synchronen Handle-Rename, für den Copy-and-Delete-
Zwischenablagepfad sowie für die erste W-Dateiöffnung
des Hintergrundworkers. Eine nach Dialogöffnung unter
identischem Namen neu angelegte Datei darf nicht
kopiert oder gelöscht werden.
Beim Cross-Volume-F6 muss der Worker außerdem
alle Alternate Data Streams berücksichtigen
(`ignoreADS = FALSE` für Moves), darf während des
Kopierens keine Fremdschreibzugriffe auf die Quelle
zulassen und darf einen von Dritten entfernten oder
ausgetauschten Zielpfad nicht bei einem Retry
neu erzeugen/überschreiben. Nach dem regulären
Worker-Copy werden Quell- und Ziel-Datei über
geöffnete W-Handles gegen Write/Delete gesperrt,
IDs und Größen verglichen und die primären
Dateiinhalte blockweise und bytegenau geprüft.
Erst danach wird die Originalquelle durch den
**selben** Quellhandle per `FileDispositionInfo`
zur Löschung markiert. Pause/Cancel wird auch während
der Nachprüfung berücksichtigt. Bei Abweichung
(`ERROR_FILE_INVALID`/`ERROR_CRC`) bleibt die
Quelle erhalten, der Benutzer wird über mögliche
Teilkopien informiert. Erweiterte native
Regressionen prüfen identische Ersatznamen/-bytes
und abweichende Bytes trotz gleicher IDs/Größen.
Die Nachprüfung kostet zusätzlich ungefähr
einen vollständigen Lesevorgang auf Quelle und
Ziel; dies ist eine bewusste Datenintegritäts-
abwägung. Die ADS-Kopie selbst folgt dem
bestehenden Worker-Vertrag.
Zusätzlich prüft der native
`tools/tests/worker_copy_io.cpp`-Test die neue
F6-`CREATE_NEW`-Zielerzeugung, die Schreibsperre der
Quell-Handleöffnung, die Ablehnung von Zielpfad-
Ersetzungen und die sichere Ablehnung von
Metadatenänderungen an fremden Zieldateien.
Auch diese Regression muss auf Windows tatsächlich
kompiliert und ausgeführt werden.

**Ein vollständiger Build, alle neuen GUI-Tests
und das echte zweite Volume sind noch ausstehend.**

### [ ] UP-04 – Kopieren/Bewegen über Volume- und Worker-Grenzen (**P0**, TEILBELEGT)
- **24.11.2026, SHA `9f524264`, 14:32–14:34:** `--build-delta --test` unter Windows PASS; nativer UTF-16-/8.3-Alias-Positivtest PASS und Worker-/Transfer-Isolationstests PASS. Die GUI-Elternverzeichnisprüfungen konnten wegen laufender Salamander-Instanz nicht beginnen. Echte F5/F6-GUI- und Cross-Volume-/Worker-End-to-End-Abnahme bleiben offen, kein Closure.
- **24.11.2026:** Release-Multiselect-GUI mit 17-MiB-Dateien und F5/F6 PASS; native F6-Identitäts-/Byteprüfungen PASS. Echte Cross-Volume-Migration in `long_path_io.cpp` mangels konfiguriertem Testvolume SKIP; kein Abschluss.

- **Lücke:** F5/F6 mit 263 UTF-16-Einheiten und >17 MiB Same-Volume-Move
  bestanden; das beweist **keinen** Cross-Volume-Move großer Dateien.
- **Fälle:** F5/F6 0/1/16/17/32/33 MiB, gleiches/anderes Volume,
  Unicode/Longpath, ADS soweit NTFS, gesperrte oder währenddessen
  veränderte Quelle, Abbruch, Zielkollision und Wiederaufnahme.
- **Abnahme:** SHA-256 von Quelle/Ziel; bei verweigerter Aktion bleiben
  Original und fremde Ziele unverändert; kein permanenter Datenverlust,
  keine unfertigen Stagingdateien. Cross-Volume-Fall ist bis zum
  Produktnachweis **OFFEN**, nicht durch Same-Volume-F6 abgedeckt.
- **Quellen:** `src/fileswn8.cpp`, `src/common/win32_unicode_file_ops.h`,
  `tools/tests/long_path_io.cpp`,
  `tools/release/tests/Test-SalamanderGui-LongPaths.ps1`.

### [ ] UP-05 – UNC/SMB, Reparse Points und Pfadnormalisierung (**P1**, TEILBELEGT)
- **Fälle:** Echte erreichbare UNC-Freigabe, `\\?\UNC`, Netzwerkfehler,
  Junction-/Symlink-Zyklen, Rechte, Pfadwechsel während Operation,
  ungültige Device-Namespaces und relative Dot-Segmente.
- **Abnahme:** Verlustfreie Pfadidentität, kein Ausbrechen aus test-eigenen
  Wurzeln, bounded recursion, korrekte Fehlermeldungen/kein Hängen;
  echter SMB-Nachweis getrennt vom rein synthetischen UNC-Pfadtest.

**F8-Hauptprogrammkorrektur (23.11.2026, Windows-Test ausstehend):**
Eindeutig aufgelöste Unicode-Dateien folgen nun auch im
nativen Dateipfad der bestehenden Umschaltregel für
Papierkorb versus permanentes Löschen. Der permanente
W-F8-Pfad merkt sich vor dem Bestätigungsdialog die
Win32-Dateiidentität und führt die Löschung über
`TryDeleteUnicodeFileWithIdentity` mit unmittelbar vor
`FileDispositionInfo` geprüfter Volume-/File-ID durch.
Die ursprüngliche Quelle darf zwischen Bestätigung und
Ausführung nicht unter gleichem Namen ausgetauscht werden.
Ein nativer Regressionstest verschiebt die ursprüngliche
Datei, setzt einen anderen Inode unter denselben UTF-16-Namen
und verlangt `ERROR_FILE_INVALID` statt Löschung.
Ein eigener GUID-isolierter GUI-Test
`-ShortUnicodePermanentDeleteOnly` ist in
`manage.cmd --test-all` für Debug/Release x64 aufgenommen;
bei aktiver Recycle-Policy prüft er zusätzlich das explizite
Shift+F8-Verhalten. Änderungen: `8f0c1370792631b3abb275e04bc9b4176b28da1b`,
`bd3d268f43c7f5d801ab250f54e540e389301e05`,
`b77035cf4db75c59a9752f9f0aeb440cde65b3d1`,
`27c8fe5afc57357bbe4f4068ee3e1d3374bb9f30`.
**Nicht als bestanden markieren:** RecycleMasks (Modus 2),
Unicode-Multifile-F8, Shell-Open/Properties/externes Editieren,
Netzwerk- und Vollintegrationsfälle sind weiterhin offen.

**Weitere Grenzen:** Unter kurzen Unicode-Elternpfaden wird
`Copy Full Name`/Pfad jetzt über W-Clipboard ausgeführt;
der alte ANSI-Dateiöffner/Archiv-Association-Handler wird
bewusst vor einer verfälschten Pfadübergabe geschützt,
kann die betreffende Datei aber weiterhin **nicht öffnen**.
Die vollständige Wide-Integration dieses Übergangs,
externen Editierens, Kopieren als UNC, Drag/Drop und
der Shell-Properties steht noch aus.

### [ ] UP-06 – Shell, Zwischenablage, externe Programme, Dateiattribute (**P1**, OFFEN)
- **24.11.2026, SHA `9f524264`, Windows-nativer Test PASS:** Die bedingte Unicode-Elternverzeichnis-Navigation über echten, exakt konvertierbaren 8.3-Pfad mit Volume-/File-ID-Identität und autoritativem `GetDiskPathW` wurde nativ positiv geprüft. **Debug-/Release-GUI-Test am 14:34 durch fremde/laufende Salamander-Instanz vor Produktausführung BLOCKIERT**. Auf Volumes ohne 8.3-Alias bleibt **FAIL-CLOSED**; vollständige W-Panelmigration und GUI-Abnahme offen. Nicht als geschlossene Unicode-Anforderung zählen.
- **24.11.2026:** Kurzer, nicht-ACP-fähiger Unicode-Elternpfad wird in beiden x64-Varianten von `ChangeUnicodePathToDisk` abgewiesen; unverändert offener Produktfehler. Externer PowerShell-Editor FAIL, nativer Vergleichseditor PASS.

- **Fälle:** Datei-Eigenschaften, Öffnen, Drag/Drop, Viewer/Editor,
  Copy Full Name/Path, Papierkorb, ADS, EFS, ACLs, alternierende
  Unicode-/ANSI-Codepages bei langen Resultaten.
- **Abnahme:** Exakte Identität oder kontrollierte Ablehnung; Rückkehr aus
  Shell/Editor ändert nie eine andere Datei; Originalbytes bei Fehlern
  unverändert. Vorhandene positive Einzeltests nicht doppelt zählen.

**Neuer Produktcode auf `bugfix/v5.2` (23.11.2026, noch nicht
Windows-getestet):** Bei F5/F6 wird jetzt vor dem ANSI-Engine-
Aufruf auch `Zielverzeichnis + Dateiname` auf die
`MAX_PATH`-Grenze geprüft, nicht mehr nur die Quelle.
Die gemeinsame `ExceedsLegacyTransferPathLimit`-Prüfung
verwendet überlaufsichere Längenberechnungen und führt
betroffene Dateioperationen zum bestehenden UTF-16-Weg.
Regressionen liegen in
`tools/tests/legacy_disk_name_safety.cpp`
(Commit `ed939834c413078094cf0359d7785cf18fd1fb65`)
und im echten F5-/F6-GUI-Test für **zwei jeweils kurze Panelpfade
bei insgesamt zu langem Ziel-Dateipfad**
(`Test-SalamanderGui-LongPaths.ps1`, Commit
`393a2459f831e1fc98b43ae4bd1b850245d06e87`) vor.
Helper/Produkt-Commits:
`68b3dd56b0afbb338237c6f1ef23d25af57559e9`,
`be004f9a99d2a0ae0d7cc945ee56ec0a49307836`.
Die reine Grenzformel wurde in einem
separaten Linux-Clang-Probelauf mit Assertions kompiliert und
ausgeführt; dies ersetzt **weder** das originale MSVC-
Testprogramm **noch** Windows-GUI-Abnahme. UP-07 bleibt
TEILBELEGT; echte UNC-/EFS-/Near-Limit-Aktionen und
LongPathsEnabled-Matrix sind weiterhin offen.

**Weitere Hauptprogramm-Korrektur (23.11.2026, Windows-Test offen):**
Nicht nur überlange Pfade, sondern auch kurze Verzeichnisse mit
verlustbehafteter ANSI-Projektion müssen die UTF-16-Identität bewahren.
Das betrifft selbst Dateinamen, die nur aus ASCII bestehen.
Die exakte ACP-Rückkonvertierung des vollständigen Panelpfads
steuert jetzt F5/F6/F8, F2, `CheckPath`, Verzeichnisaufzählung,
Clipboard-Copy/Paste, Kopieren des vollständigen Namens und
den vorläufigen Schutz des ANSI-Association-/Archiv-Handlers.
Die alte Systemicon-/Thumbnail-Ladeschicht bekommt keine
verlustbehafteten Elternpfade; die entsprechende Wide-Migration
der Icon-/Shell-Schnittstellen steht **noch aus**.
Ein neuer GUID-isolierter GUI-Test
`--test-gui-unicode-parent` prüft F2/F5/F6 sowie
die exakt in die Zwischenablage kopierten UTF-16-Pfade
und ist über `manage.cmd --test-all` eingebunden.
Bei ACP-Konfigurationen mit verlustfreiem Unicode-Roundtrip
wird nur dieser spezielle Negativpfad als `SKIP` gekennzeichnet.
Commits: `6782912ad96cc0f79162199df50c7014f166eee0`,
`5d2868628c264446a6f141b3f2062b4df9e30693`,
`c6d5587c8e84d3acfe7fb74c882c3fb816d0c1a7`,
`e42fddb3f7efdf000fad890880a24293fa6f4143`,
`483b201439f3eeaa77400312346a3c7b7b5c106b`,
`f1820ae4525668c9bfb33f291c23d7d6e20903cf`.
**Weder ein vollständiger MSVC-Build noch eine
Windows-Ausführung liegt für diese Commits vor.**
UP-07 bleibt TEILBELEGT.

### [ ] UP-07 – Pfadgrenzwerte und Dateisystembedingungen (**P1**, TEILBELEGT)
- **Fälle:** 259/260/263, 255-Komponentenlimit, echte 32.700er-Pfade,
  Varianten mit und ohne LongPathsEnabled; NTFS/ReFS/SMB nur soweit
  relevant und tatsächlich vorhanden. UTF-16-Längen statt Codepoints.
- **Abnahme:** Jeder Wert gehört einer klaren positiven/negativen
  Erwartung; bei unmöglicher Fixture dokumentierter Environment-Blocker.
  Der positive 32.700er-GUI-Navigationstest **ersetzt nicht** FIND-01.

## 5. A3 – Vollständiger Visual-Studio-2026-Build

### [ ] BUILD-01 – Komplette Vierfach-Buildmatrix (**P0**, TEILBELEGT)
- **24.11.2026, 15:28, SHA `8a6de88`:** isolierter Debug-x64-Build für Legacy-Find erfolgreich, inklusive `fileswn5.cpp`; C2039 des 15:12-Laufs damit nachweislich behoben. Nicht als kompletter Debug+Release-Delta-Test, Vierfach-Solution oder sauberer Setup-Lauf werten.
- **24.11.2026, 15:12, SHA `3820e636`:** Debug-x64-Delta-Kompilierung **FAIL C2039** in `fileswn5.cpp`, Release-Build und alle `--test`-Schritte des kombinierten Laufs nicht erreicht. Korrektur des falsch verwendeten `HANDLES`-Makros eingecheckt; neuer realer Build ausstehend.
- **Fälle:** Clean-Checkout/Solution mit Win32/x64 × Debug/Release; alle
  zugehörigen Projekte/Plugins/Ressourcen/Help; Warnungen als Fehler,
  exakte Toolset-/SDK- und CRT-Abhängigkeiten protokollieren.
- **Abnahme:** Vier erfolgreiche Builds auf **demselben SHA** mit
  Binärinventar und Buildlogs, kein ausgelassenes Projekt. PR #14
  erweitert die CI-Matrix, ist aber nicht gemergt/auf Ziel-SHA verifiziert.
- **Quellen:** `src/vcxproj/salamand.sln`,
  `.github/workflows/pr-msbuild.yml`.

### [ ] BUILD-02 – CI-Gates und reproduzierbare Artefakte (**P1**, OFFEN)
- **Fälle:** Alle verpflichtenden PR-Workflows auf endgültigem Commit,
  native Tests x86/x64, Release-Paketerzeugung, Artefakt-Hashvergleich,
  Hilfedateien, Abhängigkeiten/CRT und fehlende Toolchain.
- **Abnahme:** Vollständige Actions-Run-IDs/Logs zum identischen SHA;
  kein grüner Check von älterem Commit als Release-Freigabe ausgeben.

## 6. A4 – manage.cmd und Teststeuerung

### [ ] MGMT-01 – Gesamter Update-/Build-/Test-/Setup-Ablauf (**P1**, OFFEN)
- **24.11.2026:** Zwei x64-Delta-Builds nach Wechsel zu `.Build/` PASS (ca. 122 s / 8 s). Vollständiger autorisierter `--update --build --test-all --setup`-Lauf fehlt weiter.

- **Fälle:** Autorisiert auf sauberem Test-Checkout
  `manage.cmd --update --build --test-all --setup`; zusätzlich
  `--build-clean`, Delta/Normal-Build und deren wiederholte Aufrufe.
- **Abnahme:** Eindeutiger Commit vor/nach Update, korrekte Reihenfolge,
  alle Outputs und Fehlercodes, keine nicht autorisierten Änderungen.
  `--update` nur nach ausdrücklicher Zustimmung.

### [ ] MGMT-02 – Fehler- und Isolationsverhalten (**P1**, TEILBELEGT)
- **24.11.2026, neu implementiert, Windows-GREEN ausstehend:** `manage.cmd` wartet vor GUI-sensitiven Testaktionen bei bereits laufenden `salamand.exe`-Prozessen mit einmaliger PID-Meldung und 1-s-Polling auf deren reguläres Schließen; setzt anschließend ohne Rückfrage fort. Keine Prozesse werden beendet, Ctrl+C bleibt wirksam. Nach einem GUI-Fall verbleibende Prozesse werden weiterhin als Sicherheitsfehler behandelt, nicht als normales Warten kaschiert. Neuer simulierter Regressionstest `Test-Manage-GuiWait.ps1` in `--test` registriert, statisch geprüft.
- **24.11.2026, 14:02, SHA `a928794c`:** `manage.cmd --test` tatsächlich **PASS**; 66 Skripte vom PowerShell-AST-Parser geprüft, fehlerhafte Negativfixture erkannt; Fehleraggregation/GUI-Sicherheitsvertrag und Kontinuitätstest PASS. Parserfehler von 13:56 damit behoben. Vollständige Fehler-/Isolationsmatrix bleibt TEILBELEGT.
- **24.11.2026, 13:56:** `--test` auf `8a5cb99d` **FAIL** wegen ungültiger `$id:`-Interpolation im neuen Kontinuitätstest. `${id}:` korrigiert. Neue PowerShell-AST-Parser-Vorprüfung sammelt Syntaxfehler vor dem Restlauf; auf Windows nach Fix noch nicht ausgeführt. Status bleibt TEILBELEGT.
- **24.11.2026:** Sammeltest-Infrastruktur mit PASS/FAIL/SKIP-JSON und nonzero-Gesamtergebnis implementiert; Windows-Sammlertest im `--test` PASS; isolierte Legacy-Find-Szenarien laufen nach FAIL weiter (36 PASS/1 FAIL). Cancellation/GUI-Sicherheitsmatrix nicht vollständig bewiesen.

- **Fälle:** Vorhandene Salamander-Instanz, gesperrter Desktop, fehlendes
  MSVC/SDK, ungültige Parameter, fehlgeschlagener Worker, Unterbrechung,
  abweichender SHA, verlorenes Plugin; Clipboard/Temp/Registry-Snapshot.
- **Abnahme:** Nonzero-Exit, verständliche Diagnose, keine fremden Prozesse
  beendet, keine unbeabsichtigte Löschung, kontrolliertes Cleanup und
  keine gefälschten PASS-Meldungen.

### [ ] MGMT-03 – Test-Registry gegen unbemerkte Auslassungen (**P2**, OFFEN)
- **24.11.2026:** `Test-Manage-GuiWait.ps1` zur Test-Registry von `tools/Manage-Salamander.ps1` hinzugefügt; Realbetrieb unter Windows noch zu prüfen, Registry-/Coverage-Gap bleibt offen.
- **24.11.2026, 14:02, SHA `a928794c`:** `Test-PowerShellSyntax.ps1` und `Test-DevelopmentContinuity.ps1` im echten Windows-`--test` PASS. GUI-Szenarien-Registry, Coverage-Drift und gezielte Opt-in-Abgrenzung weiterhin OFFEN.
- **24.11.2026, 13:56:** `Test-PowerShellSyntax.ps1` vor allen übrigen Vertragstests registriert, prüft `.ps1`-Dateien und enthält eine absichtlich fehlerhafte `$id:`-Negativfixture. Erst tatsächlicher Parser- und vollständiger `--test`-Lauf kann den Syntaxgate als bestanden belegen; MGMT-03 bleibt offen.
- **24.11.2026:** Eigenständiger `Test-DevelopmentContinuity.ps1` strukturell eingebunden; ein dokumentierter neuer Test ist keine automatisch vollständige Coverage-/Registry-Garantie. Gap-/Agent-Übergabe bleibt laufende Wartungspflicht.

- **Fälle:** Neu registrierte automatische GUI-Szenarien werden durch
  `--test-all` erfasst; Opt-ins bleiben separat; fehlende Testskripte,
  unbekannte Parameter, doppelte Testregistrierung.
- **Abnahme:** Ein Regressionstest lässt die Pipeline bei Coverage-Drift
  fehlschlagen. Grundlage: `Expand-AutomatedTestActions` und
  `Invoke-IsolatedLegacyFind.ps1`.

## 7. A5 – Release-7z/Setup/saubere VM

### [ ] PKG-01 – Vollständiges und byteidentisches Plugin-Paket (**P0**, VORBEREITET)
- **Lücke:** Pflichtdateien werden geprüft, aber noch nicht alle gebauten
  `.spl` auf exakten Inhalt und vollständige Stagingliste im grünen Stand.
- **Fälle:** Geändertes, fehlendes, zusätzliches oder an falscher Stelle
  befindliches Plugin; SHA-256 aller Module; ABI/Export-Prüfung.
- **Abnahme:** Stagingliste = Buildliste, SHA-256 je Modul gleich,
  alle Pflichtplugins enthalten; negative Regressionen erzwingen FAIL.
  Die Staging-/Plugin-Inventarprüfungen aus PR #14 und #16
  wurden in `bugfix/v5.2` integriert. Der kombinierte Windows-Lauf
  scheiterte noch vor der Paketphase an einem synthetischen
  Verzeichnis-Fixture; echte Paketabnahme steht aus.

### [ ] PKG-02 – Allowlist, Abhängigkeiten, Lizenzdateien (**P0**, TEILBELEGT)
- **Fälle:** Release-only-Manifest; verbotene `.pdb/.lib/.exp/.obj/.pch/
  .idb/.ilk/.tlog/.lastbuildstate`, Debug CRT, private Logs/Secrets;
  Vollständigkeit von EXE/DLL/SPL/Sprachen/Help/EXIF/THIRD_PARTY;
  rekursive PE-Dependencies, Lizenz-/Redistributionsrechte.
- **Abnahme:** Positive Allowlist und negative Fixturetests,
  unabhängig geladenes GitHub-Release-Artefakt und SHA-256-Matching;
  kein Blindvertrauen in lokales `dist`.
- **Quellen:** `tools/release/Package-Helpers.ps1`,
  `tools/release/tests/Test-ReleasePublicArtifact.ps1`.

### [ ] PKG-03 – Saubere Windows-11-VM: portable Variante (**P0**, OFFEN)
- **Fälle:** Frischer Snapshot ohne VS, Windows SDK oder separat
  installiertes VC++-Redist; heruntergeladenes finales 7z prüfen,
  entpacken/starten, F1-Hilfe, Plugins, F3 für BMP/PNG/JPEG/TIFF,
  Unicode/Langpfade, normal schließen, Event Viewer/DLL-Fehler prüfen.
- **Abnahme:** Vollständiger protokollierter PASS auf **exakten finalen
  Artefakthashes**. Eine CI-Runner-VM mit Entwicklerwerkzeugen zählt nicht.

### [ ] PKG-04 – Saubere VM: Installer, Deinstallation, Upgrade (**P0**, OFFEN)
- **Fälle:** Separater frischer Snapshot; interaktive Installation,
  Verknüpfungen, Start/F1/F3/Plugins, vollständige Deinstallation;
  separater 5.0→5.2-Upgrade-/Rollback-Snapshot.
- **Abnahme:** Programmdateien/Shortcuts bereinigt; Benutzerdaten und
  fremde Installationen unberührt; alter Registry-Stand erhalten;
  Protokoll, Screenshots, OS-Build, Datum, SHA, Hashes.

### [ ] PKG-05 – Authenticode, rechtliche Freigabe, Public Artifact (**P0**, BLOCKIERT)
- **Fälle:** Signatur der finalen EXE/DLL/SPL/Setup **oder** ausdrücklich
  akzeptierte Veröffentlichung ohne Signatur; Lizenz- und Herkunftsprüfung;
  öffentliches ZIP enthält ausschließlich Release-7z, Release-Setup
  und `SHA256SUMS-Release.txt`.
- **Abnahme:** Dokumentierte Signing-/Redistribution-Entscheidung,
  validierte Signaturen bzw. offengelegter Unsigned-Status,
  sauberes finales Release-Manifest. Produkt-/Rechtsentscheidung
  kann kein automatisierter Test ersetzen.

## 8. A6 – Originaler Strg+F-Suchdialog

### [ ] FIND-01 – Echte 32.700-UTF-16-Suchtreffer (**P1**, BLOCKIERT)
- **Lücke:** `NearLimit` existiert, ist aber aus automatischer Suite
  ausgenommen; frühere Versuche scheiterten bei Fixture-Erstellung
  unter Windows mit Fehler 998.
- **Fälle:** Ergebnis aus 32.700-UTF-16-Pfad mit 255er-Unicode-Dateiname,
  Treffertext, negative Decoys, Resultat-/Clipboard-/Action-Identität.
- **Abnahme:** Tatsächlich erzeugte Fixture + Original-Legacy-Find
  findet exakt den Treffer; kein Ersatz durch reine Panel-Navigation;
  bei Umgebungsfehler dokumentierter BLOCKIERT-Status.
- **Quellen:** `LegacyFind-GuiCases.ps1` / `NearLimit`.

### [ ] FIND-02 – Positiver EFS-Fall (**P1**, BLOCKIERT)
- **Fälle:** Testeigene EFS-verschlüsselte Datei auf geeignetem Volume
  inklusive Key/Userzugriff; `EncryptedFixture` im ursprünglichen
  Legacy-Find; Attribute und Inhalt, Suchoptionen, Rechtefehler.
- **Abnahme:** Reale EFS-Fixture nachgewiesen, korrekte Suchtreffer und
  identische Bytes; fehlende EFS-Unterstützung nicht als PASS buchen.
- **Quellen:** `LegacyFind-GuiCases.ps1`,
  `Test-SalamanderGui-LongPaths.ps1`.

### [ ] FIND-03 – Suche in Plugin-Dateisystemen (**P0**, OFFEN)
- **Fälle:** Originales Strg+F aus echten Plugin-Panels;
  Archive/Remote-VFS, Unicode/Longpath, Masken, Inhalt/Regex sofern
  unterstützt, Advanced/Filter, Abbruch, Resultatsaktionen.
- **Abnahme:** Legacy-Dialog bleibt erhalten; Plugin-Resultate exakt,
  keine A1/A2-Verletzung und keine unbemerkte ANSI-Umdeutung.
  Plugin-Fähigkeiten je Modul vorher spezifizieren; **UP-01/UP-02**.

### [ ] FIND-04 – Erweiterte Funktionen und Ergebnisaktionen (**P1**, TEILBELEGT)
- **24.11.2026, `447af3441741e9126a5273f396e3f28f73dc40f9`:** isolierter Debug-x64-Build PASS; fokussierter `ExternalEditor` **1 PASS / 0 FAIL / 0 SKIP** (5797 ms), Bericht `legacy-find-Debug-affb27784841402d8f84d4dcf56c67fb.results.json`. Alle acht In-Process-Probes starteten mit Fehler 0, Wait 0, Exit 7; echter Editor speicherte die exakte Fixture, Nachbar unverändert, Clipboard wiederhergestellt. **Geänderte Umgebung:** statt bisheriger WindowsApps/MSIX-PowerShell nun EXE außerhalb WindowsApps; daher nur für diesen Host bestanden. Job-Zugehörigkeit ja, kein Thread-Impersonationstoken (1008); kein Beweis einer Job- oder MSIX-Endursache. Gegenüber `fa3280b4` änderte `447af344` ausschließlich `Anforderungen.md` (neue A8: nachgewiesene Produktfehler ausschließlich im Produktcode beheben, Tests nur bei nachgewiesenem Testfehler korrigieren). Kein Produktfix zwischen MSIX-FAIL und diesem PASS; bisherige MSIX-Reproduktion bleibt offen. Neue A8 verbindlich berücksichtigen, keine Testabschwaechung. Nächster Schritt: wenn ursprünglicher MSIX-Host noch vorhanden, gezielter unveränderter GUI-Test mit explizitem Host aus dem gleichen administrativen VS-Kontext und bereits gebautem isolierten Binary; andernfalls MSIX-Fall als nicht erneut verifizierbar dokumentieren. Vollständige Legacy-Find-Debug-/Release-Suiten und `--test` weiterhin erforderlich; keine Release-Freigabe.
- **24.11.2026, `370951fc`:** fokussierter Debug-x64-Build PASS, ExternalEditor FAIL (0/1/0), Bericht `legacy-find-Debug-053e9c642d9c48ba8d9e0189587fa117.results.json`. Shared-Memory-Diagnose PASS: vollständiger absoluter WindowsApps-PowerShell-EXE-Pfad, korrekte Argumente inklusive beider gequoteter Fixture-Pfade, korrekter InitDir und expliziter ApplicationName; ACP 1252, STARTF 0x7, CreationFlags 0x20, EXE-Attribute 0x20/Fehler 0, Prozess-CWD System32. CreateProcess weiterhin Win32 5. Keine erkennbare Abweichung in expandierten Parametern. Neue ausschließlich für den isolierten PowerShell-Editorfall aktivierte In-Process-Matrix startet nur exakt das vom Testtreiber konfigurierte pwsh.exe mit harmlosem `exit 7`, ohne Editorfixture-Zugriff: A/W, ApplicationName NULL/explizit, ursprüngliche/leere STARTUPINFO, neue Konsole/kein Konsolenfenster, expliziter unveränderter Unicode-Umgebungsblock, Job-/Threadtoken-Status. Begrenzte Waits, nur eigene Probehandles, bei Timeout keine weiteren Probes. Der reale Edit-Aufruf bleibt unverändert und wird nicht wiederholt; der Matrixbefund ist unabhängig vom tatsächlichen Editorerfolg. Keine Rechte-/Policy-Änderung. **Neuer Code noch nicht unter Windows ausgeführt; Fehlerursache und Produktfix offen.**
- **24.11.2026, `b36a1233`:** fokussierter isolierter Debug-x64-Build PASS; `ExternalEditor` 0 PASS / 1 FAIL / 0 SKIP; CreateProcess weiterhin Win32 5/NOT_STARTED, neue Prelaunch-Datei fehlt (`Editor-launch=[<editor launch record missing or oversized>]`). Bericht `legacy-find-Debug-7a9434dab54c44229fe4f23134cd42a6.results.json`. Ursache der fehlenden Datei nicht nachgewiesen. Test-only-Transport auf vor Prozessstart durch den Treiber erzeugtes GUID-gebundenes `Local\\OpenSalamander.EditorTest.<id>`-Mapping (4096 Byte) umgestellt; keine Abhängigkeit von TEMP oder ANSI-Dateipfad beim Schreiben. Native Seite öffnet ausschließlich vorhandenes Mapping, schreibt NUL-terminierten Record vor CreateProcess und schließt ihre Handles. Treiber liest begrenzt, dekodiert per erfasster ACP, meldet konkrete Lesefehler und erhält Textkopie nur in eigener Fehlerfixture; Mapping wird im finally freigegeben. Zusätzlich tatsächliches Prozessarbeitsverzeichnis und GetFileAttributes-Resultat/Fehler des EXE-Pfads. Produktlaunch, Sicherheitsprüfung und fachliche Assertions unverändert. **Neuer Code nicht unter Windows ausgeführt; FIND-04/QA-03 offen.**
- **24.11.2026, 17:06–17:09 CET, `d93cb4d5`:** isolierter Debug-x64-Build PASS, Legacy Find **36 PASS / 1 FAIL / 0 SKIP**; `AdvancedInputs`, `ShellClipboard`, `ExternalEditorNative` PASS, `ExternalEditor` FAIL/NOT_STARTED, CreateProcess Win32 **5 (ERROR_ACCESS_DENIED)**. Log: `manage-20261124-170629-100-b3066a.log`. Gleiches Ergebnis im Lauf 15:57–16:01. Nutzer-Gegenproben: vier A/W-API-/ApplicationName-Kombinationen im PowerShell-Prozess PASS (Exit 7); absoluter MSIX-EXE-Start aus administrativer cmd.exe PASS (Exit 7); vollständige ursprüngliche Editor-Fixture aus cmd.exe PASS (Exit 0, SAVED). Allgemeine MSIX-Startblockade nicht belegt. Neue testbuild- und GUID-gesteuerte One-shot-Datei `process-temp/editor-launch.txt` erfasst vor CreateProcess expandierten Befehl, Argumente, Arbeitsverzeichnis, Commandline, ApplicationName, ACP und Startflags. GUI-Runner meldet sie bei FAIL mit dem vorhandenen Win32-Dialog; bei PASS verlangt er eine nichtleere Datei. **Kein Windows-Lauf auf dem neuen Diagnosecode; Produktfehler bleibt offen.**
- **24.11.2026, SHA `8a6de88`, 15:28–15:32:** Debug-Editor-GUI trotz erfolgreichem PowerShell-Kontrollstart weiterhin `NOT_STARTED`; eigener Dialog `Open Salamander` sichtbar. Produktkorrektur mit explizitem `lpApplicationName` kompiliert nun, beseitigt Fehler aber **nicht**. Neue diagnose-only Abfrage beschrifteter Static-Controls des test-eigenen Dialogs über PID-geprüftes `SendMessageTimeout(WM_GETTEXT, 750 ms)`, ohne Dismiss/Retry; Windows-Nachtest ausstehend. FIND-04 bleibt offen.
- **24.11.2026, 15:12, SHA `3820e636`:** Neuer `CreateConfiguredEditorProcessA`-Aufruf innerhalb `HANDLES(...)` **C2039, Debug-Build FAIL**, isolierter Legacy-Find-GUI-Build ebenfalls FAIL; keine neuen GUI-Produktbelege. **Korrektur nach dem Lauf:** direkter `HANDLES(CreateProcess(GetExplicitEditorApplicationName(expCommand), ...))`, mit unverändertem Handle-Monitoring und Legacy-Fallback; Test ergänzt, nicht unter Windows ausgeführt. FIND-04 bleibt TEILBELEGT.
- **24.11.2026, 15:02; SHA `3119af03`, realer Debug-GUI-Lauf:** 36 PASS/1 FAIL/0 SKIP; PowerShell-Host-Preflight erfolgreich, `ExternalEditorNative` erfolgreich, *nur* tatsächlicher `ExternalEditor` FAIL mit `NOT_STARTED`. Neuer enger Produkt-Fix (absolute existierende `.exe` als explizites `lpApplicationName` in `CreateProcessA`; sonst Legacy-Fallback), nativer Test `editor_process_launch.cpp`, statischer Vertrag und Eigentümer-Fensterdiagnose eingecheckt, **MSVC-/GUI-GREEN auf neuem HEAD ausstehend**. Nicht als geschlossen markieren.
- **24.11.2026, SHA `9f524264`:** Die PowerShell-Editor-Kontraktprüfungen im echten Windows-`--test` sind PASS, aber der GUI-Editorlauf wurde wegen vorhandener Salamander-Instanz **vor Produktausführung blockiert**; die eigentliche Änderung ist nicht GUI-verifiziert. Der PowerShell-Editor erhält einen absoluten, korrekt zitierten `-File`-Pfad; vor dem eigentlichen GUI-Edit-Befehl wird der konkrete `pwsh.exe`-Host mit einem test-eigenen File unabhängig geprüft und die Fixture nachweisbar zurückgesetzt. So unterscheiden wir Host-/Policy-Fehler von Produkt-CreateProcess-Fehlern. Die Vertragsprüfung erzwingt Vorlauf und Zurücksetzen des Statusmarkers (`be853b54`). Beide Editorvarianten bleiben erhalten; Ausführungsrichtlinie bleibt unverändert. `ExternalEditorNative` und strenge Original-/Nachbar-/Argumentprüfungen bleiben bestehen. Vorhandenes Debug-FAIL `NOT_STARTED` nicht als behoben markieren, bis erneuter realer Lauf bestanden ist.
- **24.11.2026:** Debug-Legacy-Find 36 PASS, 1 FAIL; originaler PowerShell-`ExternalEditor` meldet `NOT_STARTED`, Native-Vergleich PASS. Beide Szenarien bleiben erhalten, Verhalten und Root Cause offen.

- **Lücke:** 72 GUI-Szenarien bestanden, aber nicht alle Kombinationen
  von Advanced, Regex, Ignore, zeitlichen Attributen, Mehrfachauswahl,
  Viewer, Editor, Shell, Clipboard und langen Treffern.
- **Abnahme:** Relevante Legacy-Verhaltensmatrix mit positiven,
  negativen und kombinierten Fällen; GUI/A11y-Ergebnistext,
  Fokus und Shortcut-Treue; kein Ersatzdialog.

### [ ] FIND-05 – Nebenläufigkeit und Fehlerpfade (**P2**, OFFEN)
- **Fälle:** Cancel während Enumeration/Content-Grep/Regex,
  Dateiänderung zwischen Suche und Aktion, Junction-Zyklus,
  Access Denied, gesperrte Quelle, verschwindender Netzwerkpfad.
- **Abnahme:** Keine falsche Resultatszuordnung, kein Hänger,
  unbeschädigte Daten, aussagekräftiges Fehlerlog, sauberes Ende.

## 9. A7 – WIC-PictView-Plugin

### [ ] WIC-01 – Native Codec-/Negativmatrix (**P1**, VORBEREITET)
- **Fälle:** Alle **13 derzeit registrierten Endungen**
  `bmp,dib,png,jpg,jpeg,jpe,gif,tif,tiff,ico,jxr,wdp,hdp`
  über echten WIC-Decoder; richtige BGRA-Pixel, Unicode-/Langpfad;
  ungültige Frames/Null-/Leereingabe/kaputtes Bild; kein stale Output;
  unveränderte Quellbytes.
- **Abnahme:** MSVC x86/x64 PASS mit tatsächlichem Windows-Codec;
  jeder beworbene Codec verfügbar oder Produktentscheidung/Registrierung
  korrigiert. JPEG XR/WMP darf auf einem Rechner ohne Codec
  **nicht** stillschweigend als bestanden gelten.
- **Stand:** Mehrere Tests in `bugfix/v5.2` registriert;
  erweiterte Negativ-/Datenintegritätstests in **PR #14**;
  dessen Ausführung auf Merge-SHA offen.

### [ ] WIC-02 – Echter F3-Host über mehrere Bildformate (**P0**, OFFEN)
- **Fälle:** BMP, PNG, JPEG, GIF, TIFF, ICO über echten PictView-
  Host, nicht allein `DecodeFrame`; Abmessungen, Anzeige,
  HWND-/SPL-/PID-Identität, Close/Lock und unveränderte Dateien.
- **Abnahme:** Alle Formate auf frisch gebautem Release-x64 mit
  `manage.cmd --test-pictview-host --release` erfolgreich;
  kein Modalfehler, keine fremden GUI-Prozesse beeinflusst.
  Opt-in, **nicht Bestandteil von `--test-all`**.

### [ ] WIC-03 – Thumbnail-Host und Lebenszyklus (**P1**, OFFEN)
- **Fälle:** Thumbnail über Salamanders echten Host,
  BMP/PNG/JPEG/TIFF/GIF/ICO, fehlerhafte Bilder,
  Cancel während Decode, mehrfaches Öffnen/Schließen,
  Resize/Redraw, COM-/HWND-/Thread-Ownership.
- **Abnahme:** Sichtbare korrekte Thumbnails ohne Crash,
  Hänger, Leaks oder Änderung von Quelldateien.
  Native Decoder-Unit-Tests allein reichen nicht.

### [ ] WIC-04 – Mehrbilddateien und Animation (**P1**, VORBEREITET/BLOCKIERT)
- **Fälle:** Animierte GIFs mit mehreren Frames/Farben/Delays und
  Disposal, mehrseitige TIFFs, Navigation, invalid Frame, Quelle
  unverändert, Anzeige im echten Viewer.
- **Stand:** Multi-TIFF native Tests vorhanden; unabhängige
  Zwei-Frame-GIF-Decoder-Fixture in PR #14 vorbereitet.
  **Zeitgesteuerte GIF-Wiedergabe ist laut Migrationsdokument
  noch nicht implementiert** – kein Test kann diese Lücke schließen.
- **Abnahme:** Erst konkreten Legacy-Verhaltensvertrag festhalten,
  Funktion implementieren, dann echte GUI-Animation inkl.
  Timing/Abbruch/Close testen. A0/A7-Konflikt nicht stillschweigend ausklammern.

### [ ] WIC-05 – Bildbearbeitung, Export, Zwischenablage (**P1**, TEILBELEGT)
- **Fälle:** Rotate/Mirror/Zoom/Fit, Save Copy PNG/BMP/JPEG/TIFF,
  Ziel bereits vorhanden, Alpha, EXIF-Fälle, Clipboard
  Copy/Paste, ungültige DIBs, wiederholter Export.
- **Abnahme:** Byte-/Pixelrichtigkeit, keine Quellüberschreibung,
  kein Crash bei fehlerhaften Metadaten, Originaldaten bleiben;
  reale Tastatur-/Menüaktionen zusätzlich zu nativen Tests.
  PR #14 erweitert native Exportfälle; GUI-Parität fehlt.

### [ ] WIC-06 – Historische PictView-Funktionen und Codec-Parität (**P0**, BLOCKIERT)
- **Lücke:** Laut `docs/pictview-wic-migration.md` fehlen u. a.
  Crop/Selection, Undo/History, In-place Save, Print/Capture,
  Slideshow, Metadata/Color-Management, alte Menüs und
  Legacy-Formate außerhalb verfügbarer WIC-Codecs.
- **Abnahme:** Je Alt-Funktion entweder **nachweislich erhalten**
  und regressionsgetestet oder eine **ausdrückliche Produktentscheidung**
  über Abweichung dokumentiert. A0 untersagt eigenmächtige
  Funktionseinschränkungen; Veröffentlichung ohne Parität
  nicht mit „vollständig getestet“ gleichsetzen.

### [ ] WIC-07 – ANSI-Plugingrenze und Systemcodecs (**P0**, BLOCKIERT)
- **Fälle:** WIC-Host mit nicht-ACP-Bildpfad, 260+/UNC,
  unterschiedliche Windows-Codepages, Codec installiert/
  nicht installiert, Registry-Viewerassoziationen.
- **Abnahme:** Positiver UTF-16-End-to-End-Pfad oder
  nachgewiesene kompatible SDK-Erweiterung; sichere
  Ablehnung ist Datenintegrität, aber **keine** vollständige
  A1/A2-Unterstützung. System-Codec-Abhängigkeit dokumentiert.

## 10. Weitere übergreifende Nachweise

### [ ] QA-01 – Fehler-/Abbruch- und Sicherheitsmatrix (**P0**, OFFEN)
- **Fälle:** Fehler 5/32/80/112, ACL, offene Handle-Locks,
  unerwartetes Prozessende, Quelle verändert, ADS/Reparse Point,
  Quell-/Zielkollision und unzuverlässige SMB-Verbindung.
- **Abnahme:** Bei Fehlern keine Datenverluste oder unautorisierte
  Änderungen, Stagingdateien bereinigt, genaue Fehlerursache
  und Regressionstest je entdecktem Defekt.

### [ ] QA-02 – Gemessene Branch-/Funktionsabdeckung (**P2**, OFFEN)
- **Arbeit:** Messbares Coverage-Konzept für native C++-Logik und
  PowerShell; Source-/Branch-Coverage nach Komponente, nicht
  „100 %“ ohne Instrumentierung behaupten.
- **Abnahme:** Reproduzierbarer Report mit abgedeckten/unabgedeckten
  Pfaden, priorisierte kritische Zweige, dokumentierte
  Ausschlüsse (WinAPI-/GUI-Boundaries).

### [ ] QA-03 – Wiederholbarkeit, GUI-Flakiness und Ressourcen (**P1**, TEILBELEGT)
- **24.11.2026, `447af3441741e9126a5273f396e3f28f73dc40f9`:** isolierter Debug-x64-Build PASS; fokussierter `ExternalEditor` **1 PASS / 0 FAIL / 0 SKIP** (5797 ms), Bericht `legacy-find-Debug-affb27784841402d8f84d4dcf56c67fb.results.json`. Alle acht In-Process-Probes starteten mit Fehler 0, Wait 0, Exit 7; echter Editor speicherte die exakte Fixture, Nachbar unverändert, Clipboard wiederhergestellt. **Geänderte Umgebung:** statt bisheriger WindowsApps/MSIX-PowerShell nun EXE außerhalb WindowsApps; daher nur für diesen Host bestanden. Job-Zugehörigkeit ja, kein Thread-Impersonationstoken (1008); kein Beweis einer Job- oder MSIX-Endursache. Gegenüber `fa3280b4` änderte `447af344` ausschließlich `Anforderungen.md` (neue A8: nachgewiesene Produktfehler ausschließlich im Produktcode beheben, Tests nur bei nachgewiesenem Testfehler korrigieren). Kein Produktfix zwischen MSIX-FAIL und diesem PASS; bisherige MSIX-Reproduktion bleibt offen. Neue A8 verbindlich berücksichtigen, keine Testabschwaechung. Nächster Schritt: wenn ursprünglicher MSIX-Host noch vorhanden, gezielter unveränderter GUI-Test mit explizitem Host aus dem gleichen administrativen VS-Kontext und bereits gebautem isolierten Binary; andernfalls MSIX-Fall als nicht erneut verifizierbar dokumentieren. Vollständige Legacy-Find-Debug-/Release-Suiten und `--test` weiterhin erforderlich; keine Release-Freigabe.
- **24.11.2026, `370951fc`:** fokussierter Debug-x64-Build PASS, ExternalEditor FAIL (0/1/0), Bericht `legacy-find-Debug-053e9c642d9c48ba8d9e0189587fa117.results.json`. Shared-Memory-Diagnose PASS: vollständiger absoluter WindowsApps-PowerShell-EXE-Pfad, korrekte Argumente inklusive beider gequoteter Fixture-Pfade, korrekter InitDir und expliziter ApplicationName; ACP 1252, STARTF 0x7, CreationFlags 0x20, EXE-Attribute 0x20/Fehler 0, Prozess-CWD System32. CreateProcess weiterhin Win32 5. Keine erkennbare Abweichung in expandierten Parametern. Neue ausschließlich für den isolierten PowerShell-Editorfall aktivierte In-Process-Matrix startet nur exakt das vom Testtreiber konfigurierte pwsh.exe mit harmlosem `exit 7`, ohne Editorfixture-Zugriff: A/W, ApplicationName NULL/explizit, ursprüngliche/leere STARTUPINFO, neue Konsole/kein Konsolenfenster, expliziter unveränderter Unicode-Umgebungsblock, Job-/Threadtoken-Status. Begrenzte Waits, nur eigene Probehandles, bei Timeout keine weiteren Probes. Der reale Edit-Aufruf bleibt unverändert und wird nicht wiederholt; der Matrixbefund ist unabhängig vom tatsächlichen Editorerfolg. Keine Rechte-/Policy-Änderung. **Neuer Code noch nicht unter Windows ausgeführt; Fehlerursache und Produktfix offen.**
- **24.11.2026, `b36a1233`:** fokussierter isolierter Debug-x64-Build PASS; `ExternalEditor` 0 PASS / 1 FAIL / 0 SKIP; CreateProcess weiterhin Win32 5/NOT_STARTED, neue Prelaunch-Datei fehlt (`Editor-launch=[<editor launch record missing or oversized>]`). Bericht `legacy-find-Debug-7a9434dab54c44229fe4f23134cd42a6.results.json`. Ursache der fehlenden Datei nicht nachgewiesen. Test-only-Transport auf vor Prozessstart durch den Treiber erzeugtes GUID-gebundenes `Local\\OpenSalamander.EditorTest.<id>`-Mapping (4096 Byte) umgestellt; keine Abhängigkeit von TEMP oder ANSI-Dateipfad beim Schreiben. Native Seite öffnet ausschließlich vorhandenes Mapping, schreibt NUL-terminierten Record vor CreateProcess und schließt ihre Handles. Treiber liest begrenzt, dekodiert per erfasster ACP, meldet konkrete Lesefehler und erhält Textkopie nur in eigener Fehlerfixture; Mapping wird im finally freigegeben. Zusätzlich tatsächliches Prozessarbeitsverzeichnis und GetFileAttributes-Resultat/Fehler des EXE-Pfads. Produktlaunch, Sicherheitsprüfung und fachliche Assertions unverändert. **Neuer Code nicht unter Windows ausgeführt; FIND-04/QA-03 offen.**
- **24.11.2026, 17:06–17:09 CET, `d93cb4d5`:** isolierter Debug-x64-Build PASS, Legacy Find **36 PASS / 1 FAIL / 0 SKIP**; `AdvancedInputs`, `ShellClipboard`, `ExternalEditorNative` PASS, `ExternalEditor` FAIL/NOT_STARTED, CreateProcess Win32 **5 (ERROR_ACCESS_DENIED)**. Log: `manage-20261124-170629-100-b3066a.log`. Gleiches Ergebnis im Lauf 15:57–16:01. Nutzer-Gegenproben: vier A/W-API-/ApplicationName-Kombinationen im PowerShell-Prozess PASS (Exit 7); absoluter MSIX-EXE-Start aus administrativer cmd.exe PASS (Exit 7); vollständige ursprüngliche Editor-Fixture aus cmd.exe PASS (Exit 0, SAVED). Allgemeine MSIX-Startblockade nicht belegt. Neue testbuild- und GUID-gesteuerte One-shot-Datei `process-temp/editor-launch.txt` erfasst vor CreateProcess expandierten Befehl, Argumente, Arbeitsverzeichnis, Commandline, ApplicationName, ACP und Startflags. GUI-Runner meldet sie bei FAIL mit dem vorhandenen Win32-Dialog; bei PASS verlangt er eine nichtleere Datei. **Kein Windows-Lauf auf dem neuen Diagnosecode; Produktfehler bleibt offen.**
- **24.11.2026, SHA `8a6de88`, 15:28–15:32:** 34 PASS/3 FAIL/0 SKIP; zusätzliche FAILs `AdvancedInputs` (queued Shift `0xFF81`, möglicherweise konkurrierende Desktop-Tastatureingabe) und `ShellClipboard` (Copy-FileDrop/-Effect Timeout). Neuer Treiber nutzt zeitbegrenztes `GetAsyncKeyState` statt möglicherweise veralteten Queuezustands, ohne gedrückte physische Modifikatoren zu ignorieren; Clipboard-Diagnose meldet nur Metadaten (Formatnamen, Sequenz, Anzahl, Effekt), die identischen Assertions und die Isolierung bleiben erhalten. **GUI-GREEN für diese Änderungen ausstehend**.
- **24.11.2026, 15:12:** Die erneute Legacy-Find-Debug-GUI-Prüfung scheiterte **bereits bei der isolierten Kompilierung**, ohne Testergebnis. Statischer Schutz gegen `HANDLES(Salamander::...)` eingeführt; ein echter neuer GUI-Gegenlauf steht aus.
- **24.11.2026, 14:59–15:02:** Trotz isoliertem GUI-Runner und erfolgreichem unabhängigen PowerShell-Start reproduzierbarer `ExternalEditor`-FAIL `NOT_STARTED` (36/1/0). Produktlaunch-Hypothese durch separate ausführbare Modulidentität und neue native Regression abgesichert, aber noch nicht live verifiziert. Test-Runner meldet bei erneuter Timeout-Ausnahme zusätzlich Fenster des test-eigenen Salamander-Prozesses, ohne fremde Fenster zu manipulieren.
- **24.11.2026:** Fehlgeschlagene GUI-Preflights bei bereits laufenden Salamander-Instanzen sollen künftig kontrolliert warten statt sofort mit Exit 1 enden. Die Unterläufe behalten ihre strikten Sicherheitschecks; eine wiederholte echte GUI-Testserie nach der Änderung fehlt weiterhin.
- **24.11.2026, 14:34, SHA `9f524264`:** Drei isolierte GUI-Aufrufe (Unicode-Elternverzeichnis Release/Debug, Legacy-Find Debug) scheiterten am **Preflight bereits laufender Salamander-Instanzen** und führten keine Produktschritte aus. Sicherheitsentscheidung korrekt: keine Benutzerinstanz abschießen, nicht als neue GUI-Produktregression verbuchen. Vor Wiederholung eigene Salamander-Fenster regulär schließen.
- **24.11.2026:** Hypothese zum `ExternalEditor`-Fehler (relativer Scriptpfad des MSIX-Childs) mit absolutem test-eigenen Scriptpfad und unabhängiger, zurückgesetzter PowerShell-Host-Preflight-Fixture abgesichert. Kein Root-Cause-/Laufzeitnachweis bisher; nachfolgende GUI-Wiederholungen und echte Prozessstartdiagnose erforderlich.
- **24.11.2026, 13:56:** Testinfrastruktur verursachte einen deterministischen Parserabbruch auf `8a5cb99d`; kein sporadischer Produktfehler. Regressionsfix vorhanden, auf Windows nach Fix nicht geprüft.
- **24.11.2026:** GUI-Viewer/Unicode-Fälle beim Einzel-Legacy-Debug-Lauf PASS; ursprüngliche PowerShell-Editor-Regression FAIL. Einzelner erfolgreicher Viewer-Lauf ist kein Wiederholbarkeitsnachweis.

- **Fälle:** Wiederholte paarweise `--diagnose-gui`- und
  `--test-all`-Läufe, Cold/Warm-Start, Fokus, Clipboard,
  Hintergrundthreads/Plugin-Load, Handles/COM/Memory.
- **Abnahme:** Fehlerrate pro Test und reproduzierbarer Fehlerlog;
  Timing-/Retry-Verhalten nicht allein durch längere Timeouts
  kaschieren. Fremde Prozesse nicht beenden.
- **Quelle:** `tools/release/tests/Invoke-GuiReliability.ps1`.

**QA-03 / FIND-04 – GUI-Ausfall aus realem Lauf (23.11.2026):**
Der vom Benutzer bereitgestellte vollständige Transkriptlauf
`--build-clean --test-all --setup` auf Source-SHA
`2be91b27032a2f4cb4619a606b42b0af7c8ea6c1`
begann um 21:42:30 Uhr und endete um 21:53:06 Uhr
**mit Exitcode 1**. Debug x64 und Release x64 wurden
sauber gebaut; die vorherigen nativen Tests und die bereits
abgeschlossenen Release-Legacy-Find-Fälle meldeten PASS.
Die **Debug-x64-`ViewUnicode`-Regression** brach nach
korrekter Find-Ergebnisidentität ab: `Timeout waiting for Viewer
copied the exact bytes from the named result`. Der Test sicherte
einen Screenshot und ließ sein eindeutig benanntes Testfixture
zur Diagnose bestehen. Der Abbruch erfolgte **vor** der geplanten
Setup-/Paketphase; `--setup` ist dadurch **nicht validiert**.
Die Fehlerursache (kein Clipboard-Wechsel, falsche Bytes,
Viewer-Zustand oder Ereignisreihenfolge) ist aus dem
Transkript nicht nachweisbar.

Zur Eingrenzung stellt `Assert-LegacyViewerContents` nun ohne
zusätzliche Kommandos, Timeouterhöhung, Datenkopie im Log
oder abgeschwächte Vergleiche die Metadaten
`ClipboardSequenceChanged`, `ClipboardTextKind`,
`ObservedUtf16Length`, `ExpectedUtf16Length`
und `ViewerStillMatches` bereit. Der Zustand wird wegen
des Scope-Wechsels von `Wait-Until` in einem gemeinsamen
Hashtable gehalten. Der Quellvertrag ist in
`Test-LegacyFind-UiContract.ps1` ergänzt; der Parser des
`Test-Package-Helpers.ps1` kontrolliert die GUI-Dateien.
Test `354977963aadb34961f989c1f34566d908825b70`,
Diagnose `1fe54e1f2aee063d0660cfd8be83ce405fd2d463`,
Scope-Regression `4a0494c4c765e1bb84dc504bc5207a886ae46464`,
Parser-Vorprüfung `c355c4f9c73559edf19b9a0510c94502130f1c51`.
**Noch nicht unter Windows ausgeführt, keine Ursachenbehebung
behauptet.** Wiederholung des isolierten Debug-`ViewUnicode`-
Falls auf dem aktuellen PR-SHA erforderlich, danach vollständiger
`--test-all --setup`-Lauf auf demselben SHA.

**QA-03 / FIND-04 – gezielte Debug-Verifikation auf neuerem SHA
(23.11.2026, ein erfolgreicher Durchlauf):** Benutzerseitig
ausgeführtes `Build-IsolatedGuiTest.ps1 -Configuration Debug
-OutputName isolated-legacy-find` und anschließend
`Test-SalamanderGui-LongPaths.ps1 -IsolatedConfiguration
-LegacyFindScenario ViewUnicode` auf
`62234c10b31bed4507700b2a21a0fc5dbd9fe4d2`.
Die Konsole bestätigt: isolierter Debug-x64-Build, originaler
Find-Dialog, zwei unterschiedliche UTF-16-Treffer,
**beide** bytegenauen Viewer-Copy-Prüfungen, Next/Previous
und Zwischenablage-Wiederherstellung mit PASS.
Die neuen Timeout-Diagnosezweige wurden dadurch nicht
ausgeführt; der zuvor in einem vollständigen Testlauf
beobachtete Fehler ist **nicht reproduziert, aber nicht als
behoben nachgewiesen**. Es liegt für diesen Einzellauf
kein separat versionierter vollständiger Transcript-Dateipfad
oder Binär-SHA256 vor. QA-03 bleibt offen, bis Wiederholung,
Fehlerrate und derselbe SHA im Volltest dokumentiert sind.

**QA-03 – wiederholbare `ViewUnicode`-Evidenz (23.11.2026,
VORBEREITET):** `Invoke-LegacyViewerReliability.ps1` baut
einmalig die isolierte Debug-/Release-x64-Binärdatei, notiert
Source-SHA und Binär-SHA256 und führt danach standardmäßig
fünf unabhängige `ViewUnicode`-Fälle mit jeweils eigener
GUID-Konfiguration aus. Vollständige Konsolenlogs je Lauf
und `Summary.csv` dokumentieren Exitcode, Dauer und
verbliebene Prozesse. Ein fehlerhafter Lauf führt zum
Gesamtergebnis FAIL; bei einem übrig gebliebenen Salamander-
Prozess wird ohne Beenden fremder Prozesse abgebrochen.
Parserprüfung und statischer Quellvertrag sind eingebunden.
Ein einzelner erfolgreicher Lauf ist **kein** Nachweis der
Wiederholbarkeit; der neue Runner wurde noch **nicht**
unter Windows ausgeführt.

Aufruf auf unverändertem Checkout:

```powershell
pwsh -NoProfile -File .\tools\release\tests\Invoke-LegacyViewerReliability.ps1 -Configuration Debug -Iterations 5
```

**QA-03 – fünffacher Debug-ViewUnicode-Lauf: PASS (begrenzt, 23.11.2026):**
Der Benutzer hat auf Source-SHA
`98d9d06b0cc514259f6119cc399da7d6f964b9c3`
`Invoke-LegacyViewerReliability.ps1 -Configuration Debug -Iterations 5`
auf Windows ausgeführt. Binär-SHA256:
`3E017F3ABE5C2AE56A79D78004D4440D79F096499144C0E4E1F3DF794680BCB1`.
Alle fünf isolierten Fälle meldeten Exitcode 0, zwei erfolgreiche
bytegenaue Viewer-Kopiervergleiche, Next/Previous und
erfolgreiche Clipboard-Wiederherstellung. Es verblieben
jeweils **0** Salamander-Prozesse. Laufzeiten: 3,48 s,
3,26 s, 3,25 s, 3,42 s, 3,47 s.
Laut Konsolenausgabe: lokales Evidenzverzeichnis
`D:\Build\OpenSal\logs\legacy-viewer-reliability\viewunicode-20261123-221445-fefdb01a`
mit `Summary.csv` und fünf Falllogs. Die lokalen Logdateien
wurden nicht zusätzlich eingelesen; Nachweis beruht auf der
übermittelten Konsole. Damit beträgt die beobachtete
Fehlerrate **0/5 in genau dieser isolierten Umgebung**, nicht
0 % allgemein. Der früher einmalig aufgetretene Fehler im
gesamten `--test-all`-Ablauf bleibt ungeklärt. Die vollständige
Testmatrix und der Setup-Lauf sind auf dem integrierten SHA
weiterhin ausstehend. **QA-03 bleibt TEILBELEGT.**

### [ ] QA-04 – Umgebungs-/Locale-Matrix (**P1**, OFFEN)
- **Fälle:** Windows 11 Build, CP1252 und nichtwesteuropäische
  ACP, LongPathsEnabled ein/aus, 100/125/200 %-DPI,
  Netzwerk/Offline, unterstützte Architekturen.
- **Abnahme:** Abweichende Ergebnisse je Umgebung erfasst;
  korrekte UI-Bedienung und Sicherheitsverträge.

**Branch-Konsolidierung vor Gesamtverifikation (23.11.2026):**
PR #16 per Fast-Forward nach `bugfix/v5.2` übernommen
(`98d9d06b0cc514259f6119cc399da7d6f964b9c3`);
PR #14 über den Zwei-Eltern-Merge-Commit
`c06e17ccc04540a7704b596941d56fa5b37cf6f1`
mit expliziter Auflösung der Überschneidungen integriert.
Die strengeren Plugin-ABI-/Payload-Verträge aus #16
blieben erhalten; die zusätzlichen WIC-/PictView-, VS2026-
und Binärinventartests aus #14 wurden aufgenommen.
**Diese kombinierte Quellenbasis ist noch nicht vollständig
unter Windows getestet und keine Release-Freigabe.**
Weitere Fixes erfolgen wie beauftragt direkt auf
`bugfix/v5.2`, ohne neue Entwicklungsbranches.
Die Windows-Quell-/Registry-Vorprüfung reagiert nun auch
auf Pushes in diesen Branch. Der veraltete
`Export-Csv -NoTypeInformation`-Schalter wurde wegen
der im 5/5-Lauf gemeldeten Warnung entfernt.

## 11. Arbeitsreihenfolge und Meilensteine

| Phase | IDs / Ergebnis | Vorgänger / Verifikation |
| --- | --- | --- |
| **M0** – Inventar/Beweislage | UP-01, QA-02, MGMT-03; ausgeführte vs. nur registrierte Tests erfassen | Prüfen: `a7ab5b40`, offene PRs, exakte Build-/Testlogs |
| **M1** – Vorbereitete Tests sicher übernehmen | PR #14 und #16 vor dem gemeinsamen Volltest in `bugfix/v5.2` integriert; BUILD-01, PKG-01, WIC-01/WIC-04/WIC-05 weiter prüfen | Die Integration ist kein Abnahme-PASS; vollständige MSVC-/GUI-/Setup-Ausführung auf einheitlichem SHA erforderlich |
| **M2** – Datenintegrität und Plugin-Operationen | UP-02…UP-07, QA-01, WIC-07, FIND-03 | Vollständiges Plugininventar; pro Modul reproduzierbare Matrix |
| **M3** – Originalfunktionen und GUI | A0-01/A0-02, FIND-01/FIND-02/FIND-04/FIND-05, WIC-02…WIC-06 | EFS/32.700/Host nur in geeigneter kontrollierter Umgebung |
| **M4** – CI/Build/Steuerung | BUILD-01/BUILD-02, MGMT-01…MGMT-03, QA-03/QA-04 | Vollständige Testmatrix auf demselben SHA |
| **M5** – Release-Artefakte und Endnutzer-VM | PKG-01…PKG-05; finaler Snapshot A/B und 5.0-Upgrade | Erst nach M1–M4, finaler Source-SHA und SHA-256-Artefakte |
| **M6** – GO/NO-GO | Jede A0–A7-ID mit Beleg oder ausdrücklich akzeptierter Abweichung; signierte/freigegebene Artefakte | `tools/release/Release-5.2-Gates.md`; Entscheidung dokumentieren |

Meilensteine sind Priorisierung, **keine** Erlaubnis zu ungeprüften
Großumbauten oder impliziten Systemeingriffen. Kritische Datenintegritäts-
und Regressionstests haben vor Feature-Ausbau Vorrang.

## 12. Nachweise, Pflege und Abschlussregel

Wenn eine Checkbox einer ID auf **[x]** gesetzt wird, muss **in derselben
ID-Sektion** mindestens eine ausführungsbezogene Nachweiszeile stehen,
damit der automatische Tracker-Vertrag keine unbelegten PASS-Meldungen
akzeptiert. Das maschinenprüfbare Format ist:

    - **Nachweis:** SHA=0123456789abcdef0123456789abcdef01234567; Test=manage.cmd --test-all; Log=logs/actual-run.log

Das Beispiel ist **kein echtes Testergebnis** und darf nicht als Beleg
übernommen werden. Die Felder müssen auf den **wirklich ausgeführten**
Test und dessen belegten Quellstand verweisen; relevante Umgebung, Ergebnis
und Risiken stehen ergänzend in der untenstehenden Tabelle.

Für jede abgeschlossene ID den folgenden **Belegblock** eintragen; ohne
Beleg verbleibt sie offen:

| Feld | Pflichtinhalt |
| --- | --- |
| ID / Anforderung | z. B. UP-04 / A1+A2 |
| Status / Datum | BESTANDEN am YYYY-MM-DD oder BLOCKIERT + Ursache |
| Commit und Binäridentität | vollständiger SHA; Build-Konfiguration/Architektur; ggf. Binärhash |
| Umgebung | OS-Build, Locale/ACP, VS-/SDK-Version, Dateisystem und Flags |
| Ausführung | vollständiger CLI-Aufruf, Testfallnamen, Positiv-/Negativfälle |
| Ergebnis | tatsächlicher Exitcode, PASS/FAIL/SKIP-Grund, beobachtete Werte |
| Belege | Log-/CI-Run-ID, Hashes, Screenshots, kontrollierte Fixture |
| Residualrisiko / Folge-ID | nicht getestete Grenzfälle und nächste konkrete Maßnahme |

**Vorgehen bei jeder Folgeaufgabe:**

1. Dokument und Originalanforderungen lesen; betroffene IDs nennen.
2. Produktcode, Tests, Aufrufstellen und offene PRs **aktuell** prüfen;
   der Stand vom 23.11.2026 ist nur ein Snapshot.
3. Erst reproduzierenden RED-Test, dann kleinen Fix, GREEN, Regressionen,
   Review und sichere Integration; tatsächliche Ausführung belegen.
4. IDs, Status, Nachweise und Abhängigkeiten **im selben PR/Commit**
   aktualisieren; bei neu entdeckter Lücke neue dauerhafte ID anlegen.
5. Nach erfolgreichem Volltest einen eindeutigen grünen Baseline-Commit
   sichern; ein Dokumentationscommit selbst ist **kein** neuer Testbeleg.
6. Erst wenn sämtliche zutreffenden Release-Gates und die Endnutzer-VM
   belegt sind, Release-Freigabe erwägen; ansonsten **NO-GO** dokumentieren.

**Wichtig:** Dieser Katalog ist ein lebendes Repository-Dokument, keine
automatisch laufende Prüfung. Nachfolgende ChatGPT-/Codex-Sitzungen müssen
das aktuelle Dokument über das GitHub-Repository lesen. Verlinkung in
`AGENTS.md` und `README.md` erleichtert das Auffinden; sie ersetzt
weder Projektzugriff noch eine explizite Berechtigung für Systemeingriffe.
