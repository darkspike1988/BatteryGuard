# Technische Review: B-Guard 0.3.1

Stand: 4. Oktober 2026, Commit `5a40e51484f2c4bdaf976c689f681844bebd9b29`. Unabhängige Quellenreview von REST-Transport, Authentifizierung, gemeinsamen Ladeaktionen, Konfigurationsdatei/IPC, Daemon und Updater samt vorhandenen Tests. Keine Hardwareaktionen, Änderungen an Benutzerpräferenzen oder eigenen Builds. Die Testausführung erfolgt separat durch den Hauptagenten; diese Review beansprucht keine neu ausgeführten Tests.

## Ergebnis

Zwei durch den Quellcode belegte Fehler bei konkurrierenden Änderungen verdienen Regressionstests und eine Korrektur. Kein belegter Authentifizierungs-Bypass oder beliebiger privilegierter Befehlszugriff wurde im geprüften Bereich gefunden. Das ist kein vollständiger Sicherheitsnachweis und ersetzt keine Hardwaretests auf weiteren Mac-Modellen.

## R1 — P2: Eine REST-Aktion kann ihren ausdrücklichen Zielzustand verlieren

**Stellen:** `Sources/BatteryGuard/ConfigStore.swift:128`, `Sources/BatteryGuardShared/ConfigFile.swift:45`, `Sources/BatteryGuardShared/ConfigFile.swift:73`, `Sources/batteryguardd/ConfigServer.swift:154`.

Der Produktionspfad für einen normalen Benutzer liest zunächst eine Baseline, berechnet die gewünschte Konfiguration und schickt beide an den Root-Dienst. Dieser übernimmt nur Werte, die gegenüber der Baseline unterschiedlich sind. Das ist sinnvoll für einzelne UI-Änderungen, bewahrt aber nicht die Absicht eines ausdrücklichen API-Befehls.

**Deterministischer Trigger:** Die gelesene Baseline hat `enabled=false`. Eine API-Aktion `protection=false` berechnet erneut `enabled=false`. Vor Verarbeitung dieses Requests speichert ein weiterer berechtigter Client `enabled=true`. Der Dienst stellt fest, dass `desired.enabled == baseline.enabled`, übernimmt den aktuellen Wert `true` und bestätigt die Speicherung. Die Aktion erhält HTTP 200, obwohl der ausdrücklich gewünschte Schutzstatus nicht gesetzt wurde. Analog kann ein erneutes Profil einen zwischenzeitlich geänderten Grenzwert beibehalten.

**Beweislage:** Exakter Ablauf folgt aus den genannten Funktionen; noch kein Live-Race auf dem Benutzergerät erzeugt. REST-Tests mit temporärer Konfigurationsdatei nehmen den direkt gesperrten Dateipfad und umgehen den Produktionszweig `geteuid()!=0 && url.path==BGPaths.config`. Sie können diesen Fehler deshalb nicht widerlegen.

**Fix:** Typisierte Aktionen unter der bestehenden Dateisperre im privilegierten Dienst auf den neuesten Zustand anwenden oder ihre ausdrücklich betroffenen Felder inklusive unveränderter Zielwerte übertragen. Keine beliebigen Schlüssel, Dateipfade oder Befehle über die Privilegiengrenze zulassen. Falls inkompatible Protokollerweiterung: notwendige Daemon-Version sichtbar anheben; alte Dienste müssen eindeutig ablehnen.

**Abnahme:** Temporäre Service-Tests für Baseline aus/aktuell an/Aktion aus und Baseline Profil Schreibtisch/zwischenzeitlich anderer oberer Grenzwert/erneut Schreibtisch. Letzter bestätigter ausdrücklicher Befehl setzt alle zugehörigen Werte; unabhängige Änderungen bleiben erhalten. Zusätzlich REST→IPC→Service im isolierten Socket testen.

## R2 — P2: Ein alter Daemon-Tick kann eine neue Volllade-Anforderung löschen

