# AGENTS.md — Salamander: verbindliche Arbeitsanweisungen für Codex

> **Geltungsbereich:** Das gesamte Repository `https://github.com/Fla77y/Salamander`,
> einschließlich Hauptprogramm, Plugins, SDK, Build, Tests, Dokumentation und Releases.
> Diese Datei ist eigenständig verwendbar. Sie konsolidiert die bisherige `AGENTS.md`,
> den `Master-Prompt-C++.md` und sämtliche Anforderungen 0–7 aus `Anforderungen.md`.
> Sie ersetzt nicht die Pflicht, den aktuellen Repository-Inhalt zu prüfen.

## Projektweite Testlücken und Arbeitsfortschritt

**Pflichtlektüre bei Test-, Bugfix-, Unicode-/Langpfad-, Plugin-, WIC- und
Release-Aufgaben:** [Testlücken- und Abnahmeplan 5.2](docs/maintenance/Testluecken-und-Abnahmeplan-5.2.md).

- Vor Aufgabenbeginn die **aktuelle** versionierte Datei lesen, betroffene
  Gap-IDs, Prioritäten, Voraussetzungen und Abnahmekriterien ermitteln.
- Nach erledigter Arbeit im selben PR/Commit den Status, ausgeführte
  Positiv-/Negativtests, den genauen Commit und die Nachweise aktualisieren.
- Nicht ausgeführte oder nur statisch geprüfte Tests niemals als PASS
  markieren; fehlende Funktionsparität nicht durch Tests als erfüllt ausgeben.
- Die Liste ergänzt A0–A7 und
  [die Release-Gates](tools/release/Release-5.2-Gates.md), ersetzt sie nicht.
  Für nicht zur Aufgabe gehörige IDs keine ungefragten Codeänderungen
  durchführen.

## 1. Prioritäten und Entscheidungsregeln

1. Beachte die jeweils geltenden übergeordneten Anweisungen, Sicherheitsgrenzen und
   Berechtigungen der Codex-Laufzeit sowie den ausdrücklich autorisierten Auftragsumfang.
2. **Erhalte die unten festgelegten Salamander-Produktanforderungen 0–7.** Keine
   eigenmächtige funktionale Einschränkung oder stillschweigende Abschwächung.
3. Ermittle tatsächliche Projektverträge, Architektur, Abhängigkeiten, Build- und
   Testverfahren anhand der aktuellen Dateien; historische Dokumentation ist nur Indiz.
4. Beachte die C++-/Windows-Qualitätsregeln dieser Datei, soweit sie zur Aufgabe passen.
5. Bei Widersprüchen zwischen Auftrag, Produktanforderung, technischer Machbarkeit,
   Sicherheit und Bestandscode: Konflikt und Konsequenzen offenlegen, risikoarme
   Vorarbeiten fortsetzen und die notwendige Entscheidung einholen. **Keine
   eigenmächtige Umdeutung einer verbindlichen Produktanforderung.**

Qualitätsrangfolge bei technischen Abwägungen: fachliche Korrektheit und Datenintegrität;
Sicherheit und Vermeidung undefinierten Verhaltens; reproduzierbare Nachweise;
Kompatibilität und Vertragstreue; Lesbarkeit; Wartbarkeit; angemessene Architektur;
Performance und Ressourceneffizienz; Erweiterbarkeit bei belegtem Bedarf.
Bestehende Projektkonventionen gelten, sofern sie nicht einem höherrangigen Ziel
widersprechen. Die einfachste korrekt funktionierende Lösung ist vorzuziehen.

## 2. Verbindliche Salamander-Produktanforderungen (0–7)

**A0 — Vollständiger Funktionserhalt und unveränderte Bedienung**

- Entferne, deaktiviere oder ersetze keine Programmteile eigenmächtig durch
  Neuentwicklungen, wenn dadurch Funktionen, Leistungsumfang, Benutzeroberfläche oder
  Bedienabläufe verloren gehen oder verändert werden.
- Erhalte vorhandene Menüs, Dialoge, Shortcuts, Suchoptionen, Filter, Plugins,
  Konfigurationen und sichtbares Verhalten. Technische Modernisierung ist kein
  Freibrief für ein UI-Redesign, eine Funktionsreduktion oder einen Ersatz durch
  eine vermeintlich einfachere Lösung.
- Beabsichtigte Verhaltens-/UI-Änderungen bedürfen eines klaren ausdrücklichen
  Auftrags; vorher Bestand und Auswirkungen durch Tests/vergleichbare Nachweise sichern.

**A1 — Unicode für alle Namen und Pfade**

- Alle Bereiche des Hauptprogramms **und alle Plugins** müssen Dateinamen und Pfade
  mit Unicode-Zeichen korrekt unterstützen; das umfasst Einlesen, Anzeige, Navigation,
  Suche, Vergleiche, Dateioperationen, Archiv-/Plugin-Übergänge und Persistenz.
- Erhalte verlustfrei die ursprüngliche Windows-UTF-16-Dateiidentität; vermeide
  irreversible ANSI-/Codepage-Konvertierungen und nicht eindeutige Ersatznamen.
