# Entwicklungsübergabe – 18.11.2026

> **Historischer Snapshot. Nicht als aktuellen Arbeitsstand verwenden.**
> Die laufend gepflegte, agentenübergreifende Übergabe liegt unter
> [Arbeitsstand-und-Uebergabe.md](Arbeitsstand-und-Uebergabe.md);
> die Chronologie unter [Entwicklungsjournal.md](Entwicklungsjournal.md);
> offene Aufgaben unter [Testluecken-und-Abnahmeplan-5.2.md](Testluecken-und-Abnahmeplan-5.2.md).
> Vor Änderungen den heutigen Git-HEAD und die aktuellen Tests verifizieren.


## Arbeitsstand

Worktree: `C:\Users\mk\.codex\worktrees\0e93\Salamander`.
Detached HEAD: `5303c25ff44aa69da5ae146d36359a36ee8f396d`.
Die erste Übergabe erfolgte uncommittet. Danach wurde ausdrücklich die Übernahme
aller Änderungen auf `bugfix/v5.2` beauftragt; der endgültige Git-Stand wird im
Chat-Abschluss genannt. Bis zu dieser Übernahme wurde das Originalrepository
`C:\Repositories\Salamander` nicht beschrieben.
`AGENTS.md` gilt weiterhin; insbesondere keine gemeinsamen Build-Ausgaben nutzen.

Der Stand ist zur Codeprüfung und Weiterentwicklung vorbereitet. Er ist **keine
vollständige Unicode-/Langpfadmigration und noch nicht vollständig verifiziert**.
Die zwei offenen GUI-Prüfungen unten sollten vor der Merge-Abnahme geklärt werden.

## Umgesetzt

- Verlustfreie UTF-16-Pfadidentitäten und abgesicherte Plugin-/Sprachmodulpfade.
- Isolierte GUI-Testkonfiguration, native Zwischenablage-Sicherung/-Wiederherstellung
  und Ausschluss instrumentierter Testbinärdateien aus Release-Paketen.
- Korrigierte Langpfad-Testgeometrie; Release-x64-Langpfad-GUI zuvor bestanden.
- Große Unicode-Einzelkopien über den bestehenden Hintergrundworker statt der
  bisherigen 16-MiB-Ablehnung: originale Fortschritts-, Pause-, Abbruch-,
  Überschreib- und Fehlerdialoge mit vollständigen UTF-16-Pfaden.
- Owned-Path-Sidecar, W-I/O-Adapter und native Regressionen; `COperation`-Layout
  und öffentliche Plugin-ABI bleiben erhalten. Registrierung in Manager/CI.
- Fehler der PowerShell→C#-Dialogsuche für `$null` mit RED→GREEN abgesichert.
- `manage.cmd --test-all` bindet die vier großen Unicode-Kopierfälle über einen
  eigenen isolierten Build sowie den nativen Zwischenablage-Test ein. Direkter
  Einzelaufruf: `manage.cmd --test-gui-large-unicode-copy --release`.

## Belegte Prüfungen

- VS 2026: regulärer Kern und isolierter Testkern jeweils Debug/Release x86/x64.
- Drei neue native Regressionen: 12/12 Läufe mit `/W4 /WX` erfolgreich.
- Bestehende Langpfad-/Unicode-I/O-Regressionen: weitere 12/12 erfolgreich.
- Große GUI-Kopie: Copy, Cancel, Collision, LockedSource jeweils bestanden in
  Release x64, Debug x64 und Release x86 (12 Fälle). SHA256, Unicode-ADS,
  Dateizeit/-attribute und Unversehrtheit der Quelle geprüft.
- GUI-Treiber-/Isolations-/Reliability-Verträge und Release-Testbuild-Ausschluss
  erfolgreich. CI wurde konfiguriert, aber nicht als remote ausgeführt behauptet.

## Vor Merge-Abnahme offen

1. **Debug-x86-GUI-Start:** Timeout vor Kopiertest bei isolierter
   Konfigurationsmigration/Plugin-Initialisierung. Kopie und drei Negativfälle
   dieser Konfiguration sind nicht abgenommen. Nicht durch längeren Timeout kaschieren.
2. **Kurze GUI-Regression:** F5 erfolgreich, danach sicherer Treiberabbruch wegen
   Fokusverlust bei offenem „Quick Rename“. F2/F6/F8 erneut mit gezielter Bedienung
   des verifizierten eigenen Dialogs prüfen; Produktfehler bisher nicht bestätigt.

Lokale Einstiegspunkte (ignorierte `.Build`, für die Übergabe allein nicht versioniert):
`Build-Utf16Core.ps1 -FreshNormal`, `Build-Utf16Core.ps1 -NoPdbBuild`,
`Run-Utf16IdentityTests.ps1`, `Run-IsolatedGui.ps1 -Scenario LargeUnicodeCopyOnly
-Configuration Debug -Architecture x86 -LargeUnicodeCopyCase Copy`.
Dauerhafte direkte GUI-Aufrufe stehen in README; Logs bleiben unter `.Build`.

## Weitere Migration – ausdrücklich nicht fertig

A0: begrenzte Verhaltenstests; vollständiger Funktionserhalt offen.
A1/A2: große Einzelkopie geprüft, Unicode-Verzeichnisnavigation, Mehrfach-/Move-/
Rekursionsfälle, vollständige Metadaten-/Sicherheitsmatrix und Plugin-/Archivgrenzen offen.
A3: Kern gebaut; vollständiger Plugin-/Help-/Release-Build offen.
A4: Manager/CI gepflegt; keine Update-/Setup-/Shared-Output-Aufrufe ausgeführt.
A5: Release-Testbuild-Sperre geprüft; reale Pakete und saubere Windows-11-VM offen.
A6: Legacy-Suche mit Advanced/Regex noch nicht vollständig migriert.
A7: PictView/WIC-Host-/Codec-Matrix in diesem Schritt nicht geprüft.

Die ausführliche Strategie, Ursachen, RED/GREEN-Nachweise und Einschränkungen stehen
in [Unicode-LongPath-Implementation.md](Unicode-LongPath-Implementation.md).
