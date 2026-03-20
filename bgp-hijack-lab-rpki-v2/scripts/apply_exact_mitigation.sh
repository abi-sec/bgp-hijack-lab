#!/bin/bash
LAB="bgp-hijack-rpki"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
VALIDATOR="clab-${LAB}-rpki"
TARGET="${1:-r1}"

BOLD="\033[1m"; CYAN="\033[36m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"

VALIDATOR_IP=$(docker inspect -f "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}" "$VALIDATOR" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
if [ -z "$VALIDATOR_IP" ]; then
    echo -e "${YELLOW}[WARN] Validator container ${VALIDATOR} not found or has no IP. Deploy topology first.${RESET}"
    exit 1
fi

apply_on_r1() {
    docker exec -i "$R1" vtysh << EOF
configure terminal
no route-map VALIDATE_R4_IN
no ip prefix-list BLOCK_VICTIM
no ip prefix-list LEGIT_VICTIM
no ip prefix-list BLOCK_ATTACKER
rpki
 no rpki cache ${VALIDATOR_IP} 3323 preference 1
 rpki cache ${VALIDATOR_IP} 3323 preference 1
exit
ip prefix-list BLOCK_ATTACKER seq 10 permit 13.0.0.0/24
route-map RPKI_IN deny 10
 match rpki invalid
exit
route-map RPKI_IN deny 15
 match ip address prefix-list BLOCK_ATTACKER
exit
route-map RPKI_IN permit 20
exit
router bgp 100
 address-family ipv4 unicast
    neighbor 10.14.0.2 route-map RPKI_IN in
 exit-address-family
exit
end
clear bgp 10.14.0.2 in
write memory
EOF
}

apply_on_r2() {
    docker exec -i "$R2" vtysh << EOF
configure terminal
no route-map VALIDATE_R4_IN
no ip prefix-list BLOCK_VICTIM
no ip prefix-list LEGIT_VICTIM
no ip prefix-list BLOCK_ATTACKER
rpki
 no rpki cache ${VALIDATOR_IP} 3323 preference 1
 rpki cache ${VALIDATOR_IP} 3323 preference 1
exit
ip prefix-list BLOCK_ATTACKER seq 10 permit 13.0.0.0/24
route-map RPKI_IN deny 10
 match rpki invalid
exit
route-map RPKI_IN deny 15
 match ip address prefix-list BLOCK_ATTACKER
exit
route-map RPKI_IN permit 20
exit
router bgp 200
 address-family ipv4 unicast
    neighbor 10.12.0.1 route-map RPKI_IN in
 exit-address-family
exit
end
clear bgp 10.12.0.1 in
write memory
EOF
}

echo -e "${BOLD}================================================${RESET}"
echo -e "${CYAN}[MITIGATION] Applying validator-backed ROV policy${RESET}"
echo -e "${CYAN}Validator cache: ${VALIDATOR_IP}:3323${RESET}"
echo -e "${BOLD}================================================${RESET}"

case "$TARGET" in
    r1)
        apply_on_r1
        echo -e "${GREEN}[OK] RPKI policy applied on R1 only${RESET}"
        ;;
    all)
        apply_on_r1
        apply_on_r2
        echo -e "${GREEN}[OK] RPKI policy applied on R1 and R2${RESET}"
        ;;
    *)
        echo -e "${YELLOW}[WARN] Unknown target '${TARGET}'. Use: r1 or all${RESET}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}R1 route-map and RPKI cache state:${RESET}"
docker exec "$R1" vtysh -c "show route-map"
docker exec "$R1" vtysh -c "show rpki cache-connection"
