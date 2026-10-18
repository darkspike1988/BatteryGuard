# B-Guard 0.5.0

0.5.0 beantwortet die Frage, was gerade tatsächlich gilt, und erweitert die langfristige Akkubeobachtung. App und Hintergrunddienst haben Version 0.5.0; ein älterer Dienst muss über den macOS-Administratordialog aktualisiert werden.

## Wirksamkeit statt Wunschwert

Die Übersicht zeigt jetzt, welches Ziel gespeichert ist, welches Ziel der Dienst angewendet hat, welches macOS-Limit gilt und über welchen Weg gesteuert wird. Externer Monitor und Deckelzustand stehen daneben. Meldet macOS ein niedrigeres Limit als das B-Guard-Ziel, erscheint der Zustand „begrenzt“ mit einem direkten Verweis auf die Batterieeinstellungen. B-Guard ändert diese Systemeinstellung nicht.

Die Anzeige unterscheidet außerdem zwischen wirksam, Monitor-/Deckelschutz, pausiert, nicht unterstützt sowie fehlendem oder veraltetem Dienst. Die Werte stammen aus der Statusdatei des Dienstes, nicht aus einer Schätzung der Oberfläche.

## Akkugesundheit über 12 Monate

Bei aktivierter Langzeitaufzeichnung speichert B-Guard höchstens ein Jahr lang einen Tageswert für Kapazitätsquote, Zyklenstand und Höchsttemperatur. Die Datei bleibt lokal. Die Ansicht zeigt Kapazitätsquote, Zyklen und Temperatur als getrennte Kurven über 30 Tage, 90 Tage oder 12 Monate.

Fehlende Tage werden nicht interpoliert, sondern als Lücke gezeichnet. Ein CSV-Export enthält Tageswert, Minimum, Maximum, Messanzahl, mittleren Zyklusstand, Höchsttemperatur, Quellen, Designkapazität und macOS-Version. Ältere Kapazitätsdateien ohne Zyklen- und Temperaturfelder bleiben lesbar.

## Erinnerungen und Wochenbericht

- **Kalibrierungs-Erinnerung:** Nach sechs Wochen ohne Vollladung (mindestens 99 % am Netzteil) kann B-Guard einmalig erinnern; frühestens nach 14 Tagen erneut. Es startet keine Kalibrierung und ändert keine Ladegrenzen. Der gesperrte Kalibrierungsassistent bleibt unverändert.
- **Wochenbericht:** Einmal pro Woche kann B-Guard eine lokale Zusammenfassung melden: aufgezeichnete Zeit, Zeit ab 90 %, Zeit ab 40 °C, Volllade-Tage und höchster Zyklusstand. Voraussetzung sind ausreichend lückenlos aufgezeichnete Minuten. Der Bericht bewertet die Nutzung nicht und ersetzt keine Diagnose.

Beide Mitteilungen sind in den Einstellungen getrennt schaltbar; die Kalibrierungserinnerung ist standardmäßig an, der Wochenbericht standardmäßig aus.

## Wartungshinweis für Firmen und IT

Fällt die geschätzte Akkukapazität unter eine einstellbare Grenze (Standard 80 %, Bereich 50–95 %), meldet B-Guard einmalig „Akku wartungsbedürftig“. Die Mitteilung nennt Kapazität und Grenze und weist ausdrücklich darauf hin, dass sie keine Hardwarediagnose ist. Solange der Wert unter der Grenze bleibt, wird höchstens alle 30 Tage erneut erinnert; steigt er wieder darüber, wird die Erinnerung zurückgesetzt.

Der Wert stammt aus Design- und Maximalkapazität und ist über die lokale Status-API auslesbar. Unternehmen können ihn dort mit ihrer eigenen Überwachung auswerten. Es werden keine Daten an fremde Server gesendet.

## Automatik

- **Monitorprofil:** Bei erkanntem externem Monitor kann automatisch ein gewähltes Profil gelten. Pause, Reise- und Sonderpläne bleiben vorrangig; das gespeicherte Profil wird nicht überschrieben.
- **Low Power Mode:** Auf Akkubetrieb kann B-Guard den öffentlichen macOS-Modus über `pmset` einschalten und am Netzteil wieder ausschalten. Es werden dafür keine privaten SMC-Schlüssel geschrieben.
- **Schlafassistent:** Optional verhindert B-Guard bis zu 30 Minuten den automatischen Systemschlaf, solange es den Adapter selbst getrennt hat. Bewusster Schlaf und Deckelschließen bleiben möglich; die Sperre endet bei Zustandswechsel, Fehler oder spätestens nach 30 Minuten. Ohne diese Option erzeugt B-Guard keine Schlafsperre.

## Kurzbefehle

Zusätzlich zu Akkustatus, Energiefluss und wirksamem Ladeziel stehen Aktionen für Profilwahl, Top-Up bis zum Abstecken sowie Pausieren und Fortsetzen des Ladechutzes bereit. Sie verwenden dieselbe validierte Aktionslogik wie Oberfläche und lokale API.

## Bewusst nicht enthalten

- **WidgetKit-Widget:** Der SwiftPM-Build erzeugt keine `.appex`-Erweiterung. Ein Widget ist in 0.5.0 nicht enthalten und wird nicht als umgesetzt ausgewiesen.
- **Notarisierung/Developer-ID:** Es ist weiterhin nur eine Apple-Development-Identität vorhanden. Der Community-Build bleibt ad-hoc signiert und nicht notarisiert.
- **Hardwareabnahme:** Die neuen Monitor-, Low-Power-, Schlaf- und Langzeitpfade sind durch Logik- und Vorschautests belegt, nicht durch eine physische Abnahme. Die offenen Fälle der [Abnahmematrix](validation/README.md) bleiben offen.

## Prüfstand

- `swift test`: 232 Tests in 35 Suiten bestanden.
- `scripts/build-app.sh`: Release-Build, App-Bundle und ZIP ohne Fehler erzeugt.
- Vorschauen in Hell, Dunkel, Deutsch, Englisch, Russisch sowie für Monitor- und macOS-Modus gerendert und gesichtet.
