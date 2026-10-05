# Ausbauplan: belastbare Akku- und Mac-Diagnostik

Stand: 5. Oktober 2026 · Ausgangspunkt: 0.3.7, Commit 06288623f1b8462bef94a691a26bd40c297cb447. Dies ist ein priorisierter Vorschlag mit Abnahmekriterien, keine bereits implementierte Diagnostik und kein Terminversprechen.

## Produktziel

Ein Nutzer soll beantworten können: Wie steht es um meinen Akku? Warum lädt oder entlädt mein Mac gerade? Gibt es anhaltende thermische oder Ressourcenprobleme? Was kann ich konkret prüfen? Jede Antwort muss ihren Messzeitraum, ihre Datenquelle und ihre Grenzen zeigen.

Drei getrennte Ansichten: Akku, Energie/Temperatur und Systemressourcen. Ein grüner Akku beweist keinen insgesamt gesunden Mac. Hohe CPU-Auslastung beweist keinen Defekt. Fehlende Sensoren dürfen keine grüne Entwarnung erzeugen. „Keine Auffälligkeit in den beobachteten Daten“ ist nur für tatsächlich abgedeckte Messgrößen zulässig.

## Ausgangslage aus dem Code

- Batterieprozente, Zyklen, Temperatur, Kapazitäten und vorzeichenbehaftete Leistung werden gelesen; Energiefluss und ein lokaler Siebentageverlauf existieren.
- In `Sources/batteryguardd/Battery.swift` wird `healthPercent` aus Roh-Maximal-/Designkapazität berechnet und auf 0–100 begrenzt. Unterschiedliche Fallback-Quellen werden verwendet. Dieser Wert ist ein abgeleiteter Kapazitätsquotient, nicht automatisch Apples Anzeige „Maximale Kapazität“.
- Statusfrische ist vorhanden, aber Quellen-/Qualitätsangaben sind noch nicht als einheitlicher Vertrag für jede Messgröße modelliert.
- Verlauf wird nur bei laufender App aufgenommen. App-Ende, Schlaf und Ausfälle sind echte Lücken.
- Der bestehende Diagnoseexport ist bewusst begrenzt; ein breiterer Systembericht braucht einen eigenen Datenschutzvertrag.
- CPU-, RAM-, Speicher- oder Lüfterdiagnostik ist durch diese Änderung nicht eingeführt.

## Reihenfolge

| Paket | Inhalt | Nutzerergebnis | Voraussetzung |
| --- | --- | --- | --- |
| D0 | Messvertrag und Quellenqualität | Jeder Wert ist nachvollziehbar | Erste Aufgabe |
| D1 | Akku-Zustand und Kapazitätstrends | Belastbare Akkuübersicht | D0 und Referenzabgleich |
| D2 | Langzeitverlauf und Energie-/Schlafanalyse | Veränderungen mit Messabdeckung verstehen | D0/D1 |
| D3 | Lesende Mac-Ressourcenübersicht | Hitze, Last und Speicherbedarf unterscheiden | Öffentliche Quellen praktisch prüfen |
| D4 | Erklärbare Regeln und Hinweise | Konkrete, begründete nächste Schritte | D1–D3 und Fehlalarmtests |
| D5 | Geführte Diagnose und Bericht | Problem reproduzieren und teilen | D4, Exportprüfung |
| D6 | Modellübergreifende Freigabe | Bekannte Unterstützung statt Vermutungen | Abnahmematrix und Pilotphase |

### D0 — Gemeinsamer Messvertrag zuerst

Ein lesendes `Measurement<T>`-Modell im Shared-Modul vorsehen: optionaler Wert, Einheit, Quelle, Erfassungszeit, optional bekannte Sensorzeit, Qualitätszustand, Fehlergrund und Methode/Formel bei Ableitung. Qualitätszustände beispielsweise `reported`, `derived`, `stale`, `unavailable`, `unsupported`, `invalid`. Das sind definierte Kategorien, keine erfundenen statistischen Vertrauensprozente.

Quelle nach öffentlicher API, undokumentierter Registry und hardwaregeprüftem SMC-Backend unterscheiden. Ein frischer Lesezeitpunkt beweist keine frische Firmwaremessung. Zusammengesetzte Werte dürfen nicht aktueller oder sicherer erscheinen als ihre Eingänge.

