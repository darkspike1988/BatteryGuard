# B-Guard und AlDente im Vergleich

Stand: 23. Oktober 2026. Grundlage sind die öffentlichen Seiten von AlDente (apphousekitchen.com: Übersicht, Funktionen, Preise, FAQ), die Versionshinweise 1.39 bis 1.39.4 und die GitHub-Issues #1771 und #1802. AlDente ist nicht quelloffen; was AlDente intern tut, ist nur aus diesen Angaben bekannt.

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
| Ladelimit unter macOS 27 | ab 1.39, unter 80 % mit eigenem Schalter | ab dieser Version über das macOS-Ladelimit, unter 80 % mit eigenem Schalter |
| Ladelimit im Schlaf halten | Pro („Stop Charging when Sleeping“) | ja; mit macOS-Ladelimit hält die Firmware den Wert |
| Limit gilt bei geschlossener App | Pro („Stop Charging when App Closed“) | ja, eigener Hintergrunddienst |
| Untere Grenze („Sailing“) | Pro | ja (untere und obere Grenze) |
| Hitzeschutz | Pro | ja |
| Top Up | Free | ja |
| Entladen am Netzteil | Free | vorhanden, bis zur Hardware-Abnahme gesperrt |
| Automatisches Entladen über dem Limit | Free/Pro (Angaben widersprechen sich) | ja (aktives Entladen über dem Limit) |
| Kalibrierungsmodus 100 → 10 → 100 % | Pro | bewusst entfernt ([Begründung](EVIDENCE.md#kalibrierung)) |
| MagSafe-LED | Free | ja |
| Zeitpläne | ja | ja: Profil, Ladelimit, Pause, Top Up |
| Low Power Mode | Kurzbefehl, Zeitplan | automatisch auf Akku, Kurzbefehl |
| Kurzbefehle | ja | ja |
| Energiefluss | ja | ja |
| Hardware-Ladestand | Pro | im Energiefluss und in der lokalen API |
| Wach bleiben bis zum Limit | ja | ja |
| Intel-Macs, Boot Camp | Intel-Modus | Intel nicht abgenommen |
| Lokale REST-API, CSV-Export | nein | ja |
| Reiseplanung, Monitorprofil | nein | ja |
| „Warum lädt mein Mac so?“ | „What's going on“-Zeile | Erklärung mit Ursachen, Fähigkeitstest der SMC-Schlüssel |
| Schlafbericht mit Weckgründen | nein | ja |
| Ladeketten-Check (Kabel, Dock, Netzteil) | Hinweis auf schwaches Netzteil im Energiefluss | ja |
| Austauschprognose, AppleCare-Erinnerung | nein | ja |
| Alterungsbelastung nach Studienlage | nein | ja |
| Sprachen | viele | Deutsch, Englisch, Russisch |

## Wo AlDente vorn liegt

- **Erprobung:** Viele Nutzer auf vielen Modellen. B-Guard ist auf wenigen Geräten getestet; Entladen und Halten sind bis zur Hardware-Abnahme gesperrt.
- **Installation:** AlDente ist notarisiert. B-Guard braucht beim ersten Start eine Freigabe in den Systemeinstellungen.
- **Intel und Boot Camp:** AlDente unterstützt sie ausdrücklich.
- **Kalibrierungsmodus:** Nur AlDente hat ihn. B-Guard verzichtet bewusst darauf, weil er nur die Anzeige korrigiert und einen Vollzyklus kostet.

## Wo B-Guard vorn liegt

- **Kosten und Offenheit:** Die Funktionen, die AlDente nur in Pro anbietet (Schlaf, geschlossene App, Hitzeschutz, untere Grenze), sind kostenlos und quelloffen, ohne Online-Lizenzprüfung.
- **Erklären statt nur Steuern:** Ursachen für das Ladeverhalten, Schlafbericht, Ladeketten-Check, Austauschprognose und AppleCare-Frist hat AlDente nicht.
- **Ehrlichkeit über macOS 27:** B-Guard prüft, welche Steuerung die Firmware noch erlaubt, und zeigt es an, statt eine Steuerung vorzutäuschen.
- **Automatisierung:** Lokale REST-API, CSV-Export, Reiseplanung und Monitorprofil.

## Ladelimit unter macOS 27

Seit macOS 27 sperrt die Firmware die SMC-Ladesperre (CHTE, CH0B, CH0C). Die Werkzeuge haben unterschiedliche Wege gefunden:

- **macOS-Ladelimit setzen:** PowerUIAgent liest den Wert `mclLimitValue` aus seinem Einstellungsbereich `com.apple.smartcharging.topoffprotection`. Nach der Benachrichtigung `com.apple.smartcharging.defaultschanged` lädt er ihn neu, ohne den Bereich 80–100 % zu prüfen. Diesen Weg nutzen BatLimit und Battery Toolkit für macOS 27, und B-Guard nutzt ihn jetzt auch. Der Wert gilt im Schlaf und ohne laufenden Dienst.
- **Netzteil umschalten (CHIE):** batt („adapter mode“) und ChargeCap trennen das Netzteil an der oberen Grenze und verbinden es an der unteren wieder. Das wirkt nur im Wachzustand und erzeugt zusätzliche Teilzyklen. B-Guard nutzt diesen Weg nicht.
- **AlDente:** Laut den Versionshinweisen zu 1.39 wurde die Ladesteuerung neu gebaut; Ziele unter 80 % brauchen einen eigenen Schalter. Welchen Weg AlDente nutzt, ist nicht veröffentlicht.

Keiner dieser Wege ist von Apple dokumentiert. Ein macOS-Update kann jeden davon schließen.

## Quellen

- AlDente: [Übersicht](https://apphousekitchen.com/aldente-overview/), [Preise](https://apphousekitchen.com/aldente-overview/pricing/), [FAQ](https://apphousekitchen.com/faq/), [Issue #1771](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/issues/1771), [Issue #1802](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/issues/1802)
- [BatLimit](https://github.com/DmitriyODS/BatLimit), [Battery Toolkit für macOS 27](https://github.com/andersonproescholdbell/battery-toolkit-macos27), [batt #152](https://github.com/charlie0129/batt/issues/152) und [#154](https://github.com/charlie0129/batt/pull/154)
- [Apple 102338: Ladelimit](https://support.apple.com/en-us/102338)
