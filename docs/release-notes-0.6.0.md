# B-Guard 0.6.0 (Arbeitsstand, unveröffentlicht)

0.6.0 macht den Energiebedarf des Macs sichtbar und steuert die macOS-Energiemodi je Stromquelle. App und Hintergrunddienst haben Version 0.6.0; ein älterer Dienst muss über den macOS-Administratordialog aktualisiert werden.

## Energiemodus je Stromquelle

Low Power Mode und High Power Mode lassen sich getrennt auf „Nicht steuern“, „Immer“, „Nur auf Akku“ oder „Nur am Netzteil“ stellen. Der Dienst schreibt die Werte über die öffentliche Schnittstelle `pmset -b` (Akku) und `pmset -c` (Netzteil); macOS wechselt danach selbst. Die jeweils andere Stromquelle steht auf „Automatisch“. Private SMC-Schlüssel werden dafür nicht geschrieben.

- High Power Mode erscheint nur, wenn `pmset` auf diesem Mac die Einstellung `powermode` anbietet. Auf Macs ohne `powermode` nutzt B-Guard `lowpowermode`.
- Gelten beide Modi für dieselbe Stromquelle, hat Low Power Mode Vorrang; die Einstellungen weisen darauf hin.
- Eine bisherige Automatik „Low Power Mode auf Akkubetrieb“ wird als „Nur auf Akku“ übernommen. Unbekannte Werte schalten keinen Modus ein. Das alte Konfigurationsfeld bleibt für ältere Dienste erhalten.
- Wird die Automatik ausgeschaltet, setzt der Dienst beide Stromquellen einmalig auf „Automatisch“ zurück.

## Netzteil und Energiewirkung in der Diagnose

- **Netzteil:** Bezeichnung, Hersteller, Nennleistung, ausgehandelte Spannung und Stromstärke sowie Firmware aus `AppleSmartBattery/AdapterDetails`. Nennwerte beschreiben das Ladeprofil, nicht den aktuellen Verbrauch. Die Seriennummer erscheint erst nach Klick und in keinem Export.
- **Hohe Energiewirkung:** Bis zu acht Prozesse aus der Energiespalte von `top`, gemessen über eine Sekunde und alle zehn Sekunden erneuert, solange die Diagnoseseite sichtbar ist. Der Wert ist Apples relative Energiewirkung, keine Wattangabe. Prozessnamen erscheinen in keinem Export.

Beide Ansichten sind rein lesend und benötigen keinen aktualisierten Dienst.

## Prüfstand

237 Tests in 36 Suiten bestanden, darunter neue Tests für Regeln, Vorrang, Migration, Fehlerwiederholung, Probelauf, Netzteil-Parser und `top`-Parser. Auf einem MacBookPro18,3 (M1 Pro) bestätigt: Netzteilangaben werden gelesen, `pmset` bietet dort kein `powermode`, High Power Mode bleibt ausgeblendet. Die Umschaltung durch den installierten Dienst 0.6.0 ist noch nicht physisch abgenommen.
