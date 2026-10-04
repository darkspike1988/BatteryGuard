# Lesende macOS-Kurzbefehle

Ab 0.3.6 sind zwei experimentelle App Intents enthalten: **Akkustatus lesen** und **Energiefluss lesen**. Beide liefern JSON-Text. Sie benötigen keinen API-Token und ändern keine Ladeeinstellungen. Der vorhandene Dienst 0.3.2 genügt; für den Energiefluss wird direkt eine lesende IOKit-Abfrage verwendet.

In **Kurzbefehle** einen neuen Kurzbefehl anlegen, in der Aktionssuche nach **B-Guard** suchen, eine der beiden Aktionen hinzufügen und ausführen. Die JSON-Ausgabe lässt sich mit der Aktion „Wörterbuch aus Eingabe abrufen“ weiterverarbeiten.

Der Status muss höchstens 60 Sekunden, der Power-Flow-Snapshot höchstens 10 Sekunden alt sein; maximal 5 Sekunden Zukunftstoleranz. Fehlende oder veraltete Daten liefern `{"available":false}`. Beschädigte Statusdaten führen zu einem Fehler. Die Frische bezieht sich auf die Erfassung, nicht auf einen garantierten Sensor-Refresh. `systemWatts` ist geschätzte Mac-Leistung, `adapterRatedWatts` die Netzteil-Nennleistung.

Die Aktionen verlangen mit `openAppWhenRun = false` kein Öffnen im Vordergrund; die App kann im Hintergrund gestartet werden. Ihre normale Startlogik ist davon getrennt.

**Abnahme:** Metadaten und beide automatischen App Shortcuts sind im signierten Bundle enthalten. Beide `perform()`-Methoden wurden mit echten lesenden Daten aufgerufen. Die Erkennung und Ausführung in der systemweiten Kurzbefehle-App wurde noch nicht bestätigt; P2 bleibt daher teilweise umgesetzt. Keine Steueraktionen enthalten.

Entwickler-Build: vollständiges Xcode 27 für den geprüften Metadaten-Schritt. `scripts/build-app.sh` extrahiert und kontrolliert die Metadaten vor der Signierung. Die fertige DMG benötigt beim Nutzer kein Xcode.

[Apple: AppIntent](https://developer.apple.com/documentation/appintents/appintent) · [Apple: AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider)
