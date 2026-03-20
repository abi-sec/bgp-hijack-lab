#!/bin/bash
# =============================================================
# setup_gortr.sh — Deploy GoRTR as a local RPKI RTR server
#
# GoRTR is a lightweight RTR (RPKI to Router) server developed
# by Cloudflare. It reads a JSON file of VRPs (Validated ROA
# Payloads) and serves them to FRR routers via the RTR protocol.
#
# This replaces the simulated route-map filter with real
# cryptographic RPKI Route Origin Validation (ROV).
#
# INTEGRATION: Run this AFTER your main lab is deployed.
# Run: sudo containerlab deploy -t topology.yaml first.
#
# WHAT THIS DOES:
#   1. Creates a VRP file defining legitimate ROAs for all ASes
#   2. Pulls and runs GoRTR in Docker
#   3. Connects GoRTR to your Containerlab network
#   4. Configures FRR on R1 and R2 to use real RPKI ROV
#   5. Verifies the connection is working
# =============================================================

set -e

if ! command -v docker >/dev/null 2>&1; then
  echo "[FAILED] 'docker' command not found on this machine."
  echo "[HINT] Run this script inside the VM where Docker+containerlab are installed."
  exit 1
fi

LAB="bgp-hijack"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"
YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

log()     { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

vtysh_cfg() {
  local node="$1"; shift
  docker exec "$node" vtysh -c "configure terminal" "$@" -c "end" 2>&1 || true
}

get_bgp_neighbors() {
  local node="$1"
  docker exec "$node" vtysh -c "show running-config" 2>/dev/null \
    | sed -nE 's/^[[:space:]]*neighbor[[:space:]]+([0-9.]+)[[:space:]]+remote-as.*/\1/p' \
    | sort -u
}

ensure_no_unknown_cmd() {
  local out="$1"; local context="$2"
  if echo "$out" | grep -Eqi "Unknown command|Command incomplete"; then
    if echo "$out" | grep -Eqi "Unknown command: rpki"; then
      warn "FRR rejected an RPKI-related command. This usually means the RPKI/RTR feature isn't available in the running FRR instance."
      warn "In this lab, FRR typically needs the RPKI module loaded via bgpd_options:  bgpd_options=\"  -A 127.0.0.1 -M rpki\""
      warn "Compare with the v2 lab daemons files (bgp-hijack-lab-rpki-v2/configs/r1/daemons)."
      warn "If no RTR/RPKI daemon exists, you'll need an FRR image built with RPKI/RTR support."
    fi
    error "$context failed (FRR rejected a command):\n$out"
  fi
}

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Beyond Initial Project — Real RPKI via GoRTR   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: Check lab is running ──────────────────────────────
log "Checking main lab is deployed..."
DOCKER_PS=$(docker ps 2>&1) || error "Docker is not available/usable. Output was:\n${DOCKER_PS}"
if ! echo "$DOCKER_PS" | grep -q "${LAB}-r1"; then
  error "Main lab not running. Deploy it first: sudo containerlab deploy -t topology.yaml"
fi
success "Main lab is running"

# ── Step 2: Get the Containerlab network name ─────────────────
CLAB_NETWORK=$(docker inspect "${R1}" \
  --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' \
  2>/dev/null | grep -v "^bridge$" | head -1)

if [ -z "$CLAB_NETWORK" ]; then
  # Fallback: use the management network
  CLAB_NETWORK="clab"
fi
log "Containerlab network: ${CLAB_NETWORK}"

# ── Step 3: Create VRP (ROA) file ────────────────────────────
log "Creating VRP file with legitimate ROAs..."

mkdir -p /home/bgp/gortr-data 2>/dev/null || mkdir -p ~/gortr-data

GORTR_DIR="${HOME}/gortr-data"

# ROA file defining who is authorized to announce each prefix
# maxLength: 24 means ONLY /24 is authorized — /25 subprefix from attacker = INVALID
# Change maxLength to 25 to demonstrate the MaxLength vulnerability (see maxlength_demo.sh)
cat > "${GORTR_DIR}/vrps.json" << 'VRPFILE'
{
  "metadata": {
    "counts": 4,
    "generated": 1700000000,
    "valid": 9999999999
  },
  "roas": [
    {
      "prefix": "11.0.0.0/24",
      "maxLength": 24,
      "asn": "AS100",
      "ta": "local-ta"
    },
    {
      "prefix": "12.0.0.0/24",
      "maxLength": 24,
      "asn": "AS200",
      "ta": "local-ta"
    },
    {
      "prefix": "13.0.0.0/24",
      "maxLength": 24,
      "asn": "AS300",
      "ta": "local-ta"
    },
    {
      "prefix": "14.0.0.0/24",
      "maxLength": 24,
      "asn": "AS400",
      "ta": "local-ta"
    }
  ]
}
VRPFILE

success "VRP file created at ${GORTR_DIR}/vrps.json"
log "ROAs configured:"
log "  13.0.0.0/24 → AS300 only, maxLength /24 (subprefix hijack = INVALID)"
log "  Any announcement of 13.0.0.0/24 by AS400 → INVALID"

# ── Step 4: Pull GoRTR image ──────────────────────────────────
log "Pulling GoRTR Docker image..."
if ! docker image inspect cloudflare/gortr:latest &>/dev/null; then
  docker pull cloudflare/gortr:latest
  success "GoRTR image pulled"
else
  warn "GoRTR image already present"
fi

# ── Step 5: Stop any existing GoRTR ──────────────────────────
docker stop gortr 2>/dev/null && docker rm gortr 2>/dev/null || true

# ── Step 6: Run GoRTR connected to Containerlab network ───────
log "Starting GoRTR RTR server on port 3323..."
docker run -d \
  --name gortr \
  --network "${CLAB_NETWORK}" \
  -v "${GORTR_DIR}:/data" \
  cloudflare/gortr:latest \
  -bind 0.0.0.0:3323 \
  -verify=false \
  -cache /data/vrps.json \
  -refresh 30

sleep 3

# ── Step 7: Get GoRTR IP on the Containerlab network ─────────
GORTR_IP=$(docker inspect gortr \
  --format "{{(index .NetworkSettings.Networks \"${CLAB_NETWORK}\").IPAddress}}" \
  2>/dev/null)

if [ -z "$GORTR_IP" ]; then
  # Try bridge network
  GORTR_IP=$(docker inspect gortr \
    --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    2>/dev/null | head -1)
fi

log "GoRTR IP: ${GORTR_IP}"

# Save IP for other scripts to use
echo "${GORTR_IP}" > "${GORTR_DIR}/gortr_ip"

# ── Step 8: Configure R1 to use real RPKI ROV ─────────────────
log "Configuring R1 (AS100) to use real RPKI ROV..."

OUT=$(vtysh_cfg "$R1" \
  -c "rpki" \
  -c "no rpki cache ${GORTR_IP} 3323 preference 1" \
  -c "rpki cache ${GORTR_IP} 3323 preference 1" \
  -c "exit")
ensure_no_unknown_cmd "$OUT" "R1 RPKI cache configuration"

log "Installing inbound policy to DROP RPKI-invalid routes on R1..."
R1_NEIGHBORS="$(get_bgp_neighbors "$R1" | tr '\n' ' ')"
if [ -z "${R1_NEIGHBORS// }" ]; then
  warn "Could not detect BGP neighbors from running-config on R1; policy will not be applied automatically."
else
  # Build a single vtysh config transaction.
  VTY_ARGS=(
    -c "route-map RPKI_IN deny 10"
    -c "match rpki invalid"
    -c "exit"
    -c "route-map RPKI_IN permit 20"
    -c "exit"
    -c "router bgp 100"
    -c "address-family ipv4 unicast"
  )
  for n in $R1_NEIGHBORS; do
    VTY_ARGS+=( -c "neighbor $n route-map RPKI_IN in" )
  done
  VTY_ARGS+=( -c "exit-address-family" )

  OUT=$(vtysh_cfg "$R1" "${VTY_ARGS[@]}")
  ensure_no_unknown_cmd "$OUT" "R1 RPKI inbound policy configuration"

  for n in $R1_NEIGHBORS; do
    docker exec "$R1" vtysh -c "clear bgp $n in" >/dev/null 2>&1 || true
  done
fi

CFG=$(docker exec "$R1" vtysh -c "show running-config" 2>/dev/null || true)
if ! echo "$CFG" | grep -q "rpki cache ${GORTR_IP} 3323"; then
  error "R1 running-config does not contain the expected 'rpki cache' line."
fi

success "R1 RPKI configured"

# ── Step 9: Configure R2 to use RPKI (full deployment demo) ───
log "Configuring R2 (AS200) to use real RPKI ROV..."

OUT=$(vtysh_cfg "$R2" \
  -c "rpki" \
  -c "no rpki cache ${GORTR_IP} 3323 preference 1" \
  -c "rpki cache ${GORTR_IP} 3323 preference 1" \
  -c "exit")
ensure_no_unknown_cmd "$OUT" "R2 RPKI cache configuration"

log "Installing inbound policy to DROP RPKI-invalid routes on R2..."
R2_NEIGHBORS="$(get_bgp_neighbors "$R2" | tr '\n' ' ')"
if [ -z "${R2_NEIGHBORS// }" ]; then
  warn "Could not detect BGP neighbors from running-config on R2; policy will not be applied automatically."
else
  VTY_ARGS=(
    -c "route-map RPKI_IN deny 10"
    -c "match rpki invalid"
    -c "exit"
    -c "route-map RPKI_IN permit 20"
    -c "exit"
    -c "router bgp 200"
    -c "address-family ipv4 unicast"
  )
  for n in $R2_NEIGHBORS; do
    VTY_ARGS+=( -c "neighbor $n route-map RPKI_IN in" )
  done
  VTY_ARGS+=( -c "exit-address-family" )

  OUT=$(vtysh_cfg "$R2" "${VTY_ARGS[@]}")
  ensure_no_unknown_cmd "$OUT" "R2 RPKI inbound policy configuration"

  for n in $R2_NEIGHBORS; do
    docker exec "$R2" vtysh -c "clear bgp $n in" >/dev/null 2>&1 || true
  done
fi

CFG=$(docker exec "$R2" vtysh -c "show running-config" 2>/dev/null || true)
if ! echo "$CFG" | grep -q "rpki cache ${GORTR_IP} 3323"; then
  error "R2 running-config does not contain the expected 'rpki cache' line."
fi

success "R2 RPKI configured"

# ── Step 10: Wait for RTR sync ────────────────────────────────
log "Waiting 15s for RTR synchronization..."
sleep 15

# ── Step 11: Verify RPKI is working ──────────────────────────
echo ""
echo -e "${BOLD}━━━  Verification  ━━━${RESET}"

echo -e "\n${CYAN}R1 RPKI Cache Status:${RESET}"
docker exec "$R1" vtysh -c "show rpki cache-connection" 2>/dev/null || \
  docker exec "$R1" vtysh -c "show rpki" 2>/dev/null

echo -e "\n${CYAN}R1 RPKI Prefix Table (should show 4 ROAs):${RESET}"
docker exec "$R1" vtysh -c "show rpki prefix-table" 2>/dev/null

echo -e "\n${CYAN}R1 BGP Table (check V/I/N column):${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast" 2>/dev/null

echo ""
echo -e "${BOLD}================================================${RESET}"
echo -e "${GREEN}Real RPKI ROV is now active on R1 and R2${RESET}"
echo ""
echo -e "Legend in BGP table:"
echo -e "  ${GREEN}V${RESET} = RPKI Valid   (origin AS matches ROA)"
echo -e "  ${RED}I${RESET} = RPKI Invalid (origin AS does NOT match ROA)"
echo -e "  ${YELLOW}N${RESET} = Not found   (no ROA exists for prefix)"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  Run an attack:   bash scripts/start_exact_hijack.sh"
echo -e "  Check result:    docker exec ${R1} vtysh -c 'show bgp ipv4 unicast'"
echo -e "  AS400's route should now show ${RED}I (Invalid)${RESET}"
echo -e "${BOLD}================================================${RESET}"
