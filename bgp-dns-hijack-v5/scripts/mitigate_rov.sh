#!/bin/bash
LAB="bgp-dns-hijack"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
VALIDATOR="clab-${LAB}-rpki"
TARGET="${1:-r1}"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${CYAN}[MITIGATION] Applying ROV filter on R1 (AS100)${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo ""
echo "Blocking AS400 announcements for victim prefix space:"
echo "  13.0.0.0/24 — exact prefix hijack"
echo "  13.0.0.0/25 — sub-prefix hijack (DNS server range)"
echo ""

docker exec -i "$R1" vtysh << 'EOF'
configure terminal
no ip prefix-list BLOCK_HIJACK
ip prefix-list BLOCK_HIJACK seq 5 deny 13.0.0.0/24
ip prefix-list BLOCK_HIJACK seq 6 deny 13.0.0.0/25
ip prefix-list BLOCK_HIJACK seq 10 permit 0.0.0.0/0 le 32
route-map VALIDATE_R4_IN permit 10
 match ip address prefix-list BLOCK_HIJACK
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

sleep 5

echo ""
echo -e "${GREEN}[OK] ROV mitigation applied and BGP session reset${RESET}"
echo ""
echo -e "${CYAN}Verifying filter is active:${RESET}"
docker exec "$R1" vtysh -c "show route-map" | grep -A3 "VALIDATE_R4_IN"
echo ""
echo -e "${CYAN}Verifying prefix-list:${RESET}"
docker exec "$R1" vtysh -c "show ip prefix-list BLOCK_HIJACK"
echo ""
echo -e "${BOLD}================================================${RESET}"
echo -e "${GREEN}Mitigation active. Now try the hijack:${RESET}"
echo -e "  bash scripts/start_dns_hijack.sh"
echo -e "${GREEN}Expected: DNS should stay at 13.0.0.100${RESET}"
echo -e "${BOLD}================================================${RESET}"
