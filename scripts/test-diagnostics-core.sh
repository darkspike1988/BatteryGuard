#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bguard-core.XXXXXX")"
trap 'rm -rf "$HARNESS_DIR"' EXIT
mkdir -p "$HARNESS_DIR/Sources/BatteryGuardShared" "$HARNESS_DIR/Tests/CoreTests"
for source in "$PROJECT_DIR"/Sources/BatteryGuardShared/*.swift; do
    case "$(basename "$source")" in ConfigFile.swift|ConfigIPC.swift|ConfigRecovery.swift) continue ;; esac
    cp "$source" "$HARNESS_DIR/Sources/BatteryGuardShared/"
done
for name in MeasurementTests DiagnosticAnalysisTests; do
    if [[ -f "$PROJECT_DIR/Tests/BatteryGuardTests/$name.swift" ]]; then
        cp "$PROJECT_DIR/Tests/BatteryGuardTests/$name.swift" "$HARNESS_DIR/Tests/CoreTests/"
    fi
done
cat > "$HARNESS_DIR/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DiagnosticsCore", targets: [
    .target(name: "BatteryGuardShared"),
    .testTarget(name: "CoreTests", dependencies: ["BatteryGuardShared"])
])
EOF
swift test --package-path "$HARNESS_DIR" --jobs 2
