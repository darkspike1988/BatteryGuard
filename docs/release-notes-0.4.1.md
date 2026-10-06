# B-Guard 0.4.1

Ein Fehler beim Speichern eigener Profile konnte Änderungen eines anderen Fensters oder Programms überschreiben. B-Guard erkennt jetzt einen geänderten Dateistand und fordert zum Neuladen auf. Neue Profile, Bearbeiten, Löschen und ausdrücklich bestätigter Import verwenden eine gemeinsame Dateisperre und schreiben erst nach erfolgreicher Prüfung.

- „Profile neu laden“ direkt in der Profilverwaltung.
- Zwischenzeitlich beschädigte oder gelöschte Profildateien bleiben erhalten beziehungsweise werden nicht still neu angelegt.
- Lesefehler werden nicht als JSON-Beschädigung behandelt. Ein fehlgeschlagener Ladevorgang kann keinen erfolgreichen leeren Export erzeugen.
- Die Sicherung beim Import erfolgt während derselben Dateisperre.

Appupdate; Hintergrunddienst **0.4.0** bleibt erforderlich. Ein noch installierter Dienst 0.3.2 muss über den regulären macOS-Administratordialog aktualisiert werden. Die offenen Hardware-/Kurzbefehle-Abnahmen und Notarisierung werden durch dieses Fehlerpaket nicht abgeschlossen. Community-DMG ad-hoc signiert.

Die Dateisperre koordiniert B-Guard-Prozesse; fremde Programme müssen diese Sperre ebenfalls beachten, um ein gleichzeitiges Schreiben vollständig zu verhindern. Bereits abgeschlossene externe Änderungen werden vor dem Speichern erkannt. Übergrößige Profildateien bleiben sicher abgewiesen; vor einem Wiederherstellungsimport müssen sie manuell gesichert und aus dem Profilpfad verschoben werden.

Diese Veröffentlichung enthält außerdem die bereits zusammengeführte Diagnose-Erweiterung 0.4.0: Quellenqualität, Kapazitätsquote, freiwillige lokale Kapazitäts-Tageswerte, lesende CPU-/RAM-/Swap-/Systemthermik- und Volumewerte sowie `/api/v1/diagnostics`. Die [Diagnose-Dokumentation](https://github.com/darkspike1988/BatteryGuard/blob/main/docs/diagnostics-0.4.md) beschreibt Messgrenzen und offene Geräte-/Performance-Abnahmen.
