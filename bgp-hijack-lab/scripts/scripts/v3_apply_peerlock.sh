#!/bin/bash
# Apply Peerlock-style defense (wrapper around apply_peerlock.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/apply_peerlock.sh"

R1=$(docker ps --format '{{.Names}}' | grep -E '^clab-.*-r1$' | head -n1)
if [ -z "$R1" ]; then
	echo "[FAILED] R1 container not found; cannot validate Peerlock attachment."
	exit 1
fi

CFG=$(docker exec "$R1" vtysh -c "show running-config" 2>/dev/null || true)
if echo "$CFG" | grep -q "neighbor 10.14.0.2 route-map PEERLOCK_IN in"; then
	echo "[SUCCESS] Peerlock policy attached on R1 (neighbor 10.14.0.2 inbound)."
	exit 0
fi

echo "[FAILED] Peerlock policy did not attach as expected on R1."
exit 1
