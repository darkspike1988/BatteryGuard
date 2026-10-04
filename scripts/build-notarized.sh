#!/usr/bin/env bash
set -euo pipefail

# Opt-in release workflow. Credentials stay in the macOS keychain.
: "${BGUARD_SIGN_IDENTITY:?Developer-ID-Application-Identität erforderlich}"
: "${BGUARD_NOTARY_PROFILE:?Vorbereitetes notarytool-Keychain-Profil erforderlich}"
[[ "$BGUARD_SIGN_IDENTITY" != "-" ]] || { echo "Notarisierung erfordert Developer ID." >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
"$SCRIPT_DIR/build-app.sh"
APP="$PROJECT_DIR/dist/B-Guard.app"
ZIP="$PROJECT_DIR/dist/B-Guard.zip"
xcrun notarytool submit "$ZIP" --keychain-profile "$BGUARD_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
BGUARD_NOTARIZED=1 "$SCRIPT_DIR/build-dmg.sh" --skip-build
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$PROJECT_DIR/dist/B-Guard-$VERSION-arm64.dmg"
codesign --force --timestamp --sign "$BGUARD_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$BGUARD_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
cp "$DMG" "$PROJECT_DIR/dist/B-Guard.dmg"
(cd "$PROJECT_DIR/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
(cd "$PROJECT_DIR/dist" && shasum -a 256 B-Guard.dmg > B-Guard.dmg.sha256)
echo "Signierte und notarisierte App/DMG wurden geprüft."
