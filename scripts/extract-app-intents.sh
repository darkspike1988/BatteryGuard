#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
RESOURCES_DIR="${1:?App resources directory required}"
SWIFTC="$(xcrun --find swiftc)"
TOOLCHAIN_DIR="$(dirname "$(dirname "$(dirname "$SWIFTC")")")"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
XCODE_VERSION="$(xcodebuild -version | awk '/Build version/ { print $3 }')"
TARGET_TRIPLE="$(uname -m)-apple-macosx14.0"
BG_INTENTS_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bguard-intents.XXXXXX")"
trap 'rm -rf "$BG_INTENTS_TEMP"' EXIT
python3 - "$PROJECT_DIR" "$TOOLCHAIN_DIR" "$BG_INTENTS_TEMP" <<'PY'
import json, sys
from pathlib import Path
project, toolchain, temporary = map(Path, sys.argv[1:])
schema = json.loads((toolchain / 'usr/share/swift/SwiftConstantValues/AppIntents.json').read_text())
protocols = schema['constValueProtocols'] if isinstance(schema, dict) else schema
(temporary / 'protocols.json').write_text(json.dumps(protocols))
sources = sorted((project / 'Sources/BatteryGuard').glob('*.swift'))
(temporary / 'sources.txt').write_text(''.join(str(p)+'\n' for p in sources))
(temporary / 'sources.rsp').write_text(''.join(json.dumps(str(p), ensure_ascii=False)+'\n' for p in sources))
(temporary / 'constants.txt').write_text(str(temporary / 'BatteryGuard.swiftconstvalues')+'\n')
PY
# Dedicated compile keeps constant outputs separate from other SwiftPM targets.
"$SWIFTC" -c -whole-module-optimization -parse-as-library -swift-version 6 \
    -module-name BatteryGuard -target "$TARGET_TRIPLE" -sdk "$SDK_ROOT" \
    -I "$BUILD_DIR" -I "$BUILD_DIR/Modules" -emit-const-values \
    -Xfrontend -const-gather-protocols-list -Xfrontend "$BG_INTENTS_TEMP/protocols.json" \
    -emit-const-values-path "$BG_INTENTS_TEMP/BatteryGuard.swiftconstvalues" \
    -o "$BG_INTENTS_TEMP/BatteryGuard.o" @"$BG_INTENTS_TEMP/sources.rsp"
xcrun appintentsmetadataprocessor --output "$RESOURCES_DIR" \
    --toolchain-dir "$TOOLCHAIN_DIR" --module-name BatteryGuard --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_VERSION" --platform-family macOS --deployment-target 14.0 \
    --target-triple "$TARGET_TRIPLE" --source-file-list "$BG_INTENTS_TEMP/sources.txt" \
    --swift-const-vals-list "$BG_INTENTS_TEMP/constants.txt"
test -s "$RESOURCES_DIR/Metadata.appintents/extract.actionsdata"
python3 - "$RESOURCES_DIR/Metadata.appintents/extract.actionsdata" <<'PYMETA'
import json, sys
with open(sys.argv[1]) as metadata_file:
    metadata = json.load(metadata_file)
required = {'ReadBatteryStatusIntent', 'ReadPowerFlowIntent'}
assert required <= set(metadata.get('actions', {})), 'Missing battery App Intents metadata'
assert required <= {s['actionIdentifier'] for s in metadata.get('autoShortcuts', [])}, 'Missing App Shortcuts metadata'
PYMETA