**Stellen:** `Sources/batteryguardd/main.swift:104`, `Sources/batteryguardd/main.swift:120`, `Sources/batteryguardd/main.swift:135`.

`tick()` liest eine Konfiguration und entscheidet anhand dieses Snapshots, ob eine Volllade-Anforderung zurückgesetzt werden soll. Die anschließende Funktion `resetChargeToFullOnceInConfig()` sperrt und liest den neuesten Zustand, setzt dort aber bedingungslos `chargeToFullOnce=false` und `fullChargeUntil=nil`; eine inzwischen aktive Reise wird ebenfalls gelöscht.

**Deterministischer Trigger:** Der Tick entscheidet bei 100 % anhand einer alten Volllade-Anforderung auf Reset. Zwischen Entscheidung und Reset speichert die Oberfläche oder API eine neue Anforderung mit neuer Deadline oder eine aktive Reise. Der Reset des alten Ticks löscht diese neue Anforderung. Die vorher bestätigte neue Einstellung verschwindet ohne eigene Ablaufbedingung.

**Beweislage:** Konkurrenzfenster und bedingungslose Mutation sind unmittelbar im Quellcode sichtbar. Vorhandene Controller-Tests prüfen den Entscheid bei 99/100 %, nicht die zeitlich getrennte Speicherung gegen inzwischen geänderte Requests. Kein Hardware-Race provoziert.

**Fix:** Den ursprünglichen Request-Snapshot an die Rücksetzung übergeben und unter der Dateisperre nur noch unveränderte Anforderungsfelder zurücksetzen. Manuelle Vollladung und Reise getrennt vergleichen; eine neu geplante Reise muss erhalten bleiben. Eine explizite Request-ID wäre eine spätere robustere Erweiterung.

**Abnahme:** Pure Helper-/Temporärdatei-Tests für unveränderte alte Anfrage, neue Deadline, neu aktive Reise und neue zukünftige Reise. Nur die alte abgeschlossene Anforderung wird gelöscht; unrelated Einstellungen bleiben unverändert. Keine echte Batterie erforderlich.

## Weitere Verbesserungspunkte, keine belegten Sicherheitslücken

- **REST-Kompatibilität:** `LocalAPIStore.swift:163` akzeptiert nur exakt `application/json` ohne Parameter. `application/json; charset=utf-8` wird mit 400 zurückgewiesen. Das entspricht der derzeit engen Dokumentation, erschwert aber manche Automationsclients. Media-Type und optionalen UTF-8-Parameter sauber parsen; unbekannte Typen weiterhin ablehnen.
- **Transportlast:** Parsergrenzen, acht parallele Verbindungen und fünf Sekunden absolute Deadline sind implementiert. Tests decken echte GET/POST-Verbindungen und belegten Port ab; ein tatsächlicher Test mit acht langsamen Clients, abgewiesenem neunten Client und anschließender Freigabe fehlt. Begrenzungen können einen erneuernden lokalen Angreifer nicht vollständig von Dienstverweigerung abhalten; keine entsprechende Sicherheitsgarantie formulieren.
- **Downloadbegrenzung:** Die Metadaten begrenzen das Asset auf 100 MB, die tatsächliche Dateigröße wird erst nach vollständigem Download geprüft (`UpdateStore.swift:264`). Die Progressmeldung begrenzt nur die Anzeige. Einen Transfer bei Überschreiten der erwarteten Größe abbrechen und Ressourcenfrist setzen. Das ist Härtung gegen fehlerhafte Antworten; kein Nachweis eines derzeit ausnutzbaren Angriffs auf den vertrauenswürdigen GitHub-Pfad.
- **Speicherung auf dem MainActor:** Datei-/IPC-Zugriffe können den UI-Thread für die begrenzten Sperr-/Socketwartezeiten blockieren. Vor umfangreicher Automatisierung Dateiarbeit auf einem dedizierten Actor ausführen und UI-Zustand anschließend übernehmen; Konfliktschutz beibehalten.

