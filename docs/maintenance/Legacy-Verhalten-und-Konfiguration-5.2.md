# A0-01 / A0-02 – Legacy-Verhalten und Konfigurationsmigration

**Status:** TEILBELEGT · **Referenz-Quellstand:** `a7ab5b40d859509ffe5fead2d8f00739399a5067` · **23.11.2026**

Dieses Inventar charakterisiert die **aktuell sichtbaren Verträge** und
vergleicht deklarierte Ressourcen mit dem ursprünglichen GitHub-5.0-Quellstand
`3945ecf7a655b2dbb0a50e189a2682e1e336352e` (Initial-Commit 2023-12-04;
`spl_vers.h` nennt Produktversion 5.0). Dies ist **kein Beleg vollständiger
GUI- oder Funktionsgleichheit mit einer ausgeführten Original-5.0-Version**.
Die ursprüngliche 5.0-Binärversion und ihre Laufzeitinteraktionen müssen
für A0-01 auf einer getrennten Testumgebung vermessen werden. Bestehende
Benutzeroberfläche und Shortcuts dürfen nicht ungefragt verändert werden.

## A0-01: Aktueller UI-/Funktionsbestand und Testbelege

| Bereich / Vertrag | Aktuelle Quellen | Automatisierter Nachweis im grünen Referenzstand | Noch offen |
| --- | --- | --- | --- |
| Panels: F5 Kopieren, F6 Verschieben, F8 Löschen, F2 Umbenennen | `src/salamand.rc`, `src/fileswn8.cpp` | GUI-Regressionsszenarien in `Test-SalamanderGui-LongPaths.ps1`, einschließlich 263-UTF-16-Gesamtpfad und F6 >17 MiB | Vollständige Eingabematrix, Altverhalten und alle Plugins |
| Panel-/Dateimasken, Sortierung, Hot Paths, Dateiansicht | `src/lang/lang.rc`, `src/lang/lang.rh`, Panel-Code | Einzelne GUI-Baselines/Unicode- und Pfadtests | Vollständige Menüs, Einstellungen, Mouse/Keyboard und Verhalten mit 5.0 vergleichen |
| Originalsuche Strg+F, Alt+F7, Advanced, Regex, Ignore, Duplicate, Resultataktionen | `src/lang/lang.rc: IDD_FIND, IDD_FINDADVANCED, IDD_FINDIGNORE`, `src/finddlg*.cpp`, `src/salamand.rc` | `Test-LegacyFind-UiContract.ps1` und 36 isolierte GUI-Szenarien je Release/Debug x64 | `FIND-01`/02/03 und Alt-UI-Vergleich aller kombinierbaren Optionen |
| Konfiguration/Plugins/Archiver, Viewer, Editor | `src/lang/lang.rc` (Konfigurationsdialoge), `src/mainwnd2.cpp` | Einzelne Konfigurations- und Pluginkontrakte | Persistenz-/Einstellungsvergleich jeder 5.0-Seite, Plugin-/Archiv-Einstellungen |
| PictView/F3, WIC, Navigation, Transform/Export | `src/plugins/pictview/`, `docs/pictview-wic-migration.md` | Native WIC-Tests und ein früherer realer BMP-F3-Host-Smoketest | **Historische Funktionen fehlen im Produkt** (u. a. zeitgesteuertes GIF, Bearbeitung/Undo, Capture/Print, alte Menüs); `WIC-02`…07 |
| Viewer/Editor/Shell, Clipboard, Papierkorb | `src/mainwnd*.cpp`, `src/fileswn*.cpp` | Diverse GUI-Kern- und Clipboard-/Unicode-Tests | Alle Modalfehler, Shell-Umgebungen, externe Handler, Originalverhalten |
| Locale, Skalierung, High-DPI, Barrierefreiheit | Win32-Dialogressourcen/GUI | Teilweise Ressourcen-/GUI-Verträge | DPI-/Sprach-/Tastaturnavigation, Focus/Screenreader, `QA-04` |

**Statischer Originalquellenvergleich (5.0 → 5.2):**
- `src/lang/lang.rc`: alle 107 Dialogdefinitionen einschließlich ihres
  übrigen Ressourcenquelltextes sind bytegleich nach Abzug des zusätzlichen
  UTF-8-BOM der 5.2-Datei; kein Dialog-Text-/Layout-Unterschied im
  verglichenen `.rc` nachweisbar.
- `src/lang/lang.rh`: identisches Git-Blob (`b3deae919240047f9def59238b7edc88b75644de`);
  die numerischen Ressourcen-IDs sind unverändert.
