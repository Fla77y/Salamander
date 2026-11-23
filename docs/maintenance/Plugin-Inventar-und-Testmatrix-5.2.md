# UP-01 – Plugin-Inventar und End-to-End-Testmatrix

**Stand:** 23.11.2026 · **Referenz:** bugfix/v5.2 bei a7ab5b40d859509ffe5fead2d8f00739399a5067 · **Abnahme:** TEILBELEGT (Quellen), Runtime/Release NICHT GEPRÜFT.

## 1. Tatsächliche Quellbestandsaufnahme

Die Solution **src/vcxproj/salamand.sln** enthält **35** eigenständige Plugin-Projekte (namensgleiches Hauptprojekt im jeweiligen Plugin-Unterordner). Das Verzeichnis **src/plugins** enthält **36** mögliche Plugin-Quellordner ohne das SDK-Verzeichnis shared.

| Quellentyp | Module |
| --- | --- |
| Solution-Plugin-Projekte (35) | 7zip, automation, checksum, checkver, dbviewer, demomenu, demoplug, demoview, diskmap, filecomp, folders, ftp, ieviewer, mmviewer, nethood, pak, peviewer, pictview, portables, regedt, renamer, splitcbn, tar, unarj, uncab, unchm, undelete, unfat, uniso, unlha, unmime, unole, unrar, wmobile, zip |
| Quellordner ohne gleichnamiges Haupt-Plugin-Projekt | **winscp** |
| Kein eigenständiges Plugin | **shared** (SDK) |
| Keine eigenständigen Plugin-Projekte | Sprachprojekte (lang_*), Helper-DLLs/-EXEs wie 7za und exif |

**Erweiterte Quellprüfung (23.11.2026):** Das Inventar verlangt jetzt
nicht nur einen passenden Eintrag in `salamand.sln`, sondern auch die
tatsächlich vorhandene Haupt-`.vcxproj` im erwarteten Plugin-Unterordner.
Eine isolierte Regression löscht testweise eine deklarierte Projektdatei
und muss die Erfassung abbrechen. Die 35 entsprechenden Repository-Pfade
wurden über die GitHub-Dateischnittstelle einzeln als **vorhanden**
bestätigt (Commit `4de015f7117f92fa5da9d1bf8f75753cb17da5fb`).
Das bestätigt noch weder erfolgreiche MSBuild-Kompilierung noch
UTF-16-/Langpfadfunktion oder Release-Plugin-Vollständigkeit.

Die Liste wurde unter **tools/release/plugin-source-inventory-baseline.json** maschinenlesbar versioniert. Änderungen am Projekt- oder Quellverzeichnisbestand werden vom neuen Regressionstest aufgedeckt.

**Grenze:** Ein Quellordner oder eine Projektdatei ist kein Nachweis eines gebauten, ausgelieferten oder funktionierenden Plugins. Der WinSCP-Quellordner ist ein Prüfpunkt, keine Genehmigung, dieses Modul zu entfernen oder zu aktivieren.

## 2. Neuer Inventar- und Operationenreport

**tools/release/Plugin-CoverageInventory.ps1** liest die Solution und alle Plugin-Quellverzeichnisse. Optional erfasst es die im angegebenen Build- und Staging-Baum tatsächlich vorhandenen SPL-Dateien. Unerwartet platzierte oder doppelte Module werden als Fehler behandelt.

Für jedes Modul erzeugt **Get-SalamanderPluginOperationMatrix** zwölf getrennte Arbeitsschlitze:

List, Open, Copy, Move, Rename, Delete, Find, Pack, Extract, View, Thumbnail, Menu.

Solange die echte API-Funktion und der GUI-Aufrufpfad nicht geprüft sind, lauten die Werte bewusst **Applicable=NOT_ASSESSED**, **UnicodeStatus=NOT_TESTED** und **LongPathStatus=NOT_TESTED**. Ein Arbeitsschlitz behauptet nicht, dass das Modul die Operation unterstützt.

Die Erfassung ist nur lesend: kein DLL-Load, keine Registry-Änderung, keine Änderung an Build- oder Quellverzeichnis. Bei explizit angegebenem ReportRoot entstehen **plugins.csv** und **operations.csv** in einem neu angelegten GUID-eigenen Unterverzeichnis.

### Kommando: reines Quellinventar

    pwsh -NoProfile -File .\tools\release\Invoke-PluginCoverageInventory.ps1

### Kommando: Build und Staging vergleichen

Die Pfade aus **einem tatsächlich ausgeführten, aktuellen Build** verwenden, nicht alte Build-Ausgaben als Nachweis annehmen:

    pwsh -NoProfile -File .\tools\release\Invoke-PluginCoverageInventory.ps1 -BuiltDirectory '<frische-Build-Ausgabe>' -StagedDirectory '<frische-Staging-Ausgabe>' -ReportRoot (Join-Path $env:TEMP 'Salamander-Evidence') -RequireMatchingPayloads

