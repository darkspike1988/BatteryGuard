# B-Guard 0.6.1 (Arbeitsstand, unveröffentlicht)

0.6.1 macht B-Guard auf macOS 27 nachvollziehbarer: Es erkennt Apples Akku-Kalibrierung, zeigt die Fähigkeiten mit Firmware-Version und meldet Auffälligkeiten. App und Hintergrunddienst haben Version 0.6.1.

## Apples Akku-Kalibrierung erkennen (R3)

macOS lädt gelegentlich trotz Limit auf 100 %, um den Ladestand neu zu schätzen. Der Dienst fragt dafür höchstens alle fünf Minuten `PowerUIBatteryMitigationManager.fetchCurrentMitigationState` (privat, rein lesend, ohne Berechtigung) ab. Ist die Kalibrierung aktiv, zeigt die Übersicht einen Hinweis, die Diagnose „läuft gerade“, und eine einmalige Mitteilung erklärt den Vorgang. B-Guard greift nicht in Apples Ablauf ein. Der positive Fall ließ sich auf dem Testgerät nicht auslösen; die Abfrage liefert dort „nicht aktiv“.

## Fähigkeiten und Firmware (R4)

Die Diagnose zeigt System-Firmware (aus `IODeviceTree:/chosen`), macOS-Version, SMC-Ladesperre, Netzteil-Schalter, macOS-Limit-Stufen, MagSafe-LED, High Power Mode und Apples Kalibrierungszustand. Der Dienst speichert den Stand in `/Library/Application Support/BatteryGuard/capabilities.json`; ändert er sich nach einem Update, steht die Änderung im Status, im Log und in einer einmaligen Mitteilung.

## Auffälligkeiten melden (R5)

- **Über das Limit geladen:** am Netzteil mindestens drei Prozentpunkte über dem wirksamen Ziel, ohne Vollladen, Top Up, Pause oder Beobachtungsmodus.
- **Netzteil liefert keinen Strom:** Netzteil gemeldet, Eingang unter 1 W und der Akku versorgt den Mac, obwohl der Ladestand unter dem Ziel liegt (über dem Ziel entlädt die Firmware im macOS-Limit-Modus selbst).
- Jede Auffälligkeit wird einmal gemeldet, bis sie verschwindet; abschaltbar unter Mitteilungen.

## Messung: Netzteil-Schalter bei aktivem macOS-Limit (R2)

Auf MacBookPro18,3, Firmware 20457.1.29, macOS 27.0 (Dienst angehalten, siehe Journal):

- `CHIE = 08` wird **nicht** ignoriert, wirkt aber nicht mehr als „Netzteil trennen“: Das Netzteil versorgt den Mac weiter (18–20 W Eingang), der Akku ruht (0 A); macOS meldet dabei `ExternalConnected = false`. Das gilt bei macOS-Limit 80 % und 100 %.
- Der Pendel-Modus kann auf dieser Firmware daher nicht vom Akku entladen; er hält den Ladestand. Folgepaket R7 nutzt das gezielt als Ladesperre unter 80 %.
- Nach dem Umschalten des macOS-Limits entlud die Firmware kurz am Netzteil (etwa −1 A); im Dauerbetrieb bei 80 % lag der Akkustrom bei 0 A.

## Prüfstand

266 Tests in 42 Suiten (Swift Testing) bestanden, neu: Firmware-Parser, Fähigkeitsänderungen, Speichern des Fähigkeitsstands, Auffälligkeitsregeln.
