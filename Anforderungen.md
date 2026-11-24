# SPEZIELLE ANFORDERUNGEN ZUR WEITERETWICKLUNG VON https://github.com/Fla77y/Salamander

## Folgende Features sollen umgesetzt und auf jedenfall nicht in Zukunft durch andere Änderungen zerstört, entfernt oder so verändert werden, dass sie
den Anforderungen nicht mehr entsprechen.

### Anforderung 0: Es werden keine Programmteile auf eigene Faust entfernt oder durch eigene Neuentwicklungen ersetzt, wenn dadurch Funktionalität verloren geht, oder sich die Benutzeroberfläche verändert. Funktionalität soll nicht weniger oder eingeschränkt werden. Die Oberfläche und Steuerung soll nicht geändert werden.

### Anforderung 1: Alle Dateinamen und Pfade unterstützen in allen Bereichen und Plugins Unicode-Zeichen.

### Anforderung 2: Alle Komponenten unterstützen die Langpfad Unterstützung. Bitte Teste, ob diese durchweg verwendet wird (Hauptprogramm + PlugIns) und funktioniert.

### Anforderung 3: Der Komplette Build-Prozess soll mit dem Studio 2026 umgesetzt werden.

### Anforderung 4: Pflege immer das Skript manage.cmd und halte es up to date. Insbesondere dic Parameter –update, --build, --test-all, --setup

### Anfoarderung 5: Die Release Setups und 7Z-Files für die Installation sind völlig von Build-Artefakten befreit und beinhalten nur Dateien/Verzeichnisse die zur Ausführung von Salamander nötig sind. Aber es muss alles enthalten sein, dass es in einer sauberen VM funktioniert.

### Anforderung 6: Der Suchdialog soll nicht selbstständig durch eine eigene Entwicklung ersetzt werden. Der Suchdialog (Strg-F). Der Suchdialog soll auf dem ursprünglichen (Legacy) Dialog aufbauen. Aber in diesem Suchdialog sollen die Unicode und Langpfad Unterstützung implementiert werden. Sämtliche Funktionalitäten, wie z.B. die 'Advanced...' Suchfunktionen/Filter müssen erhalten bleiben. Auch Reguläre Ausdrücke etc. Die Mächtigkeit des Suchdialogs und das Aussehen darf nicht eingeschränkt oder verändert werden!

### Anforderung 7: Das PictView-Plugin verwendet nun die Anbindung an das WIC. Alle gängigen Dateiformate (z.B. die auch in der Salamander Konfiguration zu finden für die Viewer zu finden sind), werden unterstützt.

### Anforderung 8: Wenn in einem Test ein Fehler aufgetreter ist, fixe den Fehler dann für diesen Test asschließlich im Produktcode! Das heisst insbesondere, ändere keine Tests so, dass sie grün werden obwohl sich dadurch das getestete Verhalten im Produktivcode ändert. Passe Tests nur dann an, wenn sie Nachweisslich einen Fehler enthalten und somit nicht das gewünschte Verhalten testen!
