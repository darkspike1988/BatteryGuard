# B-Guard: Nachtplan ab 03:00 Uhr

Start: **5. Oktober 2026, 03:00 Uhr Europe/Berlin (CEST)**. Der Nutzer erwartet um diese Zeit einen Limit-Reset; dieser wurde nicht beim Anbieter verifiziert. Aufgabe bleibt die vollständige offene Roadmap, nicht nur ein einzelnes Release.

## Reihenfolge und Arbeitsfenster

Die Zeiten sind Planungsfenster, keine Fertigstellungszusagen. Fehler und notwendige Abnahmen haben Vorrang vor Uhrzeiten. Danach weiterarbeiten, solange sinnvolle Fortschritte möglich sind.

| Beginn / Fenster | Paket | Arbeit und Abnahme |
| --- | --- | --- |
| 03:00–03:20 | Bestandsaufnahme / P2 | Git und laufende Prozesse prüfen; bestätigte 0.3.6 als Ausgangspunkt. Native Kurzbefehle tatsächlich im System ausführen, soweit erlaubte Werkzeuge dies ermöglichen. Andernfalls offen dokumentieren, nicht nur Build als Erfolg werten. |
| 03:20–04:20 | P3 | Top Up bis Abstecken, Einmalentladung auf Ziel und Laden hier halten. Erst Zustandsmodell/Simulation, dann atomare Dienstaktionen, REST/UI und schließlich Kurzbefehle. Request-IDs, Fristen, Neustart, Abstecken, Monitor-Fallback und Hitzeschutz prüfen. |
| 04:20–05:20 | P4 Profile | Eigene benannte Profile, Bearbeiten/Löschen, Import/Export mit Vorschau. Limits und Schutzoptionen validieren, Konflikte lösen; keine Tokens oder Ausnahmeaufträge exportieren. Atomare Anwendung. |
| 05:20–06:30 | P4 Zeitpläne | Einmalige, tägliche, werktägliche und wöchentliche Regeln im Dienst. Danach weitere Wiederholungen. Zeitzone, DST, verpasste Termine, Wake, manuelle Übersteuerung und genau-einmalige Ausführung prüfen. |
| Ab 06:30 | P2 / P5 / H1 | Schreibende Kurzbefehle, weitere Karten und nachgewiesene LED-Modi; Fähigkeiten für Sailing, Deckel, Schlaf und Benutzerwechsel prüfen. Nur bestätigte Hardwarefunktionen freigeben. |
| Danach | P6 / Qualität | Kalibrierungsassistent mit Abbruch, Reserve, Temperaturpause und Wiederherstellung; zunächst simulieren. REST-Verbindungsgrenzen, Diagnoseexport, CI, Dokumentation und Release-Abnahmen abschließen. |
| Externe Voraussetzungen | Signierung / physische Tests | Developer-ID/Notarisierung erfordert ein gültiges Zertifikat. Hardwarewirkung und manuelle Kalibrierung benötigen geeignete Testgeräte/ausdrücklich gestartete Tests. Ohne Beleg bleiben Punkte offen. |

## Delegation

- `agy` Gemini 3.8 Flash High / effort high für begrenzte Implementierungen, maximal zwei unabhängig schreibende Aufträge gleichzeitig und eindeutig getrennte Dateien/Worktrees.
- Claude Sonnet 5.5 High gezielt für unabhängige Reviews. Codex integriert, korrigiert und nimmt ab. Interne Subagents dürfen zusätzlich Recherche/Reviews übernehmen, wenn dies den Fortschritt verbessert.
- CLI-Status, echte Dateien und Tests prüfen. Ein Prozess-Exitcode ist kein Erfolg. Timeout/Tool-Schleifen begrenzen; nicht unbegrenzt neue Aufträge starten. Fortsetzungen gezielt statt wiederholter Vollkontexte.
- Keine angenommenen neuen Restprozente, keine automatische Umrechnung von CLI-Tokens in Anbieterprozente.

## Invarianten

- Bestehende Nutzerkonfiguration und Verlauf erhalten; fremde Änderungen nicht überschreiben.
- Isolierte Simulationen/Mocks statt automatischer Live-Entlade- oder Kalibrierungszyklen. Keine geratenen SMC-Schreibwerte, keine Umgehung von Berechtigungen.
- Keine Agenten-Installation/Veröffentlichung ohne Review. Die zuvor autorisierten GitHub-/DMG-/Website-Aktualisierungen bleiben erlaubt, aber nur für geprüfte Pakete.
- App-/Dienstversion passend anheben; notwendiges Dienstupdate ausdrücklich nennen. Administratorfreigaben nicht umgehen.
- Systemweite Kurzbefehle-Erkennung, Hardwarewirkung, Notarisierung und Release-Download müssen jeweils tatsächlich belegt sein, bevor diese Punkte als erledigt gelten.
- Vollständige Roadmap bleibt offen, bis alle Anforderungen einschließlich Abnahmen erfüllt sind. Nicht aufgrund eines guten Teilpakets als fertig markieren.

## Geplanter Start

Der lokale LaunchAgent `com.michael.bguard.roadmap-night` ist für die Startzeit registriert und sendet eine Nachricht an den bestehenden Codex-Thread. Die Zeitgrenze wurde trocken geprüft: 02:59:59 bleibt wartend, 03:00:00 ist startbereit. Vor 03:00 wird kein Modellauftrag gestartet. Er erzeugt keinen zweiten Entwicklerprozess und verändert keine Batterieeinstellungen. Der Mac muss eingeschaltet, angemeldet und online sein; Schlaf kann den Start bis zum Aufwachen verzögern. Der Job darf nach erfolgreicher Zustellung nicht erneut starten. Technischer Zustellstatus wird außerhalb des Repos unter `~/Library/Application Support/BGuardDevelopment/` gespeichert.