- Bei Legacy-ANSI-Plugin-APIs gilt gleichzeitig **ABI-Erhalt**: `CFileData`-Layout,
  bestehende binäre Verträge und alte Plugin-Schnittstellen nicht stillschweigend
  ändern. Implementiere nötige Unicode-Erweiterungen mit kompatiblen, expliziten
  Übergängen. Wo das mit einer Legacy-Schnittstelle nicht sicher möglich ist,
  dokumentiere den konkreten Konflikt und fordere eine Architekturentscheidung.

**A2 — Lange Pfade durchgehend, auch in Plugins**

- Prüfe und implementiere durchgängige Unterstützung langer Windows-Pfade in allen
  tatsächlich betroffenen Komponenten, einschließlich Plugin-Dateisystemen, Archiven,
  Suchdialog, Dateioperationen und abhängigen Hilfsprogrammen.
- Teste die End-to-End-Funktion, nicht nur das Vorhandensein von Wide-API-Aufrufen
  oder eines Manifests. Beachte `MAX_PATH`-Altlasten, Komponentenlängen, UNC,
  `\\?\`-Semantik, relative Pfade, Reparse Points und API-/Plugin-Grenzen.
- Gefährliche oder nicht unterstützbare Fälle sicher und verständlich ablehnen,
  statt mit abgeschnittenen oder anders aufgelösten Pfaden fortzufahren.

**A3 — Vollständige Build-Unterstützung mit Visual Studio 2026**

- Der gesamte vorgesehene Build-Prozess muss mit **Visual Studio 2026** funktionieren:
  Hauptprogramm, Plugins, Ressourcen, Tests und Release-Erstellung. Prüfe die
  tatsächlichen Versionen und Konfigurationen im Repository.

**A4 — `manage.cmd` kontinuierlich funktionsfähig halten**

- Berücksichtige bei jeder Änderung am Build-, Test-, Update- oder Paketablauf
  `manage.cmd` und seine Weiterleitungen; pflege relevante Aufrufe/Dokumentation mit.
- Besonders zu erhalten und zu überprüfen: `--update`, `--build`, `--test-all`,
  `--setup`. Ihre beabsichtigte Wirkung und Fehlermeldungen müssen konsistent bleiben.
- Ein rein dokumentarischer oder fachlich unabhängiger Codeauftrag rechtfertigt
  keine unnötige Änderung des Skripts. **Aktualisierung ist keine Zustimmung zu
  automatischem Fetch/Pull oder Installation.**

**A5 — Saubere, vollständige Release-Setups und 7z-Archive**

- Installations-Setups und `.7z`-Release-Pakete enthalten **keine** temporären
  Build-Artefakte, Objektdateien, Caches, Entwicklerlogs oder unnötigen Werkzeuge.
- Sie enthalten gleichzeitig **alle** für den vorgesehenen Betrieb notwendigen
  Binärdateien, Plugins, Ressourcen, Konfigurationen und zulässig verteilbaren
  Laufzeitabhängigkeiten. Lizenz- und Redistribution-Vorgaben beachten.
- Prüfe Paketinhalt gegen eine begründete Positivliste und den tatsächlichen
  Laufzeitbedarf. **Die Funktionsfähigkeit in einer sauberen Windows-11-VM ist
  ein eigenständiges Release-Abnahmekriterium**, nicht durch lokalen Build ersetzbar.
- Debug-Laufzeitkomponenten dürfen nicht ohne Verteilungsrecht ausgeliefert werden.

**A6 — Legacy-Suchdialog (Strg+F) unverändert erhalten und erweitern**

- **Den ursprünglichen Suchdialog nicht durch eine Eigenentwicklung ersetzen.**
  Baue bei Unicode-/Langpfadänderungen auf dem Legacy-Dialog auf.
- Aussehen, Bedienung, Leistungsumfang und `Strg+F`-Verhalten erhalten, einschließlich
  **„Advanced...“**, Suchfilter und **regulärer Ausdrücke** sowie aller weiteren
  tatsächlich vorhandenen Optionen.
- Unicode- und Langpfadfähigkeit vollständig integrieren. Teste einfache und
  erweiterte Suchmodi, Filter, Regex, Ergebnisse, Navigation und Plugin-Fälle;
  ein einfacher Sucherfolg allein belegt die Anforderung nicht.

**A7 — PictView auf WIC, breite Formatunterstützung**

- PictView verwendet **Windows Imaging Component (WIC)**. Proprietäre
  `PVW32Cnv`-Konverter nicht wiederherstellen oder ohne neuen ausdrücklichen
  Auftrag erneut einbinden/verteilen.
- Alle relevanten gängigen Bildformate unterstützen, insbesondere Formate,
  die in Salamanders Viewer-Konfiguration registriert sind. Ermittle die reale
  Format-/Extension-Liste im Repository und gleiche sie mit verfügbaren WIC-Codecs ab.
- Prüfe Decoder-Verfügbarkeit, tatsächliches Laden/Anzeigen und Fehlermeldungen
  über den PictView-Host. Systemabhängige Zusatz-Codecs nicht als überall
  vorhanden voraussetzen; fehlende Abdeckung **nicht** als erfüllt melden.

## 3. Arbeitsautonomie: bis zum überprüften Ergebnis

- Arbeite autorisierte Aufgaben eigenständig **vom Verständnis der Anforderungen
  bis zur Implementation und verfügbaren Verifikation** durch. Unterbrich nicht
  nach Analyse, erstem Patch oder Zwischenstatus und warte nicht auf „Mach weiter“.
- Führe notwendige, sichere Analyse-, Korrektur-, Test- und erneute Korrekturschleifen
  selbstständig aus. Behebe die Ursache statt bloß ein Symptom zu kaschieren.
- Frage nur nach, wenn eine fachlich wesentliche Entscheidung offenbleibt,
  ausdrückliche Genehmigung gebraucht wird oder Ressourcen/Berechtigungen fehlen,
  die eine verantwortbare Fortsetzung unmöglich machen.
- Bei Fehlschlägen Ursache ermitteln und sinnvolle Alternativen prüfen; keine
  endlosen Retries, kein Verschleiern anhaltender Blockaden und kein Überschreiten
  der Genehmigungs- oder Sicherheitsgrenzen.
- Folgeaufgaben außerhalb des autorisierten Änderungsumfangs als Befund notieren,
  nicht eigenmächtig umsetzen. Änderungen proportional zur Aufgabe halten.
- Beende erst mit geprüfter Erfüllung oder dokumentierter konkreter Blockade.
  Ein Zwischenbericht oder eine bloße Implementierung ist **kein** Fertig-Nachweis.

## 4. Repository-Erkundung, Git und Schutz fremder Arbeit

- Zu Beginn relevante `README.md`, Quelltexte, Header, Tests, `.vsconfig`,
  `.vcxproj`, `.props`, `.targets`, `.editorconfig`, `.clang-format`,
  `.gitattributes`, `.github/workflows/` und vorhandene Fach-/Release-Dokumente lesen.
  Nur existierende Dateien untersuchen; keine Build-/Teststruktur erfinden.
- Für anforderungsrelevante Arbeiten die **aktuelle** `Anforderungen.md` im
  Repository prüfen, **falls vorhanden**. Diese `AGENTS.md` enthält A0–A7
  vollständig; das Fehlen einer separaten Datei hebt sie nicht auf.
- Vor dem Ändern `git rev-parse --show-toplevel`, `git branch --show-current`
  und `git status --short` prüfen; danach Diff, Status und unbeabsichtigte Dateien
  kontrollieren. Nutze vorzugsweise den aktiven separaten Git-Worktree.
- Fremde, unversionierte und uncommittete Änderungen niemals verwerfen, ersetzen
  oder ungefragt bereinigen; bei Überschneidung behutsam integrieren oder klären.
- Ohne ausdrücklichen Auftrag: **kein** Commit, Tag, Push, Merge, Rebase,
  Branch-Löschen, Staging, Stash, Reset, Clean oder automatisches Update.
- `.git` darf eine Worktree-Verweisdatei sein. Weder gemeinsame Git-Metadaten
  noch Hooks, Konfiguration oder andere Worktrees beiläufig ändern.
- Früher beobachtet: `core.ignorecase=true`, `core.filemode=false`,
  `core.symlinks=false`, systemweites `core.autocrlf=true`. Erneut prüfen,
  bevor daraus technische Schlüsse gezogen werden. Linux-Annahmen vermeiden.
- `manage.cmd --update` und Paketpipelines mit implizitem Fetch/Pull nicht
  ungefragt ausführen. Für ausdrücklich autorisierte Paketprüfungen ohne
  Repository-Update ggf. `-SkipUpdate` verwenden; `--all` nicht als Dry-Run
  interpretieren. Verhalten am aktuellen Skript nachlesen.

## 5. Tatsächliche Architektur und Toolchain verifizieren

- Salamander ist nach bisheriger Bestandsaufnahme ein nativer C++-/WinAPI-
  Dateimanager **ohne MFC**. Die aktuelle Implementierung ist maßgeblich.
- Relevante Bereiche: `src/` (Kern), `src/common/`, `src/plugins/`,
  `src/plugins/shared/` (SDK), `src/vcxproj/`, `src/lang/`, `translations/`,
  `help/`, `convert/`, `doc/`, `docs/`, `tools/`, `tools/tests/` und
  `tools/release/tests/`. Fehlende Pfade nicht erfinden.
- Prüfe Sprachstandard, MSVC-/MSBuild-Version, Toolset, SDK, `/MD`/`/MDd`
  bzw. `/MT`/`/MTd`, Debug-/Release-Modi, `Win32`/`x64` und weitere tatsächlich
  konfigurierte Plattformen, Präprozessorwerte, Drittbibliotheken und CI.
- Bisher dokumentierte Buildbasis: Windows 11+, Visual Studio 2026,
  MSVC-v143-Toolset 14.44, passende ATL-Komponenten, Windows SDK 10.0.26100,
  Solution `src/vcxproj/salamand.sln`. **Nicht ungeprüft als aktuellen Stand
  behaupten**: Projektdateien und README haben Vorrang.
- Nur nachgewiesen unterstützte C++-Features und Windows-APIs einsetzen. Eine
  SDK-Deklaration garantiert keine Laufzeit-Unterstützung älterer Zielsysteme.
- Vorhandenes MSBuild-/Visual-Studio-System respektieren; keine ungefragte
  Migration zu CMake, fremden Paketmanagern oder neuen Testframeworks.

## 6. Verbindlicher Entwicklungsprozess: Analyse → RED → GREEN → REFACTOR → Prüfung

1. **Analyse:** Auftrag, beobachtbares Verhalten und Akzeptanzkriterien klären;
   Quellen, Header, Call-Sites, Datenflüsse, Zustände, Ownership, Fehlerpfade,
   ABI, Berechtigungen, Tests und Sicherheitsfolgen untersuchen.
2. **RED:** Bei reproduzierbaren Bugs zuerst einen kleinen dauerhaften
   Regressionstest erstellen; bei neuer Funktionalität zuerst positive und
   negative Verhaltenstests; vor riskanten Refactorings Characterization Tests.
   Tatsächlich prüfen, dass der Test **aus dem erwarteten fachlichen Grund**
   fehlschlägt. Ein kaputtes Test-Setup ist kein gültiger RED-Nachweis.
3. **GREEN:** Kleinstmögliche korrekte Änderung erstellen, die den Vertrag
   erfüllt, bestehende Funktionen erhält und relevante Tests bestehen lässt.
4. **REFACTOR:** Nur im begründeten Aufgabenbereich Verständlichkeit und
   Verantwortung verbessern; beobachtbares Verhalten und ABI erhalten; nach
   wesentlichen Schritten relevante Tests wiederholen.
5. **Prüfung:** Geänderte Targets bauen, relevante Tests und Negativfälle
   ausführen, Review und Dokumentation aktualisieren, Diff und Status prüfen.
6. **Abschluss:** Ist ein RED-Test oder Betriebssystem-/GUI-Test objektiv nicht
   ausführbar, Grund dokumentieren und nachvollziehbare Alternative verwenden.
   Fehlende Ausführung niemals durch angenommene Ergebnisse ersetzen.

- Der bestehende Testbestand bleibt maßgeblich. Neue Tests in die vorhandene
  Test-/CI-Infrastruktur integrieren; keine Testframework-Erfindung.
- Risiko- und verhaltensbezogene Tests priorisieren. Coverage ist Hilfsmittel,
  kein alleiniger Qualitätsnachweis. Bei Parsern, Konvertierungen und kritischen
  Komponenten ggf. Fuzzing, Property-/Mutation-Tests, `/analyze`, Sanitizer
  oder andere **tatsächlich verfügbare** Verfahren ergänzen.
- Regressionstests nicht so „reparieren“, dass bestehende Fehler wieder grün
  erscheinen. Tests dürfen keinen ungeplanten realen Benutzerdatenverlust erzeugen.

## 7. Standards für Tests und Verifikation

- Neue oder maßgeblich geänderte Tests klar als **Arrange – Act – Assert (AAA)**
  strukturieren; ggf. Abschnitte `// Arrange`, `// Act`, `// Assert` kennzeichnen.
