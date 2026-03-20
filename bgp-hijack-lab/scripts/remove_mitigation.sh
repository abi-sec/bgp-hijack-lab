#!/bin/bash
set -euo pipefail

LAB="bgp-hijack"; R1="clab-${LAB}-r1"
BOLD="\033[1m"; YELLOW="\033[33m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${YELLOW}[MITIGATION] Removing filter from R1${RESET}"
echo -e "${BOLD}================================================${RESET}"

if ! docker inspect "$R1" >/dev/null 2>&1; then
    echo -e "${YELLOW}[FAILED]${RESET} Lab container not running (missing $R1)."
    exit 1
fi

docker exec -i "$R1" vtysh << 'EOF'
configure terminal
router bgp 100
 address-family ipv4 unicast
  no neighbor 10.14.0.2 route-map VALIDATE_R4_IN in
 exit-address-family
exit
no route-map VALIDATE_R4_IN
no ip prefix-list BLOCK_VICTIM
no ip prefix-list LEGIT_VICTIM
end
clear bgp 10.14.0.2 in
write memory
EOF

echo ""
echo -e "${YELLOW}[OK] Mitigation removed. R1 is now unprotected.${RESET}"
echo ""
echo -e "${YELLOW}Verifying clean state...${RESET}"

PL_OUT=$(docker exec "$R1" vtysh -c "show ip prefix-list" 2>/dev/null || true)
RM_OUT=$(docker exec "$R1" vtysh -c "show route-map" 2>/dev/null || true)
echo "$PL_OUT"
echo "$RM_OUT"

if echo "$PL_OUT" | grep -q "BLOCK_VICTIM" || echo "$RM_OUT" | grep -q "VALIDATE_R4_IN"; then
    echo -e "${YELLOW}[FAILED]${RESET} Mitigation objects still present (BLOCK_VICTIM/VALIDATE_R4_IN)."
    exit 1
fi

echo -e "${YELLOW}[SUCCESS]${RESET} Mitigation fully removed (no BLOCK_VICTIM/VALIDATE_R4_IN)."
