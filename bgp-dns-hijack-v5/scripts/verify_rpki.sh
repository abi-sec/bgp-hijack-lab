#!/bin/bash
# =============================================================
# verify_rpki.sh — Show RPKI validation state on R1
# =============================================================

LAB="clab-bgp-dns-hijack"
R1="${LAB}-r1"

echo "================================================"
echo "  RPKI Status Verification"
echo "================================================"
echo ""

echo "[1] RTR cache connection (GoRTR → R1):"
docker exec "$R1" vtysh -c "show rpki cache-connection" 2>/dev/null
echo ""

echo "[2] ROA count from GoRTR:"
docker exec "$R1" vtysh -c "show rpki cache-record" 2>/dev/null | head -10
echo ""

echo "[3] RPKI prefix table (what R1 knows is valid):"
docker exec "$R1" vtysh -c "show rpki prefix-table" 2>/dev/null
echo ""

echo "[4] Validation state of victim prefix 13.0.0.0/24:"
docker exec "$R1" vtysh \
  -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep -E "rpki|valid|invalid|notfound|best|AS path"
echo ""

echo "[5] Check if hijack prefix 13.0.0.0/25 exists and its RPKI state:"
HIJACK=$(docker exec "$R1" vtysh \
  -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null)
if echo "$HIJACK" | grep -q "Network not in table"; then
  echo "  ✓ 13.0.0.0/25 not in table (blocked or not announced)"
else
  echo "$HIJACK" | grep -E "rpki|valid|invalid|notfound|best|AS path"
fi
echo ""

echo "[6] GoRTR container status:"
docker exec "${LAB}-gortr" ps aux 2>/dev/null | grep stayrtr || echo "  StayRTR process not found"
echo ""
echo "================================================"
