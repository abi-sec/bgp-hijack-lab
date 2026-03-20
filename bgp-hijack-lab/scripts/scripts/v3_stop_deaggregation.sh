#!/bin/bash
# Stop victim deaggregation defense (wrapper around stop_deaggregation.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Wrapper location: ${SCRIPT_DIR}"
echo "[INFO] Using: ${SCRIPT_DIR}/stop_deaggregation.sh"
grep -n "router bgp 300" "${SCRIPT_DIR}/stop_deaggregation.sh" 2>/dev/null | head -n 1 || true

bash "${SCRIPT_DIR}/stop_deaggregation.sh"

R1=$(docker ps --format '{{.Names}}' | grep -E '^clab-.*-r1$' | head -n1)
if [ -z "$R1" ]; then
	echo "[WARN] R1 container not found; cannot validate deaggregation removal."
	exit 0
fi

OUT=$(docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null || true)
echo "$OUT"

if echo "$OUT" | grep -q "10.12.0.2"; then
	echo "[FAILED] Deaggregation still active (/25 still via 10.12.0.2)."
	exit 1
fi

echo "[SUCCESS] Deaggregation removed (/25 no longer present via 10.12.0.2)."
exit 0
