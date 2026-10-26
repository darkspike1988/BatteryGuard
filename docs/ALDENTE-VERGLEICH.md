# B-Guard und AlDente im Vergleich

Stand: 26. Oktober 2026, B-Guard 0.9.0. Grundlage sind die öffentlichen Seiten von AlDente (apphousekitchen.com: Übersicht, Funktionen, Preise, FAQ), die Versionshinweise 1.39 bis 1.39.4 und die GitHub-Issues #1771 und #1802. AlDente ist nicht quelloffen; was AlDente intern tut, ist nur aus diesen Angaben bekannt. Kein AlDente-Code ist übernommen.

## Preis und Bedingungen

| | AlDente Free | AlDente Pro | B-Guard |
|---|---|---|---|
| Preis | kostenlos | 11,49 € pro Jahr oder 23,99 € einmalig | kostenlos |
| Quellcode | nein | nein | offen |
| Lizenzprüfung | – | online mindestens alle 30 Tage | keine |
| Signatur | notarisiert | notarisiert | ad hoc signiert, nicht notarisiert |
| Netzwerk | Lizenz, Updates | Lizenz, Updates | nur Update-Prüfung, abschaltbar |

## Funktionen

| Funktion | AlDente | B-Guard |
|---|---|---|
| Ladelimit | Free | ja |
| Ladelimit unter macOS 27 | ab 1.39, unter 80 % mit eigenem Schalter | macOS-Limit-Modus (Stufen 80–100 %), unter 80 % mit eigenem Schalter direkt als macOS-Limit |
| Ladelimit im Schlaf halten | Pro („Stop Charging when Sleeping“) | ja; Standard hält ein erreichtes Limit, optional das Laden ganz stoppen; im macOS-Limit-Modus hält die Firmware |
| Limit gilt bei geschlossener App | Pro („Stop Charging when App Closed“) | ja, eigener Hintergrunddienst |
| Untere Grenze („Sailing“) | Pro | ja |
| Hitzeschutz | Pro | ja |
| Kälteschutz | nein | ja |
| Top Up | Free | ja |
| Entladen am Netzteil | Free | im macOS-Limit-Modus auf angebotene Stufen (experimentell); sonst bis zur Hardware-Abnahme gesperrt |
| Kalibrierungsmodus 100 → 10 → 100 % | Pro | bewusst entfernt ([Begründung](EVIDENCE.md#kalibrierung)); Apples eigene Kalibrierung wird erkannt und erklärt |
| MagSafe-LED | Free | ja, auch aus |
| Zeitpläne | ja | ja: Profil, Ladelimit, Pause, Top Up, Vorlagen |
| Low Power und High Power Mode | Kurzbefehl, Zeitplan | je Stromquelle, Kurzbefehl; vorheriger Wert wird wiederhergestellt |
| Kurzbefehle, URL-Befehle | Kurzbefehle | Kurzbefehle, `bguard://`, globale Tastenkürzel |
| Energiefluss | ja | ja, dazu SoC-Leistung und Energie-Apps |
| Hardware-Ladestand | Pro | ja |
| Wach bleiben bis zum Limit | ja | ja, optional auch zugeklappt mit Sicherheitsabschaltung |
| Intel-Macs, Boot Camp | Intel-Modus | Intel nicht abgenommen |
| Lokale REST-API, CSV-Export | nein | ja |
| Reiseplanung, Monitorprofil, WLAN-Regeln | nein | ja |
| „Warum lädt mein Mac so?“ | „What's going on“-Zeile | Erklärung mit Ursachen, Fähigkeitstest der SMC-Schlüssel |
| Schlafbericht mit Weckgründen | nein | ja |
| Ladeketten-Check (Kabel, Dock, Netzteil) | Hinweis auf schwaches Netzteil im Energiefluss | ja |
| Lebensdauer-Analyse, Austauschprognose, AppleCare-Erinnerung | Stats (Pro) | ja, mit PDF-Bericht |
| Akkus verbundener Geräte | nein | ja |
| IT-Vorgaben per Konfigurationsprofil | nein | ja |
| Sicherung, verschlüsselter Verlauf | nein | ja |
| Sprachen | viele | Deutsch, Englisch, Russisch |

## Wo AlDente vorn liegt

- **Erprobung:** Viele Nutzer auf vielen Modellen. B-Guard ist auf wenigen Geräten getestet; Halten unter 80 % und Einmal-Entladen sind noch nicht physisch abgenommen.
- **Installation:** AlDente ist notarisiert. B-Guard braucht beim ersten Start eine Freigabe in den Systemeinstellungen.
- **Intel und Boot Camp:** AlDente unterstützt sie ausdrücklich.
- **Kalibrierungsmodus:** Nur AlDente hat ihn. B-Guard verzichtet bewusst darauf, weil er nur die Anzeige korrigiert und einen Vollzyklus kostet.

## Wo B-Guard vorn liegt

- **Kosten und Offenheit:** Was AlDente nur in Pro anbietet (Schlaf, geschlossene App, Hitzeschutz, untere Grenze, Hardware-Ladestand), ist kostenlos und quelloffen, ohne Online-Lizenzprüfung.
- **Erklären statt nur Steuern:** Ursachen für das Ladeverhalten, Schlafbericht, Ladeketten-Check, Lebensdauer-Analyse, Austauschprognose und AppleCare-Frist hat AlDente nicht.
- **Ehrlichkeit über macOS 27:** B-Guard prüft, welche Steuerung die Firmware noch erlaubt, und zeigt es an, statt eine Steuerung vorzutäuschen.
- **Automatisierung und Verwaltung:** Lokale REST-API, `bguard://`, CSV-Export, Reiseplanung, Monitorprofil, WLAN-Regeln und IT-Vorgaben.

## Ladelimit unter macOS 27

Seit macOS 27 sperrt die Firmware die SMC-Ladesperre (CHTE, CH0B, CH0C). Die Werkzeuge haben unterschiedliche Wege gefunden:

- **macOS-Ladelimit setzen (B-Guard, BatLimit, Battery Toolkit für macOS 27):**
  - Stufen von 80 bis 100 % setzt B-Guard über `setMCLLimit:` des privaten `PowerUISmartChargeClient`; macOS prüft dabei den Bereich.
  - Werte darunter schreibt B-Guard mit eigenem Schalter in `mclLimitValue` (`com.apple.smartcharging.topoffprotection`) und lässt PowerUIAgent die Einstellung nach `com.apple.smartcharging.defaultschanged` neu laden.
  - Der Wert gilt im Schlaf und ohne laufenden Dienst.
- **Netzteil umschalten (CHIE):** batt („adapter mode“) und ChargeCap trennen das Netzteil an der oberen Grenze und verbinden es an der unteren wieder. Das wirkt nur im Wachzustand und erzeugt zusätzliche Teilzyklen. B-Guard nutzt diesen Weg nicht für Ziele, nur ohne den Schalter für Werte unter 80 % noch als Sicherheitshalt beim Hitze- und Kälteschutz.
- **AlDente:** Laut den Versionshinweisen zu 1.39 wurde die Ladesteuerung neu gebaut; Ziele unter 80 % brauchen einen eigenen Schalter. Welchen Weg AlDente nutzt, ist nicht veröffentlicht.

Keiner dieser Wege ist von Apple dokumentiert. Ein macOS-Update kann jeden davon schließen.

## Quellen

- AlDente: [Übersicht](https://apphousekitchen.com/aldente-overview/), [Preise](https://apphousekitchen.com/aldente-overview/pricing/), [FAQ](https://apphousekitchen.com/faq/), [Issue #1771](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/issues/1771), [Issue #1802](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/issues/1802)
- [BatLimit](https://github.com/DmitriyODS/BatLimit), [Battery Toolkit für macOS 27](https://github.com/andersonproescholdbell/battery-toolkit-macos27), [batt #152](https://github.com/charlie0129/batt/issues/152) und [#154](https://github.com/charlie0129/batt/pull/154)
- [Apple 102338: Ladelimit](https://support.apple.com/en-us/102338)
