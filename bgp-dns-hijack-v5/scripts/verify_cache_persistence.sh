#!/bin/bash
# =============================================================
# verify_cache_persistence.sh — Prove DNS cache persists
# after BGP hijack is withdrawn
#
# The BGP hijack has already been withdrawn before this runs.
# Routing is clean. But the DNS cache still has the attacker's
# poisoned entry with the TTL set by the attacker.
#
# This script watches the cache every 10 seconds, showing:
#   - Direct DNS queries returning legitimate answers
#   - Cached DNS queries STILL returning attacker's answer
#   - TTL counting down — proving time-limited but real persistence
#
# NOTE ON TTL:
#   Demo config uses TTL=120s so you can observe expiry live.
#   Real-world attacker uses TTL=86400s (24 hours).
#   The mechanism is identical — only the duration differs.
#   Birge-Lee et al. (USENIX Sec 2018) documented attackers
#   using high TTLs to maximize the persistence window.
# =============================================================

LAB="clab-bgp-dns-hijack"
CLIENT="${LAB}-client"

BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"
YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

echo -e "${BOLD}================================================${RESET}"
echo -e "${BOLD}  DNS Cache Persistence Verification${RESET}"
echo -e "${BOLD}  BGP hijack withdrawn — routing is clean${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo ""

# Confirm BGP hijack is withdrawn
echo -e "${CYAN}Confirming BGP hijack is withdrawn...${RESET}"
HAS_HIJACK=$(docker exec clab-bgp-dns-hijack-r6 vtysh \
  -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null | grep -c "best" || true)

if [ "$HAS_HIJACK" -gt 0 ]; then
  echo -e "${YELLOW}  Warning: /25 route still in BGP table${RESET}"
  echo -e "${YELLOW}  Run stop_dns_hijack.sh first then re-run this script${RESET}"
  exit 1
else
  echo -e "${GREEN}  ✓ Confirmed: 13.0.0.0/25 not in BGP table (hijack withdrawn)${RESET}"
fi

echo ""
echo -e "${CYAN}Checking direct vs cached DNS every 10 seconds...${RESET}"
echo -e "${CYAN}Watch for: Direct=legitimate, Cached=poisoned (until TTL expires)${RESET}"
echo ""
echo -e "  ${BOLD}Time   | Direct @13.0.0.50 | Cached @127.0.0.1 | TTL remaining${RESET}"
echo -e "  ────────────────────────────────────────────────────────"

POISON_CONFIRMED=false
EXPIRY_CONFIRMED=false
START=$(date +%s)

for i in $(seq 1 18); do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))

  # Direct query to real DNS server
  DIRECT=$(docker exec "$CLIENT" \
    dig @13.0.0.50 www.victim.lab +short +timeout=3 2>/dev/null)

  # Cached query through unbound
  CACHED=$(docker exec "$CLIENT" \
    dig @127.0.0.1 www.victim.lab +short +timeout=3 2>/dev/null)

  # Get TTL remaining from cache
  TTL=$(docker exec "$CLIENT" \
    dig @127.0.0.1 www.victim.lab +noall +answer +timeout=3 2>/dev/null \
    | awk '{print $2}' | head -1)
  [ -z "$TTL" ] && TTL="expired"

  # Color code results
  if [ "$DIRECT" = "13.0.0.100" ]; then
    DIRECT_OUT="${GREEN}${DIRECT}${RESET}"
  else
    DIRECT_OUT="${RED}${DIRECT}${RESET}"
  fi

  if [ "$CACHED" = "14.0.0.66" ]; then
    CACHED_OUT="${RED}${CACHED} ✗${RESET}"
    POISON_CONFIRMED=true
  elif [ "$CACHED" = "13.0.0.100" ]; then
    CACHED_OUT="${GREEN}${CACHED} ✓${RESET}"
    if [ "$POISON_CONFIRMED" = true ]; then
      EXPIRY_CONFIRMED=true
    fi
  else
    CACHED_OUT="${YELLOW}${CACHED}${RESET}"
  fi

  printf "  t+%-4ss | %-18b | %-18b | %s\n" \
    "$ELAPSED" "$DIRECT_OUT" "$CACHED_OUT" "${TTL}s"

  # If cache has expired stop early
  if [ "$EXPIRY_CONFIRMED" = true ]; then
    echo ""
    echo -e "${GREEN}  Cache expired — poisoning window ended${RESET}"
    break
  fi

  sleep 10
done

echo ""
echo -e "${BOLD}================================================${RESET}"
echo -e "${BOLD}  Results Summary${RESET}"
echo -e "${BOLD}================================================${RESET}"
echo ""

if [ "$POISON_CONFIRMED" = true ]; then
  echo -e "${RED}  ✓ Cache poisoning confirmed AFTER BGP withdrawal${RESET}"
  echo -e "${RED}  The routing layer was clean but DNS was still poisoned${RESET}"
fi

if [ "$EXPIRY_CONFIRMED" = true ]; then
  echo -e "${GREEN}  ✓ Cache expiry observed within demo window${RESET}"
  echo -e "${GREEN}  After expiry, legitimate answer restored${RESET}"
fi

echo ""
echo -e "${BOLD}  Key Finding for Report:${RESET}"
echo -e "  Demo uses TTL=120s for live observation."
echo -e "  Real-world attackers use TTL=86400s (24 hours)."
echo -e "  The persistence mechanism is identical — only duration differs."
echo -e "  Birge-Lee et al. (USENIX Sec 2018) documented this exact"
echo -e "  technique used against major Certificate Authorities."
echo -e "${BOLD}================================================${RESET}"
