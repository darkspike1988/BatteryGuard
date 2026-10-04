# Lokale REST API v1

B-Guard bietet eine optionale lokale Schnittstelle für eigene Skripte und Automatisierungen. Sie ist standardmäßig ausgeschaltet. Aktiviere sie in den App-Einstellungen und kopiere dort das API-Token. Die App muss für die HTTP-Schnittstelle laufen; der Hintergrunddienst allein stellt sie nicht bereit.

Die Adresse ist `http://127.0.0.1:8767`. Es gibt keine LAN-Freigabe und keine CORS-Freigabe für Webseiten. Schreibzugriffe müssen zusätzlich und getrennt in den Einstellungen erlaubt werden. Ohne diese Freigabe bleiben die Lese-Endpunkte nutzbar.

Jede Anfrage benötigt den Header `Authorization: Bearer <Token>`. Das Token besteht aus 64 hexadezimalen Zeichen. Behandle es wie ein Passwort: nicht in URLs, Screenshots, öffentlichen Skripten oder Git speichern. Nutze bei eigenen Skripten die Umgebungsvariable `BGUARD_API_TOKEN`; unten wird kein echtes Token eingesetzt.

## Lesen

| Methode und Pfad | Antwort |
| --- | --- |
| `GET /api/v1/status` | JSON mit `daemonActive` und `status` (`BGStatus`). |
| `GET /api/v1/config` | Gespeicherte Konfiguration als `BGConfig`-JSON. Nur lesend. |
| `GET /api/v1/history?hours=24` | Lokale Messpunkte als JSON. |
| `GET /api/v1/history.csv?hours=24` | Dieselben Messpunkte als CSV. |
| `GET /api/v1/capabilities` | API-Version, App-Version, benötigte Dienstversion, `controlAllowed` und verfügbare Fähigkeiten. |
| `GET /api/v1/power-flow` | Authentifizierter Energiefluss-Snapshot aus `AppleSmartBattery`. |

Der Verlauf verwendet ohne Parameter die letzten 24 Stunden. `hours` muss eine ganze Zahl von 1 bis 168 sein. Messlücken bleiben erhalten; die API erfindet keine Werte für Schlafzeiten oder eine geschlossene App. Eine erfolgreiche Statusabfrage bedeutet nicht automatisch, dass der Dienst erreichbar ist: Prüfe `daemonActive`, bevor du Messwerte als aktuell verwendest.

### Energiefluss (`GET /api/v1/power-flow`)

Liest alle 2 Sekunden rein lesend einen Snapshot aus `AppleSmartBattery` aus. Die App übernimmt dies eigenständig; ein Update des Hintergrunddienstes ist nicht erforderlich (Dienst 0.3.2 bleibt kompatibel).

Schema der JSON-Antwort:
- `available` (Boolean): `true`, wenn frische Daten mit mindestens einem vorhandenen Leistungswert vorliegen; `false`, wenn die Messung veraltet (stale) ist.
- `sampledAt` (String, ISO-8601-Zeitstempel): Zeitpunkt der Messwerterfassung.
- `source` (String): Datenquelle (z. B. `"AppleSmartBattery"`).
- `inputWatts` (Zahl, optional): tatsächlich gemeldetes `SystemPowerIn / 1000` in Watt. 0 W wird nur bei bestätigt getrenntem Netzteil gemeldet.
- `batteryWatts` (Zahl, optional): vorzeichenbehafteter Batteriefluss aus `Voltage * InstantAmperage / 1e6` in Watt.
- `systemWatts` (Zahl, optional): geschätzter Systemverbrauch als Differenz `inputWatts - batteryWatts`.
- `adapterRatedWatts` (Zahl, optional): Typ-Nennleistung aus `AdapterDetails.Watts` (z. B. 65 W; reine Nennleistung, niemals tatsächlicher Verbrauch).
- `hardwarePercent` (Zahl, optional): Hardware-Ladestand, nur vorhanden, wenn ein Rohkapazitätspaar verfügbar ist; sonst entfällt der Wert (in der UI `—`).