Einheiten an der Quellgrenze normalisieren. Ladestand %, Kapazität mAh, Spannung V, Strom A, Leistung W und Temperatur °C klar trennen; bestehende Reader- und API-Einheiten versioniert migrieren. Keine stillen Änderungen am API-v1-Vertrag. Numerische Rohwerte nur dort erhalten, wo sinnvoll und datenschutzverträglich; ungültige Größen nicht als echte 0 darstellen.

Abnahme: fehlende, veraltete, widersprüchliche, nicht endliche und außerhalb des Quellvertrags liegende Werte testen; positive/negative Ströme; Geräte ohne Akku; Schema-Migration; gleiche Aussagen in UI, REST, Kurzbefehlen und Export. Bestehende Hardwaresteuerung bleibt davon getrennt.

### D1 — Akku-Zustand verständlich und sauber belegen

Akkuübersicht mit Ladestand, gemeldetem Zustand (falls verifiziert verfügbar), Zyklen, modellbezogener Apple-Referenz und abgeleiteter Kapazität. Apples Zustand und einen eigenen Kapazitätsquotienten getrennt benennen; bei nicht verfügbarer Apple-Quelle nicht raten. Werte über 100 % im Analysepfad als gemeldet/abgeleitet erhalten und erklären statt die Beobachtung zu verstecken; UI-Darstellung separat entscheiden.

Modellzuordnung mit gepflegter Apple-Referenzliste und Quellenstand. Unbekannte Modelle bekommen keine pauschale Zyklusgrenze. Apples Zyklusreferenz ist kein Countdown bis zum Ausfall. Einzelne Schwankungen der Kapazität nicht als Verschleißsprung interpretieren.

Kapazität bei vorhandenen Quellen täglich aggregieren; Rohquelle und Tagesstreuung behalten. Batterieaustausch, Quellenwechsel und macOS-Update als Ereignis markieren; Trendsegmente trennen. Ein einzelner negativer Sprung löst zunächst einen Datenprüfhinweis aus.

Abnahme: gleichzeitig abgelesene Werte gegen macOS-Batterieeinstellungen und Systeminformationen vergleichen. Abweichungen ausdrücklich dokumentieren statt Quellen auf vermeintliche Gleichheit zu trimmen. Fixtures für unpassende Einheiten, Quellenwechsel, negative Kapazitäten, Austausch und fehlende Designkapazität. Keine Lebensdauerprognose aus einem Einzelwert.

### D2 — Lokaler Langzeitverlauf

SQLite oder eine vergleichbare transaktionale lokale Ablage vor Umsetzung gegen Datenmenge und Migration prüfen. Vorgeschlagene Aufbewahrung: minutengenaue Daten 30 Tage, Tagesaggregate 12 Monate, einstellbar. Das sind Produktvorschläge, keine derzeitige Funktion.

Messabdeckung pro Diagramm zeigen: beobachtete Minuten, Lücken, Quelle und Stichprobenzahl. Schlaf- und App-Ausfallzeiten nicht interpolieren. Dienstseitige Aufnahme nur als bewusst wählbare Erweiterung mit eigenem Datenschutz-/Ressourcenbudget; die aktuelle App-Aufnahme nicht still ändern.

Entladerate und Energie nur innerhalb hinreichend dichter, gültiger Segmente berechnen; trapezförmige Integration mit klarer maximaler Lücke. Zeit am Netzteil, hohe Ladestände und Temperaturbereiche als beobachtete Nutzung beschreiben, nicht in erfundene „gerettete Zyklen“ umrechnen.

Schlafverbrauch aus gültigen Vorher-/Nachherwerten lediglich als Netto-Ladestandsänderung in Prozentpunkten anzeigen. Zwischenzeitliches Aufwachen, Laden, neu gestartete App und unbekannte Stromversorgung machen die Interpretation unbestimmt. Laufzeitschätzungen nur bei stabiler Entladung, genügend Beobachtung und ausdrücklich sichtbaren Modellannahmen.

