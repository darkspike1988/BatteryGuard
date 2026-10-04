# B-Guard Roadmap

Stand: 4. Oktober 2026 · Umsetzungsstand: 0.3.0

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

Validierung: 63 Tests in acht Suiten bestanden, Debug-/Release-Build und DMG-Verifikation erfolgreich, gerenderte Hell-/Dunkel- und Monitor-Vorschauen geprüft. Hardwarewirkung von Monitorereignissen, Schlaf/Aufwachen und Readback muss weiterhin am jeweiligen Mac geprüft werden.

## Bewusst außerhalb des Plans

Keine garantierten Lebensdauer- oder Verschleißprognosen, keine Telemetrie und keine eigenmächtigen Änderungen an Apples nativem Ladelimit. Unbeaufsichtigte privilegierte Selbstupdates sind derzeit nicht geplant.
