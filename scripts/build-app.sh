#!/usr/bin/env bash
set -euo pipefail

# scripts/build-app.sh
# Baut B-Guard und batteryguardd (Release), erzeugt dist/B-Guard.app und signiert ad-hoc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Baue B-Guard und batteryguardd im Release-Modus..."
swift build --package-path "$PROJECT_DIR" -c release

BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/B-Guard.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Bereite App-Bundle vor: $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Binärdateien kopieren
echo "==> Kopiere Binärdateien..."
cp "$BUILD_DIR/BatteryGuard" "$MACOS_DIR/BatteryGuard"
chmod 755 "$MACOS_DIR/BatteryGuard"

cp "$BUILD_DIR/batteryguardd" "$RESOURCES_DIR/batteryguardd"
chmod 755 "$RESOURCES_DIR/batteryguardd"

# Hilfsskripte für Daemon-Installation und -Deinstallation kopieren
echo "==> Kopiere Hilfsskripte in App-Ressourcen..."
cp "$SCRIPT_DIR/install-daemon.sh" "$RESOURCES_DIR/install-daemon.sh"
chmod 755 "$RESOURCES_DIR/install-daemon.sh"

cp "$SCRIPT_DIR/uninstall-daemon.sh" "$RESOURCES_DIR/uninstall-daemon.sh"
chmod 755 "$RESOURCES_DIR/uninstall-daemon.sh"

# AppIcon.icns kopieren (falls vorhanden, ansonsten generieren)
if [[ ! -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    echo "==> Generiere App-Icon..."
    "$SCRIPT_DIR/make-icon.swift"
fi

if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    echo "==> Kopiere AppIcon.icns..."
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Weitere optionale Projektressourcen kopieren
if [[ -d "$PROJECT_DIR/Resources" ]]; then
    for item in "$PROJECT_DIR/Resources"/*; do
        if [[ -f "$item" && "$(basename "$item")" != "README.md" && "$(basename "$item")" != "AppIcon.icns" && "$(basename "$item")" != "AppIcon-1024.png" ]]; then
            cp "$item" "$RESOURCES_DIR/"
        fi
    done
fi

# Info.plist generieren
echo "==> Schreibe Info.plist..."
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>de</string>
    <key>CFBundleExecutable</key>
    <string>BatteryGuard</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.batteryguard.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>B-Guard</string>
    <key>CFBundleDisplayName</key>
    <string>B-Guard</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.7</string>
    <key>CFBundleVersion</key>
    <string>0.3.7</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 BatteryGuard contributors. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

"$SCRIPT_DIR/extract-app-intents.sh" "$RESOURCES_DIR"

# Sign nested executable first; optional Developer ID path for notarized releases.
SIGN_IDENTITY="${BGUARD_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$RESOURCES_DIR/batteryguardd"
    codesign --force --sign - "$APP_BUNDLE"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$RESOURCES_DIR/batteryguardd"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

# Optionales Distributionsarchiv erstellen
ZIP_FILE="$DIST_DIR/B-Guard.zip"
echo "==> Erstelle Distributionsarchiv $ZIP_FILE..."
rm -f "$ZIP_FILE"
(cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "B-Guard.app" "B-Guard.zip")

echo "==> Build erfolgreich abgeschlossen!"
echo "    App: $APP_BUNDLE"
echo "    Zip: $ZIP_FILE"
