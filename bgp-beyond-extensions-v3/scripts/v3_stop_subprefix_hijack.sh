#!/bin/bash
# Stop subprefix hijack (withdraw 13.0.0.0/25) from attacker (AS400).
set -euo pipefail

find_node() {
  local suffix="$1"
  docker ps --format '{{.Names}}' | grep -E '^clab-.*-'"${suffix}"'$' | head -n1
}

R4="$(find_node r4)"
if [ -z "$R4" ]; then
  echo "[ERROR] Attacker container not found (no clab-*-r4 running)."
  exit 1
fi

echo "[INFO] R4=$R4"
echo "[INFO] Withdrawing 13.0.0.0/25 from AS400"

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/25" \
  -c "end" >/dev/null 2>&1 || true

docker exec "$R4" ip route del blackhole 13.0.0.0/25 2>/dev/null || true
