#!/bin/bash
LAB="bgp-hijack-rpki"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
VALIDATOR="clab-${LAB}-rpki"
TARGET="${1:-all}"

BOLD="\033[1m"; YELLOW="\033[33m"; RESET="\033[0m"

VALIDATOR_IP=$(docker inspect -f "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}" "$VALIDATOR" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
if [ -n "$VALIDATOR_IP" ]; then
    NO_CACHE_CMD_R1="no rpki cache ${VALIDATOR_IP} 3323 preference 1"
    NO_CACHE_CMD_R2="no rpki cache ${VALIDATOR_IP} 3323 preference 1"
else
    NO_CACHE_CMD_R1=""
    NO_CACHE_CMD_R2=""
fi

remove_on_r1() {
    docker exec -i "$R1" vtysh << EOF
configure terminal
router bgp 100
 address-family ipv4 unicast
    no neighbor 10.14.0.2 route-map RPKI_IN in
 exit-address-family
exit
no route-map RPKI_IN
no ip prefix-list BLOCK_ATTACKER
rpki
 ${NO_CACHE_CMD_R1}
exit
end
clear bgp 10.14.0.2 in
write memory
EOF
}

remove_on_r2() {
    docker exec -i "$R2" vtysh << EOF
configure terminal
router bgp 200
 address-family ipv4 unicast
    no neighbor 10.12.0.1 route-map RPKI_IN in
 exit-address-family
exit
no route-map RPKI_IN
no ip prefix-list BLOCK_ATTACKER
rpki
 ${NO_CACHE_CMD_R2}
exit
end
clear bgp 10.12.0.1 in
write memory
EOF
}

echo -e "${BOLD}================================================${RESET}"
echo -e "${YELLOW}[MITIGATION] Removing validator-backed ROV policy${RESET}"
echo -e "${BOLD}================================================${RESET}"

case "$TARGET" in
    r1)
        remove_on_r1
        ;;
    all)
        remove_on_r1
        remove_on_r2
        ;;
    *)
        echo -e "${YELLOW}[WARN] Unknown target '${TARGET}'. Use: r1 or all${RESET}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}[OK] RPKI mitigation removed.${RESET}"
echo -e "${YELLOW}R1 state:${RESET}"
docker exec "$R1" vtysh -c "show route-map"
docker exec "$R1" vtysh -c "show rpki cache-connection"
