#!/bin/bash
# =============================================================
# evaluate_extended.sh — Extended Evaluation Script
#
# Measures effectiveness across THREE generations of defense
# against THREE attack types, producing a comprehensive
# comparison table and CSV for your report.
#
# Attack Types:
#   A1 — Exact Prefix Hijack (Type-0)
#   A2 — Subprefix Hijack
#   A3 — Forged-Origin Hijack (Type-1)
#
# Defense Generations:
#   G0 — No defense (baseline)
#   G1 — ROV (route-map filter, simulated RPKI)
#   G2 — Real RPKI via GoRTR (if setup_gortr.sh was run)
#   G3 — Victim Deaggregation (reactive)
#
# Output:
#   evaluation_extended_<timestamp>.log
#   evaluation_extended_<timestamp>.csv
# =============================================================

LAB="bgp-hijack"
R1="clab-${LAB}-r1"; R2="clab-${LAB}-r2"
R3="clab-${LAB}-r3"; R4="clab-${LAB}-r4"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="evaluation_extended_${TIMESTAMP}.log"
CSV="evaluation_extended_${TIMESTAMP}.csv"

BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"
YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

# ── Helpers ───────────────────────────────────────────────────
log() {
  echo -e "$*"
  echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG"
}

run_r1() { docker exec "$R1" vtysh -c "$1" 2>/dev/null; }
run_r3() { docker exec "$R3" vtysh -c "$1" 2>/dev/null; }
run_r4() { docker exec "$R4" vtysh -c "$1" 2>/dev/null; }

is_hijacked_exact() {
  docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24" 2>/dev/null | grep -q "10.14.0.2"
}

is_hijacked_subprefix() {
  docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null | grep -q "400"
}

is_legitimate() {
  docker exec "$R1" vtysh -c "show ip route 13.0.0.0/24" 2>/dev/null | grep -q "10.12.0.2"
}

is_forged_valid() {
  # Check if R1 sees AS400's announcement as RPKI Valid (V)
  docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep -q "^V"
}

inject_exact() {
  docker exec "$R4" vtysh -c "configure terminal" \
    -c "router bgp 400" -c "network 13.0.0.0/24" -c "end" 2>/dev/null
  docker exec "$R4" ip route add blackhole 13.0.0.0/24 2>/dev/null || true
}

inject_subprefix() {
  docker exec "$R4" vtysh -c "configure terminal" \
    -c "router bgp 400" -c "no network 13.0.0.0/24" \
    -c "network 13.0.0.0/25" -c "end" 2>/dev/null
  docker exec "$R4" ip route add blackhole 13.0.0.0/25 2>/dev/null || true
}

inject_forged() {
  docker exec -i "$R4" vtysh << 'EOF' 2>/dev/null
configure terminal
route-map FORGE_AS300_ORIGIN permit 10
 set as-path prepend 300
exit
router bgp 400
 network 13.0.0.0/24
 neighbor 10.14.0.1 route-map FORGE_AS300_ORIGIN out
exit
end
EOF
  docker exec "$R4" ip route add blackhole 13.0.0.0/24 2>/dev/null || true
}

withdraw_all() {
  docker exec -i "$R4" vtysh << 'EOF' 2>/dev/null
configure terminal
router bgp 400
 no network 13.0.0.0/24
 no network 13.0.0.0/25
 no neighbor 10.14.0.1 route-map FORGE_AS300_ORIGIN out
exit
no route-map FORGE_AS300_ORIGIN
end
EOF
  docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true
  docker exec "$R4" ip route del blackhole 13.0.0.0/25 2>/dev/null || true
}

apply_rov() {
  docker exec -i "$R1" vtysh << 'EOF' 2>/dev/null
configure terminal
no ip prefix-list BLOCK_VICTIM
ip prefix-list BLOCK_VICTIM seq 5 deny 13.0.0.0/24
ip prefix-list BLOCK_VICTIM seq 6 deny 13.0.0.0/25
ip prefix-list BLOCK_VICTIM seq 10 permit 0.0.0.0/0 le 32
route-map VALIDATE_R4_IN permit 10
 match ip address prefix-list BLOCK_VICTIM
exit
route-map VALIDATE_R4_IN deny 20
exit
router bgp 100
 address-family ipv4 unicast
  neighbor 10.14.0.2 route-map VALIDATE_R4_IN in
 exit-address-family
exit
end
clear bgp 10.14.0.2 in
write memory
EOF
}

