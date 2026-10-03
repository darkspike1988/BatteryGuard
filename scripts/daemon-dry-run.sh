#!/usr/bin/env bash
set -euo pipefail

# scripts/daemon-dry-run.sh
# Baut batteryguardd im Debug-Modus (falls nötig) und führt einen Testlauf aus (--once --dry-run).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DAEMON_BINARY="$PROJECT_DIR/.build/debug/batteryguardd"

if [[ ! -f "$DAEMON_BINARY" ]]; then
    echo "==> Baue batteryguardd (Debug)..."
    swift build --package-path "$PROJECT_DIR" -c debug --product batteryguardd
fi

echo "==> Führe batteryguardd --once --dry-run aus..."
exec "$DAEMON_BINARY" --once --dry-run "$@"
