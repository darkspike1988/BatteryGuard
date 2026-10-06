# Verbleibende System- und Hardwareabnahme

Stand: 5. Oktober 2026, Software 0.3.7. Diese Liste schließt den ursprünglichen Nachtauftrag nicht ab. Für jeden Eintrag sind tatsächlicher Ablauf, erwartetes Ergebnis, beobachtetes Ergebnis und Gerät zu protokollieren. Fehlender Beleg bleibt offen.

## Reproduzierbare Abnahme und Journey

Die [Abnahmematrix mit lokalem JSON-Journal](validation/README.md) ergänzt diese Liste um konkrete Fall-IDs, Geräte-/Versionskontext, Beobachtungen, Belege und eine Markdown-Auswertung. [Kurzbefehle](shortcuts.md) und [Release-Abnahme](release-validation.md) enthalten die praktischen Abläufe. Änderungen und offene Ergebnisse stehen in der [Journey](JOURNEY.md); der weitere Diagnostikausbau in [DIAGNOSTICS_PLAN.md](DIAGNOSTICS_PLAN.md).

Die folgende Gerätebaseline ist ein historischer lesender Befund. Sie wird nicht als aktueller Hardwaretest übernommen; für jede neue Session tatsächliche App-/Dienstversion und Anschluss erneut prüfen.

## Verifiziertes lokales Ausgangsgerät

| Merkmal | Lesend festgestellt |
| --- | --- |
| Modell | MacBookPro18,3 |
| macOS | 27.0, Build 26A428 |
| App | 0.3.7, installiert und gestartet |
| Laufender Dienst | 0.3.2; 0.3.7 nur im App-Bundle |
| Steuerfähigkeiten | Lokal bisher CHIE; keine separate CHTE-/CH0B-Ladesperre nachgewiesen |
| Codesign-Identitäten | 0 gültige Identitäten |

Anschluss, Dock, Monitor und Firmware müssen bei jedem physischen Test zusätzlich angegeben werden. Seriennummern gehören nicht in öffentliche Berichte. Der lesende Snapshot beweist keine Schreibwirkung.

## Voraussetzungen und nächste Schritte

1. In B-Guard Einstellungen den Dienst auf 0.3.7 aktualisieren und den regulären macOS-Administratordialog selbst bestätigen. Anschließend tatsächlich gemeldete Dienstversion prüfen. Kein Passwort in Chat, Repository oder Log eintragen.
2. In Apples Kurzbefehle-App die B-Guard-Aktionen suchen. Zunächst einen lesenden Kurzbefehl bei geschlossener B-Guard-Oberfläche ausführen und Ausgabe dokumentieren. Für eine ausdrücklich gewählte Schreibaktion gespeicherten Auftrag und tatsächliche Hardwarewirkung getrennt beurteilen; eine verweigerte Aktion darf keinen Erfolg melden.
3. Geeignete Testgeräte mit bestätigter separater Ladesteuerung bereitstellen. Auf dem bisher erfassten Mac bleiben entsprechende neue Sonderaktionen gesperrt. Keine geratenen SMC-Werte oder Live-Zyklen zur automatischen Abnahme verwenden.
4. Ein gültiges Developer-ID-Zertifikat und den regulären Notarisierungszugang bereitstellen, bevor der notarisierten Releasepfad praktisch geprüft wird. Derzeitige Community-DMG bleibt ad-hoc signiert.

## Offene Prüfmatrix

| Paket | Tatsächliche Abnahme | Erfolgsbeleg |
| --- | --- | --- |
| P1 | Laden, Entladen, Netzteilversorgung bei 0 W Akku-Fluss, schwaches Netzteil, fehlende Rohkapazität | Gemeldete Quellen, Vorzeichen und Unbekannt-Anzeige pro Zustand; keine Nennleistung als Messung |
| P2 | Native Suche und Ausführung lesend/schreibend; Oberfläche geschlossen; verweigerte Aktion; Konkurrenz mit REST/UI | Systemausführung und gespeicherte Konfiguration, keine bloße direkte perform()-Prüfung |
| P3 | Top Up, Abstecken, Dockwechsel, Dienstneustart, Ablauf, erneuter Auftrag und Hitzeschutz auf bestätigtem Backend | Basisprofil bleibt erhalten, keine fremde Anforderung gelöscht; Wirkung physisch beobachtet |
| P4 | Zeitplan bei geschlossener App, Sleep/Wake, manuelle Übersteuerung | Eine Ausführung mit Aufgaben-ID/Ergebnis; keine Wiederholung oder unerwartete Rücksetzung |
| P5 | Tastatur, VoiceOver, geringe Fensterhöhe und Kartenkombinationen; LED-Modi je Anschluss | Alle Aktionen/Fehler erreichbar; LED-Zustand und Wiederherstellung tatsächlich sichtbar |
| H1 | Deckel auf/zu mit externem Monitor, Sleep/Wake, Neustart, zwei Benutzerkonten, Sailing | Monitorbetrieb bleibt nutzbar; sichere Rückkehr; Hintergrundkonto kann Konfiguration nicht ändern |
| H1 | Ausdrückliche Wachhaltung bis Ziel/Abstecken/Frist/Abbruch | Assertion im installierten Dienst freigegeben; kein normaler Schreibtisch-Schlafblock |
| P6 | Jede Phase und Abbruch einer ausdrücklich gestarteten manuellen Kalibrierung auf bestätigtem Backend | Reserve, Wärme-/Sensorpause, Wiederaufnahme und Rückkehr physisch bestätigt |
| Release | Developer-ID-Signierung und Notarisierung, Download auf anderem Mac | Notarisierungsannahme, Ticketprüfung und regulärer Start ohne Berechtigungsumgehung |

## Protokollvorlage

- Datum, App-/Dienstversion, Modell, macOS/Firmware, Anschluss/Dock/Monitor:
- Ausdrücklich gewählter Test und Ausgangskonfiguration:
- Schritte und erwartetes Ergebnis:
- Tatsächliches Ergebnis und vorhandener Beleg:
- Rückkehr zum vorherigen Zustand:
- Bewertung: bestanden / fehlgeschlagen / unbekannt:

Simulationen, Build-Metadaten und lokale Softwaretests bleiben gültige Softwarebelege. Sie ersetzen keine Zeile dieser System-/Hardwarematrix. Energiemodussteuerung bleibt zusätzlich offen, solange kein dokumentierter unterstützter Schreibweg nachgewiesen ist.
