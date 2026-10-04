# Marktanalyse: Bezahlmodelle für macOS-Batterieapps

Recherche: **4. Oktober 2026**. Preise sind öffentlich angezeigte Herstellerpreise beim Abruf, keine abgeschlossenen Checkout-Angebote. Keine Währungsumrechnung. Steuer-/Länderaufschläge sind nur angegeben, wenn belegt. Funktionen sind Herstellerangaben, keine unabhängig getestete Hardware-Kompatibilität. B-Guard bleibt entsprechend der bisherigen Produktentscheidung kostenlos und Open Source; dieser Bericht ändert kein Bezahlmodell.

## Preisvergleich

| Produkt | Kostenlos | Bezahlmodell / angezeigter Preis | Lizenzumfang | Quellen |
|---|---|---|---|---|
| AlDente | Free mit Ladelimit und manueller Entladung | Pro **11,49 € jährlich**, automatische Verlängerung; **23,99 € Lifetime** | Ein Schlüssel für bis zu **3 macOS-Benutzerkonten**, verteilt auf höchstens 3 Macs | [Preise](https://apphousekitchen.com/de/aldente/preisgestaltung/) |
| BatFi | Kein dauerhaft kostenloses aktuelles Angebot auf der Produktseite | **15 $ einmal**, ausdrücklich kein Abo | Alle Macs, die der Käufer besitzt bzw. kontrolliert | [Produkt](https://micropixels.software/batfi/), [FAQ](https://micropixels.software/support/) |
| Energiza | Monitoring und Benachrichtigungen | Pro **1,49 USD/Monat**, **9,99 USD/Jahr**, **19,99 USD einmal** | Monat: 2 Geräte; Jahr: 3; Forever: 5 | [Produkt und Preise](https://appgineers.de/energiza/) |
| Battery Toolkit | Kostenloser Download; BSD-3-Clause | Kein Bezahlplan gefunden | Open-Source-Lizenz statt Aktivierungszähler | [Repository](https://github.com/mhaeuser/Battery-Toolkit) |
| BatteryBoi | Vollständig kostenlos, GPL-3.0 | Kein aktueller kostenpflichtiger Mac-Tarif im Repository | Open Source; vor allem Monitoring, Bluetooth-Geräte, Benachrichtigungen | [Repository](https://github.com/thebarbican19/BatteryBoi) |
| Stasis | Download und Quellcode, GPL-3.0 | Kein kostenpflichtiger Tarif im Repository ausgewiesen | Open-Source-Lizenz | [Repository](https://github.com/srimanachanta/Stasis) |
| batt | Kostenlos und Open Source | Kein Bezahlplan im Repository | CLI und native Menüleisten-App | [Repository](https://github.com/charlie0129/batt) |

## Weitere Angebote aus den Nutzerlinks: Monitoring statt Ladesteuerung

Die im [ka2-Überblick](https://ka2.ch/batteriegesundheit-6-apps-die-deine-macbook-batterie-lieben-wird/) genannten Diagnoseprodukte werden hier anhand ihrer Primärquellen getrennt betrachtet. Der Artikel ist keine Quelle für heutige Endpreise.

| Produkt | Verifizierter Preis / Modell | Test / Umfang / offene Punkte | Primärquelle |
|---|---|---|---|
| **Better Battery 2** (agross) | Standard kostenlos; **Pro Edition 4,99 €** im deutschen App Store; kein Abozeitraum angegeben | **30 Tage kostenloser Pro-Test**, Historie und Diagramme in Pro. Explizite Gerätezahl, Hauptversionsupdates und IAP-Typ (z. B. non-consumable) auf der Webseite nicht ausgewiesen. | [Deutscher App Store](https://apps.apple.com/de/app/better-battery-2-stats-info/id1455789676?mt=12) |
| **Battery Health 2** (FIPLAB) | Kostenlos; **Power History 9,99 €** als deutscher In-App-Kauf; kein Abozeitraum angegeben | Batterieinfos/Benachrichtigungen kostenlos, Verlauf freischaltbar; keine Testfrist gefunden. Letzter ausgewiesener Release: 1.94 vom 24.01.2022. | [Deutscher App Store](https://apps.apple.com/de/app/battery-health-2-stats-info/id1120214373) |
| **Battery Monitor** (Marcel Bresink) | **4,99 €** App-Kauf im deutschen App Store | Familie bis 6 Mitglieder laut Store; Monitoring, Verlauf und Bluetooth-Batterien; kein Ladesteuerungsangebot belegt. Keine Test-/Refundfrist auf dem Listing angegeben. | [Deutscher App Store](https://apps.apple.com/de/app/battery-monitor/id413678017?mt=12) |
| **coconutBattery 4** | Basisdownload plus kostenpflichtige Plus-Editionen, beide **Einmalkauf**; Betrag im abgerufenen Seiteninhalt nicht vorhanden | v4-Lizenz mit 4.x-Updates oder Lifetime mit allen künftigen Plus-Updates; beide unbegrenzte Geräte. Test: **10 App-Starts** im Plus-Modus. | [Hersteller](https://www.coconut-flavour.com/coconutbattery/) |
| **iStat Menus 7.5** | Kauf für Single/Family; Preisfelder im Abruf nur **$?**, daher kein belastbarer Betrag | **14 Tage Test**, Familie bis 5 Mitglieder, 6 Monate Wetterdaten, lokale Steuern möglich; breite Systemüberwachung. Upgrades aus v6 separat. | [Hersteller](https://bjango.com/mac/istatmenus/) |

Better Battery 2 ist **nicht** Battery Health 2. Der Nutzerlink verweist auf agross, nicht FIPLAB. Better Battery 2 dokumentiert lokale Speicherung, bis 48 Stunden Ladekurven sowie Kapazitäts-/Zyklus-/Nutzungsdiagramme, aber keine aktive Ladegrenzsteuerung. Die Familienfreigabeformulierung im Store ist nur bedingt („einige In-App-Käufe“); sie belegt keine konkrete Pro-Mehrgerätelizenz. Der verlinkte agross-Produktpfad lieferte 404. Die Rückzahlung eines Store-Kaufs wurde hier nicht ausgelöst; keine herstellereigene Refundgarantie belegt.

Für deutsche App-Store-Angebote werden nur Euro-Listenpreise oben genutzt; US-Store-Preise werden nicht übertragen. Explizite MwSt-Ausweisung im Listing wurde nicht gefunden. Strategisch zeigt Better Battery 2: Umfangreiche Historie wird bereits für einen kleinen IAP-Betrag angeboten. B-Guard kann kostenlose Historie sinnvoll positionieren, sollte den Mehrwert aber über verlässliche Steuerung und verständliche Erklärungen liefern.

### AlDente: Freemium plus Abo und Lifetime

Pro bündelt automatische Entladung, Deckelmodus, Wärmeschutz, Sailing Mode, MagSafe-LED, Top Up, Kalibrierung und Apple Shortcuts. Free eignet sich bereits für einen einfachen Ladelimitbedarf. Auf der abgerufenen Preisseite war die Steuerbehandlung nicht ausdrücklich erkennbar; den deutschen Endbetrag deshalb im Checkout prüfen. [Herstellerpreise](https://apphousekitchen.com/de/aldente/preisgestaltung/)

Die FAQ verlangt auch für Pro eine Online-Lizenzprüfung mindestens alle 30 Tage; nach längerer Offlinezeit fällt die App auf Free zurück. Aktuelle Free/Pro-Versionen sind nicht Open Source; nur ältere Classic-Versionen bis 2.0 sind es. Eine direkte Pro-Testdauer ließ sich in der FAQ nicht bestätigen. [FAQ](https://apphousekitchen.com/faq/)

Die Lifetime-Lizenz bestätigt zeitlich unbegrenzte Nutzung. Eine ausdrückliche Garantie sämtlicher zukünftiger Hauptversionen wurde in den gelesenen Vertragsabschnitten nicht gefunden. Der Vertrag beschreibt 14 Tage Widerruf für private Verbraucher mit einer Ausnahme für digitale Bereitstellung nach entsprechenden Zustimmungen; das ist keine pauschale, bedingungslose Geld-zurück-Garantie. Das PDF trägt intern Stand März 2022 trotz späterem Uploadpfad. [Lifetime-Vertrag](https://apphousekitchen.com/wp-content/uploads/2025/03/AlDente-Lifetime-License.pdf)

**Setapp ist ein eigener Vertriebskanal.** AlDentes deutsche Seite nennt dafür 9,99 €/Monat; Setapps eigene AlDente-Seite zeigt dagegen Mitgliedschaft **ab 14,99 $/Monat** und App-Einzeltarif **ab 14,49 $/Jahr**, jeweils mit 7 Tagen Test. Diese Angaben sind widersprüchlich und teilweise andere Produkte/Währungen; nicht zu einem angeblich eindeutigen Preis zusammenziehen. Maßgeblich ist der gewählte Setapp-Tarif im Checkout. [Setapp-Angebot](https://setapp.com/apps/aldente-pro), [Setapp-Preisseite](https://setapp.com/pricing)

### BatFi: einfacher Einmalkauf, persönliche Mehrgeräte-Lizenz

BatFi verkauft aktuell einen gemeinsamen Funktionsumfang: zeit- und ortsabhängige Regeln, einmalige Vollladung, Leistungsanzeige, energieintensive Apps, Batteriegesundheit und Tastenkürzel. Es konkurriert damit über Komfort und Automatisierung, nicht nur über einen Ladeprozentsatz. [Produktseite](https://micropixels.software/batfi/)

Die FAQ bestätigt 30 Tage Geld-zurück-Garantie, personalisierte Rabatte auf Anfrage und mögliche lokale Checkout-Währungen über Gumroad. Eine kostenlose Testphase, explizite Steuerbehandlung und ein verbindliches Versprechen aller zukünftigen Hauptversionsupdates konnten dort nicht verifiziert werden. Der Gumroad-Link lieferte beim Abruf keine auswertbare Preisseite. BatFi nennt Unterstützung unter 80 % sowie Entladung bei geschlossenem Deckel unter macOS 27 ab Version 4; diese Aussagen sind für eine spätere praktische Gegenprobe wichtig. [FAQ](https://micropixels.software/support/), [Kaufseite](https://micropixels.gumroad.com/l/batfi)

### Energiza: starke Preisstaffelung

Die Produktseite kennzeichnet **USD, mögliche zusätzliche Steuern**, 30 Tage Test für alle Pro-Pläne und Paddle als Zahlungsanbieter. Ladegrenzen und manuelles Laden/Entladen sind Pro, Monitoring und Benachrichtigungen kostenlos. Entladung erfordert laut Hersteller Apple Silicon; Intel wird für andere Funktionen unterstützt. [Produktseite](https://appgineers.de/energiza/)

Die Erstattungsrichtlinie gibt Privatkunden 30 Tage zur Rückforderung, verlangt Kaufdetails und nennt E-Mail als Antragsweg; Dokumentstand November 2022. [Refund Policy](https://appgineers.de/energiza/refund.html)

Die EULA sagt regelmäßige bzw. bedarfsabhängige Updates, schließt gleichzeitig eine Verpflichtung zum fortgesetzten Support oder zur weiteren Aktualisierung aus. Ihre Mehrgeräte-/Geschäftsnutzungsformulierungen sind nicht völlig konsistent mit den Produktstaffeln und der Beschränkung auf persönliche, nichtkommerzielle Nutzung. Keine Annahme von unbegrenzten kommerziellen Lizenzen oder garantierten Lifetime-Updates. [EULA](https://appgineers.de/energiza/eula.html)

### Kostenlose Angebote sind echte Konkurrenz

Battery Toolkit bietet obere/untere Grenzen, Wärmeschutz und manuelle Aktionen, ist aber seit **21. März 2026 archiviert**. Das Repository weist ausdrücklich auf fehlende Notarisierung hin. Wartung und einfacher Start sind daher relevante Differenzierungschancen. [Repository](https://github.com/mhaeuser/Battery-Toolkit)

BatteryBoi ist primär eine Anzeige-/Benachrichtigungsalternative; das gelesene README belegt keine Ladelimitsteuerung. Es ist daher angrenzende Konkurrenz statt voller Ersatz. [Repository](https://github.com/thebarbican19/BatteryBoi)

Stasis nennt bereits Ladelimit, Sailing Mode, Entladung, Wärmeschutz, Leistungsdiagramm und MagSafe-LED. Kostenlos plus diese Funktionsliste wäre für B-Guard folglich kein einzigartiges Verkaufsversprechen. Das README enthält zudem verschiedene Mindestversionen für Nutzung und Build; nicht als umfassend getestete Kompatibilität behandeln. [Repository](https://github.com/srimanachanta/Stasis)

batt bietet obere/untere Grenzen, CLI, native GUI und experimentelle automatische Kalibrierung. Das Projekt beschreibt ausdrücklich unterschiedliche Mechanismen auf älterer und neuerer Firmware. Eine Automatisierungsschnittstelle allein ist daher ebenfalls kein exklusives Merkmal; B-Guard muss insbesondere Bedienbarkeit und zuverlässige Zustandsauskunft verbessern. [Repository](https://github.com/charlie0129/batt)

## Strategische Ableitung für B-Guard

Die folgenden Punkte sind **Empfehlungen aus dieser Recherche**, keine belegten Marktanteile oder gemessene Zahlungsbereitschaft.

1. **Kostenlos und Open Source beibehalten.** Es erfüllt die bisherige Zusage und entfernt Lizenzprüfung, Geräteaktivierung und Aboverwaltung. Nicht behaupten, allein dadurch konkurrenzlos zu sein.
2. **Vertrauen zuerst:** signierte/notarisierte Distribution, nachvollziehbare Kompatibilitätsmatrix, klare Unterscheidung zwischen gespeichertem Wunschlimit und tatsächlich wirksamer Hardwaresteuerung, zuverlässiger Deckel-/Monitorbetrieb und dokumentierter Rückweg. Das ist wertvoller als eine größere Zahl unbestätigter Features.
3. **Komfort gezielt aufholen:** einfache Regeln für Schreibtisch/unterwegs, sichere Reiseplanung, verständliche Benachrichtigungen und Apple Shortcuts. BatFi und AlDente zeigen, dass Automatisierung ein bezahltes Komfortpaket trägt.
4. **REST als gut dokumentierte Integrationsfläche ausbauen:** stabile Versionierung, aktuelle Zustände samt Gründen, Beispiele für Shortcuts/Raycast/Home Assistant, leicht auffindbare Tokenverwaltung. Ziel ist nutzbare Integration, keine bloße API-Checkbox.
5. **Finanzierung freiwillig und getrennt diskutieren:** einmalige Spenden, Sponsoring für Testhardware/Developer-ID und optional bezahlte Unternehmenseinrichtung oder Support können mit freiem Kern vereinbar sein. Preise dafür wären neue Hypothesen, keine aus dem Markt belegten Einnahmen. Nicht implementieren, ohne Produktentscheidung.
6. **Kein erzwungenes Batterie-Abo ohne zusätzlichen laufenden Dienst.** Die geprüften Konkurrenten bieten günstige Einmalkäufe neben oder statt Abos. Ein lokales B-Guard-Abo würde den bisherigen kostenlosen Nutzen schwächen und müsste erst durch echte Kundengespräche gerechtfertigt werden.

## Transparenter Kostenvergleich

Reine Rechnung auf Basis der angezeigten Listenpreise, unveränderte Tarife und Steuern unberücksichtigt: AlDente kostet bei drei Jahreszahlungen **34,47 €**, Lifetime **23,99 €**. Energiza kostet bei drei Jahreszahlungen **29,97 USD**, Forever **19,99 USD**; 36 Monatszahlungen **53,64 USD**. BatFi bleibt beim ausgewiesenen Einmalkauf **15 $**. Diese Rechnung ist keine Zukunftspreisgarantie und vergleicht keine identischen Lizenzumfänge.

## Noch zu verifizieren, bevor öffentliche Werbevergleiche erscheinen

- Deutschland-Checkout samt Steuern und Währung bei AlDente, BatFi und Energiza; im Rahmen dieser Recherche wurde kein Kauf ausgelöst.
- Künftige Hauptversionsupdates und direkte Trial-Bedingungen dort, wo die Hersteller keine eindeutige Aussage machen.
- Praktische Funktionen auf denselben Mac-/Firmware-Konfigurationen, insbesondere Limits unter 80 %, externe Monitore, Deckel und Ruhezustand.
- Wartungsaktivität und angebotene Downloads jedes kostenlosen Konkurrenten; Archivierung ist belegt, allgemeine Qualität oder Sicherheit wurde hier nicht bewertet.
- Zahlungsbereitschaft und relevante Nutzersegmente über Interviews. Preislisten und GitHub-Sterne liefern keine belastbare Marktgröße, Umsätze oder Conversionrate.
