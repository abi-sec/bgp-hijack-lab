#!/bin/bash
# Start GoRTR and configure routers for real RPKI (wrapper around setup_gortr.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
	echo "[FAILED] 'docker' command not found on this machine."
	echo "[HINT] Run this script inside the VM where Docker+containerlab are installed."
	exit 1
fi

find_node() {
	local suffix="$1"
	docker ps --format '{{.Names}}' | grep -E '^clab-.*-'"${suffix}"'$' | head -n1
}

bash "${SCRIPT_DIR}/setup_gortr.sh"

R1="$(find_node r1)"

if ! docker ps --format '{{.Names}}' | grep -q '^gortr$'; then
	echo "[FAILED] GoRTR container is not running."
	exit 1
fi

if [ -z "$R1" ]; then
	echo "[FAILED] R1 container not found; cannot validate router RPKI connection."
	exit 1
fi

OUT=$(docker exec "$R1" vtysh -c "show rpki cache-connection" 2>/dev/null || true)
echo "$OUT"

if echo "$OUT" | grep -Eqi "Unknown command|Command incomplete"; then
	echo "[FAILED] FRR in this lab does not support RPKI CLI commands (show rpki ...)."
	echo "[HINT] GoRTR is running, but routers cannot use it for ROV with this FRR build/image."
	exit 1
fi

if echo "$OUT" | grep -Eqi 'Established|Connected|Up'; then
	echo "[SUCCESS] GoRTR is running and R1 shows an active RPKI cache connection."
	exit 0
fi

echo "[FAILED] GoRTR started but R1 does not show an established cache connection yet."
exit 1