Abnahme: Datenlücken, Uhrzeitänderungen, Sommerzeit, Neustarts, voller Datenträger, defekte Ablage, Aufbewahrung und Migration prüfen. Vorher-/Nachher-Referenzintervalle mit tatsächlichem Anschluss dokumentieren.

### D3 — Mac-Ressourcen ergänzen, zunächst lesend

| Messbereich | Erste Umsetzung | Grenzen |
| --- | --- | --- |
| Systemthermik | Öffentliche `ProcessInfo.thermalState`-API und Änderungsereignisse | Keine CPU-Temperatur; keine genaue Drosselungsquote |
| CPU | Systemweite Last aus dokumentiertem, gegen Aktivitätsanzeige geprüften Sampling | Last ist Arbeit, kein Gesundheitsurteil; Definition der Prozentbasis anzeigen |
| RAM | Gesamt-/genutzter Speicher, Swap und validierter Speicherdruck-Indikator | „Wenig frei“ allein ist kein Fehler; Cache berücksichtigen |
| Speicherplatz | Verfügbare Kapazität des relevanten Volumes | Kein SSD-Gesundheitswert; APFS/entfernbarer Speicher separat |
| SSD-Zustand | Nur bei bestätigter zugänglicher Quelle | Kein pauschales SMART-/TBW-Versprechen für Apple-SSD oder USB |
| Lüfter/weitere Temperaturen | Optionales, modellgeprüftes lesendes Backend | Fanlose/unsupported Geräte ausdrücklich behandeln |
| Prozesse | Später optional, zunächst CPU-/Speicherverbrauch | Kein erfundener Energieverbrauch in Watt je App; Prozessdaten können privat sein |

Öffentliche Quellen bevorzugen; SDK-Verfügbarkeit für macOS 14+ vor Integration prüfen. Kein zusätzlicher privilegierter Dauer-Sampler allein für hübsche Widgets. Kein Standard-Root-Aufruf von Diagnosewerkzeugen und keine privaten Berechtigungsumgehungen.

Abnahme: gleichzeitige Referenzmessung, Unterschiede der Messintervalle berücksichtigen; Tests bei Ruhe, Arbeit, Speicherdruck und fehlender Quelle. Wärme nur durch normale Arbeitslast beobachten. Eigene CPU-/RAM-/Energiebelastung über dieselben Zeitfenster mit/ohne B-Guard vergleichen. Vor Freigabe ein numerisches Overhead-Budget auf den Referenzgeräten festlegen und die Ergebnisse veröffentlichen.

### D4 — Erklärbare Hinweise statt Gesamtpunktzahl

Regelwerk mit versionierten Regeln und Tests. Jeder Hinweis enthält: Beobachtung, Quelle, Dauer/Messabdeckung, Erklärung, Alternative und nächsten Prüfschritt. Hysterese und Mindestdauer reduzieren flackernde Warnungen; konkrete Schwellen erst aus Referenz-/Pilotdaten ableiten.

Beispiele für zu validierende Regeln:

- Akku entlädt trotz verbundener Versorgung: Strom-/Leistungsdaten und Adapterquelle prüfen. „Versorgung reicht möglicherweise nicht“ ist eine Hypothese, kein sicherer Kabeldefekt.
- Wiederholt erhöhte Systemthermik: zeitgleich Last und Verlauf zeigen; normale hohe Arbeitslast berücksichtigen. Ohne Taktmessung keine Prozentangabe zum Leistungsverlust.
- Kapazitätssprung: Quelle, Update und Akkuwechsel prüfen, bevor Alterung behauptet wird.
- Speicherengpass: Speicherdruck/Swap zusammen bewerten; freien RAM nicht allein bewerten.
- macOS meldet Servicebedarf: Meldung und Apple-Prüfweg darstellen; eigene Messung nicht als Reparaturdiagnose ausgeben.

Abnahme: Regeln gegen kuratierte unauffällige und auffällige Sessions prüfen. Fehlalarmrate und übersehene Fälle nach Gerät und Datenlage ausweisen. Bei unbekannter Datenlage Hinweis unterdrücken oder als unbestimmt zeigen; „keine Daten“ niemals „gesund“.

### D5 — Geführte Diagnose-Journey für Nutzer

