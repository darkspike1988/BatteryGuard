# Abnahme und Testjournal

Stand: 5. Oktober 2026 · Basis: B-Guard 0.3.7.

Diese Abnahme dokumentiert genau eine Geräte-/Software-/Anschlusskombination pro Session. Sie schaltet keine Hardwarefunktion frei. Ein bestandenes Simulationsergebnis ist keine Hardware-Abnahme. Änderungen an macOS/Firmware, App/Dienst oder Anschluss erzeugen eine neue Session; frühere Ergebnisse bleiben historische Belege.

## Journey für einen Testlauf

1. Installierte App und Dienstversion sowie Commit ermitteln. Ausgangsprofil, native Ladeeinstellung und Anschluss privat notieren.
2. Umgebungsvorlage kopieren und unbekannte Felder ehrlich als `unknown` lassen. Gerät mit Pseudonym benennen; keine Seriennummer oder Benutzerkennung.
3. Neues leeres Journal erzeugen. Es enthält anfangs keine ausgeführten Tests.
4. Je Fall Schritte, beobachtetes Verhalten und geprüfte Belegreferenzen erfassen. Einstellungen und tatsächliche Hardwarewirkung getrennt beobachten.
5. Nach Schreibtests Ausgangszustand wiederherstellen. Rückkehr und etwaige Abweichungen ebenfalls in `observed` festhalten.
6. JSON prüfen und Markdown-Bericht erzeugen. Für spätere Auswertung Journal, Bericht und separat überprüfte Belege zusammen bereitstellen.

Kein künstliches Erhitzen, erzwungenes Tiefentladen oder automatischer Kalibrierungszyklus. Sensorverlust und Temperaturgrenzen zunächst simuliert testen. Auf dem Alltagsgerät keine Systemdateien manipulieren oder den Dienst absichtlich downgraden. Nicht verfügbare Systemtestumgebungen als `blocked` erfassen.

## Journal bedienen

Python 3.9+ ohne zusätzliche Pakete; macOS oder Linux. Das Werkzeug sammelt selbst keine Gerätedaten, startet keine App und führt keine Hardwareaktionen aus.

```sh
mkdir -p /tmp/bguard-abnahme
cp docs/validation/environment.template.json /tmp/bguard-abnahme/environment.json
# environment.json vor init manuell mit der tatsächlichen Umgebung ausfüllen.
python3 scripts/validation-journal.py init /tmp/bguard-abnahme/session.json --environment /tmp/bguard-abnahme/environment.json
python3 scripts/validation-journal.py record /tmp/bguard-abnahme/session.json --case S01 --basis system --result blocked --steps "In Kurzbefehle nach B-Guard suchen" --observed "Kein Zugriff auf einen macOS-Testrechner"
python3 scripts/validation-journal.py check /tmp/bguard-abnahme/session.json
python3 scripts/validation-journal.py summary /tmp/bguard-abnahme/session.json > /tmp/bguard-abnahme/report.md
```

Diese Befehle zeigen einen blockierten Fall, keinen durchgeführten Systemtest. Für `passed` und `failed` sind tatsächliche Umgebung (Modell, OS samt Build, App, Dienst, voller Commit) sowie mindestens ein `--evidence`-Verweis erforderlich. `--tested-at` akzeptiert ISO 8601 mit Zeitzone; ohne Angabe gilt die aktuelle UTC-Zeit.

- `passed`: Das fallbezogene Sollverhalten wurde beobachtet und belegt.
- `failed`: Ein ausgeführter Test widerspricht dem Sollverhalten.
- `blocked`: Voraussetzung oder Testzugriff fehlt; Grund dokumentieren.
- `not_run`: Nicht durchgeführt.
- `simulation`: Separater Nachweis; zählt nie zu physischer/systemweiter/releasebezogener Abnahme.

Wiederholungstests werden angehängt. Der Bericht zeigt pro Fall den letzten passenden Abnahmeeintrag und zusätzlich alle früheren Fehlversuche. Ein unbekannter Fall, fehlende Belege, falsche Nachweisart oder rückwärts laufende Testzeit werden abgelehnt. Neue Dateien werden mit 0600 geschrieben; vorhandene Journale werden bei `init` nicht ersetzt. Gleichzeitige Aufrufe verwenden eine Dateisperre. Keine Bearbeitung des Journals während eines Schreibaufrufs.

Belegreferenzen sind manuelle Angaben: Das Werkzeug kontrolliert weder deren Existenz noch Inhalt oder Plausibilität. Ein schema-gültiges Journal ist noch kein valider Nachweis. Der Bericht enthält keine automatischen Freigaben und keine scheinpräzise Gesamtgesundheitsnote.

## Hardware-Abnahmematrix

Für jede tatsächlich verfügbare Kombination ein eigenes Journal anlegen. Folgende Zeilen sind eine Planung, keine bestätigte Kompatibilitätsliste.

| Geräteklasse | Anschluss | Besonderheit | Abnahme |
| --- | --- | --- | --- |
| Apple Silicon mit separater Ladesperre | USB-C direkt | Auto/Sailing und Top Up | Offen |
| Apple Silicon ohne separate Ladesperre | USB-C direkt | Pendel-Fallback | Offen |
| Apple Silicon mit passendem MagSafe | MagSafe | Anschlussabhängige Steuerung/Energiefluss | Offen |
| Apple Silicon | USB-C-/Thunderbolt-Dock + Monitor | Netzteilversorgung und Dockwechsel | Offen |
| Apple Silicon | Externer Monitor, Deckel geschlossen | Monitor-/Deckelschutz und Wake | Offen |
| Apple Silicon | Zwei Testkonten | Aktiver Konsolenbenutzer | Offen |

