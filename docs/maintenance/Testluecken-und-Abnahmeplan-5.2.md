# Salamander 5.2 – Testlücken, Nachweise und Abnahmeplan

> **Verbindlicher Arbeitskatalog für offene Qualitäts- und Release-Nachweise**
>
> Stand: **23. November 2026**. Grundlage: `bugfix/v5.2` bei
> `a7ab5b40d859509ffe5fead2d8f00739399a5067`.
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

**Quellen im Repository:** `AGENTS.md`;
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
| Aktueller Referenzstand | `baseline/test-all-pass-2026-11-23-f5-f6` → `a7ab5b40d859509ffe5fead2d8f00739399a5067` | Grüner `--test-all`-Stand laut ausgewertetem Nutzer-Testprotokoll |
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

## Arbeitsfortschritt M0 – erste Teilaufgaben (23. November 2026)

**Arbeitsbranch:** work/test-gap-m0-a0-up01 (auf bugfix/v5.2).
Dies ist **kein** neuer grüner Testreferenzstand.
Es wurden keine GUI-/Win32-Tests für diese neuen Dateien ausgeführt.

- **A0-01, TEILBELEGT:** Neues
  [Legacy-Verhaltens-/Konfigurationsinventar](Legacy-Verhalten-und-Konfiguration-5.2.md)
  ordnet die bestehenden F2/F3/F5/F6/F8-, Ctrl+F-, Plugin- und
  Konfigurationsbelege zu. Eine eigenständige Source-Regression
  (**Test-LegacyUiSurfaceInventory.ps1**) schützt die derzeit **107**
  expliziten Win32-Dialogressourcen und **4** Acceleratorgruppen
  sowie kritische F2–F8-/Find-Kommandos gegen unbemerkten Wegfall.
  Die Referenz ist der *grüne 5.2-Quellstand*, **nicht** eine
  Original-5.0-UI-Vergleichsmessung; A0 bleibt offen.
- **A0-02, TEILBELEGT:** Die nachgewiesenen 5.2-/5.0-Registry-Wurzeln,
  Versionsmigration 105, vorhandenen Quell-/GUI-Tests und die noch
  erforderlichen isolierten 5.0→5.2→5.0-Snapshots sind im
  [Legacy-Verhaltensinventar](Legacy-Verhalten-und-Konfiguration-5.2.md)
  einzeln erfasst. **Kein** echter VM-/Rollback-Test neu ausgeführt.
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

**Nächster Schritt nach dieser Quellbasis:** Neue Regressionen auf
Windows ausführen; anschließend tatsächliche Built-/Staged-/Shipped-SPLs
auf dem **selben** Commit nachweisen, pro Modul Funktionen
und Unicode-/Langpfad-Grenzen klassifizieren.

## 3. A0 – Unveränderte Originalfunktionen und Benutzeroberfläche

### [ ] A0-01 – Vollständiger Legacy-Verhaltenskatalog (**P0**, TEILBELEGT)
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
- **Fälle:** Für jedes betroffene Archiv-/VFS-Plugin Dateien mit Unicode/
  langen Pfaden auflisten, öffnen, packen, entpacken, umbenennen und löschen;
  verschachtelte Archivpfade, Kollisionen, beschädigte Archive, Dateirechte,
  Cancel und Quellwechsel prüfen; Remote-Plugins zusätzlich Offline/Timeout.
- **Abnahme:** Byte-/Namensgleichheit beim Roundtrip, keine Trunkierung,
  keine Fehlzuordnung, keine ungefragte Zielüberschreibung; pro Plugin und
  Operation unabhängige reproduzierbare Protokolle. **Abhängig von:** UP-01.

### [ ] UP-04 – Kopieren/Bewegen über Volume- und Worker-Grenzen (**P0**, TEILBELEGT)
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

### [ ] UP-06 – Shell, Zwischenablage, externe Programme, Dateiattribute (**P1**, OFFEN)
- **Fälle:** Datei-Eigenschaften, Öffnen, Drag/Drop, Viewer/Editor,
  Copy Full Name/Path, Papierkorb, ADS, EFS, ACLs, alternierende
  Unicode-/ANSI-Codepages bei langen Resultaten.
- **Abnahme:** Exakte Identität oder kontrollierte Ablehnung; Rückkehr aus
  Shell/Editor ändert nie eine andere Datei; Originalbytes bei Fehlern
  unverändert. Vorhandene positive Einzeltests nicht doppelt zählen.

### [ ] UP-07 – Pfadgrenzwerte und Dateisystembedingungen (**P1**, TEILBELEGT)
- **Fälle:** 259/260/263, 255-Komponentenlimit, echte 32.700er-Pfade,
  Varianten mit und ohne LongPathsEnabled; NTFS/ReFS/SMB nur soweit
  relevant und tatsächlich vorhanden. UTF-16-Längen statt Codepoints.
- **Abnahme:** Jeder Wert gehört einer klaren positiven/negativen
  Erwartung; bei unmöglicher Fixture dokumentierter Environment-Blocker.
  Der positive 32.700er-GUI-Navigationstest **ersetzt nicht** FIND-01.

