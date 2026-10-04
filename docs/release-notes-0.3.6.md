# B-Guard 0.3.6 — Deine Menükarten

- Messwerte, Energiefluss und Verlauf in eigener Reihenfolge anzeigen; Auf-/Ab-Pfeile in Einstellungen → Menüleiste.
- Kompakte Darstellung und optionaler Verlaufsblock. Letzte Messung mit eindeutigem Zeitpunkt statt scheinbarer Live-Daten.
- Darstellungs-Reset erhält Ladeprofil, Mitteilungen, API und Autostart.
- Experimentelle lesende App Intents „Akkustatus lesen“ und „Energiefluss lesen“ liefern JSON. Metadaten sind verpackt und `perform()`-Aufrufe geprüft; systemweite Kurzbefehle-Erkennung und -Ausführung noch unbestätigt. [Anleitung und Abnahmestand](https://github.com/darkspike1988/BatteryGuard/blob/main/docs/shortcuts.md).

Appupdate genügt mit Hintergrunddienst 0.3.2. Community-DMG ad-hoc signiert, nicht notarisiert.

Validierung: 168 Tests (141 Swift Testing, 27 XCTest), Release-Build, Bundle-Signatur, Intent-Metadaten und lesende Intent-Aufrufe geprüft. Gemini implementierte, Claude prüfte die Menükarten; Codex korrigierte und integrierte.
