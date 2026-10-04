#!/usr/bin/env bash
set -euo pipefail

# scripts/install-daemon.sh
# Installiert und startet den Root-LaunchDaemon 'batteryguardd'.
# Muss mit Administrator-/Root-Rechten (z. B. via 'sudo' oder Admin-Prompt) ausgeführt werden.

TARGET_BINARY="/usr/local/libexec/batteryguardd"
TARGET_DIR="/Library/Application Support/BatteryGuard"
PLIST_PATH="/Library/LaunchDaemons/com.batteryguard.daemon.plist"
SERVICE_LABEL="com.batteryguard.daemon"
LOG_PATH="/var/log/batteryguard.log"

# 1. Root-Prüfung
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Fehler: Dieses Skript muss mit Root-Rechten ausgeführt werden (z. B. via 'sudo $0')." >&2
    exit 1
fi

echo "==> B-Guard Daemon-Installation gestartet..."

# 2. Quell-Binary ermitteln
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)"
DAEMON_SRC=""

if [[ -n "${1:-}" ]]; then
    if [[ -f "$1" ]]; then
        DAEMON_SRC="$1"
    else
        echo "Fehler: Angegebene Binärdatei '$1' wurde nicht gefunden." >&2
        exit 1
    fi
else
    # Automatische Suche: Neben dem Skript -> dist/… -> .build/release/ -> .build/debug/
    CANDIDATES=(
        "$SCRIPT_DIR/batteryguardd"
        "$SCRIPT_DIR/../dist/B-Guard.app/Contents/Resources/batteryguardd"
        "$PROJECT_ROOT/dist/B-Guard.app/Contents/Resources/batteryguardd"
        "$SCRIPT_DIR/../.build/release/batteryguardd"
        "$PROJECT_ROOT/.build/release/batteryguardd"
        "$SCRIPT_DIR/../.build/debug/batteryguardd"
        "$PROJECT_ROOT/.build/debug/batteryguardd"
    )
    for candidate in "${CANDIDATES[@]}"; do
        if [[ -f "$candidate" ]]; then
            DAEMON_SRC="$candidate"
            break
        fi
    done
fi

if [[ -z "$DAEMON_SRC" ]]; then
    echo "Fehler: 'batteryguardd' Binärdatei konnte nicht gefunden werden." >&2
    echo "Bitte zuerst kompilieren (z. B. via 'scripts/build-app.sh') oder Pfad direkt übergeben:" >&2
    echo "  sudo $0 /pfad/zu/batteryguardd" >&2
    exit 1
fi

echo "--> Verwende Quell-Binary: $DAEMON_SRC"

# Vor dem Ersetzen stoppen: Der alte Dienst darf nicht mit der neuen Binary neu starten.
launchctl bootout "system/${SERVICE_LABEL}" 2>/dev/null || launchctl bootout system "$PLIST_PATH" 2>/dev/null || true

# 3. Zielverzeichnis anlegen und Binary kopieren
echo "--> Kopiere Binary nach $TARGET_BINARY..."
mkdir -p "$(dirname "$TARGET_BINARY")"
cp -f "$DAEMON_SRC" "$TARGET_BINARY"
chown root:wheel "$TARGET_BINARY"
chmod 0755 "$TARGET_BINARY"

# Quarantäne-Attribut entfernen (z. B. bei Download oder unbestätigter Signatur)
xattr -d com.apple.quarantine "$TARGET_BINARY" 2>/dev/null || true

# 4. Anwendungsunterstützungsverzeichnis anlegen (0755)
echo "--> Erstelle Verzeichnis $TARGET_DIR (0755)..."
mkdir -p "$TARGET_DIR"
chown root:wheel "$TARGET_DIR"
chmod 0755 "$TARGET_DIR"

# Initiale Konfiguration mit Standardwerten anlegen (0666), falls noch nicht vorhanden
CONFIG_FILE="$TARGET_DIR/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "--> Erstelle Standard-Konfiguration in $CONFIG_FILE..."
    cat << 'EOF' > "$CONFIG_FILE"
{
  "activeDischargeAboveUpper" : false,
  "chargeToFullOnce" : false,
  "enabled" : true,
  "heatProtectionCelsius" : 0,
  "lowerLimit" : 20,
  "upperLimit" : 80
}
EOF
fi
chmod 0666 "$CONFIG_FILE"

# 5. LaunchDaemon-Plist schreiben
echo "--> Schreibe LaunchDaemon-Konfiguration nach $PLIST_PATH..."
cat << EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TARGET_BINARY}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
</dict>
</plist>
EOF

chown root:wheel "$PLIST_PATH"
chmod 0644 "$PLIST_PATH"
xattr -d com.apple.quarantine "$PLIST_PATH" 2>/dev/null || true

# 6. Alten Dienst beenden (falls geladen) und neuen Dienst aktivieren
echo "--> Lade LaunchDaemon..."
launchctl enable "system/${SERVICE_LABEL}"

echo "--> Registriere Dienst mit launchctl bootstrap..."
# launchd benötigt nach bootout gelegentlich Zeit für die vollständige Freigabe.
BOOTSTRAPPED=false
for attempt in 1 2 3 4 5; do
    if launchctl bootstrap system "$PLIST_PATH"; then
        BOOTSTRAPPED=true
        break
    fi
    sleep 1
done
if [[ "$BOOTSTRAPPED" != true ]]; then
    echo "Fehler: Dienst konnte nicht registriert werden. Binary und Plist bleiben für einen erneuten Start erhalten." >&2
    exit 1
fi

echo "--> Starte Dienst mit launchctl kickstart..."
launchctl kickstart -k "system/${SERVICE_LABEL}"

echo "==> Installation erfolgreich abgeschlossen!"
echo "    Dienst:   $SERVICE_LABEL"
echo "    Binary:   $TARGET_BINARY"
echo "    Logdatei: $LOG_PATH"