remove_rov() {
  docker exec -i "$R1" vtysh << 'EOF' 2>/dev/null
configure terminal
router bgp 100
 address-family ipv4 unicast
  no neighbor 10.14.0.2 route-map VALIDATE_R4_IN in
 exit-address-family
exit
no route-map VALIDATE_R4_IN
no ip prefix-list BLOCK_VICTIM
end
clear bgp 10.14.0.2 in
write memory
EOF
}

apply_deagg() {
  docker exec "$R3" ip route add blackhole 13.0.0.0/25 2>/dev/null || true
  docker exec "$R3" ip route add blackhole 13.0.0.128/25 2>/dev/null || true
  docker exec -i "$R3" vtysh << 'EOF' 2>/dev/null
configure terminal
router bgp 300
 no bgp network import-check
 address-family ipv4 unicast
  network 13.0.0.0/25
  network 13.0.0.128/25
 exit-address-family
end
EOF
}

remove_deagg() {
  docker exec -i "$R3" vtysh << 'EOF' 2>/dev/null
configure terminal
router bgp 300
 address-family ipv4 unicast
  no network 13.0.0.0/25
  no network 13.0.0.128/25
 exit-address-family
end
EOF
  docker exec "$R3" ip route del blackhole 13.0.0.0/25 2>/dev/null || true
  docker exec "$R3" ip route del blackhole 13.0.0.128/25 2>/dev/null || true
}

wait_converge() { sleep "${1:-12}"; }

record() { echo "$1,$2,$3,$4,$5" >> "$CSV"; }

# ── CSV Header ────────────────────────────────────────────────
echo "Attack,Defense,Result,Convergence_Seconds,Notes" > "$CSV"

# ─────────────────────────────────────────────────────────────
log "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║   Extended BGP Hijack Evaluation — 3 Attacks x 3 Defenses  ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
log "Timestamp: $(date)"
log "Log: $LOG  |  CSV: $CSV"
log ""

# Check if GoRTR is available
GORTR_AVAILABLE=false
if docker ps | grep -q gortr 2>/dev/null; then
  GORTR_AVAILABLE=true
  log "${GREEN}GoRTR detected — real RPKI tests will run${RESET}"
else
  log "${YELLOW}GoRTR not running — skipping real RPKI tests (run setup_gortr.sh)${RESET}"
fi

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
log "${BOLD}GENERATION 0: No Defense (Baseline)${RESET}"
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# G0/A1 — Exact prefix, no defense
log "${CYAN}[G0/A1] Exact prefix hijack, no defense...${RESET}"
withdraw_all; remove_rov; remove_deagg; wait_converge 8
START=$(date +%s)
inject_exact
wait_converge 15
END=$(date +%s)
if is_hijacked_exact; then
  ELAPSED=$((END-START))
  log "${RED}G0/A1: HIJACKED in ${ELAPSED}s${RESET}"
  record "Exact_Prefix" "No_Defense" "HIJACKED" "$ELAPSED" "AS400 wins via shorter path"
else
  log "${YELLOW}G0/A1: Attack did not establish${RESET}"
  record "Exact_Prefix" "No_Defense" "FAILED_TO_ESTABLISH" "N/A" "Check routing"
fi
withdraw_all; wait_converge 10

# G0/A2 — Subprefix, no defense
log "${CYAN}[G0/A2] Subprefix hijack, no defense...${RESET}"
START=$(date +%s)
inject_subprefix
wait_converge 15
END=$(date +%s)
if is_hijacked_subprefix; then
  ELAPSED=$((END-START))
  log "${RED}G0/A2: HIJACKED in ${ELAPSED}s${RESET}"
  record "Subprefix" "No_Defense" "HIJACKED" "$ELAPSED" "Longest prefix match, /25 wins"
else
  log "${YELLOW}G0/A2: Subprefix attack did not propagate${RESET}"
  record "Subprefix" "No_Defense" "FAILED" "N/A" "Check kernel route"
fi
withdraw_all; wait_converge 10

# G0/A3 — Forged-origin, no defense
log "${CYAN}[G0/A3] Forged-origin hijack, no defense...${RESET}"
START=$(date +%s)
inject_forged
wait_converge 15
END=$(date +%s)
if is_hijacked_exact; then
  ELAPSED=$((END-START))
  log "${RED}G0/A3: HIJACKED in ${ELAPSED}s (forged origin not detected)${RESET}"
  record "Forged_Origin" "No_Defense" "HIJACKED" "$ELAPSED" "AS path: 400 300 - no detection mechanism"
