#!/bin/bash
# =============================================================
# stop_deaggregation.sh — Remove deaggregated prefixes from AS300
# Also stops any active exact prefix hijack from AS400
# =============================================================

LAB="bgp-hijack"
R3="clab-${LAB}-r3"
R4="clab-${LAB}-r4"
R1="clab-${LAB}-r1"

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"

echo -e "${BOLD}${YELLOW}[CLEANUP] Removing deaggregated prefixes and stopping attack${RESET}"

# Remove deaggregated sub-prefixes from AS300
docker exec -i "$R3" vtysh << 'EOF'
configure terminal
router bgp 300
 address-family ipv4 unicast
  no network 13.0.0.0/25
  no network 13.0.0.128/25
 exit-address-family
end
EOF

docker exec "$R3" ip route del blackhole 13.0.0.0/25 2>/dev/null || true
docker exec "$R3" ip route del blackhole 13.0.0.128/25 2>/dev/null || true

# Also stop any active attack
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "end" 2>/dev/null || true
docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true

echo "Waiting 10s for BGP convergence..."
sleep 10

echo -e "\n${YELLOW}--- R1 BGP Table (restored) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"
echo -e "\n${GREEN}Lab restored to clean state.${RESET}"
