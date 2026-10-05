# Nachtarbeit am 5. Oktober 2026

Start im bestehenden Thread um 03:00 CEST; kein zweiter Koordinator. Ausgangspunkt 0.3.6, Commit `6d98a6c`. Ergebnis ist ein neues geprüftes Softwarepaket 0.3.7, keine vollständige Hardwarefreigabe.

## Umsetzung

- P3-Zustandsmodell und atomare Dienstaktionen für Top Up bis Abstecken, Halten und Einmalentladung. Neue Halte-/Entladeaktionen ohne physische Backend-Bestätigung gesperrt. Manuelle Basisgrenzen bleiben erhalten.
- Eigene benannte Profile mit validiertem Import/Export, Vorschau, bestätigtem Ersetzen und Sicherung vorheriger Datei. Atomare Anwendung im Dienst.
- Einmalige, tägliche, werktägliche, wöchentliche, zweiwöchentliche, monatliche und jährliche Aufgaben im Dienst. Zeitzone/DST, fehlende Monatstage, neuester verpasster Termin, manuelle Übersteuerung, persistente Ausführungsstände und 100-Einträge-Verlauf.
- Experimentelle Schreibintents und eigene Profil-Entities ergänzen Leseintents. Kein REST-Token erforderlich. Erfolg beschreibt gespeicherten Auftrag, keine garantierte Hardwarewirkung.
- Kalibrierungsmodell 100→10→100→eine Stunde halten, persistente Phasen, Abbruch, Reserve, Frist, Sensor-/Wärmepausen und UUID-Schutz. Produktionsstart ohne bestätigten Backend gesperrt.
- Nächste-Aufgabe-Karte, kombinierte Menüanzeigen, Diagnoseexport mit festem Schema. Optionale explizit gestartete Wachhaltung bis zum Limit, höchstens zwei Stunden, kein normaler Schreibtisch-Schlafblock.
- REST-Protokollprüfung über echte TCP-Verbindungen, macOS-CI, Dokumentation und Changelog ergänzt.

## Echte Prüfungen

- 287 lokale Tests bestanden (96 XCTest, 191 Swift Testing). Release-Build und App-Intents-Metadaten erfolgreich. Der Grenztest mit 50 Aufgaben und 100 Verlaufseinträgen deckte eine zu kleine IPC-Nachrichtengrenze auf; auf begrenzte 1 MiB korrigiert, absolute Frist und Peer-Prüfung bleiben erhalten.
- REST: acht langsame Anfragen angenommen, neunte abgewiesen, Freigabe nach absoluter Fünf-Sekunden-Frist, keine Speicherung verspäteter Anfragen, anschließend acht neue Anfragen erfolgreich. Nur temporäre Testkonfigurationen.
- Öffentliche IOPM-Schnittstelle: isolierte Zwei-Sekunden-Idle-Sleep-Assertion erstellt, Eigenschaften lesbar, nach Ablauf nicht mehr vorhanden. Keine Lade-/Entladeaktion und kein Schlafzyklus. Das ersetzt keine vollständige Abnahme der Dienstfunktion.
- Lesender Daemon-Dry-Run: Dienst 0.3.7 meldet auf diesem Mac nur `CHIE`, 79 %, echten Akku-Fluss 0 W und natives Limit 80 %. Mit externem Monitor bleibt das Netzteil verbunden; ohne separate Ladesperre übernimmt macOS. Keine Hardware-Schreibprüfung ausgeführt.
- Öffentlicher AppIntentsTesting-Harness gebaut und ad-hoc signiert. XCTest-Runtime scheitert vor beiden Intent-Tests mit „Timed out while enabling automation mode“, Exit 65. Keine systemweite Intent-Ausführung nachgewiesen, keine Berechtigungsumgehung.
- Offscreen-Rendering der eigenen Views mit Beispieldaten; dabei gekürzte Profil-Buttons erkannt und angepasst. Das ist keine native Tastatur-/VoiceOver-Abnahme.

## Reviews und externe Voraussetzungen

Gemini 3.8 Flash High / effort high erstellte getrennte Programmierpakete. Claude Sonnet 5.5 High lieferte gezielte Reviews. Befunde wurden am Code geprüft; ein interner unabhängiger Review fand zusätzlich eine stale-edit-Kollision und die verlorene Hitzeschutz-Sperre bei auslaufenden Sonderaufträgen. Beide wurden mit Regressionen korrigiert.

Der letzte Claude-Aufruf meldet `Individual quota reached` und Status ERROR, ohne Reviewausgabe. Die vom Nutzer erwartete Rücksetzung um 03:00 ist nicht beim Anbieter bestätigt; keine neuen Restprozente angenommen. CLI-Tokenstatistiken sind keine Anbieter-Kontingentprozente.

- Lokaler Dienstupdate benötigt Administratorfreigabe (`sudo -n` meldet Passwort erforderlich). Keine Umgehung. Appupdate ersetzt keinen privilegierten Dienst.
- `security find-identity` meldet **0 gültige Codesign-Identitäten**. Developer-ID/Notarisierung daher nicht praktisch abgenommen; Community-DMG ad-hoc signiert.
- Kein bestätigter neuer Hardware-Backend für Halten, Einmalentladung, Kalibrierung, Deckelentladung oder Ladestopp im Schlaf. Kein geratener LED-Blinkwert. Keine unbeaufsichtigten Live-Zyklen.
- Zwei-Benutzer-Abnahme, komplette Hardwarematrix und native Kurzbefehle-Suche/-Ausführung bleiben offen.
- Energiemodi: dokumentierter Systemeinstellungsweg; automatische Modussteuerung und Modellabnahme bleiben optional offen.

## Primärquellen für die neuen Systemteile

- [Apple: öffentliche IOPM-Assertion mit Timeout](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti)
- [Apple: AppIntentsTesting](https://developer.apple.com/documentation/appintentstesting/testing-your-app-intents-code)
- [Apple: Energiemodi](https://support.apple.com/en-us/101613)
- [GitHub: Xcode-27-Runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