**PKG-01 – verschärfter Vorabvertrag (23.11.2026, noch nicht ausgeführt):**
`-RequireMatchingPayloads` weist jetzt auch **zwei leere** SPL-Ausgabebäume
zurück; mindestens ein wirklich gebautes und gestagtes SPL-Paar muss
übereinstimmen. Über `-RequiredShippedModules` können bestimmte erwartete
Module verbindlich vorgegeben werden. Fehlende, veränderte, doppelt
angegebene oder ungültig benannte Pflichtmodule führen zum Abbruch.

Die Paketpipeline ruft die Prüfung **für Debug und Release unmittelbar nach
dem Staging und vor Archiv-/Installer-Erstellung** auf. Gegenwärtige
Mindestmenge, gestützt auf die bereits bestehenden binären Plugin-
Vertragstests: `7zip`, `checksum`, `filecomp`, `renamer`, `pictview`.
Das ist **keine abschließende Positivliste** aller auszuliefernden Plugins.
Beispiel für dieselbe Prüfung außerhalb der Paketpipeline:

```powershell
pwsh -NoProfile -File .\tools\release\Invoke-PluginCoverageInventory.ps1 `
  -BuiltDirectory '<fresh-build-root>' -StagedDirectory '<fresh-stage-root>' `
  -RequireMatchingPayloads `
  -RequiredShippedModules 7zip,checksum,filecomp,renamer,pictview