## 5. A3 – Vollständiger Visual-Studio-2026-Build

### [ ] BUILD-01 – Komplette Vierfach-Buildmatrix (**P0**, TEILBELEGT)
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
- **Fälle:** Autorisiert auf sauberem Test-Checkout
  `manage.cmd --update --build --test-all --setup`; zusätzlich
  `--build-clean`, Delta/Normal-Build und deren wiederholte Aufrufe.
- **Abnahme:** Eindeutiger Commit vor/nach Update, korrekte Reihenfolge,
  alle Outputs und Fehlercodes, keine nicht autorisierten Änderungen.
  `--update` nur nach ausdrücklicher Zustimmung.

### [ ] MGMT-02 – Fehler- und Isolationsverhalten (**P1**, TEILBELEGT)
- **Fälle:** Vorhandene Salamander-Instanz, gesperrter Desktop, fehlendes
  MSVC/SDK, ungültige Parameter, fehlgeschlagener Worker, Unterbrechung,
  abweichender SHA, verlorenes Plugin; Clipboard/Temp/Registry-Snapshot.
- **Abnahme:** Nonzero-Exit, verständliche Diagnose, keine fremden Prozesse
  beendet, keine unbeabsichtigte Löschung, kontrolliertes Cleanup und
  keine gefälschten PASS-Meldungen.

### [ ] MGMT-03 – Test-Registry gegen unbemerkte Auslassungen (**P2**, OFFEN)
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
  **PR #14** enthält vorbereitete Staging-/Plugin-Inventarprüfungen;
  vor Merge Code-Review, Integration und Windows-Ausführung durchführen.

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
- **Fälle:** Wiederholte paarweise `--diagnose-gui`- und
  `--test-all`-Läufe, Cold/Warm-Start, Fokus, Clipboard,
  Hintergrundthreads/Plugin-Load, Handles/COM/Memory.
- **Abnahme:** Fehlerrate pro Test und reproduzierbarer Fehlerlog;
  Timing-/Retry-Verhalten nicht allein durch längere Timeouts
  kaschieren. Fremde Prozesse nicht beenden.
- **Quelle:** `tools/release/tests/Invoke-GuiReliability.ps1`.

### [ ] QA-04 – Umgebungs-/Locale-Matrix (**P1**, OFFEN)
- **Fälle:** Windows 11 Build, CP1252 und nichtwesteuropäische
  ACP, LongPathsEnabled ein/aus, 100/125/200 %-DPI,
  Netzwerk/Offline, unterstützte Architekturen.
- **Abnahme:** Abweichende Ergebnisse je Umgebung erfasst;
  korrekte UI-Bedienung und Sicherheitsverträge.

## 11. Arbeitsreihenfolge und Meilensteine

| Phase | IDs / Ergebnis | Vorgänger / Verifikation |
| --- | --- | --- |
| **M0** – Inventar/Beweislage | UP-01, QA-02, MGMT-03; ausgeführte vs. nur registrierte Tests erfassen | Prüfen: `a7ab5b40`, offene PRs, exakte Build-/Testlogs |
| **M1** – Vorbereitete Tests sicher übernehmen | PR #14 gegen aktuelles `bugfix/v5.2` prüfen, nötigenfalls Konflikte beheben; BUILD-01, PKG-01, WIC-01/WIC-04/WIC-05; RED/GREEN | Keine automatische Merge-Freigabe ohne tatsächliche MSVC/Windows-Tests |
| **M2** – Datenintegrität und Plugin-Operationen | UP-02…UP-07, QA-01, WIC-07, FIND-03 | Vollständiges Plugininventar; pro Modul reproduzierbare Matrix |
| **M3** – Originalfunktionen und GUI | A0-01/A0-02, FIND-01/FIND-02/FIND-04/FIND-05, WIC-02…WIC-06 | EFS/32.700/Host nur in geeigneter kontrollierter Umgebung |
| **M4** – CI/Build/Steuerung | BUILD-01/BUILD-02, MGMT-01…MGMT-03, QA-03/QA-04 | Vollständige Testmatrix auf demselben SHA |
| **M5** – Release-Artefakte und Endnutzer-VM | PKG-01…PKG-05; finaler Snapshot A/B und 5.0-Upgrade | Erst nach M1–M4, finaler Source-SHA und SHA-256-Artefakte |
| **M6** – GO/NO-GO | Jede A0–A7-ID mit Beleg oder ausdrücklich akzeptierter Abweichung; signierte/freigegebene Artefakte | `tools/release/Release-5.2-Gates.md`; Entscheidung dokumentieren |

Meilensteine sind Priorisierung, **keine** Erlaubnis zu ungeprüften
Großumbauten oder impliziten Systemeingriffen. Kritische Datenintegritäts-
und Regressionstests haben vor Feature-Ausbau Vorrang.

## 12. Nachweise, Pflege und Abschlussregel

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
