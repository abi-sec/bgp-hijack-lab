#!/bin/bash
# =============================================================
# remove_peerlock.sh — Remove Peerlock-style defense
# =============================================================

set -euo pipefail

LAB="bgp-hijack"
R1="clab-${LAB}-r1"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"
RED="\033[31m"; RESET="\033[0m"

log()     { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║          Removing Peerlock Defense (R1)          ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

log "Checking main lab is deployed..."
if ! docker ps --format '{{.Names}}' | grep -q "^${R1}$"; then
  error "Main lab not running. Nothing to remove."
fi

log "Removing inbound route-map from neighbor AS400 and cleaning objects..."

docker exec -i "$R1" vtysh <<'EOF'
configure terminal
router bgp 100
 no neighbor 10.14.0.2 route-map PEERLOCK_IN in
exit
!
no route-map PEERLOCK_IN
no bgp as-path access-list PEERLOCK_ORIGIN_300
no ip prefix-list VICTIM_PREFIXES
!
end
write memory
EOF

log "Refreshing BGP from AS400 (soft in)..."
docker exec "$R1" vtysh -c "clear bgp ipv4 unicast 10.14.0.2 soft in" >/dev/null 2>&1 || true
sleep 2

success "Peerlock defense removed"
