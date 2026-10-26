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

## Debugging-Runden (23. Oktober 2026)

- **Menüleiste in Endlosschleife (100 % CPU):** `MenuBarExtra(isInserted:)` war direkt an `@AppStorage` gebunden; jede Rückschreibung löste eine neue Aktualisierung aus. Jetzt werden nur echte Änderungen gespeichert.
- **Thread Sanitizer / Address Sanitizer:** ein Datenrennen im Test des SoC-Monitors behoben; sonst keine Befunde. Low-Power-Meldung wird auf dem Hauptthread verarbeitet, der Ladeton blockiert die Oberfläche nicht mehr.
- **Laufzeit:** App etwa 0,5 % CPU und konstanter Speicher, Dienst 0 % CPU und 0 Lecks; 19,5 KB Lecks in Apples App-Intents-Framework (nicht B-Guard-Code).
- **Code-Review:** Netzteil wird wiederhergestellt, wenn das macOS-Limit nicht gesetzt werden kann; Hitze- und Kälteschutz halten im macOS-Limit-Modus aus Sicherheitsgründen auch ohne Opt-in über den Netzteil-Schalter an (Reserve 20 %), im Pendel-Modus mit Reserve an der unteren Grenze; Top Up beachtet Hitzeschutz; `NSError`-Ausgabeparameter korrekt als autoreleasing gebrückt (Absturzgefahr); Apples ursprüngliches Limit wird beim Verlassen des Modus und bei der Deinstallation (`--restore-system-limit`) wiederhergestellt; IT-Vorgaben gelten auch vor dem Schlaf; Kalibrierung gibt vor dem Schlaf frei; WLAN-Regeln brechen keine Kalibrierung oder Sonderaktion ab und versuchen es erneut; Sicherung legt Zeitpläne vor den Einstellungen an; `bguard://`-Befehle von außen erst nach Rückfrage (abschaltbar); beim Ende des Wachhaltens mit geschlossenem Deckel schläft der Mac (nicht mit externem Monitor); die Übersicht zeigt beim Halten unter 80 % das echte Ziel.

## Zusammenführung mit dem Hauptzweig (26. Oktober 2026)

- **Aus dem Hauptzweig:**
  - Review-Korrekturen, Energieverbesserungen und Profile nach Studienlage,
  - „Warum lädt mein Mac so?“ mit Fähigkeitstest der SMC-Schlüssel,
  - Schlafbericht, Ladeketten-Check, Austauschprognose mit AppleCare-Erinnerung.
- **Pendelmodus und eigene Kalibrierung sind entfernt** ([Belege](EVIDENCE.md)). Gespeicherte Pendel-Einstellungen und IT-Vorgaben mit `pendulum` werden zu „Automatisch“.
- **Ziele unter 80 % im macOS-Limit-Modus:**
  - B-Guard schreibt den Wert direkt als macOS-Limit in die Einstellungen von PowerUIAgent und schaltet nicht mehr das Netzteil (CHIE) um.
  - Die Firmware hält den Wert auch im Schlaf.
  - Mit diesem Schalter halten auch Hitze- und Kälteschutz den aktuellen Ladestand über das macOS-Limit. Ohne ihn bleibt der Sicherheitshalt aus 0.7.0.
- **Schlaf:** Standard ist, dass ein erreichtes Limit über die SMC-Ladesperre gesperrt bleibt. „Laden im Schlaf stoppen“ hält zusätzlich den aktuellen Stand.
- **Energiemodi:** B-Guard merkt sich die Werte vor dem ersten Eingriff und stellt sie beim Abschalten und bei `--restore` wieder her.
- **Verlauf:** JSON Lines mit Anhängen. Mit Verschlüsselung wird die Datei als Ganzes versiegelt; ältere verschlüsselte Arrays bleiben lesbar.
- **Zeitpläne:** Neue Aktionen „Ladelimit setzen“ und „Schutz pausieren“.
- **Vergleich mit AlDente:** [B-Guard und AlDente](ALDENTE-VERGLEICH.md).

## Prüfstand

292 Tests in 45 Suiten (Swift Testing) bestanden, auch mit Thread und Address Sanitizer, neu: Lebensdauer-Analyse, Bluetooth-Parser, Konfigurationsprofil und Sperre im Einstellungsdienst, Sicherung und Wiederherstellung, Verschlüsselung samt Umgang mit fehlendem Schlüssel.