```

Für leere Bäume, fehlende Pflichtmodule und doppelte Namen existieren neue
synthetische Negativtests. Ein Windows-Ausführungsergebnis dieser neuen
Prüfungen liegt noch nicht vor; die volle 35-Modul-Matrix, Nicht-SPL-Dateien
und die saubere VM bleiben eigenständige offene Gates.

**Vollständigkeits-Gate für die Solution (PKG-01):**
Für die beiden Paketvarianten verlangt das Pipeline-Skript nun
zusätzlich `-RequireSolutionPluginPayloads`. Damit müssen alle
derzeit **35** als Hauptprojekt in der Solution deklarierten
Plugin-SPLs in Build und Stage vorhanden und SHA-256-identisch
sein. Eine in Build *und* Stage fehlende Datei wird nicht länger
mit `NOT_SHIPPED` übersprungen; unbekannte gestagte SPLs ohne
Solution-Zugehörigkeit werden zurückgewiesen. Source-only
`winscp` bleibt unverändert außerhalb dieser Liste, bis es
einen realen Hauptprojekt-/Distributionsvertrag gibt.
Die Zahl 35 wird aus dem jeweiligen Solution-Quellbestand
abgeleitet, nicht in der Paketpipeline hart codiert.
Die zusätzlichen Negativtests sind vorbereitet, **auf diesem
neuen HEAD aber noch nicht unter Windows ausgeführt**.

Der vom Nutzer bereitgestellte grüne Clean-Build-/Testlauf vom
23.11.2026 belegt auf dem **älteren** Commit
`2be91b27032a2f4cb4619a606b42b0af7c8ea6c1` exakt
35 unterschiedliche SPL-Buildausgaben jeweils für Debug und
Release x64. Er enthält keine danach erstellten Änderungen
und keine Ausführung von `--setup`.

**Laufzeitbegleitdateien:** Im strengen Gate werden zusätzlich
alle im Build-Pluginbaum tatsächlich vorhandenen `.dll`-, `.exe`-,
`.slg`- und `.chm`-Dateien im Staging auf Vorhandensein und
bytegleiche SHA-256-Prüfsummen kontrolliert. Zwei neue Testfälle
simulieren eine fehlende Sprachdatei und eine veränderte Hilfs-DLL.
Die nicht aus Build-Ausgaben stammenden statischen Ressourcen
sowie Setup-/Systemabhängigkeiten bleiben separate Prüfpunkte.
**Keine Windows-Verifikation dieser neuen Gate-Version.**

**Zusätzliche SHA-256-Kontrolle:** Bei expliziter Angabe beider Verzeichnisse
berechnet das Inventar für tatsächlich vorhandene SPL-Dateien zwei
SHA-256-Hashes und klassifiziert **MATCH**, **HASH_MISMATCH**,
**MISSING_BUILT**, **MISSING_STAGED** oder **NOT_SHIPPED**.
Mit `-RequireMatchingPayloads` führt bereits ein fehlendes oder
byteverschiedenes Modul zum Fehler. Quellordner ohne gebautes und
gestagtes Modul (z. B. `winscp`) werden als **NOT_SHIPPED** erfasst;
dies ist ausdrücklich keine Bestätigung, dass diese Auslassung
produktfachlich zulässig ist.

Der allgemeine Inventarvergleich erfasst **SPL-Dateien**.
Das zusätzliche strenge Paket-Gate kontrolliert außerdem die tatsächlich
im Build vorhandenen Plugin-Sprachdateien, ausführbaren Hilfsdateien,
DLLs und CHMs. Diese Kontrollen garantieren weiterhin weder
alle außerhalb des Pluginbaums liegenden Ressourcen noch Signaturen,
Redistributionsrechte oder vollständige Clean-VM-Lauffähigkeit;
**PKG-01** bleibt bis zur echten Paket- und VM-Abnahme offen.

**UP-02 – Quellseitige SDK-Exportinventarisierung (vorbereitet):**
Für alle 35 Solution-Plugins wurde eine .def-Datei im Repository
gefunden. 34 liegen direkt unter src/plugins/[Modul]/[Modul].def;
die DiskMap-Definition liegt unter
src/plugins/diskmap/DiskMapPlugin/DiskMapPlugin.def.
Alle sind jetzt durch den erweiterten Test-PluginExport-Parser.ps1
auf die deklarierten SalamanderPluginEntry- und
SalamanderPluginGetReqVer-Namen prüfbar. Der Parser berücksichtigt
sowohl einzeilige Exportdefinitionen als auch herkömmliche EXPORTS-Blöcke
mit Ordinalzahlen, PRIVATE, Kommentaren und Aliasnamen.
Der bisherige x64-Binärtest verwendet jetzt den gemeinsamen Quellparser
und durchläuft alle im angegebenen Build-Verzeichnis tatsächlich gebauten
SPL-Module. Die fünf bisherigen Pflichtmodule bleiben ausdrücklich
verpflichtend. Fremde SPLs ohne deklarierte Solution-Zugehörigkeit
werden nicht als automatisch vertrauenswürdig akzeptiert.
**Diese Ausführung wurde auf dem aktuellen Stand nicht unter Windows
nachgewiesen; die Build-/PE-/Runtime-Matrix aller 35 Module bleibt offen.**
**Keine Aussage über 35 gebaute PE-Exporttabellen oder über die
Unicode-/Langpfadfunktion beziehungsweise den Plugin-Host.**
Die neue PowerShell-Ausführung steht aus.

## 3. Mindestmatrix für jedes ausgelieferte Plugin

| Feld | Benötigter Beleg |
| --- | --- |
| Identität | Projektpfad, gebauter SPL-Pfad, Architektur, vollständiger SHA und Binärhash |
| Funktion | Tatsächlich implementierte SDK-/Host-Operation oder begründetes N/A |
| Unicode | ASCII, CP1252, nicht-ACP/Emoji, Best-Fit-Kollision und unveränderte UTF-16-Identität |
| Langpfad | 259/260/263, >260, Max-Komponente, UNC, erweiterter Pfad, ggf. 32.700 |
| Positive Fälle | Echte Plugin-Operation mit GUID-eigener Fixture, Name und Bytevergleich |
| Negative Fälle | Zielkollision, fehlende Rechte, Defekt, Offline, Lock, Cancel und Cleanup |
| Nachweis | OS-/Locale-/Toolchain-Daten, Testbefehl, Log, PASS/FAIL/BLOCKED und SHA |

**UP-01 ist erst dann abgeschlossen**, wenn der tatsächliche Build-/Release-Bestand abgeglichen und jedes ausgelieferte Plugin nach Funktionen klassifiziert ist. Positive/negative Funktionstests folgen in **UP-02/UP-03**; ein Export-/ABI-Test ersetzt sie nicht.

## 4. Bereits vorhandene und neue Tests

| Quelle | Beweis | Einschränkung |
| --- | --- | --- |
| Test-PluginBinary-Contract.ps1 (grüner Stand) | PE/SDK-ABI für fünf Pflichtmodule | Keine vollständige Modulliste oder Unicode-/Langpfadfunktion |
| Test-PluginModulePaths-Contract.ps1 | Statischer W-Modul-/Sprachpfadvertrag | Kein Plugin-End-to-End |
| **Test-PluginCoverageInventory.ps1 (neu)** | Exakte Quell-/Solution-Baseline, negatives synthetisches SPL-Layout, ungetestete Statuswerte, CSV-Report, bytegenaue SHA-256-Matching-/Tampering-/Missing-Negativfälle | Ausführung unter Windows noch ausstehend |
| [Draft-PR #14](https://github.com/Fla77y/Salamander/pull/14) | Weitere gebaute SPL-ABI-/Staging-Regressionen vorbereitet | Noch nicht gemergt und nicht Windows-verifiziert |
| --test-plugin-load | Opt-in reale Plugin-Host-Initialisierung | Keine Operationenmatrix, nicht in --test-all |

## 5. Konkrete nächsten Schritte

- [ ] Neuen Regressionstest tatsächlich unter Windows ausführen (manage.cmd --test).
- [ ] Quell-, Build-, Staging- und finales Release-Inventar auf demselben Commit aufnehmen.
- [ ] Alle 35 Solution-Plugins und den WinSCP-Quellordner mit tatsächlichen Build-/Versandrollen klassifizieren.
- [ ] Die zwölf Operationsslots je Modul als N/A oder echten Positiv-/Negativtest spezifizieren.
- [ ] Mit PKG-01 jeden gebauten und gestagten SPL-Inhalt bytegenau abgleichen.
- [ ] UP-02/UP-03 nach bestätigter Matrix priorisieren.

**Ergebnis:** Nachvollziehbares Quellinventar und ausführbare Erfassungswerkzeuge sind angelegt. Die vollständige API-/Produktabnahme bleibt offen.