Je Zeile mindestens Modell/Chip, macOS-Version und Build, Firmware (wenn bekannt), App-/Dienstversion, Commit, Netzteil, Kabel/Dock, Monitor und Deckelzustand erfassen. Der Chip allein beweist keine Backend-Fähigkeit. Nach System- oder Firmwareupdate Ergebnisse erneut prüfen; unbekannte Werte bleiben unbekannt.

Der maschinenlesbare [Fallkatalog](cases.json) definiert 25 Fälle H01–H11, S01–S08, T01, U01 und R01–R04 mit Sollverhalten. H01 und H02 je nach Backend einzeln als bestanden, blockiert oder nicht durchgeführt dokumentieren; ein Fall entfällt nicht still.

Die [bestehende Abnahmeliste](../ACCEPTANCE.md) samt historischem Gerätebaseline bleibt erhalten. Ihr weitergehender Zielumfang (z. B. LED-Modi und gesperrte Kalibrierungsphasen) wird durch den Fallkatalog nicht automatisch als abgenommen oder freigegeben betrachtet.

## Physische Testfolge

| Fälle | Ablauf | Beleg |
| --- | --- | --- |
| H01/H02 | Im gewählten Profil oberes Limit und nächste Ladefreigabe beobachten | Zeitreihe, Anschluss-/Statusbeobachtung; Readback allein genügt nicht |
| H03/H04 | Monitor verbinden; Deckel schließen/öffnen; Anzeige und Stromversorgung beobachten | Ablauf mit Uhrzeiten und Status vor/nach Wechsel |
| H05 | Normal schlafen lassen und aufwecken | Freigabe vor Schlaf und frische Prüfung danach; Schlaflücken nicht interpolieren |
| H06 | Top Up nur bei verfügbarer Ladesperre; abstecken; USB-C/Dock getrennt prüfen | Auftrag vorher/nachher und Rückkehr zum Basisprofil |
| H07 | Oberfläche beenden, Dienst weiter beobachten; anschließend neu starten | Dienststatus, Zeitplanergebnis und fehlende App-Verlaufsmessungen |
| H08 | Zwei separate Testkonten, aktives Konto wechseln | Erlaubte/abgelehnte Speicheraktion ohne personenbezogene Daten |
| H09/H10 | Energiefluss beim Laden/Entladen und native Limit-Konflikte beobachten | Vorzeichen, Zeitstempel, fehlende Werte, getrennte Nennleistung |

Hitzeschutz, Fristablauf, Sensorverlust und alte Auftragsabschlüsse ergänzend durch vorhandene Swift-Tests belegen; kein realer Sensorfehler wird absichtlich erzeugt.

## Weitere System- und Bedienfälle

T01: Temporären Profilzeitplan in einem ruhigen Ausgangszustand anlegen, Oberfläche beenden und gespeichertes Dienstresultat prüfen. Sleep/Wake separat beobachten; einen manuellen Auftrag kontrolliert dazwischen setzen. Keine Doppel-Ausführung; Testregel entfernen und Ausgangsprofil wiederherstellen. Sommerzeit zunächst simulieren statt die Systemuhr am Alltagsgerät zu verändern.

U01: Alle Menükarten und geringe Fensterhöhe mit Tastatur/VoiceOver prüfen. Reset muss Ladeprofil, API und Mitteilungen erhalten. Sichtbarkeit von Fehlermeldungen separat prüfen.

H11: Wachhalten nur bei geeigneter Ladesteuerung ausdrücklich für kurze Zeit starten. Ziel/Abstecken/Abbruch und Frist in getrennten Durchläufen beobachten; danach normalen Schlaf prüfen. Ohne geeignetes Backend blocked erfassen.

## Belege und Datenschutz

Vor Weitergabe alle Belege selbst prüfen. Der bestehende Diagnoseexport verwendet ein begrenztes Schema; freie Notizen, Screenshots, CSV-Dateien und Kurzbefehle-JSON tun das nicht. Insbesondere Konfigurationsausgaben können genaue Reisezeiten enthalten. Keine Tokens, Seriennummern, persönlichen Pfade, Profilnamen oder Reisezeiten in öffentliche Belege übernehmen. Lokale Rohbelege außerhalb des Repositorys halten; geprüfte Auszüge oder CI-URLs verlinken. Kein automatisches Hochladen.

## Später auswerten

Dem Reviewer das Journal und die tatsächlich verfügbaren Belege geben. Prüfreihenfolge:

1. Stimmen Gerät, Versionen, Build, Commit und Anschluss? Welche Felder sind unbekannt?
2. Welche Fälle wurden wirklich ausgeführt? Simulation und Blocker getrennt zählen.
3. Belegen die Inhalte das Sollverhalten oder nur die Speicherung einer Absicht?
4. Wiederholungen und frühere Fehler nennen; nicht auf andere Geräte extrapolieren.
5. Konkrete verbleibende Lücken, reproduzierbare Fehler und nächste drei Tests nennen.

Änderungen und Entscheidungen stehen in der [Entwicklungs-Journey](../JOURNEY.md), der praktische Kurzbefehleablauf in [shortcuts.md](../shortcuts.md) und der Releaseablauf in [release-validation.md](../release-validation.md).
