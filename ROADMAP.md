# B-Guard Roadmap

Stand: 4. Oktober 2026 · Ausgangsversion: 0.2.3

Die Reihenfolge richtet sich nach konkreten Review-Befunden. Die folgenden Punkte sind geplant und noch nicht umgesetzt; Versionen und Termine sind keine Zusage.

## Nächster Stabilitätsrelease

- **Reisepläne erhalten:** Vollladen über eine gemeinsame Aktion beenden. Ein zukünftiger Reiseplan bleibt dabei bestehen; ein gerade aktiver Plan wird beendet. Regressionstests für beide Fälle.
- **Verlauf reparierbar machen:** Beschädigte JSON-Dateien als Sicherung erhalten, mit sichtbarem Hinweis eine neue Aufzeichnung beginnen. Nach einer Uhrzeitkorrektur dürfen zukünftige Messpunkte aktuelle Aufzeichnungen nicht blockieren. Tests für beschädigte Dateien und Zeitsprünge.
- **Ladegrenzen vereinheitlichen:** Menü und Einstellungen verwenden dieselben gültigen Bereiche. Bestehende schmale Bereiche wie 79–80 % bleiben editierbar.
- **Status verständlicher zeigen:** Profilziel und tatsächlich angewandte Steuerung unterscheiden. Bei externem Monitor und fehlender separater Ladesperre deutlich erklären, dass macOS das Limit übernimmt.
- **Aktionen klar benennen:** Dauerhaftes Ausschalten von einer zeitlich begrenzten Schutzpause unterscheiden. Einrichtung während einer laufenden Installation nicht versehentlich schließen lassen.

Abnahme: gezielte Regressionstests, Debug-/Release-Build und gerenderte Vorschauen für Menü, Einstellungen und Monitor-Fallback. Keine Änderungen an den gespeicherten Nutzerprofilen durch die Prüfung.

## Danach: Regelung und Hardwarezuverlässigkeit

- Hitzeschutz mit Temperatur-Hysterese versehen, damit Messwerte nahe der Schwelle nicht ständig umschalten.
- Bei heißem Akku an der unteren Reserve ein Wechseln zwischen benachbarten Prozentwerten verhindern; eingeschränkte Schutzwirkung klar anzeigen.
- Monitoränderungen unmittelbar auswerten; regelmäßiges Polling bleibt als Rückfallebene erhalten.
- Seltene lesende Kontrolle der Hardwarewerte untersuchen, um Änderungen durch Firmware oder macOS zu erkennen.

Abnahme: Logiktests plus dokumentierte physische Tests für externen Monitor, Deckelschließen, Schlaf/Aufwachen und unterstützte Hardware. Die bisherigen sicheren Rückfallregeln bleiben erhalten. Ein geänderter Dienst benötigt einen eigenen Versionshinweis und die macOS-Administratorfreigabe zur Aktualisierung.

## Bedienung und Updates

- Downloadfortschritt und Abbrechen für Updates.
- Tatsächlichen Mitteilungsstatus anzeigen und bei verweigerter Freigabe zu den Systemeinstellungen führen.
- Verlauf um eine zugängliche Textzusammenfassung und per Tastatur lesbare Messpunkte ergänzen.
- App- und erforderliche Dienstversion beim Update verständlich anzeigen.

## Installation und technische Grundlage

- Developer-ID-Signierung und Notarisierung für weniger Reibung beim ersten Start. Voraussetzung sind passende Apple-Zertifikate; die DMG allein löst Gatekeeper nicht.
- Authentifizierte Kommunikation mit dem Root-Dienst statt allgemein beschreibbarer Konfiguration entwerfen; Migration mit Erhalt bestehender Einstellungen.
- Wiederherstellung nach unterbrochenen Konfigurationsschreibvorgängen verbessern, ohne eine beschädigte Originaldatei still zu überschreiben.

## Review-Arbeitsweise

Interne Review-Agenten prüfen Code, Hardwarelogik und Bedienung getrennt. Die lokal installierte Antigravity-CLI `agy` wird zusätzlich für begrenzte, lesende Research-Aufträge eingesetzt. Ein kleiner Modellaufruf war erfolgreich; nach einem Timeout beim ersten großen Auftrag folgen gezielte Reviews mit engerem Umfang.

Agentenbefunde werden am Code geprüft, bevor sie zu Änderungen werden. Hardwarevermutungen werden nicht als physisch bestätigte Fehler dargestellt. Keine automatischen Hardware-Schreibtests, Installationen oder Veröffentlichungen durch Research-Agenten.

## Bewusst außerhalb des Plans

Keine garantierten Lebensdauer- oder Verschleißprognosen, keine Telemetrie und keine eigenmächtigen Änderungen an Apples nativem Ladelimit. Unbeaufsichtigte privilegierte Selbstupdates sind derzeit nicht geplant.