- `src/salamand.rc`: alle 89 ursprünglichen Accelerator-Zeilen bleiben
  erhalten (einschließlich eines im Original wiederholten F4-Eintrags).
  Ausschließlich `Alt+Shift+F7 → CM_FINDUNICODEFILE` kam hinzu; vier
  Acceleratorgruppen und die beiden bereits vorhandenen Dialogressourcen
  bleiben erhalten.
- `src/plugins/pictview/pictview.rc` und `.rh`: identische Git-Blobs.
  Daraus folgt **nicht** PictView-Laufzeitparität; die WIC-Migration hat
  nachweislich andere und derzeit fehlende Funktionen (WIC-06).
- Die 89 Original-Bindings sind als überprüfbare Multimenge in
  `tools/release/ui-resource-inventory-baseline.json` verankert.
  `Test-LegacyUiSurfaceInventory.ps1` erkennt auch den absichtlichen
  Testfall „F5 Copy-Binding entfernt“. Diese Tests **wurden noch nicht
  unter PowerShell/Windows ausgeführt**.

**Ressourceninventar am betrachteten Stand:** `src/lang/lang.rc`
enthält **107** explizite `IDD_...`-Dialogdefinitionen;
`src/salamand.rc` enthält **4** `IDA_...`-Acceleratorgruppen.
Dies sind **Quellinventarzahlen**, keine 107 bestandenen Tests und kein
Vergleich mit 5.0. Sie können sich bei bewusst genehmigten Änderungen
erhöhen; nicht jede Definition ist zwingend im Produkt erreichbar.

### Noch zu erzeugende Vergleichsbelege

1. **Getrennte 5.0-Referenz:** SHA oder signiertes Originalartefakt, Hash,
   Lizenz-/Herkunftsnachweis, OS-/Locale-/DPI-Bedingungen festhalten.
2. **UI-Matrix ausführen:** Erreichbare Haupt-/Kontext-/Plugin-Menüs,
   Dialoge, Beschriftungen, Tastenkürzel, Tabs, Fokus und relevante
   Fehlerdialoge auf 5.0 und 5.2 erfassen (Screenshots/Bedienprotokolle).
3. **Jede Abweichung klassifizieren:** beabsichtigte 5.2-Erweiterung,
   alter bereits vorhandener Unterschied, Defekt oder A0-Vertragsbruch.
4. **Nachweis aktualisieren:** Automatisierte GUI-Charakterisierung
   ergänzen, alle positiven und negativen Fälle auf derselben SHA ausführen.
   Ein statischer Ressourcenvergleich allein reicht nicht.

## A0-02: Konfigurations- und Registry-Verträge

| Vertrag | Verifizierte Quelle/Test | Noch auszuführen |
| --- | --- | --- |
| Produktversion 5.2 hat eigene Konfigurationswurzel, 5.0 bleibt separat | `src/mainwnd2.cpp`: `THIS_CONFIG_VERSION=105`, `SalamanderConfigurationRoots` (5.2 vor 5.0). `Test-ProductVersion.ps1` sichert den Quellvertrag ab | Sauberer 5.0-Benutzerzustand, echter Migrationstest, erneuter Start |
| Originale Version-5.0-Daten nicht überschreiben/löschen | Quellvertrag für getrennte Wurzeln; neuer GUID-isolierter 5.0-Registry-Canary mit vollständigem Schlüssel-/Typ-/Wert-SHA-256 vor/nach echtem 5.2-Start in der Legacy-Find-Baseline (noch nicht ausgeführt) | Echter 5.0-Bestand, Migration/Import, Rollback und Neustart 5.0 separat in VM prüfen |
| Unicode-Historien, Find-Optionen, Plugin-Konfiguration | `LegacyFind-GuiCases.ps1` (`UnicodeSettingsStorage`) und Plugin-Konfigurationsquelle | Kombinationen, Mehrfachstart, Fehler-/Abbruchfall der Migration |
| Installations-/Deinstallationsverhalten | `tools/release/Release-5.2-Gates.md` | Getrennte saubere Windows-11-Snapshots gemäß PKG-04 |

### Neuer isolierter A0-02-Regressionstest (vorbereitet, nicht ausgeführt)

`LegacyConfig-Canary.ps1` erzeugt unter
`HKCU\Software\Open Salamander\CodexTests\<GUID>\Config1`
eine synthetische Konfiguration mit **Original-Version 104** sowie
Unicode- und binären Werten. Das Modul bildet daraus einen SHA-256-
Fingerabdruck **aller** Schlüssel, Wertnamen, Typen und Inhalte;
neue/gelöschte Schlüssel und Änderungen werden erkannt.

