#!/usr/bin/env bash
set -euo pipefail

# scripts/install-app.sh
# Installiert die gebaute BatteryGuard.app für den aktuellen Benutzer:
# 1. Beendet eventuell laufende Instanzen
# 2. Kopiert dist/BatteryGuard.app nach /Applications
# 3. Entfernt Quarantäne-Attribute (xattr)
# 4. Registriert die App bei LaunchServices (automatische Anzeige im Launchpad)
# 5. Erstellt einen Finder-Alias auf dem Schreibtisch (Desktop)
# 6. Startet die App

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SRC="$PROJECT_DIR/dist/BatteryGuard.app"
DEST_APP="/Applications/BatteryGuard.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Installation von BatteryGuard.app gestartet..."

# 1. Sicherstellen, dass die App gebaut wurde
if [[ ! -d "$APP_SRC" ]]; then
    echo "--> $APP_SRC nicht gefunden. Baue Release-App..."
    "$SCRIPT_DIR/build-app.sh"
fi

# 2. Laufende Instanz beenden falls aktiv
echo "--> Beende eventuell laufende BatteryGuard-Instanzen..."
osascript -e 'tell application id "com.batteryguard.app" to quit' 2>/dev/null || true
pkill -x "BatteryGuard" 2>/dev/null || true
sleep 0.5

# 3. Nach /Applications kopieren
echo "--> Kopiere App nach $DEST_APP..."
if [[ ! -w "/Applications" ]]; then
    echo "Hinweis: Schreibrechte für /Applications erforderlich. Bitte Passwort eingeben:"
    sudo rm -rf "$DEST_APP"
    sudo cp -R "$APP_SRC" "$DEST_APP"
    sudo chown -R "$(id -un):admin" "$DEST_APP" 2>/dev/null || true
else
    rm -rf "$DEST_APP"
    cp -R "$APP_SRC" "$DEST_APP"
fi

# 4. Quarantäne-Attribute entfernen
echo "--> Entferne Quarantäne-Attribute..."
xattr -r -d com.apple.quarantine "$DEST_APP" 2>/dev/null || true

# 5. Bei LaunchServices registrieren (Launchpad / Finder Aktualisierung)
if [[ -x "$LSREGISTER" ]]; then
    echo "--> Registriere App bei LaunchServices..."
    "$LSREGISTER" -f "$DEST_APP"
fi

# 6. Finder-Alias auf dem Desktop anlegen (nur wenn noch nicht vorhanden)
echo "--> Prüfe Finder-Alias auf dem Schreibtisch..."
DESKTOP_DIR="$HOME/Desktop"
if [[ ! -e "$DESKTOP_DIR/BatteryGuard" && ! -e "$DESKTOP_DIR/BatteryGuard.app" ]]; then
    echo "--> Erstelle Desktop-Alias 'BatteryGuard'..."
    osascript -e 'tell application "Finder" to make new alias file to POSIX file "'"$DEST_APP"'" at desktop' >/dev/null 2>&1 || {
        echo "Hinweis: Erstellung des Desktop-Alias via Finder übersprungen oder fehlgeschlagen."
    }
else
    echo "--> Desktop-Alias existiert bereits."
fi

# 7. App starten
echo "--> Starte BatteryGuard..."
open "$DEST_APP"

echo "==> BatteryGuard erfolgreich installiert und gestartet!"
echo "    Programm-Pfad: $DEST_APP"
echo "    Launchpad:     App ist nun im Launchpad und in /Applications verfügbar"
echo "    Schreibtisch:  Alias liegt auf deinem Desktop ($DESKTOP_DIR)"
echo "    Hintergrund:   Den Root-Daemon installierst du über das Menü oder mit: sudo ./scripts/install-daemon.sh"
