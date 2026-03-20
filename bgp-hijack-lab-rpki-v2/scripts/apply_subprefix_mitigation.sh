#!/bin/bash
LAB="bgp-hijack-rpki"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
TARGET="${1:-r1}"

BOLD="\033[1m"; CYAN="\033[36m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"

apply_on_r1() {
    docker exec -i "$R1" vtysh << EOF
configure terminal
no route-map SUBPREFIX_IN
no ip prefix-list BLOCK_SUBPREFIX
ip prefix-list BLOCK_SUBPREFIX seq 10 permit 13.0.0.0/25
route-map SUBPREFIX_IN deny 10
 match ip address prefix-list BLOCK_SUBPREFIX
exit
route-map SUBPREFIX_IN permit 20
exit
router bgp 100
 address-family ipv4 unicast
    neighbor 10.14.0.2 route-map SUBPREFIX_IN in
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
no route-map SUBPREFIX_IN
no ip prefix-list BLOCK_SUBPREFIX
ip prefix-list BLOCK_SUBPREFIX seq 10 permit 13.0.0.0/25
route-map SUBPREFIX_IN deny 10
 match ip address prefix-list BLOCK_SUBPREFIX
exit
route-map SUBPREFIX_IN permit 20
exit
router bgp 200
 address-family ipv4 unicast
    neighbor 10.12.0.1 route-map SUBPREFIX_IN in
 exit-address-family
exit
end
clear bgp 10.12.0.1 in
write memory
EOF
}

echo -e "${BOLD}================================================${RESET}"
echo -e "${CYAN}[MITIGATION] Applying subprefix filter policy${RESET}"
echo -e "${CYAN}Blocking attacker subprefix 13.0.0.0/25 from AS400${RESET}"
echo -e "${BOLD}================================================${RESET}"

case "$TARGET" in
    r1)
        apply_on_r1
        echo -e "${GREEN}[OK] Subprefix mitigation applied on R1 only${RESET}"
        ;;
    all)
        apply_on_r1
        apply_on_r2
        echo -e "${GREEN}[OK] Subprefix mitigation applied on R1 and R2${RESET}"
        ;;
    *)
        echo -e "${YELLOW}[WARN] Unknown target '${TARGET}'. Use: r1 or all${RESET}"
        exit 1
        ;;
esac
