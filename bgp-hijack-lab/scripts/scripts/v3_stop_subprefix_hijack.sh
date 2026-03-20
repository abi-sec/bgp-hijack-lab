#!/bin/bash
# Stop subprefix hijack (withdraw 13.0.0.0/25) from attacker (AS400).
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "[FAILED] docker CLI not found in PATH. Install Docker or run from an environment with Docker available."
  exit 1
fi

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
echo "[INFO] Withdrawing 13.0.0.0/25 from AS400"

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/25" \
  -c "end" >/dev/null 2>&1 || true

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "no route-map RM_HIJACK_SUBPREFIX25 permit 10" \
  -c "no ip prefix-list HIJACK_SUBPREFIX25" \
  -c "end" >/dev/null 2>&1 || true

docker exec "$R4" ip addr del 13.0.0.1/25 dev hijack0 2>/dev/null || true
docker exec "$R4" ip link del hijack0 2>/dev/null || true

docker exec "$R4" ip route del blackhole 13.0.0.0/25 2>/dev/null || true

sleep 10

if [ -z "$R1" ]; then
  echo "[WARN] R1 container not found; cannot validate removal."
  exit 0
fi

echo "[INFO] R1 forwarding decision for /25:" 
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" || true

if docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null | grep -q "10.14.0.2"; then
  echo "[FAILED] Subprefix hijack still present (R1 /25 next-hop is attacker)."
  exit 1
fi

echo "[SUCCESS] Subprefix hijack withdrawn (R1 /25 no longer via attacker)."
exit 0
