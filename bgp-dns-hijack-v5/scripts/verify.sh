#!/bin/bash
echo "=== BGP DNS Hijack Lab v5 — Verification ==="
echo ""

echo "[1] Checking BGP sessions on all routers..."
for r in r1 r2 r3 r4 r5 r6; do
  PEERS=$(docker exec clab-bgp-dns-hijack-$r vtysh -c "show bgp summary" 2>/dev/null | grep -c "Estab" || echo "0")
  echo "  $r: $PEERS established BGP sessions"
done

echo ""
echo "[2] Checking validator container and RTR listener..."
if docker ps --format '{{.Names}}' | grep -q '^clab-bgp-dns-hijack-rpki$'; then
  echo "  rpki container present ✓"
  docker exec clab-bgp-dns-hijack-rpki sh -c "ss -lnt 2>/dev/null | grep ':3323'" >/dev/null
  if [ $? -eq 0 ]; then
    echo "  rpki-rtr (TCP/3323) listening ✓"
  else
    echo "  rpki-rtr (TCP/3323) NOT listening ✗"
  fi
else
  echo "  rpki container not found ✗"
fi

echo ""
echo "[3] Checking 13.0.0.0/24 path from R1 (AS100)..."
docker exec clab-bgp-dns-hijack-r1 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo "[4] Checking 13.0.0.0/24 path from R6 (AS600)..."
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo "[5] Checking DNS server reachability from client..."
docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=3 2>/dev/null
RESULT=$?
if [ $RESULT -eq 0 ]; then
  echo "  DNS server reachable from client ✓"
else
  echo "  DNS server NOT reachable from client ✗"
  echo "  (Wait 30-60s for BGP convergence and retry)"
fi

echo ""
echo "[6] Checking DNS caching resolver on client..."
docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +timeout=3 2>/dev/null
if [ $? -eq 0 ]; then
  echo "  Local caching resolver working ✓"
else
  echo "  Local caching resolver NOT working ✗"
  echo "  Trying to start unbound..."
  docker exec clab-bgp-dns-hijack-client unbound -c /etc/unbound/unbound.conf 2>/dev/null
fi

echo ""
echo "[7] Checking R1 RPKI cache connection state (if configured)..."
docker exec clab-bgp-dns-hijack-r1 vtysh -c "show rpki cache-connection" 2>/dev/null || echo "  RPKI cache not configured yet"

echo ""
echo "=== Verification Complete ==="
