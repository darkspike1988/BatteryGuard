#!/usr/bin/env bash
set -euo pipefail

# scripts/uninstall-daemon.sh
# Beendet und deinstalliert den Root-LaunchDaemon 'batteryguardd'.
# Stellt vorher den normalen Lade- und Adapterzustand wieder her (--restore).
# Muss mit Administrator-/Root-Rechten (z. B. via 'sudo') ausgeführt werden.

TARGET_BINARY="/usr/local/libexec/batteryguardd"
TARGET_DIR="/Library/Application Support/BatteryGuard"
PLIST_PATH="/Library/LaunchDaemons/com.batteryguard.daemon.plist"
SERVICE_LABEL="com.batteryguard.daemon"
LOG_PATH="/var/log/batteryguard.log"

PURGE=false
for arg in "$@"; do
    case "$arg" in
        --purge)
            PURGE=true
            ;;
        -h|--help)
            echo "Verwendung: sudo $0 [--purge]"
            echo "  --purge    Entfernt zusätzlich das Konfigurationsverzeichnis und Logdateien"
            exit 0
            ;;
        *)
            echo "Unbekannter Parameter: $arg" >&2
            echo "Verwendung: sudo $0 [--purge]" >&2
            exit 1
            ;;
    esac
done

# 1. Root-Prüfung
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Fehler: Dieses Skript muss mit Root-Rechten ausgeführt werden (z. B. via 'sudo $0')." >&2
    exit 1
fi

echo "==> BatteryGuard Daemon-Deinstallation gestartet..."

# 2. Failsafe: Normalen Lade- und Adapterzustand wiederherstellen
if [[ -x "$TARGET_BINARY" ]]; then
    echo "--> Rufe $TARGET_BINARY --restore auf (Failsafe: Ladekontrolle zurücksetzen)..."
    "$TARGET_BINARY" --restore 2>/dev/null || echo "Hinweis: '$TARGET_BINARY --restore' meldete einen Fehler oder wird noch nicht unterstützt." >&2
else
    echo "--> Hinweis: $TARGET_BINARY existiert nicht oder ist nicht ausführbar. Überspringe --restore."
fi

# 3. LaunchDaemon beenden und entladen
echo "--> Beende und entlade LaunchDaemon $SERVICE_LABEL..."
launchctl bootout "system/${SERVICE_LABEL}" 2>/dev/null || launchctl bootout system "$PLIST_PATH" 2>/dev/null || true

# 4. LaunchDaemon-Plist entfernen
if [[ -f "$PLIST_PATH" ]]; then
    echo "--> Entferne $PLIST_PATH..."
    rm -f "$PLIST_PATH"
else
    echo "--> Hinweis: Plist $PLIST_PATH nicht vorhanden."
fi

# 5. Daemon-Binary entfernen
if [[ -f "$TARGET_BINARY" ]]; then
    echo "--> Entferne $TARGET_BINARY..."
    rm -f "$TARGET_BINARY"
else
    echo "--> Hinweis: Binary $TARGET_BINARY nicht vorhanden."
fi

# 6. Optionale Bereinigung (--purge)
if [[ "$PURGE" = true ]]; then
    echo "--> Bereinige Konfigurations- und Logdateien (--purge)..."
    rm -rf "$TARGET_DIR"
    rm -f "$LOG_PATH"
    echo "--> $TARGET_DIR und $LOG_PATH wurden gelöscht."
else
    if [[ -d "$TARGET_DIR" ]]; then
        echo "--> Hinweis: Konfigurationsdateien in '$TARGET_DIR' wurden beibehalten."
        echo "    Um diese ebenfalls zu löschen, führe '$0 --purge' aus."
    fi
fi

echo "==> Deinstallation erfolgreich abgeschlossen!"