- Sprechende Namen wie `Operation_WhenCondition_ExpectedBehavior`, jeweils
  ein möglichst kohärentes Verhalten pro Test; mehrere Assertions sind zulässig,
  wenn sie denselben Vertrag absichern.
- Richtwerte: ca. 10–30 Zeilen je Test, anspruchsvollere möglichst <40,
  bei 50–60 Zeilen Aufteilung prüfen; Lesbarkeit ist wichtiger als Grenzwerte.
- Tests unabhängig, deterministisch, mit isolierten temporären Daten und
  kontrolliertem Cleanup. Keine willkürlichen `Sleep`-Annahmen, fragilen
  zeitbasierten Zufallstests, unbegründeten Mocks oder realen Benutzerprofilen.
- Fehler genau am geprüften Aufruf feststellen; bei Win32, `HRESULT`,
  `std::error_code` und Exceptions konkrete Verträge und Fehlerquelle sichern.
- Grenzfälle gezielt prüfen: leere/ungültige Werte, `nullptr`, Größenlimits,
  Integer-Überläufe, ungültige Enumwerte, Mehrfachaufrufe, Reentrancy,
  Teilfehler, Abbruch, Ressourcenfreigabe, Shutdown, ACLs, Plattformen.
- Unicode-/Pfadmatrix nach Bedarf: ASCII, Akzente, CJK, kombinierende Zeichen,
  Nicht-BMP/Surrogatpaare, UNC, sehr lange Pfade und Einzelkomponenten,
  Namens-/Case-Kollisionen, reparse points, Plugin-/Archivpfade, nicht
  darstellbare Legacy-Namen, Verzeichniswechsel und destruktive Dateioperationen.
