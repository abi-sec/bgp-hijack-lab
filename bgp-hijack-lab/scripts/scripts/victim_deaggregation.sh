#!/bin/bash
# =============================================================
# victim_deaggregation.sh — Victim-Side Reactive Defense
#
# BACKGROUND:
#   Prefix deaggregation is a self-operated mitigation technique
#   where the victim AS announces more specific sub-prefixes to
#   win back traffic hijacked via an exact prefix attack.
#
#   How it works:
#     Attacker announces: 13.0.0.0/24  (exact, AS400)
#     Victim responds:    13.0.0.0/25  (more specific, AS300)
#                         13.0.0.128/25 (covers full /24 space)
#
#   BGP's longest prefix match rule means /25 ALWAYS beats /24
#   regardless of AS path length — so legitimate traffic returns.
#
#   This is the primary reactive mitigation used by ARTEMIS
#   (Sermpezis et al. 2018) and recommended in Kowalski & Mazurczyk.
#
# LIMITATION:
#   - Does NOT work against subprefix hijacks (attacker already has /25)
#   - Permanently inflates the routing table
#   - Can itself be hijacked if attacker announces a /26
#   - BGP filters at Tier-1/Tier-2 often block prefixes longer than /24
#
# DEMO ORDER:
#   1. Run start_exact_hijack.sh to confirm hijack is active
#   2. Run this script — traffic should return to legitimate AS300
#   3. Run stop_deaggregation.sh to restore normal operations
# =============================================================

LAB="bgp-hijack"
R3="clab-${LAB}-r3"
R1="clab-${LAB}-r1"
R4="clab-${LAB}-r4"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"
YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Victim-Side Reactive Defense: Deaggregation    ║"
echo "║   AS300 responds to exact prefix hijack          ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: Confirm hijack is active ─────────────────────────
echo -e "${CYAN}[1/4] Checking if exact prefix hijack is active...${RESET}"
HIJACK_ACTIVE=$(docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24" 2>/dev/null | grep "10.14.0.2" | wc -l)

if [ "$HIJACK_ACTIVE" -eq 0 ]; then
  echo -e "${YELLOW}No active hijack detected. Launching exact prefix hijack first...${RESET}"
  docker exec "$R4" vtysh \
    -c "configure terminal" \
    -c "router bgp 400" \
    -c "network 13.0.0.0/24" \
    -c "end" 2>/dev/null
  docker exec "$R4" ip route add blackhole 13.0.0.0/24 2>/dev/null || true
  echo "Waiting 12s for hijack to establish..."
  sleep 12
fi

echo -e "\n${CYAN}--- R1 Routing Table BEFORE deaggregation ---${RESET}"
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24"
echo -e "${RED}Traffic to 13.0.0.0/24 is currently routed to attacker (10.14.0.2)${RESET}"

# Record time for convergence measurement
DEAGG_START=$(date +%s)

# ── Step 2: AS300 deploys deaggregation ──────────────────────
echo -e "\n${CYAN}[2/4] AS300 (victim) deploying prefix deaggregation...${RESET}"
echo "Announcing 13.0.0.0/25 and 13.0.0.128/25 to compete with attacker's /24"
echo ""

# Add kernel routes first so FRR can originate the exact /25 network statements
docker exec "$R3" ip route add blackhole 13.0.0.0/25 2>/dev/null || true
docker exec "$R3" ip route add blackhole 13.0.0.128/25 2>/dev/null || true

docker exec -i "$R3" vtysh << 'EOF'
configure terminal
!
! Announce both halves of our /24 as more specific /25 prefixes
! BGP longest prefix match means /25 ALWAYS beats /24
router bgp 300
 no bgp network import-check
 address-family ipv4 unicast
  network 13.0.0.0/25
  network 13.0.0.128/25
 exit-address-family
!
end
EOF

# ── Step 3: Wait and measure convergence ─────────────────────
echo -e "${CYAN}[3/4] Monitoring convergence (checking every 2 seconds)...${RESET}"

RECOVERED=false
for i in $(seq 1 30); do
  sleep 2
  ROUTE=$(docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null | grep "10.12.0.2" | wc -l)
  if [ "$ROUTE" -gt 0 ]; then
    DEAGG_END=$(date +%s)
    CONVERGENCE=$((DEAGG_END - DEAGG_START))
    echo -e "${GREEN}Traffic recovered in ${CONVERGENCE} seconds${RESET}"
    RECOVERED=true
    break
  fi
  echo -n "."
done
echo ""

# ── Step 4: Show results ──────────────────────────────────────
echo -e "${CYAN}[4/4] Results after deaggregation:${RESET}"

echo -e "\n${CYAN}--- R1 Full BGP Table ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"

echo -e "\n${CYAN}--- R1 Routing Table (key prefixes) ---${RESET}"
echo -e "${YELLOW}Original /24 (still shows attacker's route as backup):${RESET}"
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24" 2>/dev/null
echo -e "\n${YELLOW}Victim's /25 (should now route to AS300):${RESET}"
docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null
echo -e "\n${YELLOW}Victim's /25 upper half:${RESET}"
docker exec "$R1" vtysh -c "show ip route 13.0.0.128/25" 2>/dev/null

echo ""
echo -e "${BOLD}================================================${RESET}"

if [ "$RECOVERED" = true ]; then
  echo -e "${GREEN}DEFENSE SUCCESSFUL:${RESET}"
  echo -e "  Traffic to 13.0.0.0/25 now routes via 10.12.0.2 (AS300 legitimate)"
  echo -e "  Traffic to 13.0.0.128/25 now routes via 10.12.0.2 (AS300 legitimate)"
  echo -e "  Convergence time: ${CONVERGENCE} seconds"
else
  echo -e "${YELLOW}Defense took longer than 60s — check routing manually${RESET}"
fi

echo ""
echo -e "${BOLD}Limitations of deaggregation (for your report):${RESET}"
echo -e "  1. Does NOT work against subprefix hijacks (attacker already has /25)"
echo -e "  2. Permanently inflates the global routing table"
echo -e "  3. Tier-1/Tier-2 routers filter prefixes longer than /24"
echo -e "     (so this only works within controlled topologies)"
echo -e "  4. Attacker can respond with /26 to re-hijack"
echo -e "  5. Requires victim to detect the hijack first (no auto-detection here)"
echo ""
echo -e "${BOLD}Comparison with ROV:${RESET}"
echo -e "  ROV (proactive):         Prevents hijack before it happens"
echo -e "  Deaggregation (reactive): Recovers traffic after hijack detected"
echo -e "  Combined:                Best protection — ROV + fallback deaggregation"
echo -e "${BOLD}================================================${RESET}"
echo ""
echo -e "${YELLOW}Run stop_deaggregation.sh when done to restore normal routing${RESET}"
