# Salamander 5.2 – Unicode-/Langpfad-Migrationspriorität der Plugins

Stand: 24.11.2026. Analysierter Quell-HEAD `320b26f376ef07fce71fc265f7f263471c675ed6` (`bugfix/v5.2`). Planungsanalyse für A1/A2, UP-01/02/03, WIC-07, QA-01; keine Implementierung, kein neuer Windows-Test, kein Gap-Abschluss.

## Methode und Grenzen

Vollständigen rekursiven Git-Baum (nicht abgeschnitten), alle 36 Plugin-Quellordner, 35 Hauptprojekte, gezielte implementierungsrelevante Quellstichproben pro Plugin, SDK-Header und vorhandene Dokumentation/Testnachweise verglichen. Keine vollständige Zeile-für-Zeile- oder Call-Graph-Prüfung; keine gemessenen Personenstunden. KiB = gerundete Git-Blob-Bytes aller .cpp/.c/.h/.hpp/.cxx/.pas unter Modulordner inklusive eingebetteter Fremd-/Altquellen, nicht effektive Build-LOC. Die Stufe 5 (sehr groß) bis 1 (klein) ist eine relative Schätzung des pluginspezifischen Restaufwands bei verfügbarer gemeinsamer W-SDK-Infrastruktur; Reihenfolge innerhalb einer Stufe unsicher. Risiko umfasst Datenverlust und Abhängigkeits-/Testbarkeit, nicht nur Aufwand. Keine pauschale Änderung von Dateiformat- oder Protokollkodierungen. SDK 103, bestehende UI/Steuerung, ABI und CFileData-Layout erhalten. Native W-Pfade können nicht aus bereits verlustbehafteten ANSI-Strings rekonstruiert werden.

## Rangfolge der 35 gebauten Plugins