- Teste sowohl lokale native APIs als auch die relevanten Benutzerabläufe.
  Foundation-/Quelltexttests oder WIC-Codecs allein beweisen keine GUI-
  beziehungsweise Plugin-End-to-End-Funktion.
- Für Nebenläufigkeit deterministische Synchronisation, definierte Cancel-
  und Shutdown-Pfade; keine unkontrollierten Hintergrundprozesse.

## 8. C++-Qualität, Verträge und Architektur

- Entwickle standardkonformes, idiomatisches, **toolchain-kompatibles** C++.
  Gute Kriterien: KISS, SOLID, DRY, YAGNI, hohe Kohäsion, geringe Kopplung,
  klare Ownership, angemessene Kapselung und Trennung von Fachlogik/Win32/UI.
- Vorhandene Architektur respektieren; Patterns wie RAII, Adapter, Facade,
  Strategy, State, Command, Observer, Factory, Pimpl oder Producer/Consumer nur
  bei konkret belegtem Nutzen einsetzen. Kein Overengineering, keine rein
  kosmetischen Abstraktionsschichten oder spekulative Erweiterbarkeit.
- Code-Semantik: Rule of Zero bevorzugen; Rule of Five bei wirklicher
  Ressourcenverwaltung. `const`, `explicit`, `override`, `final`,
  `[[nodiscard]]`, `noexcept`, `constexpr`, Concepts, Ranges und Standardtypen
  nur entsprechend realem Sprachstandard und Vertrag verwenden.
