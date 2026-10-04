# B-Guard: Umsetzung mit verbleibenden Modellkontingenten

Stand: 4. Oktober 2026 · Ausgangspunkt: App 0.3.3, Roadmap-Commit e879290.

## Planungsgrundlage

Der Nutzer meldet verbleibend: Codex 46 %, Gemini 90 %, Claude über Antigravity 100 %. Diese Werte sind Nutzerangaben, keine live ausgelesenen Kontingente. Unterschiedliche Anbieterprozente sind nicht in identische Tokens oder Arbeitsstunden umrechenbar. Kontextgröße, Toolaufrufe, Cache, Modell und Rücksetzzeit können den Verbrauch beeinflussen; eine vollständige Roadmap innerhalb dieser Prozente wird nicht zugesagt.

Die lokale CLI bietet `gemini-3.8-flash-high` und `claude-sonnet-5-5-high`. Claude wird über dieselbe installierte Antigravity-CLI angesprochen; dafür wird kein separates Anthropic-API-Konto eingerichtet. Die Modellverfügbarkeit ist per `agy models` geprüft, die konkrete Abrechnung ist damit nicht bestätigt.

## Konkrete Aufteilung

| Aufgabe | Umfang / Unsicherheit | Delegation | Abnahme |
| --- | --- | --- | --- |
| P5 Symbolstile + Darstellung zurücksetzen | Klein; nur App, kein Root-Update | Gemini programmiert, Claude prüft | Monochrom, Status erhalten, Reset verändert nur Darstellung |
| P1 Power-Flow-Messquellen | Begrenzter lesender Spike; Einheiten und Hardware variabel | Gemini untersucht, Claude prüft Quellen/Annahmen | Tatsächliche Eingangsleistung von Netzteil-Nennleistung unterscheiden; fehlende Werte bleiben unbekannt |
| P2 Kurzbefehle zunächst lesend | Mittel; App-Intents-Metadaten/Packaging offen | Gemini implementiert isoliert, Claude prüft | Echter macOS-Kurzbefehl ohne Terminal; kein Erfolg nur durch Swift-Build |
| P5 Kartenreihenfolge/kompakte Ansicht | Klein bis mittel; App-only | Gemini nach erstem Paket | Alle Aktionen/Fehler erreichbar, Tastatur/VoiceOver, kleine Displays |
| P3 Top Up bis Abstecken | Mittel bis groß; Dienstzustand und Request-Races | Gemini für Zustandsmodell/Simulation; Claude Review | Abstecken/Neustart/Timeout/Erneuerung; Hitzeschutz bleibt aktiv |
| P4 eigene Profile und Wochenregeln | Groß; getrennte Pakete erforderlich | Erst Profilspeicher, dann Aktionsprotokoll, dann Zeitplan | Atomare Aktionen, DST/Wake/Importkonflikte; keine verlorenen Nutzeränderungen |
| H1 Sailing/Deckel/Schlaf und P6 Kalibrierung | Hoch; physische Hardwareabnahme notwendig | Zunächst nur Forschung und Simulation | Nicht allein durch mehr Modellkontingent freigabefähig |

## Arbeitsweise zum Kontingentsparen

- Kleine Aufträge mit festen Dateien, eigener Abnahme und begrenzten Leseaufrufen statt wiederholtem Einlesen des ganzen Projekts.
- Gemini übernimmt den Hauptteil der Implementierung, Claude eine unabhängige Prüfung der relevanten Dateien. Codex liest den Diff, beurteilt Befunde, integriert und führt die erforderlichen Prüfungen aus.
- Isolierter Worktree, keine echten Batterieaktionen, keine Live-Präferenzänderungen durch Agenten.
- Streaming-Ausgabe und taskgerechter Timeout (kurzer Review, längerer Implementierungsauftrag). Ein CLI-Exitcode 0 reicht nicht: Ergebnisstatus, Dateien und Diff kontrollieren.
- Keine unbegrenzten Wiederholungen. Bei fehlendem Ergebnis oder wiederholtem Fehler einen engeren Auftrag formulieren bzw. Integration selbst korrigieren; Fehlversuche dokumentieren.
- Gezielte Regressionstests, danach eine vollständige Abnahme pro Veröffentlichung. Weitere Volltests nur nach relevanten Änderungen oder neuen Befunden.
- Nach jedem Paket Status und technische Hürden festhalten. Restprozente erneut vom Anbieter/Nutzer beziehen; aus Laufzeit oder Tokenlogs keine neuen Restprozente erfinden.

