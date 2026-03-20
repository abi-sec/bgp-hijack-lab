#!/bin/bash
# Start victim deaggregation defense (wrapper around victim_deaggregation.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Wrapper location: ${SCRIPT_DIR}"
echo "[INFO] Using: ${SCRIPT_DIR}/victim_deaggregation.sh"
grep -n "router bgp 300" "${SCRIPT_DIR}/victim_deaggregation.sh" 2>/dev/null | head -n 1 || true

bash "${SCRIPT_DIR}/victim_deaggregation.sh"
