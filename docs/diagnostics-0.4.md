# Diagnose 0.4.0 — erster Ausbau

Dies ist der Entwicklungsstand nach Umsetzung der ersten Diagnosebausteine. Eine neue öffentliche DMG wird hierdurch nicht veröffentlicht. App und Dienst werden als 0.4.0 gebaut; der neue Dienst muss nach einem späteren App-Update regulär installiert werden. Ältere Statusdaten bleiben lesbar, ihre Herkunft wird als unbekannt gekennzeichnet.

## Was Nutzer sehen

Im Hauptfenster gibt es die neue Seite **Diagnose**:

- Ladestand, Akkutemperatur, Zyklen, gemeldete Maximal-/Designkapazität und Kapazitätsquote mit Quelle, Qualität und Auslesezeit.
- Öffentlicher macOS-Thermalzustand; CPU-Last über ein Messintervall, RAM aktiv + verdrahtet + komprimiert, physischer RAM, belegter Swap und Volumekapazität.
- Prüffragen für kürzere Laufzeit, Ladeprobleme, Hitze, Schlafverbrauch und langsamen Mac. Die Hinweise beschreiben Daten und nächste Prüfungen, keine sichere Fehlerursache.
- Bereinigter, ausdrücklich gewählter JSON-Messbericht für spätere Auswertung. Er enthält auch vorhandene Kapazitäts-Tageswerte und deren Messzeiten.

Systemmessungen laufen nur bei sichtbarer Diagnoseseite über die bestehende Abfrage, höchstens alle zehn Sekunden. Nach erneutem Öffnen beginnt die CPU-Intervallmessung neu; der erste CPU-Wert bleibt unbekannt. Keine zusätzlichen Dauer-Timer und keine Root-Systemdiagnose. Der Eigenverbrauch dieses Samplers muss noch auf Referenzgeräten gemessen werden.

Keine Speicherdruck-, Lüfter-, GPU-, SSD-Verschleiß- oder Prozessdiagnose. RAM-Kategorien sind nicht automatisch Speicherdruck; freie Volumekapazität ist kein SMART-Wert. Der Thermalzustand ist keine CPU-Temperatur und keine genaue Drosselungsquote.

## Kapazitätsquote

Der bisher als Gesundheit dargestellte Quotient wird in der Oberfläche als **Kapazitätsquote** benannt. Formel: gemeldete Maximal-Kapazität / Designkapazität × 100. Nicht automatisch identisch mit Apples „Maximale Kapazität“. Werte über 100 % werden nicht abgeschnitten. Fehlende, ungültige oder veraltete Eingänge erzeugen keinen Quotienten. Jede Fallback-Quelle ist getrennt erkennbar.

Für MacBookPro18,1 bis 18,4 ist Apples Referenz von 1000 Zyklen anhand der Modell-/Zykluslisten hinterlegt (Quellenstand 2026-10-05). Andere Modelle bleiben ausdrücklich unbekannt. Die Zahl ist kein Countdown bis zum Ausfall. Apples Batteriezustand wird nicht aus einem Quotienten erraten.

## Freiwilliger Langzeitverlauf

Die Aufzeichnung lokaler Kapazitäts-Tageswerte ist **standardmäßig aus** und auf der Diagnoseseite einschaltbar. Sie verwendet gültige Daten bei laufender App, höchstens einen Punkt pro Minute. Kein Nachtragen fehlender Tage. Aufbewahrung bis zu 365 Tage; UTC-Tagesgrenzen vermeiden Sommerzeit-/Reiseeffekte.

Gespeichert werden Mittel-/Min-/Max-Wert, Anzahl, Messzeiten, Kapazitätsquellen, Designkapazität und numerische OS-Version. Unterschiedliche Quellen, Designkapazitäten und OS-Versionen werden getrennt geführt. Die dargestellte Veränderung benötigt mindestens drei vergleichbare Tageswerte und ist rein beschreibend, keine Alterungs-/Lebensdauerprognose.

Datei: `~/Library/Application Support/BatteryGuard/capacity-days.json`, 0600. Abschalten pausiert die Aufzeichnung und behält vorhandene Werte. Beschädigte vorhandene Dateien werden nicht still überschrieben. Der bisherige minutengenaue Siebentageverlauf und sein API-/CSV-Vertrag bleiben erhalten.

## Messvertrag und REST

Der Status ergänzt optional `measurements` mit `schemaVersion: 1` und einer Liste:

| Feld | Bedeutung |
| --- | --- |
| `metric`, `value`, `unit` | Definierte Größe, optionaler Wert, geprüfte Einheit |
| `source` | Feste Quellenkennung, keine beliebigen Benutzerstrings |
| `sampledAt` | Auslesezeit des Hosts |
| `sensorUpdatedAt` | Nur falls tatsächlich bekannt; derzeit für Akkuquellen nicht erfunden |
| `quality`, `reason` | reported/derived/unavailable/unsupported/invalid/stale und begrenzter Grund |

Im neuen Vertrag sind Spannung **V** und Strom **A**. Die alten Statusfelder `voltage` (mV) und `amperage` (mA) sowie das begrenzte Legacy-Feld `healthPercent` behalten ihren bisherigen Vertrag. Normierung wird nicht still in API v1 geändert. Diagnosewerte werden bei mehr als 60 Sekunden Alter ohne numerischen Wert dargestellt; Zukunftstoleranz fünf Sekunden. Eine frische Host-Abfrage beweist keine Firmwareaktualisierung.

`GET /api/v1/diagnostics` liefert den bereinigten Messbericht mit Schema- und Regelversion. Er benötigt denselben Bearer-Token und dieselben Localhost-/Origin-Prüfungen wie andere Leseendpunkte. Er startet weder Hardwareaktionen noch einen unsichtbaren Systemsampler; ohne sichtbare Diagnoseseite können Systemdaten fehlen.

Der Bericht enthält keine Rohkonfiguration, Statusmeldungen, Profile, Reisezeiten, Tokens, Seriennummern, persönlichen Pfade oder Prozessnamen. Er enthält ausdrücklich Messzeiten, Messwerte und gegebenenfalls die nicht personenbezogene Modellkennung. Vor öffentlicher Weitergabe prüfen.

## Validierung und verbleibende Schritte

Neue Tests prüfen Frische, Einheiten, fehlende/ungültige Werte, Kapazitätsquellen, Werte über 100 %, Legacy-Kompatibilität, CPU-Intervallrechnung, Tagesaggregate, Quellen-/OS-Wechsel, Retention, Export und Dateierhalt. Bestehende Ladesteuerungslogik wurde nicht erweitert. Die neue Diagnose nutzt Simulationen als Softwarebelege; daraus entsteht keine Gerätefreigabe.

Die [Journey](JOURNEY.md) hält tatsächliche Prüfergebnisse fest. Noch nötig: vollständiger macOS-Build, visuelle Prüfung der Hell-/Dunkel-Vorschauen, gleichzeitiger Vergleich mit Batterieeinstellungen/Systeminformationen/Aktivitätsanzeige, Eigenverbrauchsmessung und Testmatrix. Der [Ausbauplan](DIAGNOSTICS_PLAN.md) bleibt für weitergehende Trends, Regeln und geführte Beobachtung offen.

Primärquellen: [Apple-Modellkennung](https://support.apple.com/108052), [Apple-Zyklusreferenz](https://support.apple.com/102888), [Thermalzustand](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property). Die Quellen-/Unit-Verträge der undokumentierten Registry benötigen weiter modellbezogene Abnahme.
