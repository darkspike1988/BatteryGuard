#!/usr/bin/env bash
set -euo pipefail

# scripts/uninstall-app.sh
# Deinstalliert BatteryGuard.app für den aktuellen Benutzer:
# 1. Beendet die laufende App
# 2. Entfernt eventuelle Login-Items (Autostart)
# 3. Löscht /Applications/BatteryGuard.app
# 4. Löscht den Finder-Alias auf dem Schreibtisch
# 5. Deregistriert die App bei LaunchServices

DEST_APP="/Applications/BatteryGuard.app"
DESKTOP_DIR="$HOME/Desktop"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Deinstallation von BatteryGuard.app gestartet..."

# 1. App beenden
echo "--> Beende BatteryGuard..."
osascript -e 'tell application id "com.batteryguard.app" to quit' 2>/dev/null || true
pkill -x "BatteryGuard" 2>/dev/null || true
sleep 0.5

# 2. Autostart-Eintrag entfernen
echo "--> Entferne Login-Items (Autostart)..."
osascript -e 'tell application "System Events" to delete (every login item whose name is "BatteryGuard")' 2>/dev/null || true

# 3. LaunchServices deregistrieren
if [[ -x "$LSREGISTER" && -d "$DEST_APP" ]]; then
    echo "--> Entferne Registrierung aus LaunchServices..."
    "$LSREGISTER" -u "$DEST_APP" 2>/dev/null || true
fi

# 4. App aus /Applications löschen
if [[ -d "$DEST_APP" ]]; then
    echo "--> Lösche $DEST_APP..."
    if [[ ! -w "/Applications" ]]; then
        sudo rm -rf "$DEST_APP"
    else
        rm -rf "$DEST_APP"
    fi
else
    echo "--> Keine Installation unter $DEST_APP gefunden."
fi

# 5. Desktop-Alias löschen
echo "--> Entferne Desktop-Alias..."
rm -f "$DESKTOP_DIR/BatteryGuard" "$DESKTOP_DIR/BatteryGuard.app"

echo "==> BatteryGuard.app wurde erfolgreich deinstalliert!"
echo "Hinweis: Falls auch der Root-Daemon installiert war, kannst du ihn mit folgendem Befehl entfernen:"
echo "    sudo ./scripts/uninstall-daemon.sh --purge"
