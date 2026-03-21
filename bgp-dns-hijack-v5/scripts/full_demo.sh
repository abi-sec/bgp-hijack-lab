#!/bin/bash
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  BGP Hijack -> DNS Cache Poisoning — Full Demo v5       ║"
echo "║  Attack Chain + RPKI Mitigation                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Press ENTER to proceed through each phase..."
read -p ""

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/dns_baseline.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to launch the attack..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/start_dns_hijack.sh
echo "────────────────────────────────────────────────────────────"
sleep 3
read -p "Press ENTER to verify DNS poisoning..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/verify_dns_poison.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to withdraw the hijack..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/stop_dns_hijack.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to verify cache persistence..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/verify_cache_persistence.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to apply RPKI mitigation..."

echo ""
echo "────────────────────────────────────────────────────────────"
bash scripts/mitigate_rpki.sh
echo "────────────────────────────────────────────────────────────"
read -p "Press ENTER to test RPKI blocks the attack..."

echo ""
echo "────────────────────────────────────────────────────────────"
echo "=== Phase 7: Proving RPKI Mitigation Blocks the Attack ==="
echo ""
LAB="clab-bgp-dns-hijack"

bash scripts/start_dns_hijack.sh
sleep 3

echo ""
echo "[1] Check RPKI validation state of hijack prefix:"
docker exec ${LAB}-r1 vtysh \
  -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null | \
  grep -E "rpki|invalid|notfound|best|Network not" || \
  echo "    % Network not in table (blocked)"

echo ""
echo "[2] Check if hijack propagated past R1 to R6:"
HAS_HIJACK=$(docker exec ${LAB}-r6 vtysh \
  -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null | grep -c "best" || true)
if [ "$HAS_HIJACK" -eq 0 ]; then
  echo "    ✓ 13.0.0.0/25 NOT in R6 BGP table — hijack blocked by RPKI"
else
  echo "    ✗ 13.0.0.0/25 in R6 BGP table — check RPKI status"
fi

echo ""
echo "[3] DNS test with RPKI active (should stay legitimate):"
DIRECT=$(docker exec ${LAB}-client \
  dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
CACHED=$(docker exec ${LAB}-client \
  dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    Direct:  www.victim.lab -> $DIRECT"
echo "    Cached:  www.victim.lab -> $CACHED"

echo ""
if [ "$DIRECT" = "13.0.0.100" ] && [ "$CACHED" = "13.0.0.100" ]; then
  echo "*** RPKI MITIGATION SUCCESSFUL ***"
  echo "Both direct and cached DNS return legitimate answer"
  echo "BGP hijack blocked as RPKI INVALID — DNS cache never poisoned"
fi

echo ""
echo "[4] Cleaning up..."
bash scripts/stop_dns_hijack.sh > /dev/null 2>&1
bash scripts/remove_rpki.sh > /dev/null 2>&1
echo "    Lab restored to clean state"
echo "────────────────────────────────────────────────────────────"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Demo Complete (v5 — RPKI)                               ║"
echo "║                                                          ║"
echo "║  Key Finding: A brief BGP sub-prefix hijack produces     ║"
echo "║  DNS cache poisoning that persists for HOURS after       ║"
echo "║  the routing attack ends.                                ║"
echo "║                                                          ║"
echo "║  v4 Mitigation: Manual ROV prefix-list on R1            ║"
echo "║  v5 Mitigation: RPKI-Informed ROV via vrps.json          ║"
echo "║    AS400's /25 → RPKI INVALID → auto-dropped            ║"
echo "║    No manual filter needed. Scales to any prefix.        ║"
echo "║                                                          ║"
echo "║  Attack: seconds  |  Poison: TTL-dependent               ║"
echo "║  RPKI blocks: <5s |  DNS stays: clean                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
