#!/bin/bash
echo "=== Phase 3: Verifying DNS Poisoning During Attack ==="
echo ""

echo "[1] Flush client's DNS cache (restart unbound)..."
docker exec clab-bgp-dns-hijack-client pkill unbound 2>/dev/null
sleep 1
docker exec clab-bgp-dns-hijack-client unbound -c /etc/unbound/unbound.conf 2>/dev/null
sleep 1

echo ""
echo "[2] Direct query to 13.0.0.50 from client (now routed to attacker):"
ANSWER=$(docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    www.victim.lab -> $ANSWER"
if [ "$ANSWER" = "14.0.0.66" ]; then
  echo "    *** DNS POISONED — Response from ATTACKER (14.0.0.66) ***"
elif [ "$ANSWER" = "13.0.0.100" ]; then
  echo "    Response from legitimate server (13.0.0.100) — hijack not effective"
else
  echo "    Unexpected response: $ANSWER"
fi

echo ""
echo "[3] Query through caching resolver (populates cache with poison):"
CACHED=$(docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    www.victim.lab -> $CACHED"

echo ""
echo "[4] Full DNS response showing TTL (notice 86400s attacker TTL):"
docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +timeout=5 2>/dev/null | grep -A5 "ANSWER SECTION"

echo ""
echo "[5] Traceroute from client to 13.0.0.50 (should show attacker path):"
docker exec clab-bgp-dns-hijack-client traceroute -n -w 2 -q 1 13.0.0.50 2>/dev/null

echo ""
echo "[6] Compare: BGP table on R6 for 13.0.0.0/24 vs 13.0.0.0/25"
echo "    --- Legitimate /24 route ---"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep -E "AS path|best"
echo "    --- Hijacked /25 route ---"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null | grep -E "AS path|best"
echo ""
echo "=== DNS Poisoning Verified ==="
