#!/bin/bash
# Start victim deaggregation defense (wrapper around victim_deaggregation.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Wrapper location: ${SCRIPT_DIR}"
echo "[INFO] Using: ${SCRIPT_DIR}/victim_deaggregation.sh"
grep -n "router bgp 300" "${SCRIPT_DIR}/victim_deaggregation.sh" 2>/dev/null | head -n 1 || true

bash "${SCRIPT_DIR}/victim_deaggregation.sh"

R1=$(docker ps --format '{{.Names}}' | grep -E '^clab-.*-r1$' | head -n1)
if [ -z "$R1" ]; then
	echo "[WARN] R1 container not found; cannot validate deaggregation effect."
	exit 0
fi

OUT=$(docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null || true)
echo "$OUT"

if echo "$OUT" | grep -q "10.12.0.2"; then
	echo "[SUCCESS] Deaggregation recovered traffic (/25 now routes via legitimate 10.12.0.2)."
	exit 0
fi

echo "[FAILED] Deaggregation did not recover routing on R1 (/25 not via 10.12.0.2)."
exit 1