- `std::optional`, `std::expected`, `std::span`, `std::string_view`,
  `std::unique_ptr`, `std::shared_ptr` etc. nur, wenn der Projektstandard
  und die Lebensdauer-/Ownership-Regeln erfüllt sind.
- Bevorzuge passende Standardcontainer, Value Types und klare Typen gegenüber
  Raw-`new`/`delete`, unklaren C-Casts, riskanten Makros und globalem
  veränderbarem Zustand. ABI-erforderliche Low-Level-Techniken dokumentieren.
- Verwende englische C++-Bezeichner. Lokalen Stil und bestehende APIs erhalten.
- Funktionen mit vielen Verantwortungen, tiefen Bedingungen, verdeckten
  Seiteneffekten, unklarer Ownership und etwa 40–60+ Zeilen kritisch prüfen;
  nur auftragsrelevant nach Testabsicherung zerlegen, nicht künstlich atomisieren.
- Keine unbeabsichtigten Änderungen an API, ABI, Datenlayout, Calling Convention,
  CRT-Grenzen, Exceptions, Logging, Fehlercodes, Persistenz oder UI-Verträgen.
- Externe Eingaben an passender Grenze validieren, interne Invarianten
  wohldefiniert halten. `assert` ersetzt keine Release-Validierung.
  Programmierfehler, reguläre Negativergebnisse und technische Fehler trennen.
- Zustandsübergänge, Vor-/Nachbedingungen, Wiederholbarkeit und teilweise
  fehlgeschlagene Operationen explizit behandeln.

## 9. Ownership, Ressourcen, Speicher- und Exception-Sicherheit

- Für jede Ressource Eigentümer, Lebensdauer und korrekte Freigabe definieren:
  Heap, Handles, Registry-Keys, GDI-Objekte, HMODULEs, COM-Objekte,
  Synchronisationsobjekte, Prozesse, Dateien, Callbacks und asynchrone Arbeiten.
- Bevorzuge RAII/Scope Guards und `unique_ptr` für echte exklusive Ownership;
  `shared_ptr` nur bei tatsächlich geteilter Lebensdauer. Rohe Zeiger/Referenzen
  sind ohne expliziten Gegenvertrag nicht besitzend. Dangling Views verhindern.
- Win32-Ressourcen benötigen **API-spezifische** Invalidwerte und Freigaben:
  `CloseHandle` ist nicht universell; z. B. `RegCloseKey`, `DeleteObject`,
  `FreeLibrary`, COM-`Release`/passender Smartpointer verwenden.
- Beachte Copy/Move, C++-Objektmodell, ODR, Aliasing, Alignment, Buffergrößen,
  Narrowing, Integer Overflow, Out-of-Bounds, Double-Free, Use-after-Free,
  Iteratorinvalidierung und falsche CRT-/Allocator-Grenzen.
- Keine absichtliche Undefined Behavior; Compilerwarnungen und statische
  Analyse nicht grundlos unterdrücken. Sanitizer unterstützen Review/Tests,
  ersetzen aber keine korrekte Eigentums-/Lifetime-Analyse.
- Fehler nicht verschlucken; ursprüngliche Ursachen erhalten; sinnvolle
  Basic-/Strong-/No-throw-Garantien wahren, keine unkontrollierten Retry-Schleifen
  und grundsätzlich keine werfenden Destruktoren.
- Exceptions niemals ungeschützt über C-/Win32-Callback-/COM-/DLL-ABI-Grenzen
  propagieren. Nur `noexcept` zusagen, wenn die Garantie wirklich gilt.

## 10. Native Windows-APIs, Unicode, COM und DLL-Grenzen

- Win32-APIs nach ihrer **jeweiligen** Rückgabe-/Fehlersemantik prüfen;
  `GetLastError()` nur wenn zulässig und **unmittelbar nach dem Fehlschlag**
  sichern. `HRESULT` mit `FAILED`/`SUCCEEDED` prüfen, `NTSTATUS` und SEH
  nicht mit gewöhnlichen C++-Fehlermechanismen verwechseln.
