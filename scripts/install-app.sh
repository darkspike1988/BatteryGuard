#!/usr/bin/env bash
set -euo pipefail

# scripts/install-app.sh
# Installiert die gebaute B-Guard.app für den aktuellen Benutzer:
# 1. Beendet eventuell laufende Instanzen
# 2. Kopiert dist/B-Guard.app nach /Applications
# 3. Entfernt Quarantäne-Attribute (xattr)
# 4. Registriert die App bei LaunchServices (automatische Anzeige im Launchpad)
# 5. Erstellt einen Finder-Alias auf dem Schreibtisch (Desktop)
# 6. Startet die App

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SRC="$PROJECT_DIR/dist/B-Guard.app"
DEST_APP="/Applications/B-Guard.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Installation von B-Guard.app gestartet..."

# 1. Sicherstellen, dass die App gebaut wurde
if [[ ! -d "$APP_SRC" ]]; then
    echo "--> $APP_SRC nicht gefunden. Baue Release-App..."
    "$SCRIPT_DIR/build-app.sh"
fi

# 2. Laufende Instanz beenden falls aktiv
echo "--> Beende eventuell laufende B-Guard-Instanzen..."
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

# Remove the legacy bundle only if it is this application's previous installation.
LEGACY_APP="/Applications/BatteryGuard.app"
if [[ -d "$LEGACY_APP" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_APP/Contents/Info.plist" 2>/dev/null || true)" == "com.batteryguard.app" ]]; then
    rm -rf "$LEGACY_APP"
fi

# 7. App starten
echo "--> Starte B-Guard..."
open "$DEST_APP"

echo "==> B-Guard erfolgreich installiert und gestartet!"
echo "    Programm-Pfad: $DEST_APP"
echo "    Launchpad:     App ist nun im Launchpad und in /Applications verfügbar"

echo "    Hintergrund:   Den Root-Daemon installierst du über das Menü oder mit: sudo ./scripts/install-daemon.sh"
