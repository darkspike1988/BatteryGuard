# B-Guard 0.9.0 (Arbeitsstand, unveröffentlicht)

0.9.0 ergänzt Auswertung, Geräteakkus, IT-Verwaltung und Datenschutz. App und Hintergrunddienst haben Version 0.9.0.

## Lebensdauer-Analyse und PDF-Bericht (R19)

Im Verlauf zeigt ein neues Panel Temperatur (Minimum, Mittel, Maximum), den Zeitanteil unter 20 %, 20–80 % und über 80 %, die mittlere Lade- und Entladeleistung aus dem Minutenverlauf sowie Kapazitätsquote und Zyklen aus den Tageswerten. Trends je Monat erscheinen erst bei mindestens 30 Tagen Abstand. „PDF-Bericht sichern“ erzeugt eine A4-Seite mit denselben Kennzahlen; sie enthält keine Seriennummern, Profile oder Prozessnamen. Spannungsverläufe fehlen, weil der Minutenverlauf keine Spannung speichert.

## Geräteakkus (R20)

Die Diagnose zeigt Akkustände verbundener Geräte aus `system_profiler SPBluetoothDataType` (AirPods mit links, rechts und Case) und Apple-HID-Geräten aus der IORegistry (`BatteryPercent`). Abfrage nur bei sichtbarer Diagnoseseite, höchstens alle fünf Minuten. Logitech-Geräte melden ihren Akku auf dem Testgerät nicht an macOS.

## IT-Vorgaben, Sicherung und Wiederherstellung (R21)

- **Konfigurationsprofil:** Domain `com.batteryguard.app`, Schlüssel `LockSettings`, `UpperLimit`, `LowerLimit`, `Mode`, `ProtectionEnabled`. Der Dienst setzt die Werte bei jedem Regeltakt durch; mit `LockSettings` lehnt der Einstellungsdienst Änderungen normaler Benutzer ab (Abfragen bleiben möglich). Die App zeigt die Vorgaben an und sperrt die betroffenen Abschnitte.
- **Sicherung:** „Einstellungen sichern“ schreibt Ladegrenzen, Modus, Schutz, Automatik, Zeitpläne und App-Darstellung als JSON (höchstens 512 KiB). Laufende Aufträge, Verläufe, Reisezeiten, Zeitstempel und der API-Token gehören nicht dazu. „Sicherung wiederherstellen“ übernimmt die Einstellungen, legt Zeitpläne über die validierte Aktion an und lässt laufende Aufträge unverändert.

## Verschlüsselter Verlauf (R22)

Optional speichert die App den Minutenverlauf mit AES-256-GCM (CryptoKit). Der Schlüssel liegt im Anmelde-Schlüsselbund (`AfterFirstUnlockThisDeviceOnly`). Verschlüsselte Dateien beginnen mit „BGENC1“ und werden beim Laden automatisch erkannt. Fehlt der Schlüssel, bleibt die Datei unangetastet, statt als beschädigt verschoben zu werden. Die Kapazitäts-Tageswerte bleiben unverschlüsselt.

## Prüfstand

287 Tests in 45 Suiten (Swift Testing) bestanden, neu: Lebensdauer-Analyse, Bluetooth-Parser, Konfigurationsprofil und Sperre im Einstellungsdienst, Sicherung und Wiederherstellung, Verschlüsselung samt Umgang mit fehlendem Schlüssel.