Ablauf: Problem wählen → Datenlage prüfen → Ausgangszustand aufnehmen → begrenzte Beobachtung → Ergebnis erklären → optional bereinigten Bericht exportieren.

Erste Journeys: „Akku hält kürzer“, „Lädt nicht“, „Mac wird heiß“, „Verliert Ladung im Schlaf“, „Mac ist langsam“. Hintergrund: Netzteil/Dock, Monitor, Modus und native Ladeeinstellung können die Interpretation verändern.

Keine automatische Belastungsprüfung oder Entladung. Ein Vorher-/Nachhervergleich desselben Macs braucht vergleichbare Helligkeit, Anschluss, Arbeit und Temperatur; ohne Kontrolle nur beschreibende Korrelation, keine Kausalitätsbehauptung.

Export mit festem, versioniertem Schema. Standardmäßig keine Prozessnamen, persönlichen Pfade, Seriennummern, Tokens oder genauen privaten Termine. Vorschau und ausdrückliche Wahl zusätzlicher Felder. Nutzerjournal für Messsessions und Entwicklungs-Journey für Codeentscheidungen getrennt halten.

Abnahme: Export gegen sensible Marker testen; Nutzer können jeden Hinweis zu seinen Daten zurückverfolgen; Offlinebetrieb und VoiceOver prüfen.

### D6 — Freigabe und langfristige Validität

Nachweis je Kombination aus Modell, macOS/Build, Firmware, Backend und Anschluss. Kein „funktioniert auf allen Apple Silicon“-Versprechen aus einem Referenzgerät. Für reine Diagnose zunächst mindestens verschiedene Chips/Modelle, direkte Versorgung, Dockbetrieb und einen nicht verfügbaren Sensorfall als geplante Pilotabdeckung; konkrete Geräte nur nach tatsächlichem Zugriff als getestet führen.

Hardwaresteuerung separat abnehmen. Jede Veröffentlichung dokumentiert bekannte Einschränkungen, neue Quellen, Regeländerungen und offene Fälle. Bibliothek bereinigter Messfixtures und reproduzierbare Vergleichsjournale führen; OS-Updates lösen erneute Prüfungen relevanter Quellen aus.

## Erste drei Implementierungsaufträge

1. D0: Messmodell plus Einheit-/Frische-/Quellenvertrag und Migration entwerfen; Reader-Fixtures erstellen. Noch keine neuen Warnungen.
2. D1: Aktuellen Kapazitätsquotienten klar kennzeichnen und Roh-/Referenzwerte trennen; Vergleichsjournal mit macOS erstellen.
3. D3 klein: Öffentlichen System-Thermalzustand als lesende Karte ergänzen; Verfügbarkeit, Ereignisse und Eigenverbrauch prüfen. CPU/RAM erst nach diesem vertikalen Durchstich.

D2 anschließend: bessere Datengrundlage vor komplexen Regeln. Ein kostenpflichtiger Funktionsvergleich ist kein Validitätsnachweis; der Nutzen entsteht durch nachvollziehbare Messungen.

## Quellen und Belegstatus

Am 5. Oktober 2026 geprüfte Primärquellen:

- [Apple: Akkuzyklen und modellbezogene Grenzen](https://support.apple.com/en-us/102888): Zyklen sind kumulierter Verbrauch; Grenzwerte unterscheiden sich nach Modell. Keine individuelle Restlebensdauer ableiten.
- [Apple: Thermalzustände auf dem Mac](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html): öffentliche Systemzustände nominal/fair/serious/critical. Keine Celsiusmessung.
- [Apple: thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property) und [Änderungsmitteilung](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification).
- [Apple: IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h): öffentliche Power-Source-Abfragen; ein tatsächlicher Source-Key-Vertrag muss im SDK und auf Testgeräten geprüft werden.
- Repository: `Battery.swift`, `PowerFlowReader.swift`, `BatteryHistory.swift`, `DiagnosticsExport.swift` und bestehende Release-Abnahmen.

Aufbewahrung, Regelgestaltung, Reihenfolge und Prüfmethodik sind unsere Produkt-/Engineeringvorschläge. CPU/RAM/SSD-/Lüfterquellen werden hier bewusst noch nicht als implementiert oder auf allen Macs verfügbar behauptet.