## In dieser Sitzung

- Gemini: Symbolstile und Reset im isolierten Worktree beauftragt.
- Claude: begrenzte Bewertung der verbleibenden Arbeit und Power-Flow-Lücken beauftragt.
- Veröffentlichung erst nach Review und erfolgreicher Abnahme; abschließendes Ergebnis wird hier ergänzt.

Nächster fachlicher Schwerpunkt bleibt P1 aus der [Roadmap](../ROADMAP.md): lesender Messquellen-Nachweis, dann Power Flow. Das kleine P5-Paket kann unabhängig davon fertiggestellt werden.

## Geprüfter Kern aus Claudes Einschätzung

Der Claude-Aufruf wurde mit `claude-sonnet-5-5-high` erfolgreich abgeschlossen. Sein Review-Vorschlag wurde am vorhandenen Code eingeordnet: `Battery.swift` berechnet derzeit Batterie-Watt, liest aber keine Eingangsmessung und liefert keinen zweiten Hardware-Ladestand. Quellenqualität und Aktualität neuer Messwerte müssen im P1-Paket ergänzt werden. Pauschale Behauptungen zu angeblich falscher Vorzeichendekodierung werden nicht als Bug übernommen: bestehende Tests prüfen bereits UInt32-/UInt64-Entladestrom. Eine neue physische Vorzeichen-/Einheitenabnahme bleibt sinnvoll.

Die Kontingente ermöglichen vor allem mehr delegierte Arbeit, beseitigen aber keine Hardware-, Packaging- oder Zertifikatsvoraussetzungen. Für das nächste Paket zuerst eine Messquellen-Spezifikation und lesende Abnahme, anschließend begrenzte Implementierung; kein großes unkontrolliertes „alles bauen“-Prompt.

## Tatsächliche CLI-Nutzungswerte dieser Delegation

Alle drei Aufrufe meldeten `SUCCESS`. Die folgenden Werte stammen aus `result.usage` der CLI, nicht aus einer Anbieter-Abrechnung oder einer Restkontingentabfrage:

| Aufruf | Modell | Dauer | Input-Tokens | Output-Tokens | Cache-Read-Tokens | Gemeldete Total-Tokens |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Symbolstile implementieren | Gemini 3.8 Flash High | 113 s | 135.403 | 39.058 | 449.267 | 174.461 |
| Kontingent-/Aufwandseinschätzung | Claude Sonnet 5.5 High | 27 s | 62.268 | 2.801 | 44.103 | 65.069 |
| Unabhängiger Code-Review | Claude Sonnet 5.5 High | 22 s | 53.163 | 2.955 | 59.310 | 56.118 |

Gemini meldete zusätzlich 30.938 Thinking-Tokens. Diese Zahl nicht nochmals auf `total_tokens` addieren: Die CLI meldet Total hier bereits als Input + Output; ihre genaue Abrechnungssemantik ist nicht geprüft. Cache-Tokens sind separat aufgeführt. Große System-/Toolkontexte und mehrere Agentenschritte machen auch kleine Aufträge aufwendig. Folgerung: weitere Aufträge möglichst auf eine Datei/klare Änderung begrenzen und vorhandenen Kontext gezielt wiederverwenden; keine pauschale Zusage, dass verbleibende Prozentwerte die gesamte Roadmap tragen. Neue Restprozente wurden nicht ermittelt.

## Ergebnis

