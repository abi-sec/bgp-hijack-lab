#!/bin/bash
set -euo pipefail

LAB="bgp-hijack"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; CYAN="\033[36m"; GREEN="\033[32m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${CYAN}[MITIGATION] Applying ROV-style filter on R1${RESET}"
echo -e "${BOLD}================================================${RESET}"

if ! docker inspect "$R1" >/dev/null 2>&1; then
    echo -e "${CYAN}[FAILED]${RESET} Lab container not running (missing $R1)."
    echo -e "Deploy first: sudo containerlab deploy -t topology.yaml"
    exit 1
fi

docker exec -i "$R1" vtysh << 'EOF'
configure terminal
no ip prefix-list LEGIT_VICTIM
no ip prefix-list BLOCK_VICTIM
ip prefix-list BLOCK_VICTIM seq 5 deny 13.0.0.0/24
ip prefix-list BLOCK_VICTIM seq 6 deny 13.0.0.0/25
ip prefix-list BLOCK_VICTIM seq 10 permit 0.0.0.0/0 le 32
route-map VALIDATE_R4_IN permit 10
 match ip address prefix-list BLOCK_VICTIM
exit
route-map VALIDATE_R4_IN deny 20
exit
router bgp 100
 address-family ipv4 unicast
  neighbor 10.14.0.2 route-map VALIDATE_R4_IN in
 exit-address-family
exit
end
clear bgp 10.14.0.2 in
write memory
EOF

echo ""
echo -e "${GREEN}[OK] Mitigation applied and session reset${RESET}"
echo ""
echo -e "${CYAN}Verifying route-map is attached...${RESET}"
NEI_OUT=$(docker exec "$R1" vtysh -c "show bgp neighbors 10.14.0.2" 2>/dev/null || true)
echo "$NEI_OUT" | grep -i "route-map" || true

if echo "$NEI_OUT" | grep -qi "VALIDATE_R4_IN"; then
    echo -e "${GREEN}[SUCCESS]${RESET} Mitigation is attached (VALIDATE_R4_IN)."
else
    echo -e "${CYAN}[FAILED]${RESET} Mitigation did not attach (VALIDATE_R4_IN not found)."
    exit 1
fi
echo ""
echo -e "${CYAN}Verifying prefix-list...${RESET}"
docker exec "$R1" vtysh -c "show ip prefix-list"
echo ""
echo -e "${CYAN}Verifying route-map invocations...${RESET}"
docker exec "$R1" vtysh -c "show route-map"
