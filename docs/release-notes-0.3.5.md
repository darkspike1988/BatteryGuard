# B-Guard 0.3.5 — Energiefluss

- **Power-Flow-Snapshot:** Rein lesende Erfassung über `AppleSmartBattery` alle 2 Sekunden, rein app-seitig umgesetzt. Kein Daemon-Update erforderlich; der bestehende Hintergrunddienst 0.3.2 bleibt kompatibel.
- **Leistungswerte & Dashboard:**
  - **Netzteil-Eingang:** Tatsächlich gemeldetes `SystemPowerIn / 1000` in Watt. Bei bestätigt getrenntem Netzteil wird 0 W angenommen; bei angeschlossenem Netzteil wird ein gemeldeter Nullwert ebenfalls erhalten.
  - **Batteriefluss:** Vorzeichenbehafteter Wert berechnet aus `Voltage * InstantAmperage / 1e6` in Watt (Laden/Entladen).
  - **Mac-Leistung:** Schätzwert berechnet aus der Differenz `Eingang - Batterie`.
  - **Netzteil-Nennleistung:** `AdapterDetails.Watts` (z. B. 65 W) ist eine reine Typ-Nennleistung, niemals der tatsächliche Verbrauch.
- **Hardware-Ladestand:** Hardware-% wird ausschließlich bei verfügbarem Rohkapazitätspaar berechnet; andernfalls als unbekannt (`—`) ausgewiesen.
- **Sensorgenauigkeit & Grenzen:** Undokumentierte IOKit-Schlüssel variieren nach Hardware und macOS-Version. Ein Frischezeitfenster (`collected-at`, 10 s) garantiert keine Sensoraktualisierung durch die Firmware. Keine Zusage für Steckdosenmessgerät-Genauigkeit.
- **Quellenbasis:** Basiert auf unabhängig verifizierten Community-Erkenntnissen ([robzr Gist](https://gist.github.com/robzr/2abf9c7e7f576d8af00d90b671489b48) und [power-flow-lite](https://github.com/isliliming/power-flow-lite)). Dokumentiert praktische Einheiten, keinen offiziellen Apple-API-Vertrag.
- **Oberfläche:** Optionale Menüleistenkarte für den Energiefluss (standardmäßig ausgeschaltet), abgedeckt über das Zurücksetzen der Darstellung.
- **Lokale REST API:** Neuer Endpunkt `GET /api/v1/power-flow` (authentifiziert mit Bearer-Token). Liefert `available`, `sampledAt`, `source` sowie optional `inputWatts`, `batteryWatts`, `systemWatts`, `adapterRatedWatts` und `hardwarePercent`. Bei veralteten Daten (`available: false`) werden keine numerischen Leistungswerte ausgegeben.
- **CLI-Diagnose:** `B-Guard.app/Contents/MacOS/BatteryGuard --read-power-flow` liest genau einen JSON-Snapshot aus, ohne App-Einstellungen oder Steuerungszustände zu verändern.
- **Roadmap-Stand:** P1 ist teilweise umgesetzt. Native Kurzbefehle/Intents (P2) und Kalibrierung (P6) sind ausdrücklich nicht enthalten.

Validierung: 143 Tests erfolgreich (134 Swift Testing, 9 XCTest); Release-Build, Bundle-Signatur und gerenderte Ansichten geprüft.
