# B-Guard 0.3.7

Eigene Profile und wiederkehrende Zeitpläne ergänzen die bisherigen Ladeprofile. Für diese Version ist **Hintergrunddienst 0.3.7** erforderlich; nach dem App-Update den Dienst in den Einstellungen über den macOS-Administratordialog aktualisieren.

- Benannte Profile speichern, bearbeiten, löschen und als JSON exportieren. Import mit Vorschau und ausdrücklich bestätigtem Ersetzen; die vorherige Datei wird gesichert. Ungültige oder zu große Dateien werden abgelehnt.
- Zeitpläne einmalig, täglich, werktags, wöchentlich, zweiwöchentlich, monatlich und jährlich. Ausführung im Dienst bei geschlossener App, feste Zeitzone, Sommerzeitbehandlung, begrenztes Nachholen und Aufgabenverlauf. Manuelle Ladeaktionen haben Vorrang.
- Top Up bis zum bestätigten Abstecken oder spätestens nach 24 Stunden. Separate Ladesteuerung erforderlich; Basisprofil bleibt erhalten und Hitzeschutz aktiv.
- Halten, Einmalentladung und Kalibrierungsassistent mit Zustandsmodellen und Simulation vorbereitet. **Ohne physisch bestätigtes Backend bleiben diese neuen Aktionen gesperrt.** Kein automatischer Kalibrierungs- oder Entladezyklus.
- Weitere experimentelle App Intents: Ladeprofil/Aufträge lesen, Ladeaktionen ausführen und gespeicherte Profile wählen. Kein REST-Token erforderlich. Systemweite Erkennung und Ausführung bleiben unbestätigt.
- Menükarte für die nächste Aufgabe, kombinierte Prozent-/Temperatur- oder Prozent-/Akku-Watt-Anzeige und vollständiger Darstellungs-Reset.
- Optionales, ausdrücklich gestartetes Wachhalten bis zum Limit, höchstens zwei Stunden; nur bei geeigneter Ladesteuerung. Kein automatisches Wachhalten im Schreibtischmodus.
- Diagnoseexport mit festem Schema ohne Tokens, Seriennummern, Profilnamen, persönliche Pfade oder genaue Reisezeiten.
- REST-Abnahme mit acht langsamen Verbindungen, Ablehnung der neunten, absoluter Frist und Prüfung gegen verspätete Speicherung. macOS-CI für Tests, Release-Bundle, Metadaten, Signatur und DMG ergänzt.
- Fehlerkorrekturen: Fehlende Akkumessung wird intern von echten 0 % unterschieden. Veraltete unabhängige Einstellungen löschen keinen erneuerten Sonderauftrag. Hitzeschutz bleibt beim Ende eines Sonderauftrags und bei Sensorausfall erhalten.

Die Community-DMG ist ad-hoc signiert. Ein Developer-ID-Zertifikat für die praktische Notarisierung fehlt weiterhin. Tests und Builds ersetzen keine Hardware- oder Kurzbefehle-Systemabnahme.
