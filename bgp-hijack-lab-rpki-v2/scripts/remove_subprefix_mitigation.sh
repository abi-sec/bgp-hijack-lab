#!/bin/bash
LAB="bgp-hijack-rpki"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
TARGET="${1:-all}"

BOLD="\033[1m"; YELLOW="\033[33m"; RESET="\033[0m"

remove_on_r1() {
    docker exec -i "$R1" vtysh << EOF
configure terminal
router bgp 100
 address-family ipv4 unicast
    no neighbor 10.14.0.2 route-map SUBPREFIX_IN in
 exit-address-family
exit
no route-map SUBPREFIX_IN
no ip prefix-list BLOCK_SUBPREFIX
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
    no neighbor 10.12.0.1 route-map SUBPREFIX_IN in
 exit-address-family
exit
no route-map SUBPREFIX_IN
no ip prefix-list BLOCK_SUBPREFIX
end
clear bgp 10.12.0.1 in
write memory
EOF
}

echo -e "${BOLD}================================================${RESET}"
echo -e "${YELLOW}[MITIGATION] Removing subprefix filter policy${RESET}"
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

echo -e "${YELLOW}[OK] Subprefix mitigation removed.${RESET}"
