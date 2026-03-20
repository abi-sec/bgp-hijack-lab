#!/bin/bash
# =============================================================
# apply_peerlock.sh — Peerlock-style defense for forged-origin
#
# Goal:
#   Block forged-origin hijacks that bypass RPKI-ROV by appending
#   the legitimate origin ASN (e.g., AS_PATH [400, 300]).
#
# How it works (lab-scoped, demo-friendly):
#   On R1 (AS100), deny routes for the victim prefix learned from
#   the attacker neighbor (AS400) when the *origin* appears to be
#   AS300 (regex _300$). This is similar in spirit to Peerlock/
#   neighbor-based AS-path filtering.
#
# Note:
#   This does not require BGPsec/ASPA and demonstrates a practical
#   operator policy that can mitigate forged-origin *in this lab*.
# =============================================================

set -euo pipefail

LAB="bgp-hijack"
R1="clab-${LAB}-r1"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"
YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

log()     { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║        Peerlock-Style Forged-Origin Defense      ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

log "Checking main lab is deployed..."
if ! docker ps --format '{{.Names}}' | grep -q "^${R1}$"; then
  error "Main lab not running. Deploy it first: sudo containerlab deploy -t topology.yaml"
fi
success "Main lab is running"

log "Applying Peerlock-style inbound filter on R1 (neighbor AS400)..."

docker exec -i "$R1" vtysh <<'EOF'
configure terminal
!
! Scope the policy to the victim prefixes (exact and subprefix)
ip prefix-list VICTIM_PREFIXES seq 5 permit 13.0.0.0/24
ip prefix-list VICTIM_PREFIXES seq 10 permit 13.0.0.0/25
!
! Match routes whose origin appears to be AS300 (rightmost ASN)
bgp as-path access-list PEERLOCK_ORIGIN_300 permit _300$
!
! Deny victim prefix routes from AS400 when origin==AS300
route-map PEERLOCK_IN deny 10
 match ip address prefix-list VICTIM_PREFIXES
 match as-path PEERLOCK_ORIGIN_300
exit
!
route-map PEERLOCK_IN permit 100
exit
!
router bgp 100
 neighbor 10.14.0.2 route-map PEERLOCK_IN in
exit
!
end
write memory
EOF

# Trigger a refresh so the new policy is applied immediately
log "Refreshing BGP from AS400 (soft in)..."
docker exec "$R1" vtysh -c "clear bgp ipv4 unicast 10.14.0.2 soft in" >/dev/null 2>&1 || true
sleep 3

success "Peerlock defense applied"

echo ""
echo -e "${BOLD}Verification:${RESET}"
echo -e "${CYAN}R1 best path for victim prefix (should be via AS200 when attack runs):${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" || true

echo ""
echo -e "${YELLOW}Tip:${RESET} Run forged-origin attack, then re-check the route:"
echo "  bash scripts/forged_origin_attack.sh"
echo "  docker exec ${R1} vtysh -c 'show bgp ipv4 unicast 13.0.0.0/24'"
