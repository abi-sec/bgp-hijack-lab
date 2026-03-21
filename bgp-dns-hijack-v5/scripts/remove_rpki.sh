#!/bin/bash
# Remove RPKI-Informed ROV from R1

LAB="clab-bgp-dns-hijack"
R1="${LAB}-r1"

echo "================================================"
echo "[MITIGATION] Removing RPKI-Informed ROV from R1"
echo "================================================"

docker exec -i "$R1" vtysh << 'EOF'
configure terminal
router bgp 100
 address-family ipv4 unicast
  no neighbor 10.12.0.2 route-map RPKI_ROV in
  no neighbor 10.14.0.2 route-map RPKI_ROV in
 exit-address-family
exit
no route-map RPKI_ROV
no ip prefix-list RPKI_INVALID
end
clear bgp * in
write memory
EOF

echo ""
echo "  ✓ RPKI-Informed ROV removed. R1 is now unprotected."
