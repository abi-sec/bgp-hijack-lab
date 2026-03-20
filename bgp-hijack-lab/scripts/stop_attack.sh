#!/bin/bash
# =============================================================
# stop_attack.sh — Withdraw all hijacked routes from AS400
# BGP will reconverge and traffic returns to legitimate AS300
# =============================================================

set -euo pipefail

LAB="bgp-hijack"
R4="clab-${LAB}-r4"
R1="clab-${LAB}-r1"

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${GREEN}[STOP] Withdrawing hijacked routes from AS400${RESET}"
echo -e "${BOLD}================================================${RESET}"

if ! docker inspect "$R4" >/dev/null 2>&1 || ! docker inspect "$R1" >/dev/null 2>&1; then
  echo -e "${YELLOW}[FAILED]${RESET} Lab containers not running (missing $R1 or $R4)."
  exit 1
fi

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "no network 13.0.0.0/25" \
  -c "end" \
  -c "write memory"

docker exec "$R4" ip route del 13.0.0.0/24 dev lo 2>/dev/null || true
docker exec "$R4" ip route del 13.0.0.0/25 dev lo 2>/dev/null || true
docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true
docker exec "$R4" ip route del blackhole 13.0.0.0/25 2>/dev/null || true

echo "Waiting 10 seconds for BGP convergence..."
sleep 10

echo ""
echo -e "${YELLOW}--- R1 BGP Table After Attack Stopped ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"

echo ""
echo -e "${GREEN}Expected: 13.0.0.0/24 back via AS200 AS300 (legitimate path)${RESET}"

LEGIT=false
if docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24" 2>/dev/null | grep -q "10.12.0.2"; then
  LEGIT=true
fi

SUBPREFIX_OK=true
if docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null | grep -q "10.14.0.2"; then
  SUBPREFIX_OK=false
fi

if [ "$LEGIT" = true ] && [ "$SUBPREFIX_OK" = true ]; then
  echo -e "${GREEN}[SUCCESS]${RESET} Attack(s) withdrawn and legitimate routing restored on R1."
  echo -e "${BOLD}================================================${RESET}"
  exit 0
else
  echo -e "${YELLOW}[FAILED]${RESET} Routing did not fully revert (check R1 routes)."
  echo -e "${BOLD}================================================${RESET}"
  exit 1
fi
