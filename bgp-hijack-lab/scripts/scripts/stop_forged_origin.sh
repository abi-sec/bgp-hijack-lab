#!/bin/bash
# =============================================================
# stop_forged_origin.sh — Clean up after forged-origin attack
# Removes the route-map and withdraws the forged announcement
# =============================================================

LAB="bgp-hijack"
R4="clab-${LAB}-r4"
R1="clab-${LAB}-r1"

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"

echo -e "${BOLD}${YELLOW}[CLEANUP] Removing forged-origin attack configuration${RESET}"

docker exec -i "$R4" vtysh << 'EOF'
configure terminal
router bgp 400
 no network 13.0.0.0/24
 no neighbor 10.14.0.1 route-map FORGE_AS300_ORIGIN out
exit
no route-map FORGE_AS300_ORIGIN
end
write memory
EOF

docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true

echo "Waiting 10s for BGP convergence..."
sleep 10

echo -e "\n${YELLOW}--- R1 BGP Table (restored) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"
echo -e "\n${GREEN}Lab restored to clean state.${RESET}"
