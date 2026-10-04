BatteryGuard 0.2.0 ergänzt Ladeprofile, zeitliche Schutzpausen, Reiseplanung, lokalen Verlauf mit CSV-Export und eine neu gestaltete native macOS-Oberfläche.

Die Menüleiste bietet ein Profil-Dropdown mit eigenen Ladegrenzen, Schutz starten/pausieren und Beenden. Das App-Icon ist minimalistisch in Grau und Weiß. Ein Speicherfehler verwirft ungespeicherte Einstellungen nicht mehr.

### Installation

1. `BatteryGuard-0.2.0-arm64.dmg` herunterladen und öffnen.
2. BatteryGuard auf „Programme“ ziehen.
3. Aus Programme öffnen und „BatteryGuard einrichten“ wählen. Für den Hintergrunddienst fragt macOS einmal nach einem Administratorpasswort.

Apple Silicon, macOS 14 oder neuer. Kein Terminal erforderlich.

Die Community-Version ist ad-hoc signiert, **nicht notarisiert**. Wenn macOS sie blockiert und du dieser Quelle vertraust, nach dem Öffnungsversuch unter Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen freigeben. [Apple-Anleitung](https://support.apple.com/102445).

Bei Updates die App beenden, in Programme ersetzen und neu öffnen. Ein älterer Hintergrunddienst lässt sich in den App-Einstellungen aktualisieren. Konfiguration und Verlauf bleiben erhalten. „Beenden“ schließt nur die App; „Schutz pausieren“ deaktiviert den Eingriff des Dienstes.

### Prüfung und Grenzen

26 automatisierte Tests erfolgreich, Release-Build und ad-hoc Signatur geprüft, echte SwiftUI-Ansichten isoliert gerendert und DMG geprüft. Die DMG enthält App, Programme-Link und Installationsanleitung; SHA-256-Prüfsumme liegt bei.

SMC nutzt undokumentierte Hardware-Schlüssel. Authentifizierte IPC sowie eine bessere Schlaf-/Aufwachbehandlung bleiben Verbesserungsfelder. Aktives Entladen kann Systemschlaf verhindern; vollständige Hardware-Zyklen sind nicht durch Logiktests abgedeckt. Apples natives Ladelimit kann höhere Ziele verhindern. Details stehen im README und Review.
