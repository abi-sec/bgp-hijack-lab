#!/bin/bash
# Stop forged-origin hijack (wrapper around stop_forged_origin.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/stop_forged_origin.sh"

R1=$(docker ps --format '{{.Names}}' | grep -E '^clab-.*-r1$' | head -n1)
if [ -z "$R1" ]; then
	echo "[WARN] R1 container not found; cannot validate removal."
	exit 0
fi

sleep 10

OUT=$(docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null || true)
if echo "$OUT" | grep -q "400 300"; then
	echo "[FAILED] Forged-origin AS_PATH (400 300) still visible on R1."
	exit 1
fi

echo "[SUCCESS] Forged-origin configuration removed (no '400 300' path on R1)."
exit 0