| Rang | Plugin | Aufwand (1–5) | Quell-KiB | Risiko | Hauptaufwand | Quellstichprobe relativ zu src/plugins/<Modul>/ | Zentraler Test |
| ---: | --- | ---: | ---: | --- | --- | --- | --- |
| 1 | ftp | 5 | 4681 | Sehr hoch | Remote-/lokale Pfade, FTP-Serverkodierung, Queue, Resume, Konflikte | fs2.cpp; operats1.cpp | UTF-8/Legacy-Server, Upload/Download/Move, Abbruch und Wiederaufnahme |
| 2 | zip | 5 | 1147 | Sehr hoch | Eigenes Archivformat, Update/Delete, SFX, Mehrteilarchive, ANSI-Puffer | add.cpp; extract.cpp | UTF-8-Flag/Legacy-Namen, Pack/Extract/Update, SFX, Traversal |
| 3 | automation | 5 | 386 | Hoch | COM-BSTR zu ANSI-SDK, Panel-/Itemobjekte, Skriptverträge | panelaut.cpp; itemaut.cpp; salamanderaut.cpp | Bestehende Skripte, BSTR-Roundtrip, Panel- und Dateioperationen |
| 4 | 7zip | 5 | 3922 | Sehr hoch | Unicode-fähige interne Strings werden an SDK-Grenze zu ANSI; viele Formate | 7zclient.cpp; extract.cpp | Archivnamen, mehrere Formate, Update, Passwörter, Extraktion |
| 5 | renamer | 5 | 359 | Sehr hoch | Regex, Masken, Vorschau, Namenskollisionen, Batch-Rename | crenamer.cpp | Emoji/Surrogates, Regex, Kollisions-/Teilfehler, Identität |
| 6 | undelete | 5 | 516 | Sehr hoch | Rohdatenträger, FAT/NTFS, Wiederherstellung mit exakter Zielidentität | restore.cpp | Verlorene Namen, Wiederherstellung, kein Überschreiben, Test-Images |
| 7 | regedt | 4 | 360 | Hoch | Registry-W-API vorhanden, aber ANSI-FS-Namen, Suche, Export | fs.cpp; fs3.cpp | Unicode-Schlüssel/-Werte, Import/Export, Suche in isoliertem Hive |
| 8 | portables | 4 | 336 | Hoch | WPD-COM/Object-IDs, Gerätepfade, lokale Transfers und SDK | wpdfscontentlevel.cpp; wpdfs.cpp | MTP-Gerät, Namensduplikate, Disconnect, Copy/Move |
| 9 | wmobile | 4 | 253 | Hoch / abhängig | RAPI-Altgeräte, feste W-Puffer und ACP-Konvertierung | fs1.cpp; rapi.cpp | Kompatible RAPI-Testumgebung, lokale/Remote-Pfade |
| 10 | unrar | 4 | 104 | Hoch / abhängig | Dynamisch geladene unrar.dll, vorhandene W-Felder werden nicht durchgängig genutzt | unrar.cpp; unrardll.h | Verfügbare lizenzkonforme Engine, RAR4/5, Unicode, Passwörter |
| 11 | pictview | 4 | 1360 | Hoch | Nativer WIC-Pfad bereits W; Legacy-Viewer/Thumbnail-SDK, Export und Restfunktionen | pictview.cpp; WicImageDecoder.cpp (Dokumentation) | F3, Thumbnails, Unicode-/UNC-Bilder, Export |
| 12 | uniso | 4 | 327 | Hoch | ISO/Joliet/UDF/HFS und weitere Imageformate, unterschiedliche Namensräume | file.cpp; Formatdateien im Baum | Image-Öffnen, Unicode-Namen, sichere Extraktion |
| 13 | demoplug | 4 | 380 | Hoch | SDK-Referenz für FS, Archiv, Viewer, Thumbnail, Menü | fs1.cpp; weitere Dateistruktur | Alle Beispieloperationen und SDK-Rückwärtskompatibilität |
| 14 | filecomp | 4 | 561 | Mittel–hoch | Zwei Panelpfade, Remote-Helfer, Worker, Unicode-Inhalt getrennt vom Dateinamen | filecomp.cpp; filemap.cpp | Zwei lange Unicode-Pfade, Text/Binärvergleich, Remote-Aufruf |
| 15 | nethood | 4 | 292 | Mittel–hoch | UNC, Netzwerkressourcen, Authentifizierung, Cache und Shell | nethoodfs.cpp | Nicht-ACP-Server/Share, Offline, Credentials, Navigation |
| 16 | diskmap | 3 | 339 | Mittel–hoch | Rekursive Dateibaumaufnahme, Pfadgrenzen und Rücknavigation | DiskMapPlugin/DiskMapPlugin.cpp; DiskMap/TreeMap.FileData.CZDirectory.cpp | Tiefe Bäume, Junctions, Abbruch, Fokus auf exakte Zeile |
| 17 | tar | 3 | 341 | Hoch | Archiv-/Kompressionsfamilie, Header-Namenskonventionen, ANSI-Dateiöffnung | fileio.cpp; Formatverzeichnisse | PAX/GNU/Legacy-Header, Unicode-Extraktion |
| 18 | uncab | 3 | 80 | Mittel–hoch | FDI-Callback-API mit schmalen Pfaden und mehrteiligen CABs | uncab.cpp | CAB-Extraktion, Callback-Bridge, Folgebände |
| 19 | pak | 3 | 99 | Mittel–hoch | Archivpfade und begrenzte Formatnamen, Schreiben/Extrahieren | spl/pak.cpp | Formatlimits ohne Verlust, Pack/Extract, Kollisionen |
| 20 | unarj | 3 | 117 | Mittel | Altes Archivformat, Extraktionspfade und Volumes | unarjspl.cpp | ARJ-Namenskodierung, mehrteilige Archive, Kollisionen |
| 21 | unlha | 3 | 85 | Mittel | LHA/LZH-Header, alte Kodierungen, feste Zielpuffer | unlha.cpp | Japanische/Legacy-Namen, Unicode-Ziel, Traversal |
| 22 | unfat | 3 | 69 | Mittel | FAT-Images, LFN/OEM-Namen, feste Extraktionspuffer | unfat.cpp | LFN/8.3-Kollisionen, Image- und Zielpfade |
| 23 | ieviewer | 3 | 683 | Mittel | WebBrowser-COM, file-URLs, Markdown-fopen und Tempdateien | ieviewer.cpp; markdown.cpp | Unicode/Longpath HTML/Markdown, relative Ressourcen |
| 24 | mmviewer | 3 | 720 | Mittel | Mehrere Medienparser und Metadatenkodierungen, Datei-/Exportpfade | mmviewer.cpp | Alle Parserformate, Unicode-Name, HTML/XML-Export |
| 25 | dbviewer | 3 | 287 | Mittel | CSV/DBF-Parser, Dateiöffnen und Export, getrennte Datenkodierung | dbviewer.cpp | CSV/DBF öffnen, Unicode-Pfade und Zeichensatz unverändert |
| 26 | folders | 3 | 59 | Mittel | Shell-PIDL/StrRetToBuf, virtuelle Baumansicht | fs1.cpp; fs2.cpp | Shell-Ordner, UNC, Navigation und Fokus |
| 27 | unchm | 2 | 141 | Mittel | CHM-Bibliothek, Dateiname, Archivinterne Pfade | chmfile.cpp | Unicode-CHM, interne Namen, Zielpfad |
| 28 | unmime | 2 | 115 | Mittel | MIME-Parser und Attachment-Namen/Kodierung, Extraktion | unmime.cpp | RFC-kodierte Namen, Kollisions-/Traversal-Schutz |
| 29 | unole | 2 | 26 | Mittel | Structured Storage liefert W-Namen, ACP-Konvertierung am Listing | unole2.cpp | W-Stream-/Storage-Namen, Extraktion |
| 30 | splitcbn | 2 | 94 | Mittel | Teil-/Zieldateinamen, SafeFile, Split/Combine | split.cpp | Lange Teilpfade, bytegenaue Rekombination, Abbruch |
| 31 | checksum | 2 | 316 | Niedrig–mittel | Hash-Algorithmen weitgehend pfadunabhängig; Datei- und Prüfsummenlisten | checksum.cpp; misc.cpp | Unicode-Dateien, Prüfsummen-Manifest, Verify |
| 32 | peviewer | 2 | 152 | Niedrig–mittel | Dateiöffnung und Mapping, PE-Parser getrennt vom Dateinamen | peviewer.cpp; pefile.cpp | PE über lange W-Pfade, Ressourcenanzeige, Tempdatei |
| 33 | demoview | 2 | 73 | Niedrig–mittel | Viewer-Pfade, DragDrop, Dateidialoge und Thumbnail-Beispiel | viewer.cpp | F3/Drop/Thumbnail und Dialogpfad |
| 34 | checkver | 1 | 128 | Niedrig | Modul-/Hilfsdateipfade, WinInet; kaum Nutzdateioperationen | checkver.cpp; internet.cpp | Unicode-Installationspfad, Updateabfrage |
| 35 | demomenu | 1 | 12 | Niedrig | Kleines Menübeispiel; vor allem SDK-Hostgrenze | menu.cpp; demomenu.cpp | Menüaufruf und Auswahlidentität |

