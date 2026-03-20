#!/bin/bash
# =============================================================
# maxlength_demo.sh — Demonstrate the RPKI MaxLength Vulnerability
#
# BACKGROUND:
#   A ROA for 13.0.0.0/24 with maxLength /24 means ONLY /24
#   announcements from AS300 are valid. Any /25 = INVALID.
#
#   A ROA for 13.0.0.0/24 with maxLength /25 means BOTH /24
#   AND /25 announcements from AS300 are valid.
#
#   The problem: if maxLength is /25, AS400 announcing /25
#   is still RPKI-INVALID (wrong origin). BUT a forged-origin
#   attack where AS400 announces /25 with AS300 appended as
#   the last hop would appear VALID — bypassing ROV entirely.
#
# REFERENCE: Chung et al. (IMC 2019) found 84% of prefixes
# using MaxLength had it set incorrectly, exposing them to
# forged-origin subprefix hijacks even with RPKI deployed.
#
# PREREQUISITE: setup_gortr.sh must have been run first.
#
# WHAT THIS DEMONSTRATES:
#   Phase 1 — Safe config (maxLength /24): subprefix = INVALID
#   Phase 2 — Unsafe config (maxLength /25): creates attack surface
# =============================================================

LAB="bgp-hijack"
R1="clab-${LAB}-r1"
R4="clab-${LAB}-r4"

BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"
YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

GORTR_DIR="${HOME}/gortr-data"

if [ ! -f "${GORTR_DIR}/gortr_ip" ]; then
  echo -e "${RED}[ERROR]${RESET} GoRTR not set up. Run setup_gortr.sh first."
  exit 1
fi

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║     MaxLength Vulnerability Demonstration        ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}━━━  Phase 1: Safe Configuration (maxLength /24)  ━━━${RESET}"
# ─────────────────────────────────────────────────────────────
echo ""
echo "ROA: 13.0.0.0/24 → AS300, maxLength /24"
echo "Effect: Only exact /24 from AS300 is VALID"
echo "        Any /25 from any AS = INVALID"
echo ""

# Restore safe maxLength /24
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

echo "Updated VRP file with maxLength /24. Waiting 35s for GoRTR refresh..."
sleep 35

echo -e "${CYAN}Injecting subprefix hijack (13.0.0.0/25) from AS400...${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/24" \
  -c "network 13.0.0.0/25" \
  -c "end" 2>/dev/null || true
docker exec "$R4" ip route add blackhole 13.0.0.0/25 2>/dev/null || true
sleep 15

echo -e "\n${CYAN}--- R1 BGP Table (Phase 1: safe maxLength) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"

echo ""
echo -e "${GREEN}Phase 1 result: AS400's /25 appears as (I) INVALID${RESET}"
echo -e "${GREEN}RPKI correctly blocks the subprefix hijack${RESET}"

# Cleanup
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/25" \
  -c "end" 2>/dev/null || true
docker exec "$R4" ip route del blackhole 13.0.0.0/25 2>/dev/null || true
sleep 10

echo ""
echo -e "${BOLD}━━━  Phase 2: Unsafe Configuration (maxLength /25)  ━━━${RESET}"
echo ""
echo -e "${RED}WARNING: This simulates a MISCONFIGURED ROA${RESET}"
echo "ROA: 13.0.0.0/24 → AS300, maxLength /25"
echo "Effect: /24 AND /25 from AS300 are VALID"
echo "        /25 from AS400 = still INVALID (wrong origin)"
echo "        BUT: forged-origin /25 with AS300 appended = VALID"
echo "        This is the MaxLength attack surface described by Chung et al."
echo ""

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
      "maxLength": 25,
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

echo "Updated VRP file with maxLength /25. Waiting 35s for GoRTR refresh..."
sleep 35

echo -e "${CYAN}Injecting subprefix hijack (13.0.0.0/25) from AS400...${RESET}"
docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "network 13.0.0.0/25" \
  -c "end" 2>/dev/null || true
docker exec "$R4" ip route add blackhole 13.0.0.0/25 2>/dev/null || true
sleep 15

echo -e "\n${CYAN}--- R1 BGP Table (Phase 2: unsafe maxLength) ---${RESET}"
docker exec "$R1" vtysh -c "show bgp ipv4 unicast"

echo ""
echo -e "${RED}Phase 2 result: AS400's /25 STILL appears as (I) INVALID${RESET}"
echo -e "${YELLOW}BUT: maxLength /25 means a forged-origin attack announcing${RESET}"
echo -e "${YELLOW}13.0.0.0/25 with AS300 as last hop would appear (V) VALID${RESET}"
echo -e "${YELLOW}ROV cannot distinguish legitimate from forged when MaxLength is set too broadly${RESET}"
echo ""
echo -e "${BOLD}Key Finding (Chung et al. 2019):${RESET}"
echo -e "  84% of prefixes using MaxLength in RPKI had it set too broadly"
echo -e "  Recommendation: Use maxLength ONLY if you actually announce sub-prefixes"
echo -e "  Best practice: Issue separate ROAs for each prefix you announce"

# Cleanup — restore safe config
echo ""
echo -e "${CYAN}Restoring safe maxLength /24 configuration...${RESET}"
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

docker exec "$R4" vtysh \
  -c "configure terminal" \
  -c "router bgp 400" \
  -c "no network 13.0.0.0/25" \
  -c "end" 2>/dev/null || true
docker exec "$R4" ip route del blackhole 13.0.0.0/25 2>/dev/null || true
echo -e "${GREEN}Lab restored to clean state.${RESET}"