**Verhalten bei veralteten Daten:** Ist die Messung älter als die Frischefrist von 10 Sekunden (`available: false`), werden **keine** numerischen Leistungswerte geliefert. Die Frische von 10 s garantiert jedoch keine Sensoraktualisierung durch die Firmware. Die undokumentierten IOKit-Schlüssel variieren nach Hardware und macOS-Version; es wird keine Steckdosenmessgerät-Genauigkeit zugesagt. Die Umsetzung basiert auf unabhängig verifizierten Community-Quellen ([robzr Gist](https://gist.github.com/robzr/2abf9c7e7f576d8af00d90b671489b48) und [power-flow-lite](https://github.com/isliliming/power-flow-lite)), die praktische Einheiten dokumentieren, keinen offiziellen Apple-Vertrag.

### CLI-Direktausgabe

Über die Kommandozeile kann ein einzelner Snapshot ohne HTTP-Server und ohne Änderung von App-Einstellungen oder Steuerung ausgegeben werden:

```sh
B-Guard.app/Contents/MacOS/BatteryGuard --read-power-flow
```

Gibt genau ein JSON-Objekt gemäß dem obigen Schema aus.

```sh
# BGUARD_API_TOKEN vorher lokal setzen; Token nicht in die URL schreiben.
curl --fail-with-body \
  -H "Authorization: Bearer ${BGUARD_API_TOKEN:?API-Token setzen}" \
  http://127.0.0.1:8767/api/v1/status

curl --fail-with-body \
  -H "Authorization: Bearer ${BGUARD_API_TOKEN:?API-Token setzen}" \
  http://127.0.0.1:8767/api/v1/power-flow

curl --fail-with-body \
  -H "Authorization: Bearer ${BGUARD_API_TOKEN:?API-Token setzen}" \
  'http://127.0.0.1:8767/api/v1/history?hours=24'

curl --fail-with-body \
  -H "Authorization: Bearer ${BGUARD_API_TOKEN:?API-Token setzen}" \
  'http://127.0.0.1:8767/api/v1/history.csv?hours=168' \
  -o B-Guard-history.csv
```

## Aktionen

Ab B-Guard 0.3.2 benötigen Steueraktionen den Hintergrunddienst 0.3.2. Der Dienst wendet den Befehl atomar auf die aktuelle Konfiguration an; alte Dienste können ihn nicht still als unveränderten Feldvergleich bestätigen. Ein neuer Volllade- oder Reiseauftrag erhält eine eindeutige ID, damit der Abschluss eines älteren Auftrags ihn nicht entfernt.

Sende ein JSON-Objekt an `POST /api/v1/actions`, mit `Content-Type: application/json`. Das Feld `action` ist eine Zeichenkette; die Parameter stehen daneben im selben Objekt.

| `action` | Weitere Felder | Wirkung |
| --- | --- | --- |
| `profile` | `profile`: `desk`, `everyday` oder `mobile` | Schreibtisch-, Alltags- oder Unterwegsprofil aktivieren. |
| `protection` | `enabled`: Boolean | Schutz dauerhaft einschalten oder ausschalten. |
| `pause` | `minutes`: ganze Zahl 1–720 | Schutz vorübergehend pausieren. |
| `resume` | keine | Zeitliche Schutzpause beenden. |
| `full-charge` | keine | Einmaliges Vollladen anfordern. |
| `cancel-full-charge` | keine | Vollladen abbrechen; aktive Reiseaufladung beenden, zukünftigen Reiseplan behalten. |
| `travel` | `readyAt`: ISO-8601-Zeitpunkt | Vollladen für einen zukünftigen Termin planen, höchstens 30 Tage voraus. |
| `cancel-travel` | keine | Reiseplan entfernen. |

Zeitpunkte benötigen eine Zeitzone, beispielsweise `2026-10-05T08:00:00+02:00`. Der tatsächliche Termin muss bei der Anfrage in der Zukunft liegen. Hitzeschutz und hardwareabhängige Einschränkungen gelten auch für API-Aktionen; eine volle Ladung zum Termin wird nicht garantiert.

Eine erfolgreiche Aktion liefert `savedConfig` und `hardwareApplied: false`. Das bestätigt die gespeicherte Konfiguration, **keinen sofortigen Hardwarewechsel**. Der Dienst prüft und führt die Einstellungen anschließend aus. Verwende danach `/status`, um den tatsächlichen Zustand zu beobachten.

```sh
curl --fail-with-body \
  -H "Authorization: Bearer ${BGUARD_API_TOKEN:?API-Token setzen}" \
  -H 'Content-Type: application/json' \
  -d '{"action":"profile","profile":"desk"}' \
  http://127.0.0.1:8767/api/v1/actions

curl --fail-with-body \
  -H "Authorization: Bearer ${BGUARD_API_TOKEN:?API-Token setzen}" \
  -H 'Content-Type: application/json' \
  -d '{"action":"pause","minutes":60}' \
  http://127.0.0.1:8767/api/v1/actions
```

## Fähigkeiten und Token

`/capabilities` enthält `apiVersion`, `appVersion`, `requiredDaemon`, `daemonActive`, `controlAllowed`, `controlReady`, `availableProfiles`, `historyRetentionHours`, `smcKeysDetected` und `usesNativeDesktopFallback`. `controlReady` beschreibt den Zustand des Dienstes; eine Aktion benötigt zusätzlich `controlAllowed: true`.

Das Token liegt unter `~/Library/Application Support/BatteryGuard/api-token` mit Dateirechten `0600`. „Token erneuern“ macht das bisherige Token sofort ungültig. Der Server akzeptiert direkte Anfragen mit Host `127.0.0.1:8767`; Browser-Anfragen mit `Origin` werden abgewiesen. Bei belegtem Port zeigt die App einen Startfehler und bietet einen erneuten Versuch an.

## Fehler

HTTP-Statuscodes unterscheiden ungültige Anfragen von fehlender Freigabe oder einem nicht verfügbaren Dienst. Werte im Fehlertext nicht als Erfolg interpretieren.

| Code | Bedeutung |
| --- | --- |
| `400` | Ungültiges JSON, unbekannte Aktion oder ungültige Parameter. |
| `401` | Bearer-Token fehlt oder ist ungültig. |
| `403` | Schreibaktionen sind nicht freigegeben. |
| `404` | Endpunkt nicht vorhanden. |
| `405` | HTTP-Methode für diesen Endpunkt nicht erlaubt. |
| `409` | Aktion widerspricht dem aktuellen Zustand oder den verfügbaren Fähigkeiten. |
| `503` | Benötigter Dienst oder Speichervorgang nicht verfügbar. |

Ist die App geschlossen oder die API ausgeschaltet, ist der HTTP-Server nicht erreichbar; das ist ein Verbindungsfehler statt einer JSON-Fehlerantwort. Das API-Token ersetzt nicht die Berechtigungsprüfung des lokalen Einstellungsdienstes. Für eine erfolgreiche Schreibaktion müssen auch dessen Voraussetzungen erfüllt sein.
