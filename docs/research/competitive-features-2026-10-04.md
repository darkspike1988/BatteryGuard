# Konkurrenzfunktionen und Chancen für B-Guard

Stand: 4. Oktober 2026. Recherche anhand offizieller Herstellerseiten, Hersteller-Changelogs und Projekt-Repositories; keine eigene physische Prüfung der Konkurrenz. B-Guard-Basis: lokales README, ROADMAP und `Controller.swift` der Version 0.3.1. „Unbekannt“ bedeutet fehlenden Nachweis in den geprüften Quellen, nicht fehlende Funktion. Preise gehören in die separate Zahlungsmodell-Recherche.

## Wichtigste Erkenntnis

Ein einfaches 80%-Limit ist inzwischen eine kostenlose macOS-Funktion. Apples Grenze liegt zwischen 80 und 100 Prozent; Optimiertes Laden lernt zusätzlich Tagesroutinen. Gelegentliche Vollladungen gehören ausdrücklich zum Systemverhalten. Voraussetzung für das manuelle Limit: Apple Silicon und macOS Tahoe 26.4+. [Apple: Ladelimit und Optimiertes Laden](https://support.apple.com/en-gb/102338).

Auch Automatisierung ist kein exklusiver Drittanbieter-Vorteil: Apple dokumentiert seit 26.4 die Aktion „Set Battery Charge Limit“. macOS 26 bietet persönliche Automationen unter anderem für Uhrzeit, Bildschirm, WLAN, Ladegerät, Batteriestand und Fokus. B-Guard muss deshalb mehr als einen Schalter oder einfache Zeitregeln liefern. [Apple: neue Kurzbefehle](https://support.apple.com/en-us/125148).

## Belegte Funktionsmatrix

| Bereich | macOS | AlDente | BatFi | Battery Toolkit | BatteryBoi | B-Guard 0.3.1 |
|---|---|---|---|---|---|---|
| Manuelles Limit | 80–100 %, ab 26.4 | Ja, Free | Ja, auch <80 % laut FAQ für 4.0/macOS 27 | Ja, ab 50 % | Unbekannt; primär Anzeige | Profile und eigene Ziele, hardwareabhängig |
| Untere Grenze/Hysterese | Nachladen nach >5 Prozentpunkten Verlust | Sailing Mode, Pro | Unbekannt, nicht als getrennte Untergrenze belegt | Eigene Untergrenze ab 20 % | Unbekannt | Eigene Grenze bei separater Ladesperre; Netzteil-Fallback max−5 |
| Einmalig voll laden | Ja | Top Up, Pro | Ja | Ja | Unbekannt | Ja, begrenzte Ausnahme |
| Zeit-/Reiseregeln | Kurzbefehle kombinierbar | Schedule, Pro | Zeit und Ort | Unbekannt | Trigger stehen in Roadmap; Umsetzung unbekannt | Ein Reisezeitpunkt, feste 3-Stunden-Vorlaufzeit |
| Temperatur | Systemschutz, eigene Schwelle unbekannt | Heat Protection, Pro | Temperaturanzeige; Temperaturlimit im Changelog | Unbekannt | Unbekannt | Konfigurierbarer Hitzeschutz mit Hysterese |
| Automatisierung | Native Kurzbefehle | Native Kurzbefehle, Pro | App Intents und globale Tastenkürzel | Unbekannt | Tastenkürzel/Trigger in Roadmap | REST, getrennte Schreibfreigabe; keine nativen App Intents gefunden |
| Verlauf/Export | Keine gleichwertige CSV-Auswertung hier belegt | Diagramm-Widgets im Changelog; CSV unbekannt | Diagramm und gespeicherter Verlauf; CSV unbekannt | Unbekannt | Statistiken; CSV unbekannt | 7 Tage JSON/CSV, Temperatur und Leistung |
| Externe Geräte | Systemanzeigen | Unbekannt | Unbekannt | Unbekannt | Bluetooth-Akkustände | Keine Bluetooth-Akkus |
| Offener Quellcode | Keine offene Implementierung dieser Funktion belegt | GitHub-Release-/Issue-Projekt beweist keine offene aktuelle Pro-Version | Unbekannt | BSD-3-Clause, archiviert | GPL-3.0 | MIT |

Belege: [AlDente-Funktionen](https://apphousekitchen.com/aldente-overview/features/), [AlDente-Changelog](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/releases), [BatFi-Produktseite](https://micropixels.software/batfi/), [BatFi-FAQ](https://micropixels.software/support/), [BatFi-Changelog](https://files.micropixels.software/batfi/BatFi-latest.html), [Battery Toolkit](https://github.com/mhaeuser/Battery-Toolkit), [BatteryBoi](https://github.com/thebarbican19/BatteryBoi). B-Guard: [README](../../README.md), [API](../api.md).

## Monitor, Deckel und Hardware: keine Überlegenheit behaupten

AlDente erklärt, dass Entladen im Clamshell-Betrieb eine Schlafsperre benötigt. Battery Toolkit beschreibt denselben Zusammenhang und sperrt außerdem beim Laden den Schlaf, um das Limit rechtzeitig umzusetzen. Das sind technische Einschränkungen und Produktentscheidungen, keine Beweise für unsichere Software. [AlDente-Funktionen](https://apphousekitchen.com/aldente-overview/features/), [Battery Toolkit](https://github.com/mhaeuser/Battery-Toolkit).

Wesentlich neuer: BatFi nennt in seiner aktuellen FAQ für macOS 27 eine Systemsteuerung, die Entladen bei geschlossenem Deckel übernimmt; ältere Systeme benötigen die Schlafsperre. Grenzen unter 80 % seien mit BatFi 4.0 wieder möglich. Das ist eine Herstellerangabe, hier nicht nachgemessen. [BatFi-FAQ](https://micropixels.software/support/).

B-Guard hält dagegen bei externem Bildschirm oder geschlossenem Deckel das Netzteil verbunden. Fehlt die separate SMC-Ladesperre, übernimmt macOS das tatsächliche Limit. Damit ist ein ausgewähltes 55–60%-Profil auf solchen Macs **kein wirksames 60%-Clamshell-Limit**. Im Code wird dieser Rückfall ausdrücklich vor der Pendelregelung angewandt. Die App vermeidet dadurch die frühere Schlafproblematik, erreicht aber nicht denselben Steuerungsumfang. Direkte/native Modi, Pendelbetrieb und unbekannte Firmwarelayouts müssen getrennt dargestellt bleiben. Quelle: [Controller](../../Sources/batteryguardd/Controller.swift), [README](../../README.md).

BatFis aktueller Changelog beschreibt Firmware-Fähigkeitserkennung statt einer reinen Versionsannahme. Unter-80%-Limits könnten bis zu 45 Sekunden zum Anwenden benötigen. Das ist ein wertvoller Recherchehinweis für eine neue B-Guard-Hardwareebene, keine Grundlage zum ungeprüften Kopieren von Schlüsseln oder blindem Schreiben. [BatFi-Changelog](https://files.micropixels.software/batfi/BatFi-latest.html).

## Zuverlässigkeit und Distribution

Battery Toolkit ist seit 21. März 2026 als archiviert gekennzeichnet; seine README beschreibt nicht notarisierte ZIP-Installation und Homebrew. B-Guard kann hier mit aktiver Pflege und verständlicher Einrichtung punkten, hat momentan aber dieselbe grundlegende Gatekeeper-Hürde: Die Community-DMG ist nicht notarisiert. [Battery Toolkit](https://github.com/mhaeuser/Battery-Toolkit), [B-Guard-README](../../README.md).

BatteryBoi bietet kostenlose DMG-/Homebrew-Installation und konzentriert sich auf Anzeige und Bluetooth-Akkus. Seine README nennt Installationslogging; B-Guards lokale Datenhaltung ist daher konkret erklärbar, aber nicht pauschal als einzigartige Datenschutzposition zu bewerben. [BatteryBoi](https://github.com/thebarbican19/BatteryBoi).

BatFi bietet direkten Download, Homebrew und ein öffentliches Changelog. Das Changelog nennt wiederholt Reparaturen am Backend und Helfer. AlDente dokumentiert ebenfalls Reparaturen für Ladegrenzen, Sleep-Verhalten und Monitorfehler. Das belegt aktive Wartung und zugleich die Änderlichkeit der Plattform; es belegt keine vergleichbare Fehlerquote. [BatFi-Produktseite](https://micropixels.software/batfi/), [BatFi-Changelog](https://files.micropixels.software/batfi/BatFi-latest.html), [AlDente-Releases](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/releases).

## Priorisierte Chancen und Abnahmekriterien

Diese Reihenfolge ist eine Produktbewertung aus den Quellen, keine gemessene Marktpräferenz.

1. **P0: Tatsächliche Fähigkeiten verständlich machen.** Pro Funktion „verfügbar“, „durch macOS begrenzt“ oder „nicht unterstützt“ anzeigen, einschließlich effektivem Limit und Hardwarebestätigung. Abnahme: Ein Monitor-Fallback kann weder in Menü noch REST als aktives 60%-Limit erscheinen; gespeichertes Ziel und bestätigte Wirkung sind unterscheidbar.
2. **P0: Verlässliche Installation und Updatekette.** Developer-ID/Notarisierung praktisch prüfen; Erststart ohne Terminal, verständlicher Dienstzustand und überprüfbare Wiederherstellung. Externe Voraussetzung: Zertifikat. Abnahme: frischer Mac/Benutzer, DMG-Drag-and-drop, Adminfreigabe, Update von alter Dienstversion und saubere Deinstallation dokumentiert.
3. **P1: Neue macOS-27-Steuerung untersuchen.** Zuerst lesende Firmware-/Capability-Recherche, dann eng begrenzte physische Abnahme auf freiwilligen Testgeräten. Ziel: unter-80%-Limit bei externem Monitor ohne Schlafsperre, falls bestätigt möglich. Abnahme: Limit setzen, warten, readback und tatsächlicher Stromfluss; Schlaf/Aufwachen/Neustart; Rücknahme bei Fehler. Bis dahin keine Zusage.
4. **P1: Native Kurzbefehle auf bestehender Aktionslogik.** Profile, Pause, Fortsetzen, Reiseplan, Status und effektives Limit ohne REST-Token-Handarbeit. Abnahme: dieselben Validierungs- und Konfliktregeln wie UI/REST; verweigerte oder nicht unterstützte Aktionen erklären ihre Ursache. Die API bleibt für Skripte und Auswertungen nützlich.
5. **P1: Reiseplanung, die ihren Zustand erklärt.** Nach Vollladung Akku bis zum Abziehen bewahren statt sofort auf das Alltagsziel aktiv zu entladen; Fortschritt und verpassten Termin zeigen. BatFi reparierte genau dieses sofortige Entladen nach Top-up. Abnahme: keine eigenmächtige Änderung des gespeicherten Profils, unverändert aktiver Hitzeschutz, deterministische Rückkehr nach Abziehen/Frist. [BatFi-Changelog](https://files.micropixels.software/batfi/BatFi-latest.html).
6. **P2: Wenige nachvollziehbare Regeln statt großer Automationsmaschine.** Wochentag/Uhrzeit und Bildschirm anschließen mit klarer Priorität „manuelle Ausnahme vor Regel vor Profil“. Standorterfassung erst bei belegtem Bedarf; macOS-Kurzbefehle decken bereits viele Trigger ab. Abnahme: Regelvorschau „warum gilt welches Ziel“, Konflikte und Schlaflücken getestet.
7. **P2: Diagnose als offene Stärke.** Export ohne Token, persönliche Pfade und Seriennummern; Fähigkeiten, letzte Fehler, Versions-/Limitkonflikt und Zeitstempel. API-Schema und Beispiele für Home Assistant, Raycast oder eigene Analysen. Keine LAN-Freigabe nötig, kein Cloudkonto. Abnahme: Export enthält keine Geheimnisse und unterscheidet letzte erfolgreiche Aktion von aktuellen Messwerten.
8. **P3: Komfort danach.** Frei benannte Profile, globale Tastenkürzel, Englisch, Homebrew-Cask; Bluetooth-Anzeigen und Energie-Modi nur bei Nachfrage. Diese Extras haben Konkurrenzangebote, lösen aber nicht den aktuellen Hardware-/Installationsnachteil.

## Glaubwürdige Positionierung

„Kostenlose, offene Akkuwerkzeuge mit verständlichen Profilen, lokalen Messdaten und dokumentierter Automatisierung“ ist heute belegbar. „Besser als macOS für jeden Mac“, „funktioniert immer im Clamshell-Modus“, „garantiert weniger Verschleiß“ und „einziges Tool mit Automatisierung“ sind es nicht. Ein künftiger Vorsprung sollte an funktionierender Installation, sichtbarer tatsächlicher Wirkung und reproduzierbaren Hardwaretests festgemacht werden.

## Ergänzung: AlDente Pro vollständig als Arbeitsliste

Die deutsche Preistabelle unterscheidet Free (Limit und manuelles Entladen) von Pro. Der reine Textabruf listet auch die ausgeschlossenen Features unter Free; im offiziellen HTML tragen diese ein `times-circle`, die enthaltenen ein `check-circle`. Daher nicht alle sichtbaren Wörter als Free-Funktionen übernehmen. Pro bewirbt außerdem automatische Entladung, Clamshell-Entladen, Hitzeschutz, Sailing, LED-Steuerung, Top-up, Kalibrierung, Kurzbefehle, anpassbare Menüleiste/Popover und E-Mail-Support. Die Funktionsseite ergänzt weitere Einzelfunktionen. [Offizielle Preise](https://apphousekitchen.com/de/aldente/preisgestaltung/), [deutsche Funktionen](https://apphousekitchen.com/de/aldente/funktionen/).

Die folgende Liste führt jedes Preislistenmerkmal und jeden zusätzlich benannten Funktionsseiten-Eintrag auf. Umsetzungsvorschläge sind eigene Bewertungen, kein Vorschlag, Quellcode oder geschützte Gestaltung zu kopieren.

| Merkmal | B-Guard-Stand | Eigenständige Umsetzung / Risiko |
|---|---|---|
| Ladelimit (Free/Pro) | Teilweise | Fähigkeiten und effektives Ziel klar zeigen; Grenzen hängen vom Backend ab |
| Manuelles Entladen (Free/Pro) | Teilweise | Separate einmalige Aktion statt nur Automatikschalter; Reserve und Monitor-Fallback beachten |
| Automatische Entladung | Teilweise | Bereits aktive Entladung über Maximum; Clamshell/Netzteilgrenzen sichtbar machen |
| Entladen bei geschlossenem Deckel | Technischer Spike | Firmwarefähigkeit prüfen; niemals still Schlaf verhindern |
| Hitzeschutz | Bereits, hardwareabhängig | Bestehende Hysterese/Reserve; tatsächliche Wirksamkeit im Monitor-Fallback deutlich machen |
| Sailing-Modus | Teilweise | Eigene Unter-/Obergrenze vorhanden; Fallback-Pendel erzeugt zusätzliche Bewegungen und ist keine gleichwertige Ladesperre |
| MagSafe-LED-Steuerung | Teilweise / Spike | Boolean und SMC-Pfad vorhanden; erfolgreiche Wirkung nicht modellübergreifend belegt; keine unbegrenzten Fehlversuche |
| Top Up | Bereits / verbessern | Einmaliges Vollladen mit Rückkehr; bis Abziehen bewahren als bewusste Ausnahme |
| Kalibrierungsmodus | Offen | Später ausdrücklich gestartete Zustandsmaschine mit Abbruch/Reserve und Erhalt aller Einstellungen; keine periodische Tiefentladung als gesicherten Gesundheitsgewinn darstellen |
| Kurzbefehle | Offen | App Intents auf gemeinsamer Aktionslogik; REST allein ist nicht gleichwertiger Komfort |
| Anpassbare Menüleistensymbole | Teilweise | Bestehenden Status um Prozent-/Watt-/Temperaturwahl erweitern, stabile Breite und VoiceOver |
| Anpassbares Popover | Offen | Wenige optionale Informationsblöcke und Reihenfolge; native Übersicht behalten |
| E-Mail-Support | Kein Serviceversprechen | Öffentliche Issues und Diagnoseexport; persönliche Antwortzeiten nur mit personeller Kapazität zusagen |
| Lizenzumfang | MIT, kostenlos | Kein Schlüssel nötig; freiwillige Finanzierung separat, kein Schutz hinter Aktivierungsserver |
| Ruhezustand bis Limit deaktivieren | Offen, bewusst nicht Standard | Allenfalls explizite befristete Option mit sichtbarem Ende; Konflikt mit Nutzerwunsch, Deckel normal schließen zu können |
| Schneller Benutzerwechsel | Teilweise | Socket akzeptiert aktuelle Konsole; Status und verweigerte Sitzung verständlich zeigen; kein Beweis gleicher Featurelogik |
| Hardware-Batteriestand | Offen / Spike | System- und Rohwert trennen, sofern verlässlich verfügbar; nicht annehmen, macOS sei „falsch“ |
| Live-Statussymbole | Bereits / verbessern | Bestehende Lade-/Halte-/Fehlerzustände; veraltete Messwerte und „nur macOS“ zusätzlich eindeutig |
| Power Flow | Teilweise | Batterieleistung vorhanden; Adapter-, System- und Akkuwerte nur mit belegter Messbasis als Fluss darstellen |
| Zeitplan | Teilweise | Ein Reiseplan; später wiederkehrende Regeln mit Priorität, Schlaflücken und Zeitumstellung |
| Laden stoppen bei App-Ende | Anders gelöst | Dienst bleibt aktiv; keine künstliche App-Ende-Ladesperre nötig, Lebenszyklus klar erklären |
| Laden im Ruhezustand stoppen | Technischer Spike | B-Guard gibt vor Schlaf frei; Firmwarebackend könnte andere sichere Möglichkeiten schaffen. Keine allgemeine Schlaf-Limit-Garantie |

## Ergänzung: Better Battery 2

Better Battery 2 ist laut Entwicklerbeschreibung im App Store ein Monitoringprodukt: kostenlose aktuelle Akku-/Systemwerte; Pro erweitert Historie, Leistungs-, Kapazitäts-, Zyklen- und Nutzungsdiagramme sowie Empfehlungen. Genannt werden 48-Stunden-Ladekurven, 30 Tage Pro-Test und ausschließlich lokale Speicherung. Eine tatsächliche Ladelimit-Steuerung ist dort nicht belegt. Es wäre daher falsch, seinen Kaufpreis als Preis eines gleichen Ladecontrollers zu vergleichen. [Offizieller App-Store-Eintrag](https://apps.apple.com/de/app/better-battery-2-stats-info/id1455789676?mt=12).

B-Guards Diagramme/CSV konkurrieren hier mit Auswertung, nicht bloß mit Ladesteuerung. Eine sinnvolle Ergänzung wären längerfristige, sparsame tägliche Kapazitäts-/Zyklenwerte und ausgewiesene Datenlücken. Empfehlungen wie tägliches Entladen brauchen eine eigene belastbare Grundlage; die Herstellerbeschreibung allein beweist keinen Gesundheitsgewinn.

## Ergänzung: Primärquelle grenzt macOS-27-Chance ein

Die aktuelle `batt`-README beschreibt eine Firmwareebene mit `bfF0`, `bfD0` und `bfE0`, anschließend aber eine neue Sperre ab Firmware `20457.0.125.0.2`: Lade-Schlüssel benötigen das private Entitlement `com.apple.private.iokit.soc-limit`; root genügt nicht. Als Alternative dokumentiert das Projekt einen expliziten Netzteilmodus mit den bekannten Clamshell-/Schlafgrenzen oder einen nativen 80%+-Fallback über PowerUIAgent. Firmware kann durch Updates neuer sein als das gebootete macOS. [batt: Firmware und gated keys](https://github.com/charlie0129/batt#macos-27--20xxx-firmware-behavior).

Folgerung: BatFis pauschale Produktangabe zu macOS 27 ist keine Übertragbarkeitsgarantie für B-Guard oder jedes Firmwarelevel. Den technischen Spike auf konkrete Fähigkeiten, Schreibberechtigungen und physische Wirkung begrenzen; bekannte private Entitlements nicht als frei nutzbare API darstellen. Eine Implementierung wurde hier nicht ausprobiert, keine Hardwarewerte geschrieben.