## Positiv verifiziert durch Quellen und vorhandene Testfälle

- API standardmäßig aus; Steuerbefehle zusätzlich freizugeben. Bindung ausdrücklich an `127.0.0.1`, exakte Hostprüfung, keine Browser-Origin-Anfragen und keine CORS-Freigabe.
- Zufälliger 256-Bit-Token, private Datei/Verzeichnis, Eigentümer-/Dateitypprüfung und `O_NOFOLLOW`; Tokenrotation widerruft den alten Speicherwert. Kein Token im Status-/Konfigurationsresponse.
- Parser begrenzt Header, Body und Request; doppelte Header, Transfer-Encoding, gefaltete Header und mehrdeutige Frames werden abgelehnt.
- Schreibaktionen prüfen frischen passenden Daemon, UI-Konflikte und tatsächlichen Speichervorgang. Unbekannte Aktionsfelder und ungeeignete Modi werden abgelehnt. Die Antwort behauptet keine bereits bestätigte Hardwareanwendung.
- Root-IPC akzeptiert typisierte Konfiguration statt Befehlen/Pfaden; Peer-UID wird vor und nach Empfang gegen den Console-Benutzer geprüft, Framing und Zeit sind begrenzt.
- Updater validiert Versionsformat, Repository-/Release-/Asset-Pfad, erwartete Größe und SHA-256 vor Öffnen; Fehler/Abbruch beseitigen abgeschlossene temporäre Downloads.

## Priorisierte nächste Prüfung

1. R1/R2 deterministisch reproduzieren und mit Regressionstests schließen.
2. Transport-Lasttest und tatsächliche Downloadgrößenbegrenzung ergänzen.
3. Kompatibilitätsmatrix für Mac-Modelle, externe Displays, Sleep/Wake und Firmware anhand echter Geräte veröffentlichen. Aktuelle einzelne Gerätetests beweisen keine breite Hardwareunterstützung.
4. Signierte/notarisierte Veröffentlichung und verifizierte automatische Installation als eigenes Produktvorhaben behandeln; Prüfsumme und DMG-Öffnen sind noch kein automatischer Austausch der App.

## Validierung durch den Hauptagenten

Am 4. Oktober 2026 bestanden die bestehenden 83 Tests in elf Suiten. Zusätzlich liefen drei gezielte Reproduktionstests mit `swift test --filter ReviewReproductionTests`: alle bestätigten das oben beschriebene unerwünschte IST-Verhalten. Einer davon verwendet die tatsächliche `ConfigServer.apply`-Funktion mit einer temporären Konfiguration; R2 simuliert exakt die Reset-Mutation und testet keinen Hardware-Tick. Die Tests sind **Bugnachweise, keine erfolgreichen Fix-Regressionen**. Die temporäre Testdatei wurde anschließend aus dem regulären Testtarget entfernt und unter [reproductions/ReviewReproductionTests.swift.txt](reproductions/ReviewReproductionTests.swift.txt) archiviert.

Zum Nachstellen die archivierte Datei vorübergehend nach `Tests/BatteryGuardTests/ReviewReproductionTests.swift` kopieren, den genannten Filter ausführen und die temporäre Datei wieder entfernen. Es werden ausschließlich temporäre Konfigurationsdateien verwendet. R1 und R2 sind in 0.3.1 weiterhin offen; in dieser Review wurde keine Produktionslogik geändert.

## Nachfolgende Korrektur in 0.3.2

R1/R2 wurden nach dieser Review korrigiert: Protokoll-2-Aktionen werden im Dienst atomar auf den aktuellen Stand angewandt; Abschlüsse vergleichen Snapshot, Frist und eindeutige Anforderungs-IDs. Neue Regressionstests stehen in `AtomicActionTests.swift` und `ChargeCompletionTests.swift`. Der obige Bericht und die archivierten IST-Reproduktionen beziehen sich auf 0.3.1; ihre Aussagen über offene Fehler beschreiben diesen damaligen Stand.
