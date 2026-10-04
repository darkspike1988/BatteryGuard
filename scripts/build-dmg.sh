#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "${1:-}" != "--skip-build" ]]; then
    "$SCRIPT_DIR/build-app.sh"
fi
APP="$PROJECT_DIR/dist/BatteryGuard.app"
[[ -d "$APP" ]] || { echo "App-Bundle fehlt." >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/batteryguard-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/BatteryGuard.app"
ln -s /Applications "$STAGING/Programme"
cat > "$STAGING/Installation.txt" <<'TEXT'
BatteryGuard installieren

1. BatteryGuard.app auf „Programme“ ziehen.
2. BatteryGuard aus dem Programme-Ordner öffnen.
3. „BatteryGuard einrichten“ anklicken und den macOS-Administratordialog bestätigen.

Kein Terminal und kein separates Installationsskript erforderlich.
Updates: BatteryGuard beenden, die App in Programme ersetzen und wieder öffnen.
Den Hintergrunddienst bei Bedarf in den Einstellungen aktualisieren.

Diese Community-Version ist ad-hoc signiert, aber nicht notarisiert.
Wenn macOS die App blockiert: nach dem Öffnungsversuch in Systemeinstellungen >
Datenschutz & Sicherheit „Dennoch öffnen“ auswählen, sofern du dieser Quelle vertraust.
https://support.apple.com/102445

Voraussetzungen: Apple Silicon, macOS 14 oder neuer.
TEXT
OUTPUT="$PROJECT_DIR/dist/BatteryGuard-$VERSION-arm64.dmg"
hdiutil create -volname "BatteryGuard" -srcfolder "$STAGING" -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
(cd "$PROJECT_DIR/dist" && shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")
echo "DMG: $OUTPUT"
