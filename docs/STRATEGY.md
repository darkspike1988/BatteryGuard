# B-Guard: Review, Markt und Umsetzung

Stand: 4. Oktober 2026. Ausgangspunkt: B-Guard 0.3.1, Commit `5a40e51484f2c4bdaf976c689f681844bebd9b29`.

## Entscheidungsvorschlag

B-Guard bleibt kostenlos und MIT Open Source. Zielgruppe: MacBook-Nutzer am Schreibtisch, die verlässliche Ladeprofile und nachvollziehbare Automatisierung wollen. Die bestehende Oberfläche bleibt einfach; zusätzliche Optionen kommen schrittweise hinzu. Der Wettbewerbsvorteil soll aus **belegter Kompatibilität, erklärbaren Entscheidungen und offenen Integrationen** entstehen. Weder Gratispreis noch REST allein beweisen eine Überlegenheit.

Die vorgeschlagenen Versionen unten sind Arbeitspakete, keine bereits implementierten Funktionen oder zugesagten Termine. Vor jeder Veröffentlichung zählen die Abnahmen, nicht die Versionsnummer. Die laufende App und gespeicherte Nutzerkonfiguration wurden für diese Analyse nicht verändert.

## Belege und Grenzen

- [Technische Review](research/code-review-2026-10-04.md): zwei offene Fehler bei konkurrierenden Änderungen; 83 bestehende Tests erfolgreich, drei zusätzliche IST-Reproduktionen bestätigen die Fehler. Kein Hardware-Race provoziert.
- [Preise und Bezahlmodelle](research/market-pricing-2026-10-04.md): aktuelle öffentliche Primärquellen; Währungen, Geräterecht und Lizenzlaufzeit getrennt. Keine Checkout-Bestellung durchgeführt.
- [Funktionsvergleich](research/competitive-features-2026-10-04.md): Herstellerangaben getrennt von B-Guard-Implementierung und physisch belegtem Verhalten.
- Die vom Nutzer genannte [Ka2-Übersicht](https://ka2.ch/batteriegesundheit-6-apps-die-deine-macbook-batterie-lieben-wird/) stammt vom 3. Juli 2025. Sie dient als Entdeckungsliste; alte CHF-Preise und Aussagen zu Ladeprofilen übernehmen wir nicht ungeprüft. Monitoring und aktive Ladesteuerung sind unterschiedliche Märkte.
- Apples [natives Limit](https://support.apple.com/en-gb/102338) deckt auf unterstützten Systemen bereits 80–100 % ab. Das bloße Anbieten eines 80-%-Limits ist deshalb ein schwaches Verkaufsargument. Apple dokumentiert zudem [native Lade-Kurzbefehle und persönliche Automationen](https://support.apple.com/en-us/125148); einfache Zeitregeln allein reichen ebenfalls nicht zur Differenzierung.

## Was wir aus AlDente Pro übernehmen wollen

Ausgangspunkt sind [Preisgestaltung](https://apphousekitchen.com/de/aldente/preisgestaltung/) und [Funktionen](https://apphousekitchen.com/de/aldente/funktionen/). Die Produktnamen in der ersten Spalte dienen dem Vergleich. Umsetzung und Bedienung darunter sind eigene B-Guard-Vorschläge, keine Behauptung über internen Konkurrenzcode. Die Preisübersicht enthält teils durchgestrichene Einträge; die Free/Pro-Zuordnung folgt zusätzlich den Funktionskennzeichnungen.

| Vergleichspunkt | B-Guard 0.3.1 | Umsetzung und Abnahme |
| --- | --- | --- |
| Individuelles Ladelimit | Vorhanden, hardwareabhängig | Wirksames Limit und Profilziel immer getrennt anzeigen; Testmatrix je Firmware. |
| Manuelles Entladen | Kein eigener Einmalbefehl | Zeitlich begrenzte `discharge-to`-Anforderung mit Ziel, Abbrechen, Reserve und Rückkehr zum Profil; nur mit bestätigter Hardwarefähigkeit. |
| Automatische Entladung | Einstellung vorhanden | Bei Monitorbetrieb derzeit abgeschaltet; keine Gleichwertigkeit behaupten. Neues Backend zuerst physisch prüfen. |
| Entladen mit geschlossenem Deckel | Auf diesem Mac bewusst eingeschränkt | Hardware-Spike B1; keine automatische Rückkehr zur früher problematischen Schlafsperre. |
| Hitzeschutz | Vorhanden mit 2-°C-Hysterese | Sensorverlust, Reserve und Sonderaktionen testen; Schwelle für Batterietemperatur nicht mit Umgebungstemperatur verwechseln. |
| Sailing / Bereich halten | Teilweise: Lade-Hysterese vorhanden | Echte Ladesperre hält Netzteil aktiv; Adapter-Pendeln ist anderes Verhalten. Backend und Energiequelle klar benennen. |
| MagSafe-LED | Implementiert, Writes nicht auf jedem Mac erfolgreich | Fähigkeit als nachgewiesen/fehlgeschlagen/unbekannt zeigen; wiederholte Fehler drosseln. Zusätzliche Farben erst nach Readbackprüfung. |
| Top Up | Einmaliges Vollladen vorhanden | Unterschiedliche Rückkehrbedingungen dokumentieren. Optional „bis zum Abstecken“ mit Request-ID, Frist und sicherer Rückkehr ergänzen. |
| Kalibrierungsmodus | Fehlt | Geprüfter, manuell gestarteter Zustandsautomat mit Abbruch, Fristen und weiter aktivem Hitzeschutz. Erst nach Hardware-Abnahme; kein regelmäßiger Zwangszyklus als Standard. |
| Kurzbefehle | REST vorhanden, native Integration fehlt | App Intents für Status, Profil, Vollladen, Pause und Reise; dieselben validierten Aktionen, keine Token-Eingabe für native Intents. |
| Wiederkehrende Zeitpläne | Ein Reisezeitpunkt vorhanden | Wochentage, lokaler Zeitpunkt, eindeutige Ausführung und kontrolliertes Nachholen; Ausführungsprotokoll im Daemon. |
| Konfigurierbare Menüleiste | Live-Status vorhanden, Auswahl fehlt | Auswahl Symbol/Prozent/Temperatur/Leistung; neutrale monochrome Standardansicht, VoiceOver und geringe Aktualisierungsrate. |
| Konfigurierbares Popover | Feste Ansicht | Wenige auswählbare Karten und kompakter Modus; Aktionen bleiben konsistent und per Tastatur erreichbar. |
| Hardware-Ladestand | Kein getrenntes Feld | Quellen und Einheiten prüfen; zusätzlichen Schätzwert optional anzeigen, Steuerung weiterhin an nachvollziehbarem Standardwert orientieren. |
| Power Flow | Batterie-Watt vorhanden | Erst echte Eingangsleistung messen. Netzteil-Nennleistung ist kein Messwert; unbekannte Flüsse als unbekannt zeigen. |
| Regelung nach App-Beenden | Dienst läuft weiter | Bereits architektonisch vorhanden; sichtbare Erklärung und Abnahme bei Quit/Logout/Daemonstop. REST und Verlauf enden weiterhin mit der App. |
| Regelung beim Benutzerwechsel | Maschinenkonfiguration + Console-UID-Prüfung | Zwei-Konten-Abnahme und klares Modell „eine Batterie, eine Gerätekonfiguration“; Hintergrundkonto darf nichts schreiben. |
| Laden im Schlaf stoppen | B-Guard stellt Normalbetrieb vor Schlaf her | Separater Backend-Spike für persistente Hemmung; Default unverändert bis Readback und Wake-Restore nachgewiesen. |
| Bis zum Limit wach halten | Absichtlich entfernt | Nur spätere ausdrückliche Option mit Zeitlimit, Netzteil-/Temperatur-/Deckelprüfung und verlässlichem Freigeben aller Assertions. |
| E-Mail-Support / notarisiertes Paket | Community-Support; ad-hoc DMG | Issuevorlagen, Diagnoseexport und notarisiertes Paket. Ein Supportversprechen braucht verlässlich verfügbare Kapazität. |

## Reihenfolge mit überprüfbaren Arbeitspaketen

### A — Stabilität vor neuen Pro-Funktionen · vorgeschlagen 0.3.2

**A1: Aktionen atomar anwenden.** `BGConfigRequest` erhält eine klar versionierte typisierte Aktion. Der Root-Dienst prüft Rechte und Parameter und wendet diese unter der Dateisperre auf den neuesten Stand an. UI-Feldänderungen behalten ihren getrennten Mergepfad. Alternativ Revision/CAS mit klarer Konfliktantwort; niemals einen unverändert berechneten Zielwert als „nicht angefragt“ behandeln. Abnahme: ausdrückliches Ausschalten und erneute Profilwahl gewinnen gegen zwischenzeitliche Änderungen; REST→IPC→Service-Test mit temporärem Socket. Ein erforderliches Dienstupdate sichtbar versionieren.

**A2: Alte Abschlüsse dürfen neue Anforderungen nicht löschen.** Voll-/Reiseanforderungen bekommen stabile IDs oder werden mit ihrem vollständigen Snapshot verglichen. Nur die beendete unveränderte Anforderung löschen. Abnahme: neue Deadline und neue aktive/zukünftige Reise bleiben erhalten, alte abgeschlossene Anfrage endet, andere Profileinstellungen bleiben erhalten.

**A3: Transport und Updates härten.** Acht langsame Verbindungen, neunte Verbindung und Freigabe nach Deadline tatsächlich testen. JSON-Medientyp mit UTF-8-Parameter akzeptieren. Download während des Transfers bei überschrittener Größe abbrechen. Test: keine gespeicherte Aktion nach Requestablauf; Downloadabbruch entfernt temporäre Datei.

**A4: Release-Grundlage.** macOS-CI mit Swift-6-Tests, Shell-Prüfung, Release-Build und Bundleprüfung; Diagnosevorlage und SECURITY.md. Token, Benutzerpfade und genaue geplante Termine nicht unbemerkt in Diagnoseexport aufnehmen. Developer-ID und notarisierten Pfad separat abnehmen, sobald Zertifikat verfügbar ist. Der vorhandene Community-Build bleibt bis dahin korrekt gekennzeichnet.

### B — Hardwarefähigkeit als wichtigster Wettbewerbshebel · parallel als Forschung

**B1: Neue Firmwaresteuerung erforschen.** BatFi nennt für macOS 27 wieder niedrigere Limits und Deckelbetrieb ([Hersteller-FAQ](https://micropixels.software/support/)). Das freie [batt-Projekt](https://github.com/charlie0129/batt) dokumentiert aber Firmwaremechanismen und zusätzliche private Berechtigungsgrenzen. Eine macOS-Versionsprüfung allein reicht nicht. Zuerst lesend Modell, Firmware, bekannte Schlüssel und Rechte ermitteln. Keine geratenen SMC-Bytes und keine Beschaffung privater Entitlements durch Umgehungen.

Implementierungsvorschlag: `ChargingBackend` mit Fähigkeiten `canInhibitCharging`, `canDisconnectAdapter`, `canPersistAcrossSleep`, `canSetFirmwareLimit`; Diagnose begründet die Auswahl. Backends getrennt für bestätigte Firmwaresteuerung, separate Ladesperre, Adaptersteuerung und native Beobachtung. Bestehende sichere Monitor-/Deckelregeln bleiben Rückfallebene. Erfolg ist ein nachgewiesener Readback plus physische Wirkung, nicht ein erfolgreicher API-Aufruf.

**B2: Abnahmematrix.** M1/M2/M3/M4/M5 soweit Testgeräte tatsächlich verfügbar, macOS 14/15/26/27, vor/nach Firmwareupdate, MagSafe/USB-C/Dock, externer Bildschirm, Deckel, Sleep/Wake, Neustart, leeres/geladenes Akku und Sensorfehler. Nicht getestete Kombinationen bleiben „unbekannt“. Unterstützungsumfang richtet sich nach belegten Kombinationen, nicht nach Marketingliste. Restore und Rückkehr zum normalen Laden ebenfalls prüfen. Keine Broad-Support-Zusage aus dem einzelnen lokalen M1 Pro ableiten.

Wenn neue Firmwaresteuerung nicht verfügbar ist, wird B-Guard trotzdem besser: verständliche Einschränkungen und passende native Empfehlung. Eine bestätigte Fähigkeit ist Voraussetzung für Schlafstopp, sichere Deckelentladung und Kalibrierung.

### C — Automatisierung alltagstauglich machen · vorgeschlagen 0.4

**C1: Native Kurzbefehle.** Zunächst Status/Temperatur/Profil auslesen; danach Profilwahl, Schutz, zeitliche Pause, Vollladen und Reise. Eigener `ChargingActionService` verbindet UI, REST und App Intents mit demselben Root-Protokoll. Fehler statt falschem Erfolg; fehlender/alter Dienst, Nutzerwechsel und Konflikte testen. Keine lokalen Tokens in geteilte Kurzbefehle schreiben.

**C2: Wiederholungen.** Typ `ScheduleRule` mit UUID, Aktion, Wochentagen, Uhrzeit/Zeitzonenregel, aktiviertem Zustand und zuletzt ausgeführtem Ereignis. Ausführung im Daemon, damit das Menüfenster nicht laufen muss. DST, Zeitzonenwechsel, Uhrzeitkorrektur und Wake berücksichtigen. Höchstens die aktuell relevante verpasste Aufgabe nachholen, keine Reihe alter Vollladungen ausführen. Priorität explizit: Hardware-Sicherheitsregeln → wirksame Schutzbedingungen → aktuelle manuelle Ausnahme → aktueller Zeitplan → Basisprofil. Eine ausdrücklich gewählte Schutzpause bleibt als Ausnahme nachvollziehbar.

**C3: Eigene Profile.** Benannte gespeicherte Profile, Import/Export ohne Token, Vorschau der Änderung, eindeutige Konfliktregeln. Ein manueller Profilwechsel darf nicht Sekunden später durch einen alten Zeitplan unerwartet rückgängig werden; zeitliche Übersteuerung sichtbar machen.

**C4: Unterschiedliche Pausen.** „Schutz pausieren“ gibt die Regelung frei. Neue Aktion „Laden hier halten“ verlangt tatsächliche Ladesperre bzw. bestätigtes Firmwarelimit und lässt Hitzeschutz aktiv. Die beiden Aktionen brauchen eigene Namen und Statuswerte. Nicht dieselbe Pause semantisch umdeuten.

Abnahme C: realer Kurzbefehl ohne Terminal; Werktagsregel trotz geschlossener App; genau eine Ausführung bei DST/Wake; zeitliche manuelle Übersteuerung nachvollziehbar beendet.

### D — Besser erklären und auswerten · vorgeschlagen 0.5

**D1: Entscheidungsprotokoll.** Strukturierte Ursachen statt nur Freitext: angewandtes Backend, Quelle der Regel, Ziel, tatsächlicher Zustand, Firmware-/Monitorlimit, Messzeitpunkt. Nur Zustandswechsel speichern, begrenzte lokale Aufbewahrung. Oberfläche „Warum lädt mein Mac gerade?“; REST liefert dieselben Ursachecodes. Abnahme: Nutzer kann Hitzeschutz, macOS-Fallback und Reiseausnahme unterscheiden.

**D2: Langzeittrends.** Sieben Tage Rohmessungen behalten; Tagesaggregate für 90/365 Tage mit Abdeckung, Kapazität, Zyklen und Beobachtungsdauer. Keine Linien über Messlücken. Batterieaustausch beginnt neue Serie; geänderte Kapazität nicht als bewiesene Alterung behandeln. Speichergröße und I/O messen. CSV/JSON mit Schema-Version und Import-/Backupstrategie.

**D3: Energiefluss und Zusatzwerte.** Read-only Messspike für Adaptereingang/Leistungsbudget; nur bestätigte Werte zeigen. Flussrichtung ist aus Batterie-Watt bereits möglich, gesamte Systemleistung derzeit nicht. VoiceOver-Text und Reduced Motion. Separater Hardware-Ladestand als Schätzwert, keine ungeprüfte Ersatzregelung.

**D4: Bedienung.** Menüleistenoptionen, kompakte Karten, unabhängige Warnschwelle für niedrigen Akkustand (derzeit hängt sie am unteren Ladebereich), erklärter Limitstatus und wiederherstellbare Einstellungen. Deutsche/englische Texte, Tastatur und VoiceOver prüfen. Keine neue Optionssammlung ohne klare Defaults.

### E — Fortgeschrittene Funktionen · nach Hardware-Abnahme

**E1: Einmalentladung und Vollladen bis Abstecken.** Neue Requesttypen mit Ziel, Deadline, Abbruch und Rückkehr zum Basisprofil. Adapter-/Monitor- und Reservebedingungen gelten immer. Auch API und Kurzbefehle verfügbar; keine unbekannten Hardwareaktionen freigeben.

**E2: Kalibrierungsassistent.** Nur mit nachgewiesenem Backend. Zustandsautomat mit gespeicherter Anfrage-ID und Phasen, Gesamtfrist, temperaturbedingter Pause und klarer Wiederaufnahme nach Neustart. Expliziter Abbruch führt zum Basisprofil. Test Simulation jeder Phase und Ausfallsituation; physische Testcharge erst separat. Nutzen für Anzeigequalität erklären, keine garantiert verlängerte Lebensdauer behaupten. Monatlicher Automatismus ist nicht Default.

**E3: Schlafoptionen.** Persistente Ladesperre und optionale befristete Wachhaltung sind zwei verschiedene Funktionen. Für jede eigene Fähigkeit, Beschreibung und Abnahme. Kein erzwungenes Wachhalten im normalen Schreibtischprofil; das zuvor behobene Deckelproblem darf nicht zurückkehren.

## Bezahlmodell für B-Guard

Empfehlung: **alle Kernfunktionen bleiben kostenlos**, einschließlich REST, Kurzbefehlen, Hitzeschutz und Export. Freiwillige einmalige Unterstützung und GitHub Sponsors können Entwicklung, Signierung und Testgeräte finanzieren. Keine Spendenbuttons oder Zahlungsintegration sind mit dieser Analyse bereits eingerichtet.

Ein Abo erzeugt wiederkehrende Erwartungen an Support und OS-Kompatibilität. Für ein ausschließlich lokal arbeitendes Utility ist ohne fortlaufende Dienstleistung kein klarer Abo-Mehrwert nachgewiesen. Ein günstiger Einmalkauf wäre grundsätzlich marktnäher, widerspricht aber dem bisherigen Gratisversprechen, wenn bestehende Funktionen dafür gesperrt würden. Ein künftiges separates Firmenangebot wäre denkbar: dokumentierte MDM-Bereitstellung und vertraglicher Support, während die lokale App frei bleibt. Bedarf zuerst mit Nutzern prüfen; kein Firmenbedarf aus vorhandenem REST ableiten.

Apple nennt [99 USD pro Mitgliedschaftsjahr, regionale Preise können abweichen](https://developer.apple.com/programs/enroll/). Das ist ein belegter wiederkehrender Vertriebsaufwand, kein Grund, ohne Nutzerentscheidung ein Abo einzuführen. Arbeitszeit, Gebühren und reale Testhardware kommen hinzu; Spendenhöhe und Konversion sind unbekannt.

Vor einer Monetarisierungsentscheidung: 10–15 freiwillige Gespräche zu installierter Konkurrenz, tatsächlichem Nutzen, Installationsabbrüchen und Bereitschaft zur Unterstützung. Zahlungsbereitschaft nicht aus App-Downloads ableiten. Direkte Konkurrenzkosten in Originalwährung vergleichen, keine erfundenen Umsätze oder Marktgrößen.

## Wie wir „besser“ belegen

| Ziel | Nachweis | Freigabekriterium |
| --- | --- | --- |
| Zuverlässige Aktionen | Isolierte API/IPC-Races, vollständige Rückmeldungen | Kein verlorener bestätigter Auftrag in deterministischen Konflikttests. |
| Einfache Installation | Frischer Test-Mac/Account mit öffentlicher DMG | Drag-to-Applications plus verständliche Einrichtung; keine unerklärten Warnungen. Notarisierung separat nachweisen. |
| Deckelbetrieb | Reale Matrix mit Monitor, Stromquelle, Firmware | Displaybetrieb bleibt stabil, normale Schlafmöglichkeit bleibt erhalten, Restore funktioniert. |
| Automatisierung | Kurzbefehl und Wochenregel auf Testsystem | Ohne Terminal nutzbar; keine doppelten Aktionen nach Wake/DST. |
| Verständlichkeit | Fünf freiwillige Usabilitytests | Nutzer erkennen gewünschtes vs. tatsächlich wirksames Limit und Ursache selbstständig. |
| Geringe Eigenlast | Instruments/Activity Monitor bei geöffnetem und geschlossenem UI | CPU/Wakeups/RSS/I/O dokumentieren und gegen identische Baseline messen, kein erfundenes Prozentversprechen. |
| Auswertung | Tagesaggregate mit Datenabdeckung | Keine Lücken als Beobachtungszeit, keine Kalibrierungsänderung als Verschleißnachweis. |

Keine Telemetrie als Voraussetzung. Lokale Diagnoseexporte werden nur nach ausdrücklichem Nutzerentschluss geteilt. Akkukapazitätswerte und Ladezyklen allein belegen keinen chemischen Lebensdauervorteil gegenüber macOS; Gerät, Temperatur, Last, Alter und Kalibrierung sind Störfaktoren. Zuerst funktionale Zuverlässigkeit messen.

## Research-Agenten und Qualitätsprüfung

Drei interne Subagents bearbeiteten Preise, Funktionen und unabhängige Codeprüfung. Die lokal installierte Antigravity-CLI `agy` lieferte zusätzlich eine begrenzte Produktkritik. Übernommen wurde die Idee offener Integrationen. Nicht übernommen wurden unbelegte Alleinstellungsbehauptungen zur Temperatur-Hysterese, ein angeblicher Vertrauensvorteil fehlender Notarisierung, eine unbewiesene Spenden-Konversionsquote und ein zu einfacher Kapazitäts-/Zyklenvergleich als Lebensdauerbeweis.

A1/A2 sind anschließend in 0.3.2 umgesetzt: atomare typisierte Dienstaktionen sowie Request-IDs und snapshotgebundene Abschlüsse. Die ursprüngliche Review bleibt als Befund für 0.3.1 erhalten. Nächster Umsetzungsschritt ist A3/A4. B1 kann lesend parallel laufen. Danach C1/C2; kosmetische Erweiterungen ersetzen keine belegte Steuerungswirkung.

## Umsetzungsnachtrag 0.3.3

D4 und der Pro-Vergleich sind teilweise umgesetzt: frei wählbare Menüleistenanzeige, optionale Popover-Messwerte und unabhängige Niedrigakku-Warnschwelle. A3 ist mit UTF-8-Medientypen und frühzeitigem Größenabbruch bei DMG-Downloads teilweise umgesetzt; Verbindungssättigungs- und Deadline-Abnahme bleiben offen. Native Kurzbefehle, eigene Profile und wiederkehrende Regeln sind weiterhin geplant. Keine neue Hardwaresteuerung oder Systemleistungsmessung wird mit diesem Appupdate behauptet.

## Aktuelle Umsetzungsreihenfolge

Die [Pro-Funktionsroadmap](../ROADMAP.md#nächste-umsetzung-funktionsumfang-aus-aldente-pro) konkretisiert den Abgleich nach 0.3.3 und ersetzt die ältere Reihenfolge für die nächste Umsetzung: Power Flow/Messquellen → native Kurzbefehle → Sonderaktionen → eigene Profile/Zeitpläne → Darstellung/LED. Hardwareforschung läuft zunächst lesend parallel; Kalibrierung folgt erst nach bestätigter Steuerungsfähigkeit.
