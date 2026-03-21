#!/bin/bash
echo "=== Phase 4: Withdrawing Hijack ==="
echo ""
echo "[1] AS400 withdrawing 13.0.0.0/25..."

docker exec clab-bgp-dns-hijack-r4 vtysh -c "configure terminal" \
  -c "router bgp 400" \
  -c "address-family ipv4 unicast" \
  -c "no network 13.0.0.0/25" \
  -c "end" \
  -c "configure terminal" \
  -c "no ip route 13.0.0.0/25 10.40.0.2" \
  -c "end"

echo "[2] Waiting 10s for BGP withdrawal propagation..."
sleep 10

echo "[3] Confirm withdrawal — R6 should no longer have /25 route:"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null
echo ""
echo "=== Hijack Withdrawn ==="
