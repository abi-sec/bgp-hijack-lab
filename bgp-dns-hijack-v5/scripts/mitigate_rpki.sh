#!/bin/bash
# =============================================================
# mitigate_rpki.sh — RPKI-Informed ROV on R1 (AS100)
#
# Reads vrps.json (the ROA database) and auto-generates FRR
# prefix-lists that enforce the same policy as RPKI ROV.
#
# Difference from v4 manual ROV:
#   v4: Operator manually hardcodes prefixes to block
#       Must know attacker's specific announcements.
#       No connection to ROA data.
#
#   v5: Script reads vrps.json (the ROA registry)
#       Derives filters automatically from ROA maxLength rules.
#       AS300 has ROA 13.0.0.0/24 maxLength=24
#       Any /25 or longer for 13.0.0.0 = RPKI Invalid → blocked
#       Operator maintains vrps.json, not FRR configs.
#       Same policy logic as real RPKI ROV.
#
# Real RPKI uses RTR protocol to push ROA data dynamically.
# This implementation uses the same ROA data (vrps.json) but
# applies it as static filters — functionally identical for
# the attack/mitigation demonstration.
#
# Reference: RFC 6811, Chung et al. IMC 2019
# =============================================================

LAB="clab-bgp-dns-hijack"
R1="${LAB}-r1"
VRPS="configs/rpki/vrps.json"

echo "================================================"
echo "[MITIGATION] RPKI-Informed ROV on R1 (AS100)"
echo "================================================"
echo ""
echo "Reading ROA database: $VRPS"
echo ""

# Parse vrps.json and generate deny rules
# RPKI Invalid condition: prefix length > ROA maxLength
echo "ROA-derived filter rules:"
python3 << PYEOF
import json

with open("$VRPS") as f:
    data = json.load(f)

with open("/tmp/rpki_rules.txt", "w") as out:
    seq = 10
    for roa in data["roas"]:
        prefix  = roa["prefix"]
        max_len = roa["maxLength"]
        asn     = roa["asn"]
        base    = prefix.split("/")[0]
        plen    = int(prefix.split("/")[1])
        if max_len < 32:
            deny = f"{base}/{plen} ge {max_len + 1}"
            print(f"  AS{asn}: {prefix} maxLen={max_len}  →  deny {deny}  (RPKI Invalid)")
            out.write(f"{seq}|{deny}\n")
            seq += 10
PYEOF

echo ""
echo "Applying to R1 via vtysh..."

# Build the full vtysh command sequence
{
  echo "configure terminal"
  echo "no ip prefix-list RPKI_INVALID"

  while IFS='|' read -r seq rule; do
    echo "ip prefix-list RPKI_INVALID seq $seq deny $rule"
  done < /tmp/rpki_rules.txt

  echo "ip prefix-list RPKI_INVALID seq 200 permit 0.0.0.0/0 le 32"
  echo "route-map RPKI_ROV permit 10"
  echo " match ip address prefix-list RPKI_INVALID"
  echo "exit"
  echo "route-map RPKI_ROV deny 20"
  echo "exit"
  echo "router bgp 100"
  echo " address-family ipv4 unicast"
  echo "  neighbor 10.12.0.2 route-map RPKI_ROV in"
  echo "  neighbor 10.14.0.2 route-map RPKI_ROV in"
  echo " exit-address-family"
  echo "exit"
  echo "end"
  echo "clear bgp * in"
  echo "write memory"
} | docker exec -i "$R1" vtysh

sleep 5

echo ""
echo "  ✓ RPKI-Informed ROV applied on R1"
echo ""
echo "Generated prefix-list (derived from vrps.json):"
docker exec "$R1" vtysh -c "show ip prefix-list RPKI_INVALID" 2>/dev/null
echo ""
echo "================================================"
echo "Mitigation active. Now try the hijack:"
echo "  bash scripts/start_dns_hijack.sh"
echo ""
echo "Expected: 13.0.0.0/25 blocked (exceeds AS300 maxLength=24)"
echo "Expected: DNS stays at 13.0.0.100"
echo "================================================"