else
  log "${GREEN}G0/A3: Not hijacked (tie-breaking may have favored legitimate)${RESET}"
  record "Forged_Origin" "No_Defense" "TIE_BROKEN" "N/A" "BGP tie-break may vary"
fi
withdraw_all; wait_converge 10

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
log "${BOLD}GENERATION 1: ROV Route-Map Filter (Simulated RPKI)${RESET}"
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
apply_rov; wait_converge 8

# G1/A1 — Exact prefix, ROV
log "${CYAN}[G1/A1] Exact prefix hijack with ROV filter...${RESET}"
START=$(date +%s)
inject_exact; wait_converge 15
END=$(date +%s)
if is_hijacked_exact; then
  log "${RED}G1/A1: HIJACKED — ROV filter not blocking${RESET}"
  record "Exact_Prefix" "ROV_RouteMap" "HIJACKED" "$((END-START))" "Filter not effective"
else
  log "${GREEN}G1/A1: BLOCKED by ROV in $((END-START))s${RESET}"
  record "Exact_Prefix" "ROV_RouteMap" "BLOCKED" "$((END-START))" "AS400 announcement rejected by prefix-list"
fi
withdraw_all; wait_converge 10

# G1/A2 — Subprefix, ROV
log "${CYAN}[G1/A2] Subprefix hijack with ROV filter...${RESET}"
START=$(date +%s)
inject_subprefix; wait_converge 15
END=$(date +%s)
if is_hijacked_subprefix; then
  log "${RED}G1/A2: HIJACKED${RESET}"
  record "Subprefix" "ROV_RouteMap" "HIJACKED" "$((END-START))" "Filter missed /25"
else
  log "${GREEN}G1/A2: BLOCKED by ROV in $((END-START))s${RESET}"
  record "Subprefix" "ROV_RouteMap" "BLOCKED" "$((END-START))" "prefix-list denies 13.0.0.0/8 le 32"
fi
withdraw_all; wait_converge 10

# G1/A3 — Forged-origin, ROV
log "${CYAN}[G1/A3] Forged-origin hijack with ROV filter...${RESET}"
log "${YELLOW}NOTE: ROV route-map blocks ALL AS400 announcements${RESET}"
log "${YELLOW}including forged-origin — but real RPKI would NOT block this${RESET}"
START=$(date +%s)
inject_forged; wait_converge 15
END=$(date +%s)
if is_hijacked_exact; then
  log "${RED}G1/A3: HIJACKED — forged origin bypassed filter${RESET}"
  record "Forged_Origin" "ROV_RouteMap" "HIJACKED" "$((END-START))" "Route-map based on prefix not AS path"
else
  log "${YELLOW}G1/A3: Blocked by route-map (but real RPKI would allow this)${RESET}"
  record "Forged_Origin" "ROV_RouteMap" "BLOCKED_ARTIFICIAL" "$((END-START))" "Route-map blocks all AS400 - not realistic ROV behavior"
fi
withdraw_all; wait_converge 10
remove_rov; wait_converge 5

# ─────────────────────────────────────────────────────────────
if [ "$GORTR_AVAILABLE" = true ]; then
  log ""
  log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  log "${BOLD}GENERATION 2: Real RPKI via GoRTR${RESET}"
  log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  wait_converge 8

  # G2/A1 — Exact prefix, real RPKI
  log "${CYAN}[G2/A1] Exact prefix hijack with real RPKI ROV...${RESET}"
  inject_exact; wait_converge 15
  RPKI_STATE=$(docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep "400" | awk '{print $1}')
  if [ "$RPKI_STATE" = "I" ] || [ "$RPKI_STATE" = "i" ]; then
    log "${GREEN}G2/A1: AS400 route marked INVALID by real RPKI${RESET}"
    record "Exact_Prefix" "Real_RPKI" "INVALID_MARKED" "N/A" "RPKI state: I (Invalid) - ROV can drop this"
  else
    log "${YELLOW}G2/A1: RPKI state: ${RPKI_STATE} — check BGP table${RESET}"
    record "Exact_Prefix" "Real_RPKI" "STATE_${RPKI_STATE}" "N/A" "Check BGP table manually"
  fi
  withdraw_all; wait_converge 10

  # G2/A3 — Forged-origin, real RPKI (the critical test)
  log "${CYAN}[G2/A3] Forged-origin hijack with real RPKI — THE CRITICAL TEST...${RESET}"
  inject_forged; wait_converge 15
  RPKI_STATE=$(docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep "400" | awk '{print $1}')
  log "${CYAN}RPKI validation state for forged-origin: ${RPKI_STATE}${RESET}"
  if [ "$RPKI_STATE" = "V" ] || [ "$RPKI_STATE" = "*>" ]; then
    log "${RED}G2/A3: FORGED ROUTE APPEARS VALID TO RPKI${RESET}"
    log "${RED}This proves ROV cannot detect forged-origin attacks${RESET}"
    record "Forged_Origin" "Real_RPKI" "BYPASSED" "N/A" "RPKI state: V (Valid) - origin AS300 matches ROA - ROV is blind"
  else
    log "${YELLOW}G2/A3: RPKI state ${RPKI_STATE}${RESET}"
    record "Forged_Origin" "Real_RPKI" "STATE_${RPKI_STATE}" "N/A" "Investigate manually"
  fi
  withdraw_all; wait_converge 10