**Sonderfall WinSCP:** 228 C/C++/Pascal-Dateien, ca. 3818 KiB; im aktuellen Baum kein aktives Haupt-vcxproj und kein SPL im letzten Paket. `winscp/salamander/FileSystem.cpp` und `winscp/core/SftpFileSystem.cpp` verwenden umfangreich AnsiString und explizite UTF-Konvertierung. Wiederinbetriebnahme der Altintegration, Toolchain und Abhängigkeiten wäre ein eigener sehr großer Auftrag, möglicherweise größer als FTP. Kein Ausbau-/Entfernungsauftrag abgeleitet. `shared` ist SDK und kein Plugin.

## Gemeinsame Vorleistung und Umsetzung

- `src/plugins/shared/spl_gen.h`, `spl_fs.h`, `spl_arc.h`, `spl_view.h`, `spl_file.h`: bestehende char*-Verträge, teils MAX_PATH-Aufruferpuffer, keine inkompatible Änderung vorhandener VTables. Kompatibel ausgehandelte W-Erweiterungen mit expliziter Länge/Ownership und exakter Panel-/Archiv-/FS-Identität; W-SafeFile und dynamische Pfade, format-/protokollspezifische Kodierung separat behandeln. Sichere Ablehnung alter Plugins ist kein vollständiger A1/A2-PASS.
- Empfohlene Umsetzung, nicht identisch mit Aufwandsrangfolge: gemeinsamer SDK-W-Prototyp mit demomenu/demoview/checksum/peviewer (Menü/Viewer/SafeFile); anschließend splitcbn/filecomp/renamer (Schreib-/Batchoperationen); parallel technische Abhängigkeitsprüfung von unrar/wmobile/winscp und WIC-Host; danach Archiv-Familien, virtuelle FS und FTP/Automation. Priorität für Datenintegrität, keine pauschale Neuimplementierung.
- Letzte echte Belege: `aae7e76c` --test-all 109/0/32; `28c18a48` --build-clean --test --setup PASS, 35 SPLs und 40 Sidecars je Variante SHA256-identisch; ältere Host-Smokes für 7zip/checksum/filecomp/renamer (Laden) und pictview (sechs F3-Formate). Keine Plugin-End-to-End-UTF16-/Langpfad-Vollabnahme. WIC native x86/x64 bereits grün; ABI-/Staging-PASS kein Funktionsnachweis. UnRAR lädt im analysierten Code unrar.dll, setzt ArcNameW=NULL und konvertiert FileNameW zu ACP; Runtime-/Lizenzkonformität und funktionsfähiger Ersatz offen. WMobile RAPI-Umgebung und WinSCP Wiederinbetriebnahme ungeklärt.
- Nächster fachlicher Schritt: vorhandene Plugin-Operationsmatrix pro Modul um echte Anwendbarkeit und RED/GREEN-Fälle erweitern; erst gemeinsame Schnittstellendesigns prüfen, dann konkrete Änderungen nach A8. Aktueller operativer Release-Schritt bleibt Manifest-/Paket-/VM-Validierung. Keine Freigabe.
