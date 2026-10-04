BatteryGuard 0.2.1 behebt den Konflikt zwischen Schreibtisch-/Pendelbetrieb und einem externen Monitor bei geschlossenem MacBook-Deckel.

- Bei externem Monitor, geschlossenem Deckel oder fehlgeschlagener Erkennung bleibt das Netzteil verbunden. Bereits softwareseitig getrennte Netzteile werden wieder verbunden.
- Keine von BatteryGuard erzeugte System-Schlafsperre mehr.
- Separate SMC-Ladesperren bleiben nutzbar; aktives Entladen entfällt im Monitorbetrieb.
- Auf Macs ohne separate Ladesperre übernimmt macOS in diesem Zustand das Ladelimit. BatteryGuard zeigt dies im Status. Ein eigenes 60-%-Limit kann mit dem Netzteil-Schalter hier nicht zuverlässig erzwungen werden.

28 Regressionstests bestanden. Monitorbetrieb, zuvor getrenntes Netzteil, expliziter Pendelmodus, Hitzeschutz und Rückkehr ohne Monitor sind durch Logiktests abgedeckt. Das physische Schließen des Deckels muss am Gerät bestätigt werden.

Installation: DMG öffnen, App auf Programme ziehen, öffnen. Bei bestehenden Installationen den Hintergrunddienst in den Einstellungen aktualisieren; die Korrektur steckt im Dienst. Einstellungen und Verlauf bleiben erhalten.

Apple Silicon, macOS 14+. Ad-hoc signiert, nicht notarisiert; bei einem blockierten Erststart kann die Freigabe unter Datenschutz & Sicherheit erforderlich sein. [Apple-Anleitung](https://support.apple.com/102445).