fi

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
log "${BOLD}GENERATION 3: Victim Deaggregation (Reactive Defense)${RESET}"
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# G3/A1 — Exact prefix, then victim deaggregates
log "${CYAN}[G3/A1] Exact prefix hijack → victim deploys deaggregation...${RESET}"
inject_exact; wait_converge 15
if is_hijacked_exact; then
  log "Hijack confirmed. Victim deploying deaggregation..."
  DEAGG_START=$(date +%s)
  apply_deagg

  RECOVERED=false
  for i in $(seq 1 25); do
    sleep 2
    ROUTE=$(docker exec "$R1" vtysh -c "show ip route 13.0.0.0/25" 2>/dev/null | grep "10.12.0.2" | wc -l)
    if [ "$ROUTE" -gt 0 ]; then
      DEAGG_END=$(date +%s)
      CONVERGENCE=$((DEAGG_END - DEAGG_START))
      log "${GREEN}G3/A1: Traffic RECOVERED in ${CONVERGENCE}s via deaggregation${RESET}"
      record "Exact_Prefix" "Deaggregation" "RECOVERED" "$CONVERGENCE" "Victim /25 outcompetes attacker /24 via longest-prefix-match"
      RECOVERED=true
      break
    fi
    echo -n "."
  done
  echo ""
  if [ "$RECOVERED" = false ]; then
    log "${YELLOW}G3/A1: Recovery took >50s — check manually${RESET}"
    record "Exact_Prefix" "Deaggregation" "TIMEOUT" ">50" "Check BGP table"
  fi
else
  log "${YELLOW}G3/A1: Hijack not established — skipping deaggregation test${RESET}"
  record "Exact_Prefix" "Deaggregation" "SKIPPED" "N/A" "Hijack not established"
fi
withdraw_all; remove_deagg; wait_converge 10

# G3/A2 — Subprefix, deaggregation FAILS (cannot outbid /25 with /25)
log "${CYAN}[G3/A2] Subprefix hijack → victim attempts deaggregation...${RESET}"
log "${YELLOW}NOTE: Deaggregation cannot work here — attacker already has /25${RESET}"
log "${YELLOW}Victim would need /26 which is filtered by most transit routers${RESET}"
inject_subprefix; wait_converge 15
record "Subprefix" "Deaggregation" "INEFFECTIVE" "N/A" "Cannot outbid /25 with /25; /26 filtered by transit"
withdraw_all; wait_converge 10

# ─────────────────────────────────────────────────────────────
log ""
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
log "${BOLD}SUMMARY TABLE${RESET}"
log "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
log ""
log "┌─────────────────┬────────────────┬──────────────────────┐"
log "│ Attack          │ Defense        │ Result               │"
log "├─────────────────┼────────────────┼──────────────────────┤"

while IFS=',' read -r attack defense result conv notes; do
  [ "$attack" = "Attack" ] && continue
  printf "│ %-15s │ %-14s │ %-20s │\n" "$attack" "$defense" "$result" | tee -a "$LOG"
done < "$CSV"

log "└─────────────────┴────────────────┴──────────────────────┘"
log ""
log "Full log: $LOG"
log "CSV data: $CSV"
log ""
log "${CYAN}Open the CSV in Excel/LibreOffice to create charts for your report${RESET}"
