#!/bin/bash
# Fetches the OpenAPI spec from a running Sleepypod and saves it locally.
# Usage:
#   ./scripts/sync-api-spec.sh              # uses default pod IP from UserDefaults
#   ./scripts/sync-api-spec.sh 192.168.1.88 # explicit IP
#   POD_IP=192.168.1.88 ./scripts/sync-api-spec.sh

set -euo pipefail

POD_IP="${1:-${POD_IP:-192.168.1.88}}"
SPEC_URL="http://${POD_IP}:3000/api/openapi.json"
SPEC_FILE="$(dirname "$0")/../Sleepypod/openapi.json"

echo "Fetching spec from ${SPEC_URL}..."
curl -sf --connect-timeout 5 "${SPEC_URL}" -o "${SPEC_FILE}"

# Quick validation
PATHS=$(python3 -c "import json; print(len(json.load(open('${SPEC_FILE}')).get('paths',{})))")
echo "Saved ${SPEC_FILE} (${PATHS} paths)"

# Show diff if in git
if git diff --stat -- "${SPEC_FILE}" 2>/dev/null | grep -q .; then
    echo ""
    echo "API spec changed:"
    git diff --stat -- "${SPEC_FILE}"
    echo ""
    echo "Review with: git diff Sleepypod/openapi.json"
else
    echo "No changes from committed spec."
fi
