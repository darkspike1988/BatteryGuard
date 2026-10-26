# B-Guard 0.7.0 (Arbeitsstand, unveröffentlicht)

0.7.0 erweitert die Ladesteuerung auf Macs ohne SMC-Ladesperre (macOS 27). Grundlage ist die Messung aus 0.6.1: Auf Firmware 20457 hält `CHIE = 08` das Laden an, während das Netzteil den Mac weiter versorgt. App und Hintergrunddienst haben Version 0.7.0. Alle neuen Hardwarewege sind opt-in oder experimentell gekennzeichnet; ihre physische Abnahme steht aus.

## Limits unter 80 % im macOS-Limit-Modus (R7)

Mit „Ziele unter der kleinsten macOS-Stufe über den Netzteil-Schalter halten“ hält B-Guard zum Beispiel 60 %: Bis zum Ziel wird geladen, dann hält `CHIE = 08` den Ladestand; unter der unteren Grenze lädt der Mac wieder. Das macOS-Limit bleibt dabei auf der kleinsten Stufe (80 %) und begrenzt, falls der Schalter versagt.

- Während des Haltens meldet macOS „kein Netzteil“, obwohl es den Mac versorgt. Energieeinstellungen für Akkubetrieb (Low Power Mode „Nur auf Akku“, Schlafzeiten) können dann gelten.
- Bei externem Monitor oder geschlossenem Deckel nutzt B-Guard nur das macOS-Limit, weil ein gemeldeter Netzteilverlust zugeklappt zum Schlaf führen kann.
- Hitze- und Kälteschutz nutzen den Schalter nur mit diesem Opt-in, sonst die kleinste macOS-Stufe.

## Einmal entladen über das macOS-Limit (R6, experimentell)

Im macOS-Limit-Modus lässt sich auf eine angebotene Stufe unter 100 % entladen (85–95 %, bei mehr Ladung auch 80 %). Der Dienst setzt das Limit auf die Stufe; die Firmware entlädt am Netzteil, bis sie erreicht ist. Danach gilt wieder das Profil. Der Dienst lehnt Ziele ab, die macOS nicht anbietet.

## Kalibrierung (R8)

Die eigene Kalibrierung bleibt bis zur Hardware-Abnahme gesperrt. Apples Kalibrierung wird seit 0.6.1 erkannt und erklärt; laut Community-Messungen entlädt die Firmware danach selbst zurück auf das macOS-Limit.

## Schlafsteuerung (R9)

- „Bis zum Ladelimit wachhalten“ funktioniert jetzt auch im macOS-Limit-Modus; bisher verlangte es eine SMC-Ladesperre.
- Optional verhindert der Dienst den Schlaf auch zugeklappt (`SleepDisabled`, wie `pmset disablesleep`), nur am Netzteil und nur solange das Wachhalten läuft (höchstens zwei Stunden).
- Sicherheitsregeln: Netzteil bei geschlossenem Deckel getrennt → Sperre aufheben und sofort schlafen; vor dem Schlaf, beim Beenden und nach einem Absturz (Marker-Datei) wird die Sperre aufgehoben.
- „Display aus bei Inaktivität“ ist nicht umgesetzt; es bräuchte das private `DisplayServices`.

## Kälteschutz und Ladeton (R10)

- Kälteschutz sperrt das Laden unter 1–15 °C (aus = 0) und gibt es zwei Grad darüber wieder frei; mit SMC-Ladesperre, im Pendel-Modus über den Netzteil-Schalter, im macOS-Limit-Modus wie oben beschrieben.
- „Ladeton beim Anstecken stumm“ setzt die macOS-Benutzereinstellung `com.apple.PowerChime ChimeOnNoHardware` und startet PowerChime neu.

## Prüfstand

272 Tests in 43 Suiten (Swift Testing) bestanden, neu: Halten unter der Mindeststufe mit Hysterese und Monitor-/Deckelschutz, Hitze/Kälte mit und ohne Opt-in, Kälteschutz-Hysterese, Entladeplan auf Stufen, Schlafwächter mit Absturzbereinigung.
