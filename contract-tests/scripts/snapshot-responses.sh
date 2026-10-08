#!/usr/bin/env bash
# Snapshot tRPC API responses into contract-tests/Tests/ContractTests/Fixtures/
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)/Tests/ContractTests/Fixtures"
EMPTY='{"json":{}}'
EMPTY_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$EMPTY'))")

mkdir -p "$FIXTURES_DIR"

trpc_query() {
  local name="$1"
  local procedure="$2"
  local input="${3:-$EMPTY_ENC}"
  echo "  -> $name ($procedure)"
  local code
  code=$(curl --max-time 15 -sS -w '%{http_code}' \
    "${BASE_URL}/api/trpc/${procedure}?input=${input}" -o "${FIXTURES_DIR}/${name}.json")
  if [[ "$code" == 200 ]]; then
    return
  fi
  # Hardware-free CI may explicitly allow a device I/O error. Missing procedures,
  # transport failures, and errors from every other endpoint remain failures.
  if [[ "$procedure" == device.getStatus && "$code" == 500 && "${ALLOW_UNAVAILABLE_DEVICE:-0}" == 1 ]]; then
    echo "     Device unavailable in hardware-free CI (HTTP 500)"
    echo '{"result":{"data":{"json":null}}}' > "${FIXTURES_DIR}/${name}.json"
    return
  fi
  echo "ERROR: $procedure returned HTTP $code" >&2
  return 1
}

echo "Snapshotting tRPC API responses..."

# Healthcheck
trpc_query healthcheck healthcheck

# Health
trpc_query health-system health.system
trpc_query health-scheduler health.scheduler
trpc_query health-hardware health.hardware
trpc_query health-dacmonitor health.dacMonitor

# Device
trpc_query device-status device.getStatus

# Settings
trpc_query settings settings.getAll

# System
trpc_query internet-status system.internetStatus
trpc_query wifi-status system.wifiStatus

# Biometrics (need Date meta for date params)
SIDE_LEFT=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{\"json\":{\"side\":\"left\"}}'))")

# Calibration
trpc_query calibration-left calibration.getStatus "$SIDE_LEFT"

echo "Done. Fixtures saved to $FIXTURES_DIR"
