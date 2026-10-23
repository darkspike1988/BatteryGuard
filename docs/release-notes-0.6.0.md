# B-Guard 0.6.0 (Arbeitsstand, unveröffentlicht)

0.6.0 macht den Energiebedarf des Macs sichtbar und steuert die macOS-Energiemodi je Stromquelle. App und Hintergrunddienst haben Version 0.6.0; ein älterer Dienst muss über den macOS-Administratordialog aktualisiert werden.

## macOS-Limit: Ladesteuerung ab macOS 27

Auf aktuellen Apple-Silicon-Macs mit macOS 27 fehlen die bisherigen SMC-Ladesperren (`CH0B`, `CH0C`, `CHTE`); B-Guard konnte dort nur noch beobachten oder das Netzteil umschalten. Der neue Modus **macOS-Limit** setzt stattdessen Apples natives Ladelimit über die Klasse `PowerUISmartChargeClient` aus dem privaten PowerUI-Framework.

- Angeboten werden nur die Stufen, die macOS selbst meldet (derzeit 80, 85, 90, 95 und 100 %). Ein Profilziel wird auf die nächste Stufe aufgerundet; die Übersicht zeigt Ziel und tatsächlich gesetzte Stufe.
- Die SMC bleibt in diesem Modus unberührt. Weil macOS das Limit selbst durchsetzt, gilt es auch bei externem Monitor, geschlossenem Deckel und geschlossener App.
- Schutz aus und Pause setzen 100 %, Vollladen, Reiseplanung und Top Up ebenfalls. Hitzeschutz senkt das Limit auf die niedrigste Stufe, bis der Akku abgekühlt ist.
- Kalibrierung, Halten und Einmal-Entladen sind in diesem Modus nicht verfügbar und werden mit Hinweis beendet.
- Der Dienst setzt nur abweichende Werte und liest sie danach zurück. Lehnt macOS ab, meldet B-Guard „nicht unterstützt“ und das bisherige Limit bleibt.
- Beim Wechsel in einen anderen Modus bleibt das zuletzt gesetzte macOS-Limit stehen; es lässt sich in den Batterieeinstellungen ändern.
- Die Schnittstelle ist undokumentiert und kann sich mit macOS-Updates ändern. Ältere Dienste lesen den Modus als „macOS · nur beobachten“.

## Energiemodus je Stromquelle

Low Power Mode und High Power Mode lassen sich getrennt auf „Nicht steuern“, „Immer“, „Nur auf Akku“ oder „Nur am Netzteil“ stellen. Der Dienst schreibt die Werte über die öffentliche Schnittstelle `pmset -b` (Akku) und `pmset -c` (Netzteil); macOS wechselt danach selbst. Die jeweils andere Stromquelle steht auf „Automatisch“. Private SMC-Schlüssel werden dafür nicht geschrieben.

- High Power Mode erscheint nur, wenn `pmset` auf diesem Mac die Einstellung `powermode` anbietet. Auf Macs ohne `powermode` nutzt B-Guard `lowpowermode`.
- Gelten beide Modi für dieselbe Stromquelle, hat Low Power Mode Vorrang; die Einstellungen weisen darauf hin.
- Eine bisherige Automatik „Low Power Mode auf Akkubetrieb“ wird als „Nur auf Akku“ übernommen. Unbekannte Werte schalten keinen Modus ein. Das alte Konfigurationsfeld bleibt für ältere Dienste erhalten.
- Wird die Automatik ausgeschaltet, setzt der Dienst beide Stromquellen einmalig auf „Automatisch“ zurück.

## SoC-Leistung im Energiefluss

Der Hintergrunddienst misst etwa alle 30 Sekunden eine Sekunde lang mit Apples `powermetrics` die Leistung von CPU, GPU und Neural Engine (niedrige Priorität, ohne den Regeltakt aufzuhalten). Der Energiefluss zeigt daraus die SoC-Leistung mit Aufteilung und „Übrige Komponenten“ als Differenz zur abgeleiteten Mac-Leistung. Display und USB meldet macOS auf getesteten Macs nicht einzeln in Watt; B-Guard schätzt sie nicht. Apples IOReport-Energiemodell liefert unter macOS 27 für CPU, Neural Engine und DRAM keine Werte mehr und wird deshalb nicht verwendet.

## Netzteil und Energiewirkung in der Diagnose

- **Netzteil:** Bezeichnung, Hersteller, Nennleistung, ausgehandelte Spannung und Stromstärke sowie Firmware aus `AppleSmartBattery/AdapterDetails`. Nennwerte beschreiben das Ladeprofil, nicht den aktuellen Verbrauch. Die Seriennummer erscheint erst nach Klick und in keinem Export.
- **Hohe Energiewirkung:** Prozesse aus der Energiespalte von `top`, gemessen über eine Sekunde und alle zehn Sekunden erneuert, solange die Diagnoseseite sichtbar ist. Schwelle (ab 1, 5 oder 20) und Hintergrundprozesse sind wählbar. Sichtbare Apps lassen sich nach Rückfrage normal beenden. Der Wert ist Apples relative Energiewirkung, keine Wattangabe. Prozessnamen erscheinen in keinem Export.

Netzteil und Energiewirkung benötigen keinen aktualisierten Dienst; die SoC-Leistung erscheint erst mit Dienst 0.6.0.

## Menüleiste und Kurzbefehle

- **Weitere Werte in der Menüleiste:** Restlaufzeit, wirksames Ladeziel, SoC-Leistung und ein gelbes Blatt bei aktivem Low Power Mode lassen sich einzeln zuschalten. Sie erscheinen hinter der bisherigen Anzeige und nur, wenn aktuelle Werte vorliegen.
- **Kurzbefehl „Energiemodus festlegen“:** setzt die Regeln für Low Power Mode und High Power Mode; leere Parameter bleiben unverändert. Dieselbe Aktion steht in der lokalen API als `power-mode` bereit und setzt keinen manuellen Vorrang für Ladeprofile.

## Prüfstand

252 Tests in 39 Suiten (Swift Testing) und 106 XCTests bestanden, darunter neue Tests für Regeln, Vorrang, Migration, Fehlerwiederholung, Probelauf, Netzteil-Parser, `top`-Parser sowie Stufenwahl, Hitzeschutz, Top Up und Rücklesen im macOS-Limit-Modus. Auf dem MacBookPro18,3 unter macOS 27.0 meldet PowerUI die Stufen 80–100 %; Lesen und ein Schreibtest mit unverändertem Wert gelangen ohne Administratorrechte. Auf einem MacBookPro18,3 (M1 Pro) bestätigt: Netzteilangaben werden gelesen, `pmset` bietet dort kein `powermode`, High Power Mode bleibt ausgeblendet. Die Umschaltung durch den installierten Dienst 0.6.0 ist noch nicht physisch abgenommen.
