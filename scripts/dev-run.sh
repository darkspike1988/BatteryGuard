#!/usr/bin/env bash
set -euo pipefail

# scripts/dev-run.sh
# Baut BatteryGuard im Debug-Modus und führt das Binary direkt aus.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Baue BatteryGuard (Debug)..."
swift build --package-path "$PROJECT_DIR" -c debug --product BatteryGuard

APP_BINARY="$PROJECT_DIR/.build/debug/BatteryGuard"

echo "==> Starte BatteryGuard..."
exec "$APP_BINARY" "$@"