- Bevorzuge dokumentierte `W`-Win32-APIs und eindeutige UTF-16-/UTF-8-Grenzen.
  Unicode-Codepoints, UTF-8-Bytes und UTF-16-Code-Units nicht verwechseln;
  Konvertierungen auf Fehler und Rundtrip-Verlust prüfen.
- Windows-Pfade: Drive/UNC, `\\?\`, Case-Sensitivity, Sharing,
  Zugriffsrechte, File-ID, Link/Junction/Reparse Point und TOCTOU behandeln.
  `std::filesystem` nicht als universellen Ersatz spezieller Win32-Semantik
  ansehen. Destruktive Operationen niemals auf verlustbehaftete Aliasnamen
  oder ungesicherte Pfadauflösung stützen.
- COM: `CoInitializeEx`-Modell und `CoUninitialize`-Bilanz, STA/MTA,
  Marshaling, Thread-Affinität, `AddRef`/`Release`, `BSTR`, `VARIANT`,
  `SAFEARRAY`, `HRESULT` und korrekte Freigabe beachten.
- DLL-/Plugin-Grenzen: Exportnamen, ABI, Datenlayout, Calling Convention,
  Allocator-/CRT-Zuordnung, Exceptions, Modul-Lifetime, sichere DLL-Suche.
  `DllMain` minimal halten und Loader-Lock-Beschränkungen respektieren.
- Win32-GUI: Nachrichtenpumpen, HWND-Lebensdauern, Fokus, Tastaturbedienung,
  DPI, Multimonitor, GDI-Ressourcen und UI-Thread-Affinität berücksichtigen;
  blockierende Arbeit aus dem UI-Thread heraushalten, ohne Bedienung zu ändern.
- Prozesse: `CreateProcessW`-/Argument-Quoting, Arbeitsverzeichnis,
  Umgebung, Exitcode, Handle-Vererbung, Timeouts und Shutdown korrekt behandeln.
  Keine unkontrollierte Shell-Ausführung aus untrusted Inputs.
- Nebenläufigkeit: Datenrennen, Lockreihenfolge, Deadlocks, Memory Ordering,
  Reentrancy, Worker-Lifetime, Cancel/Shutdown und COM-Apartments prüfen.
  `std::jthread`, Stop-Tokens, Mutex, Events, Threadpools usw. nur bei
  dokumentierter Toolchain-Unterstützung und fachlicher Eignung verwenden.

## 11. Sicherheit, Persistenz und kontrollierte Testausführung

- Grundsatz **Least Privilege**: keine ungefragten Registry-/Policy-/ACL-/
  Dienst-/Shell-/Defender-/UAC-Änderungen, Windows-Installationen,
  Systemreparaturen oder produktiven Releases. Fehlende Werkzeuge dokumentieren,
  nicht eigenmächtig nachinstallieren oder Schutzmaßnahmen deaktivieren.
- Vor jedem ausführbaren Skript seine Seiteneffekte, Schreibziele und externen
  Programme prüfen. In Tests nur ausdrücklich autorisierte isolierte Testdaten
  ändern. GUI-/Systemtests mit echter Registry, Zwischenablage, Papierkorb,
  Benutzerprofil oder Prozesslandschaft bedürfen passender Genehmigung.
- Keine fremden Salamander-Instanzen beenden; ausschließlich verifizierte,
  selbst gestartete Testprozesse steuern. Hang-Dumps/Logs können sensible
  Daten enthalten und dürfen nicht unkontrolliert geteilt werden.
- Für Löschung, Spiegelung, Massenänderung und Migration: Zielpfade vorab
  absolut auflösen, erwartete Grenzen prüfen, Junction-/Symlink-Angriffe und
  Race Conditions berücksichtigen, sicheren Dry-Run/Backup/Rollback nutzen.
  Keine rekursiven Löschaktionen in mehreren ineinander verschachtelten Shells.
- Prüfe Path Traversal, Command Injection, DLL-Hijacking, Deserialisierung,
  Integer-/Buffer-Fehler, ACLs, Geheimnisse, unsichere Logs, Netzwerk-
  Authentisierung und Ressourcenerschöpfung.
- Persistenz-/Konfigurationsänderungen: Versionsformate, Migrationspfade,
  atomare Ersetzung nur mit tatsächlich garantierter Semantik,
  Interruption/Crash-Konsistenz, Wiederanlauf, 32-/64-Bit-Registry-Views
  und Rückwärtskompatibilität beachten.
- Auf echten Windows-Systemen keine gefährlichen End-to-End-Tests ohne
  Freigabe; für solche Szenarien kontrollierte VM oder isolierte Testumgebung.

## 12. Build, Formatierung und Abhängigkeiten

- `pwsh` (PowerShell 7.4+) für die projektbezogenen Verwaltungsskripte
  verwenden, nicht Windows PowerShell 5.1. Lokale Programme explizit (`.\manage.cmd`)
  starten; Pfade mit Leerzeichen quoten; PowerShell-Pfade nach Möglichkeit
  mit `-LiteralPath` und `Join-Path` behandeln; native Exitcodes unmittelbar prüfen.
- Vorliegende Buildwege laut bisheriger Bestandsaufnahme (aktuelle Skripte prüfen):
  `manage.cmd --build-delta` = inkrementelles Debug/Release x64;
  `--build` = Rebuild mit HTML Help; `--build-clean` = destruktives Löschen
  dedizierter Outputs; `src/vcxproj/rebuild.cmd` = interaktiver Alternativweg.
- Bisherige Ausgabeorte: `D:\Build\OpenSal` für Verwaltung/Logs;
  `OPENSAL_BUILD_DIR` in direkten MSBuild-Projekten mit abschließendem `\`;
  Paketpipeline `-BuildRoot` außerhalb des Repositories. **Worktree-Kollisionen
  und gemeinsam benutzte Ausgabeordner prüfen**, keine generelle Umleitung
  aller Skripte durch eine einzelne Umgebungsvariable unterstellen.
- HTML-Help-Builds können `hhc.exe` benötigen, Paketierung zusätzlich 7-Zip
  und Inno Setup. Ein Paketbuild ist keine Zustimmung zu Installation oder
  Veröffentlichung. `--setup` kann einen erneuten Build auslösen.
- Kodierungen/Zeilenenden vorhandener Dateien erhalten. Laut bisheriger
  Projektkonvention gelten für gepflegte Quellen UTF-8 **mit BOM**, CRLF,
  vier Leerzeichen, Allman-Klammern, keine automatische Include-Sortierung;
  `.editorconfig`, `.clang-format`, `.gitattributes` und
  `normalize_config.json` sind maßgeblich. `.sh`, `.svg`, `.po` können LF
  erfordern. Normierung auf **tatsächliche Dateiregeln** abstimmen.
- `normalize.ps1` nicht pauschal schreibend ausführen; ggf. `-DryRun` und nur
  betroffene Dateien bearbeiten. Vendored-/generierte Dateien nicht beiläufig
  umformatieren oder umcodieren.
- Python-Werkzeuge in `tools/` nutzen laut Projektkontext Python 3.13+,
  `pyproject.toml`, `uv.lock` und `uv`. Vorhandene Umgebung verwenden,
  keine ungefragten Dependency-/Toolchain-Upgrades.
- Reine Kommentar-/Übersetzungsaufträge dürfen ausführbaren Code nicht ändern.

## 13. Projektbezogene Prüfmatrix und Release-Abnahme

- Lies vorhandene Testskripte **vor** Ausführung, insbesondere mögliche
  System-/Clipboard-/Papierkorbwirkungen. Nach bisherigem Stand:
  `manage.cmd --test` = native Regressionen, Datei-/Namensprüfungen und
  Projektverträge; `--test-all` zusätzlich GUI/WIC. Beide erzeugen externe
  Logs und die Verwaltung kann in die Zwischenablage schreiben.
- Native Regressionen: `tools/tests/`; Vertrags-, Paket- und GUI-Tests:
  `tools/release/tests/`; CI-Aufrufe: `.github/workflows/`.
- GUI-Tests benötigen gegebenenfalls interaktiven, entsperrten Windows-Desktop.
  Recycle-Restore, Plugin-Load und PictView-Host sind nach bisherigem Stand
  zusätzliche Opt-in-Prüfungen und **nicht automatisch in `--test-all` enthalten**.
- Für C++-/Projektänderungen betroffene Debug/Release- und x86/x64-Konfigurationen
  prüfen. Nach bisheriger CI: Debug Win32/x64 mit Warnungen als Fehler;
  WIC x86/x64; Verwaltungsbuilds Debug/Release x64. Ein x64-Erfolg ersetzt
  keinen x86-Nachweis.
- Nach Unicode-/Pfadarbeiten Tests für **Hauptprogramm und Plugins**,
  Legacy-Suche inkl. `Advanced...`/Regex, reale Dateioperationen,
  WIC/PictView-Host und relevante negative Sicherheitsfälle kombinieren.
  Ungeprüfte Fälle in einer Anforderungsmatrix offen markieren.
- Für Releases Clean-Build, vollständige geeignete Tests, Build- und
  Laufzeit-Abhängigkeitsprüfung, 7z-/Setup-Inhaltsprüfung, Installieren/Starten/
  Deinstallieren und **Abnahme in sauberer Windows-11-VM** durchführen,
  soweit ausdrücklich freigegeben und möglich. Ein inkrementeller Build
  gilt nicht als Release-Abnahme.
- Bei reinen Dokumentationsänderungen Inhalt, referenzierte Pfade,
  Dateikodierung, Whitespace, Diff und Änderungsumfang prüfen; keine
  unnötigen systemverändernden Builds/GUI-Tests.

## 14. Dokumentation, Reviews, Wartbarkeit und Performance

- Nicht offensichtliche Verträge relevant betroffener APIs, Funktionen,
  Methoden, Konstruktoren, Destruktoren, Callbacks und Testhilfen knapp,
  korrekt und nach Projektstil (ggf. Doxygen-kompatibel) dokumentieren.
  Zweck, Parameter, Wertebereiche, Nullbarkeit, Ownership, Lifetime,
  Fehlersemantik, Threading, Seiteneffekte und Plattformgrenzen nennen,
  sofern relevant. Keine tautologischen Kommentare.
- Dokumentation bei tatsächlichen Vertragsänderungen mitpflegen.
  Kommentare/Bezeichner im C++-Code grundsätzlich Englisch; Antworten Deutsch.
- Review betroffener Bereiche auf Fachlogik, API/ABI, UB, Ownership,
  Error Handling, Unicode/Pfade, Reentrancy, Windows-Sicherheit,
  Tests, Deployment, Lesbarkeit und Wartbarkeit durchführen.
- Befunde einstufen: **BLOCKER**, **HOCH**, **MITTEL**, **NIEDRIG**;
  bestätigte Fehler, plausible Risiken und optionale Verbesserungen trennen.
  Wenn verfügbar Datei, Funktion, Zeile, Auswirkungen, Reproduktion und
  Test-/Korrekturvorschlag nennen. Keine Fundstellen erfinden.
- Performance nur nach Messung und Vergleich bewerten: CPU, Speicher,
  Allokationen, I/O, Lock-Contention, UI-Latenz, Start/Shutdown,
  Datenträger-/Netzwerkzugriffe. Profiler, WPR/WPA, ETW oder Benchmarks
  nur bei Verfügbarkeit und Relevanz einsetzen. Messung ≠ Vermutung.
- Größere Refactorings nur mit vorher gesichertem Verhalten und klarer
  Problembegründung. Benachbarte Risiken erkennen, aber keine großflächigen
  Nebenbei-Umbauten oder ungefragten Formatierungsaktionen durchführen.

## 15. Definition of Done und Pflicht zur wahrheitsgemäßen Berichterstattung

Eine Aufgabe ist erst **vollständig verifiziert**, wenn alle für ihren Umfang
relevanten und in der autorisierten Umgebung ausführbaren Kriterien erfüllt sind:

- Fachliche Anforderungen und **A0–A7** werden nicht verletzt; relevante
  Akzeptanzkriterien sind umgesetzt und ggf. durch neue Tests abgesichert.
- RED→GREEN wurde bei testbaren Änderungen nachgewiesen, betroffene Builds,
  Positiv-/Negativ-/Regressionstests wurden ausgeführt, und passende
  Konfigurationen/Architekturen sind berücksichtigt.
- Sicherheits-, Fehler-, Ownership-, API-/ABI-, Pfad-/Unicode- und
  Ressourcenverträge sind geprüft; erforderliche Dokumentation ist aktuell.
- Keine unbeabsichtigten Dateien/Änderungen; `git diff` und Status kontrolliert.
- Nicht mögliche oder nicht autorisierte Prüfungen sind **konkret** benannt;
  sie dürfen niemals als bestanden gewertet werden.

Statusbegriffe ausdrücklich unterscheiden:

- **Implementiert:** Änderung liegt vor, Verifikation noch nicht vollständig.
- **Statisch geprüft:** Quelltext/Verträge geprüft, aber nicht ausgeführt.
- **Durch Tests verifiziert:** Namentlich aufgeführte Tests tatsächlich bestanden.
- **Vollständig verifiziert:** Alle relevanten, verfügbaren und autorisierten
  Qualitätsprüfungen der konkreten Aufgabe erfolgreich abgeschlossen.
- **Blockiert / offen:** Fehlende Genehmigung, Testumgebung, reproduzierbarer
  Nachweis oder technische Voraussetzung verhindert einen Abschluss.

Abschlussbericht auf **Deutsch**, knapp und nachvollziehbar:

1. Tatsächlich umgesetzte Änderungen und betroffene Dateien.
2. Bei Bugfixes Ursache, Reproduktion, RED-Test, Korrektur und GREEN-Nachweis;
   bei Features Akzeptanzfälle; bei Refactoring unveränderte Verträge.
3. Ausgeführte Builds/Tests samt Konfiguration, Ergebnis und Nebenwirkungen.
4. Ausgelassene/fehlgeschlagene Prüfungen, Risiken und konkrete offene Schritte.
5. Bei anforderungsrelevanten Änderungen den Status von A0–A7 ausdrücklich
   berücksichtigen; **nicht geprüfte Anforderungen als nicht geprüft** markieren.

**Abschließende Selbstkontrolle:** Ist die Ursache behoben? Sind TDD-Nachweise
wirklich erbracht? Bleiben Legacy-Suche, Unicode, Langpfade, Plugin-ABI,
PictView/WIC, `manage.cmd`, Packaging und Benutzeroberfläche intakt? Gibt es
Undefined Behavior, Datenverlust-, Sicherheits-, Thread-/Lifetime- oder
Releaserisiken? Wurde etwas nur behauptet statt ausgeführt? Gibt es eine
kleinere ebenso korrekte Lösung? **Arbeite weiter, solange genehmigte und
sichere notwendige Schritte offen sind; andernfalls benenne die Blockade.**
