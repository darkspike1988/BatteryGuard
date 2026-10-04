BatteryGuard heißt jetzt **B-Guard**. App, Oberfläche und DMG tragen den neuen Namen; Dienstkennung und Speicherpfade bleiben unverändert, damit Einstellungen und Verlauf erhalten bleiben.

- App und Dienst koordinieren Konfigurationszugriffe mit einer Dateisperre. Änderungen werden feldweise zusammengeführt: ein durch den Dienst abgeschlossenes Vollladen wird beim Speichern anderer Einstellungen nicht mehr erneut aktiviert.
- Vor dem Systemschlaf wird der Normalbetrieb wiederhergestellt. Nach dem Aufwachen werden Cache, Konfiguration und Hardware neu geprüft. Kein Verhindern des Systemschlafs.
- „Akkuleistung“ erklärt Plus, Minus und 0 W. Der Wert misst den Stromfluss am Akku, nicht den gesamten Mac-Verbrauch. Fehlende Werte sind ausdrücklich gekennzeichnet, und einzelne Messpunkte nach Verlaufslücken bleiben sichtbar.
- Profilwahl verhält sich in Dashboard und Menüleiste konsistent und beendet laufendes Vollladen.
- Eine kleine responsive Website erklärt Funktionen und Grenzen und bietet einen direkten DMG-Download.

32 automatisierte Tests bestanden, darunter konkurrierende Dateizugriffe, Erhalt von Dienständerungen, negative/fehlende/null Leistungswerte und Ablehnung von Symlinks. Die physische Schlaf-/Aufwachfolge bleibt ein manueller Hardwaretest.

Installation: `B-Guard.dmg` öffnen, **B-Guard.app auf Programme ziehen**, aus Programme öffnen. Der Hintergrunddienst lässt sich mit einem macOS-Administratordialog einrichten oder aktualisieren. Bei Updates von BatteryGuard die alte App beenden; nach Installation von B-Guard kann die alte BatteryGuard.app entfernt werden. Daten bleiben unter den bisherigen Pfaden erhalten.

Apple Silicon, macOS 14+. Ad-hoc signiert, nicht notarisiert. [Apple-Anleitung zur Freigabe blockierter Apps](https://support.apple.com/102445). Die Konfiguration bleibt für lokale Benutzer beschreibbar; Dateisperren ersetzen keine authentifizierte IPC.
