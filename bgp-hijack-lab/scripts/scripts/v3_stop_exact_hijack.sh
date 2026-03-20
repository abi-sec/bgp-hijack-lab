#!/bin/bash
# Stop exact-prefix hijack (withdraw 13.0.0.0/24) from attacker (AS400).
set -euo pipefail

find_node() {
  local suffix="$1"
  docker ps --format '{{.Names}}' | grep -E '^clab-.*-'"${suffix}"'$' | head -n1
}

R4="$(find_node r4)"
R1="$(find_node r1)"
if [ -z "$R4" ]; then
  echo "[ERROR] Attacker container not found (no clab-*-r4 running)."
  exit 1
fi

echo "[INFO] R4=$R4"
echo "[INFO] Withdrawing 13.0.0.0/24 from AS400"

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "end" >/dev/null 2>&1 || true

docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true

sleep 10

if [ -z "$R1" ]; then
  echo "[WARN] R1 container not found; cannot validate full recovery."
  exit 0
fi

echo "[INFO] R1 forwarding decision:" 
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24" || true

if docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24" 2>/dev/null | grep -q "10.12.0.2"; then
  echo "[SUCCESS] Exact-prefix hijack withdrawn (R1 next-hop is legitimate 10.12.0.2)."
  exit 0
fi

echo "[FAILED] Exact-prefix hijack may still be affecting routing (R1 did not revert to 10.12.0.2)."
exit 1
