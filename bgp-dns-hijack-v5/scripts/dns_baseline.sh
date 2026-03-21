#!/bin/bash
echo "=== Phase 1: DNS Baseline (No Attack) ==="
echo ""
echo "[1] Direct query to DNS server (13.0.0.50) from client:"
echo "    dig @13.0.0.50 www.victim.lab"
docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +ttlid +timeout=5
echo ""

echo "[2] Query through caching resolver from client:"
echo "    dig @127.0.0.1 www.victim.lab"
docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +ttlid +timeout=5
echo ""

echo "[3] Traceroute from client to DNS server:"
docker exec clab-bgp-dns-hijack-client traceroute -n -w 2 -q 1 13.0.0.50 2>/dev/null
echo ""

echo "[4] Expected: www.victim.lab -> 13.0.0.100 (legitimate)"
echo "    Path: Client -> R6(AS600) -> R5(AS500) -> R2(AS200) -> R3(AS300) -> DNS"
echo ""
echo "=== Baseline Complete ==="