Das kleine P5-Paket wurde als App 0.3.4 umgesetzt: Ladering/Batterie/Schild, sichere Darstellungsvorgaben und Reset. Claude bestätigte den falschen Ladehinweis bei bloßem Netzteilanschluss und den globalen Reset-Zugriff in isolierten Vorschauen; Codex korrigierte beide. Claudes pauschaler Hinweis auf fehlende Preview-Isolation wurde nicht übernommen, weil `DesignPreview` bereits `.defaultAppStorage` verwendet. Nach visueller Prüfung bekam die Batterieanzeige einen kontrastreichen Status-Badge.

115 Tests bestanden (106 Swift Testing, 9 XCTest). Release-Build, Bundle-Signatur, DMG-Prüfsumme und gerenderte Symbolansichten erfolgreich geprüft. Vorhandener Dienst 0.3.2 bleibt ausreichend; keine Hardwareaktion oder Benutzer-Ladeprofiländerung durch Agenten. Die größeren Pakete aus der Tabelle bleiben geplant.

## Fortsetzung mit 36 % Codex laut Nutzer · Power Flow 0.3.5

Mehr Remote-Delegation: neun begrenzte Aufträge über Antigravity, getrennte Dateien; Gemini für Recherche, Modell, Anzeige, Integration und Dokumentation, Claude für Reader, API-Tests und zwei Reviews (insgesamt neun Aufträge). Die 36 % sind eine neue Nutzerangabe; Gemini-/Claude-Restwerte wurden nicht erneut abgefragt.

| Auftrag | Status laut CLI | Dauer | Input | Output | Cache Read | Total |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| research | SUCCESS | 55 s | 90998 | 5767 | 183541 | 96765 |
| model | SUCCESS | 49 s | 85996 | 16938 | 89779 | 102934 |
| ui | SUCCESS | 53 s | 60505 | 18051 | 98013 | 78556 |
| reader | SUCCESS | 62 s | 57934 | 10042 | 91664 | 67976 |
| integration | ERROR | 193 s | 242651 | 55330 | 1470611 | 297981 |
| docs | ERROR | 111 s | 165147 | 25844 | 620488 | 190991 |
| api-tests | ERROR | 54 s | 51485 | 4605 | 218210 | 56090 |
| review | SUCCESS | 68 s | 47221 | 9029 | 115364 | 56250 |
| integration-review | SUCCESS | 34 s | 45774 | 3980 | 59300 | 49754 |

Drei Aufträge (Integration, Dokumentation, API-Tests) meldeten ERROR nach einem Netzwerk-Verbindungsabbruch, obwohl Dateien und Antworten vorhanden waren. Diese wurden einzeln geprüft statt als erfolgreiche Delegation verbucht. Codex korrigierte den falschen Test-Parameternamen, API-Zeitinjektion, unbekannte API-Werte, CLI-Verfügbarkeit/Fehlerausgabe und kleine Darstellungsfehler. Claudes vermuteter CFNumber-Kompilierfehler war durch erfolgreichen Swift-Build widerlegt; ein zusätzlicher Widget-Timer ist unnötig, weil die vorhandene 2-Sekunden-Abfrage jeden Snapshot ersetzt oder löscht. Pauschale Forschungsbehauptungen zu sämtlichen Apple-OSS-Repositories oder Modell-/OS-Grenzen wurden nicht übernommen.

Abnahme: 143 Tests (134 Swift Testing, 9 XCTest), Release-Build und Bundle-Signatur. Live-Snapshot auf diesem Mac: Netzteil-Nennleistung 65 W, Eingang 13,144 W, Akku 0 W, abgeleitete Mac-Leistung 13,144 W; Hardware-Prozent mangels Rohkapazitätspaar unbekannt. Kein aktiver Ladeeingriff zur Abnahme. Die Werte sind Momentaufnahmen und keine Steckdosenmessung. P1 teilweise umgesetzt; nächste Pakete P2 lesende Kurzbefehle und P5 Kartenkonfiguration, Hardware-/Kalibrierungspakete bleiben separat abnahmepflichtig.
