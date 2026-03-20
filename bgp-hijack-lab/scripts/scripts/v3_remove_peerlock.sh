#!/bin/bash
# Remove Peerlock-style defense (wrapper around remove_peerlock.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/remove_peerlock.sh"

R1=$(docker ps --format '{{.Names}}' | grep -E '^clab-.*-r1$' | head -n1)
if [ -z "$R1" ]; then
	echo "[WARN] R1 container not found; cannot validate Peerlock removal."
	exit 0
fi

CFG=$(docker exec "$R1" vtysh -c "show running-config" 2>/dev/null || true)
if echo "$CFG" | grep -q "neighbor 10.14.0.2 route-map PEERLOCK_IN in"; then
	echo "[FAILED] Peerlock policy still attached on R1."
	exit 1
fi

echo "[SUCCESS] Peerlock policy removed from R1."
exit 0
