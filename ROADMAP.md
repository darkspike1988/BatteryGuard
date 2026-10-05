# B-Guard Roadmap

Stand: 5. Oktober 2026 · Umsetzungsstand: 0.3.7

Der aktuelle [Schlachtplan mit Review, Marktanalyse und AlDente-Pro-Abgleich](docs/STRATEGY.md) ergänzt diese bisherige Umsetzungshistorie. Die zwei dort beschriebenen Fehler bei konkurrierenden Änderungen sind in 0.3.2 korrigiert; weitere Pro-Funktionen bleiben geplant.

## Nächste Umsetzung: Funktionsumfang aus AlDente Pro

Diese Roadmap beschreibt eigene B-Guard-Implementierungen anhand der [offiziellen Funktionsseite](https://apphousekitchen.com/aldente-overview/features/) und der [Preisübersicht](https://apphousekitchen.com/de/aldente/preisgestaltung/), geprüft am 4. Oktober 2026. Die Pakete sind priorisierte Ziele, keine bereits verfügbaren Funktionen oder festen Veröffentlichungstermine. B-Guard bleibt kostenlos und MIT Open Source. Die weiter unten dokumentierte Umsetzungshistorie bleibt erhalten. Für die nächste Arbeit gilt die Reihenfolge hier; sie aktualisiert die ältere Reihenfolge in [STRATEGY.md](docs/STRATEGY.md).

### Reihenfolge und Abhängigkeiten

| Paket | Priorität | Ergebnis | Voraussetzung |
| --- | --- | --- | --- |
| P1 | Hoch · teilweise in 0.3.5 | Power Flow und zusätzlicher Hardware-Ladestand (teilweise umgesetzt) | Verifizierte lesende Messquellen |
| P2 | Hoch | Native Kurzbefehle und gemeinsame Aktionsschnittstelle | Bestehendes atomisches Dienstprotokoll |
| P3 | Hoch | Vollständiges Top Up, Einmalentladung und „Laden hier halten“ | Fähigkeitsprüfung für jede Steueraktion |
| P4 | Hoch | Eigene Profile und wiederkehrende Zeitpläne | P2/P3 und definierte Konfliktregeln |
| P5 | Mittel | Frei konfigurierbares Menüfenster, Symbolstile und LED-Optionen | P1; LED-Fähigkeit je Hardware |
| H1 | Parallel · zunächst lesend | Bestätigte Backends für Sailing, Deckel und Schlaf | Hardware-/Firmware-Abnahmematrix |
| P6 | Später | Manueller Kalibrierungsassistent | H1 mit bestätigter Lade-/Entladesteuerung |

### P1 — Energiefluss verständlich anzeigen (teilweise umgesetzt in 0.3.5)

- **Power Flow & Snapshot:** Rein lesender Snapshot aus `AppleSmartBattery` alle 2 s, rein in der App umgesetzt. Bestehender Dienst 0.3.2 bleibt kompatibel.
- **Berechnungen & Messwerte:**
  - Netzteileingang: tatsächlicher gemeldeter Wert `SystemPowerIn / 1000` (in Watt). 0 W wird nur bei bestätigt getrenntem Netzteil angezeigt.
  - Batteriefluss: vorzeichenbehaftet aus `Voltage * InstantAmperage / 1e6` (in Watt, Laden positiv / Entladen negativ).
  - Mac-Leistung: geschätzter Systemverbrauch aus Differenz `Eingang - Batterie`.
  - Nennleistung: `AdapterDetails.Watts` (z. B. 65 W) ist reine Typ-Nennleistung, niemals tatsächlicher Verbrauch.
  - Hardware-%: nur bei vorhandenem Rohkapazitätspaar, andernfalls unbekannt (`—`).
- **Quellen & Grenzen:** Basiert auf unabhängig verifizierten Community-Quellen ([robzr Gist](https://gist.github.com/robzr/2abf9c7e7f576d8af00d90b671489b48) und [power-flow-lite](https://github.com/isliliming/power-flow-lite)). Dokumentiert praktische Einheiten, keinen offiziellen Apple-Vertrag. Undokumentierte IOKit-Schlüssel variieren nach Hardware/macOS. Eine Frische von 10 s (`collected-at`) garantiert keine Sensoraktualisierung durch die Firmware; keine Steckdosenmessgerät-Genauigkeit.
- **Oberfläche & Schnittstellen:** Optionale Menüleistenkarte (standardmäßig aus), vom Darstellungs-Reset umfasst. Authentifizierter Endpunkt `GET /api/v1/power-flow` (bei veralteten Daten `available: false` ohne numerische Werte) und CLI-Befehl `B-Guard.app/Contents/MacOS/BatteryGuard --read-power-flow` (einmaliger JSON-Snapshot ohne Einstellungs- oder Steuerungsänderung).
- **Status:** P1 ist teilweise umgesetzt. Native Kurzbefehle/Intents (P2) und Kalibrierung (P6) sind separate spätere Pakete.

**Abnahme:** Netzteilbetrieb bei 0 W Akkustrom, Laden, Entladen, schwaches Netzteil mit Akku-Unterstützung, fehlende/veraltete Sensoren und Vorzeichen testen. Konkrete Hardwarewerte lesend gegenprüfen. Ein Diagramm darf nur tatsächlich verfügbare Flüsse zeigen. In 0.3.5 per Simulation und lokalem Netzteil-Snapshot teilweise erfüllt; physische Prüfung der weiteren Zustände und Modelle bleibt offen.

### P2 — Native Kurzbefehle

- App Intents für Batteriestand, Temperatur, Status und Profil/Ladeziel auslesen.
- Danach Profile wählen, Schutz starten/stoppen, zeitlich pausieren/fortsetzen, Vollladen und Reise planen/abbrechen. Neue P3-Aktionen anschließend ergänzen.
- UI, REST und Kurzbefehle verwenden dieselbe validierte, atomare Aktionslogik. Native Kurzbefehle benötigen keinen REST-Token und keine eingeschaltete REST API.
- Fehlender/alter Dienst, inaktive Benutzersitzung und nicht unterstützte Hardware liefern einen konkreten Fehler. Erfolg erst nach bestätigter Speicherung; gespeicherter Wunsch und tatsächliche Hardwarewirkung bleiben unterscheidbar.
- Stromspar-/Hochleistungsmodus als optionalen Teilauftrag recherchieren. Nur dokumentierte, unterstützte Wege integrieren; kein Modusangebot für ungeeignete Macs.

**Abnahme:** Echte Kurzbefehle aus Apples Kurzbefehle-App ohne Terminal verwenden; Lese- und Schreibaktion bei geschlossener B-Guard-Oberfläche, verweigerte Aktion und Konkurrenz zu REST/UI prüfen. Build muss die erforderlichen App-Intents-Metadaten enthalten.

### P3 — Sonderaktionen mit klarer Rückkehr

- **Top Up bis Abstecken:** 100 % erreichen und am Netzteil bewahren; danach Basisprofil wiederherstellen. Persistente Request-ID, feste maximale Frist und Abbrechen. Wiederaufnahme nach App-/Dienstneustart und Netzteilwechsel definieren. Hitzeschutz bleibt aktiv.
- **Einmal entladen auf X %:** Ziel, Reserve, Frist, Abbrechen und Rückkehr zum Basisprofil. Bei fehlender Fähigkeit oder Monitor-/Deckelkonflikt verständlich ablehnen. Automatische Entladung über dem Limit als getrennte bestehende Option behandeln.
- **Laden hier halten:** Aktuellen Ladestand als befristetes Ziel übernehmen, nur bei bestätigter geeigneter Steuerung. Der Hitzeschutz bleibt aktiv. Die bestehende „Schutzpause“ gibt die Regelung weiterhin frei und wird nicht umgedeutet.
- Alle Sonderaktionen in UI, REST und Kurzbefehlen anbieten; kein alter Abschluss darf eine erneuerte Anforderung löschen.

**Abnahme:** Abstecken, USB-C-/Dockwechsel, Neustart, Timeout, erneuter Auftrag, alte Abschlüsse, Sensorverlust und Hitzeschutz simuliert prüfen. Wirkung auf dem jeweiligen Backend physisch bestätigen, bevor eine hardwareabhängige Aktion freigegeben wird.

### P4 — Eigene Profile und wiederkehrende Regeln

- Benannte Profile speichern, bearbeiten, löschen sowie mit Vorschau importieren/exportieren. Keine API-Tokens oder temporären Ausnahmeaufträge exportieren.
- Eigene Profile atomar anwenden; untere/obere Grenze und optionale Schutzparameter explizit definieren. Import validieren, Größen begrenzen und Namens-/ID-Konflikte verständlich lösen.
- Zeitpläne zunächst einmalig, täglich, an Werktagen und wöchentlich; danach zweiwöchentlich, monatlich und jährlich. Fehlende Monatstage ausdrücklich behandeln.
- Aktionen: Profil/Ladelimit, Top Up, Laden hier halten und Einmalentladung. Kalibrierung und Energiemodi erst ergänzen, sobald die jeweiligen Pakete abgenommen sind.
- Ausführung im Hintergrunddienst, damit die App geschlossen sein darf. Aktivierung, letzte/nächste Ausführung, Ergebnis und begrenzten lokalen Aufgabenverlauf anzeigen.
- Optional nur die aktuell relevante verpasste Ausführung nachholen; keine alten Entlade-/Kalibrierungsaufträge stapeln. Zeitzone, Sommerzeit, Uhrzeitkorrektur und Wake berücksichtigen.
- Priorität: Hardware-Sicherheit → wirksame Schutzbedingungen → aktive manuelle Ausnahme → gültiger Zeitplan → Basisprofil. Dauer einer manuellen Übersteuerung sichtbar machen.

**Abnahme:** Genau eine Ausführung bei DST/Wake; kein unerwartetes Zurücksetzen einer manuellen Profilwahl; Regeln laufen bei geschlossener App. Import mit ungültigen Daten und Konflikten getestet, Einstellungen bleiben bei Fehlern erhalten.

### P5 — Darstellung und MagSafe ausbauen

- Menüfenster um wählbare Karten für Energiefluss, Hardware-Prozent, Verlauf und nächste Aufgabe erweitern. Reihenfolge, kompakte Ansicht und „Standard wiederherstellen“ anbieten; Aktionen und Fehler bleiben erreichbar.
- Zusätzliche monochrome Symbolstile und kombinierbare Messanzeigen. Keine zusätzlichen Polling-Timer pro Widget; Tastatur, VoiceOver, Hell-/Dunkelmodus und geringe Bildschirmhöhe prüfen.
- MagSafe-Modi: Automatisch, Grün, Orange, Orange blinkend und Aus; optional Aus im Schlaf. Nur nachgewiesene Modi freigeben, Fehler drosseln und vorherigen Hardwarezustand wiederherstellen.

**Abnahme:** Alle Kartenkombinationen bleiben bedienbar, lange Menüs scrollbar. LED-Wirkung pro unterstütztem Anschluss/Modell tatsächlich bestätigt; unbekannte Fähigkeiten nicht als unterstützt anzeigen.

### H1 — Sailing, Deckel, Schlaf und Benutzerwechsel

- Backends anhand tatsächlicher Fähigkeiten auswählen: separate Ladesperre, Adaptersteuerung, bestätigte Firmwaresteuerung oder native Beobachtung. Modell, Firmware und Berechtigungen zählen; die macOS-Version allein genügt nicht.
- **Sailing:** Netzteil verbunden lassen und erst unterhalb der Untergrenze nachladen. Aktives Adapter-Pendeln bleibt ein anderer Modus und darf nicht als gleichwertiges Sailing beworben werden.
- **Deckelentladung:** Nur anbieten, wenn Displaybetrieb und Rückkehr zuverlässig funktionieren. Keine automatische Schlafsperre im normalen Schreibtischprofil; das behobene Deckelproblem darf nicht zurückkehren.
- **Laden im Schlaf stoppen:** Persistente Hemmung mit Readback, physischer Wirkung und Wiederherstellung prüfen. Bis dahin bestehende Freigabe vor Schlaf beibehalten.
- **Wach bis zum Limit:** Allenfalls ausdrückliche, befristete Option mit sichtbarer Erklärung; bei Abstecken, Frist, Abbruch oder Fehler Wachhaltung lösen.
- **App-Ende und Benutzerwechsel:** Bestehenden weiterlaufenden Dienst dokumentieren; zwei Konten praktisch prüfen. Eine Batterie hat eine Gerätekonfiguration; Hintergrundkonten dürfen diese nicht ändern.

**Abnahme:** Verfügbare Testgeräte nach Chip, macOS/Firmware, Anschluss und Monitor erfassen. Deckel zu/auf, Sleep/Wake, Neustart, Benutzerwechsel und Restore testen. Nicht geprüfte Kombinationen bleiben unbekannt. Keine geratenen SMC-Schreibwerte oder Umgehung privater Berechtigungen.

### P6 — Kalibrierungsassistent

- Explizit manuell starten; Phasen: bis 100 % laden → kontrolliert bis 10 % entladen → erneut bis 100 % laden → eine Stunde halten → Basisprofil wiederherstellen.
- Zustand und Request-ID speichern; Abbruch, Gesamtfrist, Reserve, Stromunterbrechung, Sensorverlust und Neustart berücksichtigen. Temperaturbedingte Pause und Fortsetzung anzeigen; Hitzeschutz bleibt aktiv.
- Nutzen als mögliche Verbesserung der Ladestandsschätzung erklären. Keine garantierte Lebensdauer-/Kapazitätsverbesserung und kein standardmäßiger monatlicher Zwangszyklus.
- Zeitplanintegration erst nach manueller Abnahme; pro Gerät nur mit bestätigtem Backend freigeben.

**Abnahme:** Jede Phase und jeder Ausfallpfad zunächst simuliert; danach eine ausdrücklich gestartete physische Testfolge auf geeigneter Hardware. Abbruch führt zuverlässig zum Basisprofil, ohne fremde oder neu gestartete Anforderungen zu löschen.

### Begleitende Qualität und Veröffentlichung

- Offene REST-Abnahme: acht langsame Verbindungen, Ablehnung der neunten, Freigabe nach Deadline und keine nachträgliche gespeicherte Aktion.
- macOS-CI für relevante Tests, Release-Build, Shell- und Bundleprüfung; Diagnoseexport ohne Token, Seriennummern, persönliche Pfade oder genaue Reisezeiten.
- Developer-ID/Notarisierung separat praktisch abnehmen, sobald ein Zertifikat verfügbar ist. E-Mail-Support ist kein kopierbares Softwaremerkmal; Issues und Diagnose bleiben der aktuelle Supportweg.
- `agy` mit `gemini-3.8-flash-high` und effort high für kleine isolierte Programmieraufträge verwenden; Streaming-Fortschritt kontrollieren, anschließend Code selbst reviewen und erforderliche Tests ausführen. Agenten veröffentlichen oder installieren nicht eigenständig.
- Pro freigegebenem Paket: Roadmap und Changelog aktualisieren, App-/Dienstversion passend setzen, Einstellungen und Verlauf erhalten, DMG bauen/verifizieren und GitHub/Website aktualisieren. Hardwarewirkung nur dort zusagen, wo sie belegt ist.

## Bisherige Umsetzung und offene Abnahmen

Die Reihenfolge richtet sich nach konkreten Review-Befunden. Die folgenden Funktionen sind in 0.3.0 umgesetzt; offene Abnahmen und externe Voraussetzungen stehen separat.

## Erledigt: Stabilität

- **Reisepläne erhalten:** Vollladen über eine gemeinsame Aktion beenden. Ein zukünftiger Reiseplan bleibt dabei bestehen; ein gerade aktiver Plan wird beendet. Regressionstests für beide Fälle.
- **Verlauf reparierbar machen:** Beschädigte JSON-Dateien als Sicherung erhalten, mit sichtbarem Hinweis eine neue Aufzeichnung beginnen. Nach einer Uhrzeitkorrektur dürfen zukünftige Messpunkte aktuelle Aufzeichnungen nicht blockieren. Tests für beschädigte Dateien und Zeitsprünge.
- **Ladegrenzen vereinheitlichen:** Menü und Einstellungen verwenden dieselben gültigen Bereiche. Bestehende schmale Bereiche wie 79–80 % bleiben editierbar.
- **Status verständlicher zeigen:** Profilziel und tatsächlich angewandte Steuerung unterscheiden. Bei externem Monitor und fehlender separater Ladesperre deutlich erklären, dass macOS das Limit übernimmt.
- **Aktionen klar benennen:** Dauerhaftes Ausschalten von einer zeitlich begrenzten Schutzpause unterscheiden. Einrichtung während einer laufenden Installation nicht versehentlich schließen lassen.

Abnahme: gezielte Regressionstests, Debug-/Release-Build und gerenderte Vorschauen für Menü, Einstellungen und Monitor-Fallback. Keine Änderungen an den gespeicherten Nutzerprofilen durch die Prüfung.

## Erledigt: Regelung und Hardwarezuverlässigkeit

- Hitzeschutz mit Temperatur-Hysterese versehen, damit Messwerte nahe der Schwelle nicht ständig umschalten.
- Bei heißem Akku an der unteren Reserve ein Wechseln zwischen benachbarten Prozentwerten verhindern; eingeschränkte Schutzwirkung klar anzeigen.
- Monitoränderungen unmittelbar auswerten; regelmäßiges Polling bleibt als Rückfallebene erhalten.
- Seltene lesende Kontrolle bekannter Hardwarewerte ungefähr alle 60 Sekunden durchführen, um Änderungen durch Firmware oder macOS zu erkennen.

Offene Abnahme: dokumentierte physische Tests für externen Monitor, Deckelschließen, Schlaf/Aufwachen und unterstützte Hardware. Die bisherigen sicheren Rückfallregeln bleiben erhalten. Ein geänderter Dienst benötigt einen eigenen Versionshinweis und die macOS-Administratorfreigabe zur Aktualisierung.

## Erledigt: Bedienung und Updates

- Downloadfortschritt und Abbrechen für Updates.
- Tatsächlichen Mitteilungsstatus anzeigen und bei verweigerter Freigabe zu den Systemeinstellungen führen.
- Verlauf um eine zugängliche Textzusammenfassung und per Tastatur lesbare Messpunkte ergänzen.
- App- und erforderliche Dienstversion beim Update verständlich anzeigen.

## Technische Grundlage und offene Voraussetzungen

- **Vorbereitet, externe Voraussetzung fehlt:** Developer-ID-Signierung und Notarisierung über `scripts/build-notarized.sh`. Kein gültiges Developer-ID-Zertifikat auf diesem Mac; der komplette notarisierten Pfad ist noch nicht praktisch geprüft. Die Community-DMG bleibt ad-hoc signiert.
- **Erledigt:** Authentifizierter lokaler Unix-Socket statt allgemein beschreibbarer Konfiguration. Gegenseitige Peer-UID-Prüfung, root oder aktueller Konsolenbenutzer, feste Nachrichtengröße und absolute Frist. Dienstupdate migriert Konfiguration auf root-eigenes 0644 und bewahrt bestehende Einstellungen.
- **Erledigt:** Gültiger vorheriger Stand wird vor Konfigurationsschreibvorgängen gesichert. Bei JSON-Beschädigung zuerst exakte Originalbytes sichern, dann kontrolliert mit deaktiviertem Schutz wiederherstellen. Dateisperren, Zugriffsfehler und Symlinks werden nicht als JSON-Beschädigung behandelt.

## Review-Arbeitsweise

Interne Review-Agenten prüfen Code, Hardwarelogik und Bedienung getrennt. Die lokal installierte Antigravity-CLI `agy` wird zusätzlich für begrenzte, lesende Research-Aufträge eingesetzt. Ein kleiner Modellaufruf war erfolgreich; nach einem Timeout beim ersten großen Auftrag folgen gezielte Reviews mit engerem Umfang.

Agentenbefunde werden am Code geprüft, bevor sie zu Änderungen werden. Hardwarevermutungen werden nicht als physisch bestätigte Fehler dargestellt. Keine automatischen Hardware-Schreibtests, Installationen oder Veröffentlichungen durch Research-Agenten. Der externe Review bestätigte den Reiseplanfehler und schlug Protokolltests vor; pauschale thermische Gefahrenbehauptungen wurden nicht als Befunde übernommen.

Validierung der damaligen 0.3.0-Arbeiten: 63 Tests in acht Suiten bestanden, Debug-/Release-Build und DMG-Verifikation erfolgreich, gerenderte Hell-/Dunkel- und Monitor-Vorschauen geprüft. Hardwarewirkung von Monitorereignissen, Schlaf/Aufwachen und Readback muss weiterhin am jeweiligen Mac geprüft werden.

## Bewusst außerhalb des Plans

Keine garantierten Lebensdauer- oder Verschleißprognosen, keine Telemetrie und keine eigenmächtigen Änderungen an Apples nativem Ladelimit. Unbeaufsichtigte privilegierte Selbstupdates sind derzeit nicht geplant.

## Lokale Automatisierung · umgesetzt in 0.3.1

- Optionale REST API v1 auf 127.0.0.1:8767 mit Bearer-Token; standardmäßig ausgeschaltet.
- Status, gespeicherte Konfiguration, Fähigkeiten und sieben Tage Verlauf als JSON/CSV.
- Separat freigegebene Aktionen verwenden dieselben validierten Regeln wie die Oberfläche.
- Tests für Authentifizierung, Token-Erneuerung, Anfragen, Konflikte, Speicherfehler und echten HTTP-Verkehr.
- [Dokumentation und Beispiele](docs/api.md). Die App muss laufen; keine LAN-Freigabe.

## Atomare Aktionen und sichere Abschlüsse · umgesetzt in 0.3.2

- Typisierte Aktionen mit IPC-Protokoll 2 werden erst im Dienst unter der Dateisperre auf den aktuellen Zustand angewandt. Feldänderungen und lesende Abfragen bleiben Protokoll 1. Alte Dienste können neue Aktionen nicht als erfolgreiche No-op bestätigen.
- Volllade- und Reiseaufträge erhalten eindeutige IDs. Der Abschluss eines alten Ticks löscht nur dieselbe unveränderte Anforderung, auch bei erneuten Aufträgen mit identischem Zeitstempel.
- Regressionen prüfen aktuellen Servicezustand, echte isolierte Socket-Kommunikation, Altprotokolle, Berechtigungen, neue Deadlines und erneute Reiseaufträge.
- Umsetzung durch Codex nach zwei agy-Aufträgen mit `gemini-3.8-flash-high` / high: beide endeten per Timeout ohne Codeänderungen. Keine ungeprüften Agentenänderungen übernommen.
- Validierung: 90 Tests in 13 Suiten erfolgreich. Hintergrunddienst 0.3.2 erforderlich. Bestehende Einstellungen bleiben erhalten.

## Komfort aus dem Pro-Funktionsvergleich · umgesetzt in 0.3.3

- Konfigurierbare Menüleiste: Symbol, Prozent, Temperatur oder Akku-Leistung mit monochromem Ladering, gespeichertem Modus und VoiceOver-Zusammenfassung.
- Optional zuschaltbare Messwerte im Menüfenster: Temperatur, Akku-Leistung und Gesundheit. Alle Steueraktionen bleiben erreichbar; lange Menüs sind scrollbar.
- Unabhängige Warnschwelle für niedrigen Akkustand: 5–50 %, Standard 20 %, mit 2-%-Hysterese. Das Ladeprofil bestimmt die Warnung nicht mehr.
- Akku-Leistung erklärt realen Lade-/Entladefluss. Auf dem lokalen Mac waren 0 mA bei Netzteilversorgung bestätigt; 0 W ist dort kein fehlender Messwert und kein gesamter Systemverbrauch.
- Teil von A3: UTF-8-JSON mit charset-Parameter akzeptieren; Update-Download vor Abschluss bei überschrittener veröffentlichter Größe abbrechen. Abnahme für acht langsame Verbindungen, neunte Verbindung und Deadline bleibt offen.
- Vier begrenzte Programmieraufträge an agy mit `gemini-3.8-flash-high`, effort high und Streaming-Ausgabe waren erfolgreich. Codex prüfte und korrigierte Einheitenheuristiken, Swift-6-Testzustand und Headerbehandlung; optionale Menüwerte und Erklärung ergänzt.
- Nur Appupdate; vorhandener Dienst 0.3.2 bleibt ausreichend. Nächste größere Arbeitspakete: native Kurzbefehle, eigene gespeicherte Profile und wiederkehrende Zeitpläne. Hardwareabhängige Kalibrierung und Deckelentladung bleiben bis zu einer belegten Abnahme geplant.

Validierung: 109 Tests (100 Swift Testing und 9 XCTest) erfolgreich; Release-Build und Bundle-Signaturprüfung erfolgreich.

## Kontingentplan und kleines P5-Paket · 0.3.4

[Kontingentplan](docs/CONTINGENT_PLAN.md): Aufgabenverteilung Gemini/Claude/Codex, Umfang, Abnahme und externe Hürden anhand der vom Nutzer gemeldeten Restprozente.

- Symbolstile Ladering/Batterie/Schild und Zurücksetzen der Darstellung umgesetzt; Ladeprofile, Mitteilungen, API und Autostart werden vom Reset nicht verändert.
- Gemini programmierte, Claude prüfte unabhängig; Codex korrigierte Statuswahrheit und Reset-Isolation. Tatsächliches Laden wird nicht aus Netzteilanschluss allein abgeleitet.
- P5 ist damit weiterhin teilweise umgesetzt: zusätzliche Karten, Reihenfolge und LED-Modi bleiben offen. Power Flow bleibt der nächste fachliche Schwerpunkt; keine neue Eingangsmessung mit dieser Version.
- Vorhandener Hintergrunddienst 0.3.2 reicht aus.

## Energiefluss und Power Flow · 0.3.5 (P1 teilweise)

- **Rein lesender Snapshot:** Alle 2 Sekunden Erfassung aus `AppleSmartBattery` direkt in der App. Kein Daemon-Update nötig; Hintergrunddienst 0.3.2 bleibt kompatibel.
- **Berechnungen & Heuristiken:**
  - Netzteileingang: `SystemPowerIn / 1000` (in Watt). Bei bestätigtem Akkubetrieb wird Eingang 0 W angenommen; ein tatsächlich gemeldeter Nullwert bleibt auch am Netzteil erhalten.
  - Batteriefluss: `Voltage * InstantAmperage / 1e6` (in Watt, vorzeichenbehaftet).
  - Mac-Leistung: geschätzte Differenz `Eingang - Batterie`.
  - Nennleistung: `AdapterDetails.Watts` (z. B. 65 W) ist reine Typ-Nennleistung, niemals tatsächlicher Verbrauch.
  - Hardware-%: nur bei vorhandenem Rohkapazitätspaar, andernfalls `—`.
- **Quellen & Grenzen:** Unabhängig verifizierte Community-Quellen ([robzr Gist](https://gist.github.com/robzr/2abf9c7e7f576d8af00d90b671489b48) und [power-flow-lite](https://github.com/isliliming/power-flow-lite)), die praktische Einheiten dokumentieren (kein offizieller Apple-Vertrag). Undokumentierte IOKit-Schlüssel variieren nach Hardware und macOS. Frische von 10 s (`collected-at`) garantiert keine Sensoraktualisierung durch die Firmware; keine Steckdosenmessgerät-Genauigkeit.
- **Oberfläche & Schnittstellen:** Optionale Menüleistenkarte (standardmäßig aus), integriert in das Zurücksetzen der Darstellung. Authentifizierter Endpunkt `GET /api/v1/power-flow` (bei veralteten Daten `available: false` ohne numerische Werte) und CLI-Befehl `B-Guard.app/Contents/MacOS/BatteryGuard --read-power-flow` (einmaliger JSON-Snapshot ohne Einstellungs- oder Steuerungsänderungen).
- **Abgrenzung:** P1 ist damit teilweise abgeschlossen. Native Kurzbefehle/Intents (P2) und Kalibrierungsassistent (P6) sind nicht enthalten. 143 Tests bestanden; Release-Build und Bundle-Signatur geprüft. Physische Abnahme bisher auf dem lokalen Mac, keine vollständige Hardware-Matrix.

## Menükarten und lesende Intents · 0.3.6

- P5: Reihenfolge von Messwerten, Energiefluss und Verlauf, optionaler Verlaufsblock, kompakte Darstellung und vollständiger Darstellungs-Reset umgesetzt. Fehler, Ladeaktionen und Beenden bleiben im scrollbaren Menü erreichbar. LED-Modi bleiben offen.
- P2: Zwei lesende App Intents mit JSON-Ausgabe implementiert. Metadaten mit Xcode 27 im Bundle extrahiert; Provider registriert. Tests und echte lesende `perform()`-Aufrufe erfolgreich. Erkennung und Ausführung durch die systemweite Kurzbefehle-App noch nicht bestätigt, deshalb experimentell und P2 nicht abgeschlossen. Steueraktionen, App Entities und gemeinsame Automatisierungsoberfläche folgen separat.
- 168 Tests bestanden. Daemon 0.3.2 bleibt ausreichend. Nächste Abnahme: Kurzbefehle-Systemtest; danach P3 „Top Up bis Abstecken“ als eigenes Zustandsmodell mit Simulation und Review.

## Nachtarbeit · 0.3.7 · 5. Oktober 2026

Der vollständige Umfang bleibt erhalten. **Software umgesetzt** ist ausdrücklich nicht gleichbedeutend mit **System-/Hardware-Abnahme bestanden**.

| Paket | Softwarestand | Verbleibende Abnahme / Voraussetzung |
| --- | --- | --- |
| P1 | Energiefluss wie 0.3.5; fehlende Prozent-/Stromquellen jetzt explizit gekennzeichnet | Weitere reale Lade-/Entladezustände, schwaches Netzteil und Modelle; Rohkapazitätspaar auf diesem Mac fehlt |
| P2 | Lese- und Schreibintents, gespeicherte Profil-Entities, gemeinsame atomare Aktionen; Metadaten im Bundle | Echte Suche/Ausführung durch Kurzbefehle. Öffentlicher XCTest-Harness scheiterte vor Teststart an Automation-Initialisierung; kein Intent-Erfolg behauptet |
| P3 | Top Up bis Abstecken, IDs/Fristen/Abbruch; Hold/Entladezustandsmodell, Dienstaktionen und REST/Intents | Top Up verlangt separate Ladesteuerung. Neue Hold-/Einmalentladeaktionen bleiben ohne physisch bestätigten Backend gesperrt |
| P4 | Benannte Profile mit CRUD/Importvorschau/Export/Sicherung; alle sieben Wiederholungen im Dienst, Übersteuerung und begrenzter Verlauf | Dienst 0.3.7 lokal über Administratordialog installieren; tatsächliche Ausführung mit geschlossener App und Sleep/Wake beobachten |
| P5 | Kartenreihenfolge/kompakt/Reset plus nächste Aufgabe; kombinierte Anzeigen | Native Tastatur/VoiceOver-Bedienung und vollständige Kombinationen; neue MagSafe-LED-Modi und „Aus im Schlaf“ benötigen nachgewiesene Hardware, insbesondere kein geratener Blinkwert |
| H1 | Bestehender Monitor-/Deckelschutz; optionale explizite Wachhaltung mit maximal zwei Stunden, Abbruch-/Fehlerfreigabe | Vollständige physische Matrix für Sailing, Deckel, Schlaf und zwei Benutzerkonten. Keine automatische Schlafsperre im Schreibtischmodus |
| P6 | Persistente Kalibrierungsphasen, Wiederaufnahme, IDs, Abbruch, Reserve, Wärme-/Sensorpausen und Rückkehr simuliert | Start im echten Dienst gesperrt, bis Backend und ausdrücklich gestartete physische Testfolge bestätigt sind; keine Zeitplankalibrierung freigegeben |
| Qualität | REST-Verbindungsgrenzen real geprüft; Diagnoseexport mit festem Schema; macOS-CI hinzugefügt | CI-Ergebnis nach Push prüfen. Developer-ID-Zertifikat fehlt; Notarisierung bleibt extern offen |

Für Energiemodi dokumentiert Apple die Systemeinstellungen als unterstützten Weg. B-Guard bietet weiterhin den Weg zu den Batterieeinstellungen; keine ungeprüfte private Schnittstelle zum automatischen Umschalten. Eine sichere Modellprüfung und automatische Modussteuerung bleiben Teil des offenen optionalen P2-Auftrags.

Neue Regressionen betreffen atomare UI-Aktionen, veraltete unabhängige Einstellungen, erneuerte Aufträge, Sensorverfügbarkeit und eine erhaltene Hitzeschutz-Sperre beim Ablauf von Sonderaktionen. Fehlender Ladestand wird nicht als echte 0-%-Messung aufgezeichnet oder gemeldet.

Konkrete Ergebnisse und externe Grenzen: [Nachtbericht](docs/NIGHT_RESULTS.md). Die Version allein schließt keines der oben offenen Abnahmekriterien ab.