`Test-LegacyConfig-Canary.ps1` führt negative Registry-Fixtures aus:
ungültiger Zielroot, wiederholtes Seeding, geänderte Unicode-/Binärdaten,
neu hinzugefügter Schlüssel, **vollständig gelöschter alter Root** und
falsche 5.2-Versionsnummer. Es räumt
ausschließlich seinen GUID-eigenen Root ab und ist durch `manage.cmd --test`
registriert.

Im realen, bestehenden `LegacyFindScenario=Baseline` wird der alte
`Config1`-Snapshot **vor** dem Start der isolierten 5.2-GUI erzeugt und
**nach** der vollständigen Upgrade-/GUI-Bereitschaft mit dem
vorherigen Fingerabdruck verglichen. Außerdem muss der neue `Config0`
die **Versionsnummer 105** haben. Der ursprüngliche Registry-Root
der installierten Version 5.0 wird **nie gelesen oder beschrieben**.

### Separat offener Löschpfad beim echten Konfigurationsimport

Der aktuelle Produktcode `src/mainwnd2.cpp`,
`CMainWindow::DeleteOldConfigurations`, kann einen als zu löschend
ausgewählten alten Registry-Root entfernen. Zusätzlich kann der
`autoImportConfig`-Pfad den importierten Original-Root löschen, wenn
`doNotDeleteImportedCfg` nicht gesetzt ist. Die Aufrufstelle befindet
sich in `src/salamdr1.cpp`, unmittelbar nach `SaveConfig()`.

Das ist **nicht** durch den neuen `Config0`-vorhanden-Canary-Test
abgedeckt, weil `FindLatestConfiguration` bei vorhandenem
`Config0\Configuration` bereits vor dem Import älterer Roots zurückkehrt.
Für die verbindliche Release-Abnahme („5.0-Konfiguration erhalten“)
muss in einem **separaten VM-Snapshot** die echte 5.0→5.2-Importentscheidung
einschließlich des Löschpfads und des Neustarts von 5.0 geprüft werden.
Eine Änderung der originalen Importdialog- oder Löschsemantik
ohne abgestimmten Kompatibilitätsvertrag wäre ein A0-Risiko.

**Grenze:** Dieser Test beweist nur die Nichtveränderung einer synthetischen
alten Konfiguration beim 5.2-Start. Ein 5.0→5.2-Datenimport, tatsächliche
5.0-Plugin-Einstellungen, 5.0-VM-Neustart und Rollback bleiben
**nicht abgedeckt**; A0-02 ist deshalb weiterhin TEILBELEGT.

**Sicherheitsvorgabe:** Test-Skripte dürfen nie ungefragt die reale
Benutzerkonfiguration `HKCU\Software\Open Salamander\5.0` verändern oder
löschen. Für Tests eine isolierte Benutzerumgebung/Snapshot verwenden und
Originaldaten als Beleg **lesen**, nicht korrigieren. Freigabe ausstehend.

## Arbeiten in Reihenfolge

- [x] Originales 5.0-GitHub-Quellcommit für die oben genannten
  Dialog-/Accelerator-Ressourcen verifiziert (statischer Quellvergleich).
- [ ] Originales 5.0-**Binärartefakt** und die zugehörige
  Benutzerkonfiguration nachweisen und auf isolierter VM bereitstellen
  (A0-01, A0-02).
- [ ] Charakterisierung aller erreichbaren Dialoge/Menüs/Shortcuts gegen
  Originalerwartungen dokumentieren; fehlende automatisierte GUI-Fälle
  ergänzen (A0-01).
- [ ] Test für 5.0→5.2-Migration, Restart, Fehlerpfad und 5.0-Rollback
  mit exportiertem Registry-Vorher-/Nachhervergleich erstellen (A0-02).
- [ ] A0-Abweichungen an PictView als **Produktlücken** behandeln, nicht
  als bestandene oder absichtlich ausgelassene Tests (WIC-06).
- [ ] Pass/Fail/Blocker nur mit Commit-SHA, Windows-Build, Testbefehl,
  OS/Locale, Dateihashes und Protokollen in
  `Testluecken-und-Abnahmeplan-5.2.md` eintragen.

**Ergebnis dieses Inventarisierungsschritts:** Der statische
5.0→5.2-Ressourcenvergleich ist belegt; wichtige Tastenkürzel und
Dialogdeklarationen bleiben erhalten. A0-01/A0-02 verbleiben
**TEILBELEGT**; ein echter 5.0-/5.2-Laufzeit-, Registry- und
Funktionsvergleich wurde noch nicht ausgeführt.
