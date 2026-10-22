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
# Wird von build-app.sh bei Developer-ID-Builds gesetzt. Leer = Community-Build (ad-hoc).
EXPECTED_TEAM_ID=""

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

# Refuse unsafe paths before stopping the current service or changing ownership.
if [[ -L "$TARGET_DIR" ]] || [[ -e "$TARGET_DIR" && ! -d "$TARGET_DIR" ]]; then
    echo "Fehler: Konfigurationsverzeichnis ist kein reguläres Verzeichnis." >&2
    exit 1
fi
if [[ -L "$TARGET_DIR/config.json" ]] || [[ -e "$TARGET_DIR/config.json" && ! -f "$TARGET_DIR/config.json" ]]; then
    echo "Fehler: Konfiguration ist keine reguläre Datei." >&2
    exit 1
fi

# Ein Root-Dienst darf nur aus Verzeichnissen starten, die ausschließlich root ändern kann.
# Sonst könnte ein normaler Benutzer die Binary umbenennen oder ersetzen.
require_root_only_dir() {
    local dir="$1"
    if [[ -L "$dir" ]] || [[ -e "$dir" && ! -d "$dir" ]]; then
        echo "Fehler: $dir ist kein reguläres Verzeichnis." >&2
        exit 1
    fi
    if [[ ! -d "$dir" ]]; then
        mkdir -m 0755 "$dir"
        chown root:wheel "$dir"
    fi
    local owner mode
    owner="$(stat -f '%u' "$dir")"
    mode="$(stat -f '%Lp' "$dir")"
    if [[ "$owner" != "0" ]] || (( (8#$mode & 8#022) != 0 )); then
        echo "Fehler: $dir gehört nicht root oder ist für andere beschreibbar (Besitzer $owner, Rechte $mode)." >&2
        echo "Bitte prüfen, z. B. mit: ls -ld '$dir'" >&2
        exit 1
    fi
}
require_root_only_dir "/usr/local"
require_root_only_dir "$(dirname "$TARGET_BINARY")"

# Quelle zuerst in ein root-eigenes Verzeichnis kopieren und dort prüfen:
# Die geprüfte Kopie kann danach kein Benutzerprozess mehr austauschen.
STAGE_DIR="$(mktemp -d /private/var/tmp/bguard-install.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED_BINARY="$STAGE_DIR/batteryguardd"
cp "$DAEMON_SRC" "$STAGED_BINARY"
chown root:wheel "$STAGED_BINARY"
chmod 0755 "$STAGED_BINARY"
xattr -c "$STAGED_BINARY" 2>/dev/null || true

echo "--> Prüfe Code-Signatur der Binary..."
if ! codesign --verify --strict "$STAGED_BINARY"; then
    echo "Fehler: Die Signatur von batteryguardd ist ungültig oder beschädigt." >&2
    exit 1
fi
if [[ -n "$EXPECTED_TEAM_ID" ]]; then
    REQUIREMENT="=anchor apple generic and certificate leaf[subject.OU] = \"$EXPECTED_TEAM_ID\""
    if ! codesign --verify --strict -R="$REQUIREMENT" "$STAGED_BINARY"; then
        echo "Fehler: batteryguardd ist nicht mit der erwarteten Developer-ID ($EXPECTED_TEAM_ID) signiert." >&2
        exit 1
    fi
fi

# Vor dem Ersetzen stoppen: Der alte Dienst darf nicht mit der neuen Binary neu starten.
launchctl bootout "system/${SERVICE_LABEL}" 2>/dev/null || launchctl bootout system "$PLIST_PATH" 2>/dev/null || true

# 3. Binary atomar installieren: neue Datei im Zielverzeichnis, dann rename.
# mv ersetzt einen vorhandenen Symlink, statt ihm zu folgen.
echo "--> Installiere Binary nach $TARGET_BINARY..."
if [[ -d "$TARGET_BINARY" && ! -L "$TARGET_BINARY" ]]; then
    echo "Fehler: $TARGET_BINARY ist ein Verzeichnis." >&2
    exit 1
fi
TARGET_STAGE="$(dirname "$TARGET_BINARY")/.batteryguardd.$$"
install -o root -g wheel -m 0755 "$STAGED_BINARY" "$TARGET_STAGE"
mv -f "$TARGET_STAGE" "$TARGET_BINARY"

# 4. Anwendungsunterstützungsverzeichnis anlegen (0755)
echo "--> Erstelle Verzeichnis $TARGET_DIR (0755)..."
mkdir -p "$TARGET_DIR"
chown root:wheel "$TARGET_DIR"
chmod 0755 "$TARGET_DIR"

# Root owns settings; authenticated IPC applies user changes.
CONFIG_FILE="$TARGET_DIR/config.json"
if [[ -L "$CONFIG_FILE" ]] || [[ -e "$CONFIG_FILE" && ! -f "$CONFIG_FILE" ]]; then
    echo "Fehler: Konfiguration ist keine reguläre Datei." >&2
    exit 1
fi
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
# A fresh inode also revokes writable descriptors held from the legacy 0666 file.
# The old daemon has stopped; the new service has not started yet.
CONFIG_STAGE=$(mktemp "$TARGET_DIR/.config-migration.XXXXXX")
trap 'rm -f "$CONFIG_STAGE"; rm -rf "$STAGE_DIR"' EXIT
cat "$CONFIG_FILE" > "$CONFIG_STAGE"
chown root:wheel "$CONFIG_STAGE"
chmod 0644 "$CONFIG_STAGE"
mv -f "$CONFIG_STAGE" "$CONFIG_FILE"
trap 'rm -rf "$STAGE_DIR"' EXIT

# 5. LaunchDaemon-Plist schreiben
echo "--> Schreibe LaunchDaemon-Konfiguration nach $PLIST_PATH..."
if [[ -L "$PLIST_PATH" ]]; then rm -f "$PLIST_PATH"; fi
PLIST_STAGE="$STAGE_DIR/daemon.plist"
cat << EOF > "$PLIST_STAGE"
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

plutil -lint "$PLIST_STAGE" >/dev/null
install -o root -g wheel -m 0644 "$PLIST_STAGE" "$PLIST_PATH.$$"
mv -f "$PLIST_PATH.$$" "$PLIST_PATH"

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
