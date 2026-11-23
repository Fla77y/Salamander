# A0-01 / A0-02 – Legacy-Verhalten und Konfigurationsmigration

**Status:** TEILBELEGT · **Referenz-Quellstand:** `a7ab5b40d859509ffe5fead2d8f00739399a5067` · **23.11.2026**

Dieses Inventar charakterisiert die **aktuell sichtbaren Verträge**; es ist
**kein Beleg vollständiger Gleichheit mit dem Original 5.0**. Die ursprüngliche
5.0-Binärversion und ihre Ressourcen/Interaktionen müssen für A0-01 auf einer
geeigneten, getrennten Testumgebung als Referenz vermessen werden. Bestehende
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
| Originale Version-5.0-Daten nicht überschreiben/löschen | Quellvertrag für eigenständigen 5.2-Root; keine vollständige Registry-Diff-Ausführung | Export **vor/nach** 5.2-Start, Wert-/Typvergleich, Rollback und Neustart 5.0 |
| Unicode-Historien, Find-Optionen, Plugin-Konfiguration | `LegacyFind-GuiCases.ps1` (`UnicodeSettingsStorage`) und Plugin-Konfigurationsquelle | Kombinationen, Mehrfachstart, Fehler-/Abbruchfall der Migration |
| Installations-/Deinstallationsverhalten | `tools/release/Release-5.2-Gates.md` | Getrennte saubere Windows-11-Snapshots gemäß PKG-04 |

**Sicherheitsvorgabe:** Test-Skripte dürfen nie ungefragt die reale
Benutzerkonfiguration `HKCU\Software\Open Salamander\5.0` verändern oder
löschen. Für Tests eine isolierte Benutzerumgebung/Snapshot verwenden und
Originaldaten als Beleg **lesen**, nicht korrigieren. Freigabe ausstehend.

## Arbeiten in Reihenfolge

- [ ] 5.0-Referenzartefakt/-konfiguration nachweisen und auf isolierter VM
  bereitstellen (A0-01, A0-02).
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

**Ergebnis dieses Inventarisierungsschritts:** Belegquellen und bislang
fehlende Referenzszenarien sind nun explizit zugeordnet. A0-01/A0-02
verbleiben **TEILBELEGT**; es gab noch keinen Original-5.0-Vergleich.
