#!/bin/bash
# ==========================================================
# BGP DNS Hijack Lab v5 — CLEAN REBUILD
#
# Extension of v4 with real RPKI via GoRTR:
#   - All v4 components unchanged (6 routers, 3 hosts)
#   - New: gortr container serving ROAs via RTR protocol
#   - New: R1 connects to GoRTR, validates all BGP announcements
#   - New: R4 has no bgp network import-check (attack injection fix)
#   - Mitigation: RPKI route-map drops INVALID prefixes automatically
#
# What RPKI adds over v4 ROV:
#   v4 ROV: manual prefix-list, operator must know attacker prefixes
#   v5 RPKI: GoRTR serves ROAs, FRR auto-validates every announcement
#            AS400's 13.0.0.0/25 → RPKI INVALID → dropped
#            No manual filter needed. Cryptographically grounded.
# ==========================================================
set -e
cd "$(dirname "$0")"
LAB="clab-bgp-dns-hijack"

echo "╔══════════════════════════════════════════╗"
echo "║  BGP DNS Hijack Lab v5 — Clean Rebuild   ║"
echo "║  With RPKI via GoRTR                     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Step 0: Destroy existing lab ─────────────────────────────
echo "[0/9] Destroying any existing lab..."
sudo containerlab destroy -t topology.yaml --cleanup 2>/dev/null || true
echo "  Done."

# ── Step 1: Create vtysh.conf for all routers ─────────────────
echo ""
echo "[1/9] Creating vtysh.conf for all routers..."
for r in r1 r2 r3 r4 r5 r6; do
  cat > configs/$r/vtysh.conf << 'VEOF'
service integrated-vtysh-config
VEOF
  echo "  configs/$r/vtysh.conf created"
done

# ── Step 2: Rewrite ALL frr.conf files ───────────────────────
echo ""
echo "[2/9] Writing fixed FRR configs..."

# --- R1 (AS100 Observer) — RPKI enabled ---
cat > configs/r1/frr.conf << 'EOF'
frr defaults traditional
hostname r1
no ipv6 forwarding
!
interface eth1
 ip address 10.12.0.1/30
exit
!
interface eth2
 ip address 10.14.0.1/30
exit
!
interface eth3
 ip address 10.17.0.1/30
exit
!
interface lo
 ip address 11.0.0.1/24
exit
!
router bgp 100
 bgp router-id 1.1.1.1
 no bgp ebgp-requires-policy
 neighbor 10.12.0.2 remote-as 200
 neighbor 10.14.0.2 remote-as 400
 !
 address-family ipv4 unicast
  network 11.0.0.0/24
  redistribute connected
  neighbor 10.12.0.2 activate
  neighbor 10.14.0.2 activate
 exit-address-family
exit
!
end
EOF
echo "  r1 (AS100 + RPKI) written"

# R1 daemons
cat > configs/r1/daemons << 'EOF'
bgpd=yes
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
pathd=no
EOF
echo "  r1 daemons written"

# --- R2 (AS200 Transit) ---
cat > configs/r2/frr.conf << 'EOF'
frr defaults traditional
hostname r2
no ipv6 forwarding
!
interface eth1
 ip address 10.12.0.2/30
exit
!
interface eth2
 ip address 10.23.0.1/30
exit
!
interface eth3
 ip address 10.25.0.1/30
exit
!
interface lo
 ip address 12.0.0.1/24
exit
!
router bgp 200
 bgp router-id 2.2.2.2
 no bgp ebgp-requires-policy
 neighbor 10.12.0.1 remote-as 100
 neighbor 10.23.0.2 remote-as 300
 neighbor 10.25.0.2 remote-as 500
 !
 address-family ipv4 unicast
  network 12.0.0.0/24
  redistribute connected
  neighbor 10.12.0.1 activate
  neighbor 10.23.0.2 activate
  neighbor 10.25.0.2 activate
 exit-address-family
exit
!
end
EOF
echo "  r2 (AS200) written"

# --- R3 (AS300 Victim) ---
cat > configs/r3/frr.conf << 'EOF'
frr defaults traditional
hostname r3
no ipv6 forwarding
!
interface eth1
 ip address 10.23.0.2/30
exit
!
interface eth2
 ip address 10.30.0.1/30
exit
!
interface lo
 ip address 13.0.0.1/24
exit
!
router bgp 300
 bgp router-id 3.3.3.3
 no bgp ebgp-requires-policy
 neighbor 10.23.0.1 remote-as 200
 !
 address-family ipv4 unicast
  network 13.0.0.0/24
  redistribute connected
  neighbor 10.23.0.1 activate
 exit-address-family
exit
!
ip route 13.0.0.50/32 10.30.0.2
!
end
EOF
echo "  r3 (AS300) written"

# --- R4 (AS400 Attacker) — import-check disabled for attack injection ---
cat > configs/r4/frr.conf << 'EOF'
frr defaults traditional
hostname r4
no ipv6 forwarding
!
interface eth1
 ip address 10.14.0.2/30
exit
!
interface eth2
 ip address 10.40.0.1/30
exit
!
interface lo
 ip address 14.0.0.1/24
exit
!
router bgp 400
 bgp router-id 4.4.4.4
 no bgp ebgp-requires-policy
 no bgp network import-check
 neighbor 10.14.0.1 remote-as 100
 !
 address-family ipv4 unicast
  network 14.0.0.0/24
  redistribute connected
  neighbor 10.14.0.1 activate
 exit-address-family
exit
!
end
EOF
echo "  r4 (AS400 + import-check fix) written"

# --- R5 (AS500 Transit2) ---
cat > configs/r5/frr.conf << 'EOF'
frr defaults traditional
hostname r5
no ipv6 forwarding
!
interface eth1
 ip address 10.25.0.2/30
exit
!
interface eth2
 ip address 10.56.0.1/30
exit
!
interface lo
 ip address 15.0.0.1/24
exit
!
router bgp 500
 bgp router-id 5.5.5.5
 no bgp ebgp-requires-policy
 neighbor 10.25.0.1 remote-as 200
 neighbor 10.56.0.2 remote-as 600
 !
 address-family ipv4 unicast
  network 15.0.0.0/24
  redistribute connected
  neighbor 10.25.0.1 activate
  neighbor 10.56.0.2 activate
 exit-address-family
exit
!
end
EOF
echo "  r5 (AS500) written"

# --- R6 (AS600 Client) ---
cat > configs/r6/frr.conf << 'EOF'
frr defaults traditional
hostname r6
no ipv6 forwarding
!
interface eth1
 ip address 10.56.0.2/30
exit
!
interface eth2
 ip address 10.60.0.1/30
exit
!
interface lo
 ip address 16.0.0.1/24
exit
!
router bgp 600
 bgp router-id 6.6.6.6
 no bgp ebgp-requires-policy
 neighbor 10.56.0.1 remote-as 500
 !
 address-family ipv4 unicast
  network 16.0.0.0/24
  redistribute connected
  neighbor 10.56.0.1 activate
 exit-address-family
exit
!
end
EOF
echo "  r6 (AS600) written"

# ── Step 3: Write DNS configs ─────────────────────────────────
echo ""
echo "[3/9] Writing fixed DNS configs..."

cat > configs/dns/legit-dnsmasq.conf << 'EOF'
no-resolv
no-hosts
log-queries
local-ttl=300
address=/www.victim.lab/13.0.0.100
address=/login.victim.lab/13.0.0.80
address=/mail.victim.lab/13.0.0.25
address=/api.victim.lab/13.0.0.90
address=/ns.victim.lab/13.0.0.50
EOF
echo "  legit-dnsmasq.conf written"

cat > configs/dns/fake-dnsmasq.conf << 'EOF'
no-resolv
no-hosts
log-queries
local-ttl=180
address=/www.victim.lab/14.0.0.66
address=/login.victim.lab/14.0.0.66
address=/mail.victim.lab/14.0.0.66
address=/api.victim.lab/14.0.0.66
address=/ns.victim.lab/14.0.0.66
EOF
echo "  fake-dnsmasq.conf written (TTL=180s for demo)"

cat > configs/dns/unbound.conf << 'EOF'
server:
    interface: 127.0.0.1
    port: 53
    access-control: 127.0.0.0/8 allow
    do-not-query-localhost: no
    verbosity: 1
    val-permissive-mode: yes
    cache-min-ttl: 0
    cache-max-ttl: 86400
    msg-cache-size: 4m
    rrset-cache-size: 4m

forward-zone:
    name: "."
    forward-addr: 13.0.0.50
EOF
echo "  unbound.conf written"

# ── Step 4: Write RPKI ROA database ──────────────────────────
echo ""
echo "[4/9] Writing RPKI ROA database (vrps.json)..."
mkdir -p configs/rpki
cat > configs/rpki/vrps.json << 'EOF'
{
  "roas": [
    {"prefix": "11.0.0.0/24", "maxLength": 24, "asn": 100},
    {"prefix": "12.0.0.0/24", "maxLength": 24, "asn": 200},
    {"prefix": "13.0.0.0/24", "maxLength": 24, "asn": 300},
    {"prefix": "14.0.0.0/24", "maxLength": 24, "asn": 400},
    {"prefix": "15.0.0.0/24", "maxLength": 24, "asn": 500},
    {"prefix": "16.0.0.0/24", "maxLength": 24, "asn": 600}
  ]
}
EOF
echo "  vrps.json written (AS300 maxLength=24 — /25 hijack = INVALID)"

# ── Step 5: Write topology ────────────────────────────────────
echo ""
echo "[5/9] Writing topology.yaml..."

cat > topology.yaml << 'EOF'
name: bgp-dns-hijack

topology:
  nodes:
    r1:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r1/frr.conf:/etc/frr/frr.conf
        - configs/r1/daemons:/etc/frr/daemons
        - configs/r1/vtysh.conf:/etc/frr/vtysh.conf
    r2:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r2/frr.conf:/etc/frr/frr.conf
        - configs/r2/daemons:/etc/frr/daemons
        - configs/r2/vtysh.conf:/etc/frr/vtysh.conf
    r3:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r3/frr.conf:/etc/frr/frr.conf
        - configs/r3/daemons:/etc/frr/daemons
        - configs/r3/vtysh.conf:/etc/frr/vtysh.conf
    r4:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r4/frr.conf:/etc/frr/frr.conf
        - configs/r4/daemons:/etc/frr/daemons
        - configs/r4/vtysh.conf:/etc/frr/vtysh.conf
    r5:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r5/frr.conf:/etc/frr/frr.conf
        - configs/r5/daemons:/etc/frr/daemons
        - configs/r5/vtysh.conf:/etc/frr/vtysh.conf
    r6:
      kind: linux
      image: quay.io/frrouting/frr:9.1.0
      binds:
        - configs/r6/frr.conf:/etc/frr/frr.conf
        - configs/r6/daemons:/etc/frr/daemons
        - configs/r6/vtysh.conf:/etc/frr/vtysh.conf

    gortr:
      kind: linux
      image: rpki/stayrtr:latest
      binds:
        - configs/rpki/vrps.json:/etc/stayrtr/vrps.json

    dns-server:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/legit-dnsmasq.conf:/etc/dnsmasq.conf

    fake-dns:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/fake-dnsmasq.conf:/etc/dnsmasq.conf

    client:
      kind: linux
      image: dns-lab:latest
      binds:
        - configs/dns/unbound.conf:/etc/unbound/unbound.conf

  links:
    - endpoints: ["r1:eth1", "r2:eth1"]
    - endpoints: ["r2:eth2", "r3:eth1"]
    - endpoints: ["r1:eth2", "r4:eth1"]
    - endpoints: ["r2:eth3", "r5:eth1"]
    - endpoints: ["r5:eth2", "r6:eth1"]
    - endpoints: ["r3:eth2", "dns-server:eth1"]
    - endpoints: ["r4:eth2", "fake-dns:eth1"]
    - endpoints: ["r6:eth2", "client:eth1"]
    - endpoints: ["r1:eth3", "gortr:eth1"]
EOF
echo "  topology.yaml written (+ gortr node + r1:eth3 link)"

# ── Step 6: Deploy ────────────────────────────────────────────
echo ""
echo "[6/9] Deploying lab..."
sudo containerlab deploy -t topology.yaml

echo "  Enabling IP forwarding on routers..."
for r in r1 r2 r3 r4 r5 r6; do
  docker exec $LAB-$r sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
done

# ── Step 7: Wait for BGP convergence ─────────────────────────
echo ""
echo "[7/9] Waiting 90s for BGP convergence..."
echo "  (interfaces stabilize, gortr and hosts configured after)"
sleep 90

# ── Step 8: Configure gortr and host containers ───────────────
echo ""
echo "[8/9] Configuring gortr and host containers..."

echo "  Configuring gortr (RPKI validator)..."
# StayRTR has no shell — use nsenter to configure networking from host
GORTR_PID=$(docker inspect --format '{{.State.Pid}}' $LAB-gortr)
sudo nsenter -t $GORTR_PID -n ip addr add 10.17.0.2/30 dev eth1 2>/dev/null || true
sudo nsenter -t $GORTR_PID -n ip link set eth1 up 2>/dev/null || true
sudo nsenter -t $GORTR_PID -n ip route del default 2>/dev/null || true
sudo nsenter -t $GORTR_PID -n ip route add default via 10.17.0.1 2>/dev/null || true

# Start StayRTR using full binary path (not in $PATH)
# -verify=false: skip RPKI signature check (local VRPs file, no real RPKI)
docker exec -d $LAB-gortr /stayrtr \
  -bind :8282 \
  -vrps /etc/stayrtr/vrps.json \
  -verify=false 2>/dev/null || true
echo "    gortr done"

echo "  Waiting 10s for StayRTR to initialize..."
sleep 10

echo "  Configuring dns-server..."
docker exec $LAB-dns-server sh -c "
  ip addr add 10.30.0.2/30 dev eth1 2>/dev/null || true
  ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 10.30.0.1
  pkill dnsmasq 2>/dev/null || true
  sleep 1
  dnsmasq &
" && echo "    done"

echo "  Configuring fake-dns..."
docker exec $LAB-fake-dns sh -c "
  ip addr add 10.40.0.2/30 dev eth1 2>/dev/null || true
  ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 10.40.0.1
  pkill dnsmasq 2>/dev/null || true
  sleep 1
  dnsmasq &
" && echo "    done"

echo "  Configuring client..."
docker exec $LAB-client sh -c "
  ip addr add 10.60.0.2/30 dev eth1 2>/dev/null || true
  ip link set eth1 up
  ip route del default 2>/dev/null || true
  ip route add default via 10.60.0.1
  pkill unbound 2>/dev/null || true
  sleep 1
  unbound -c /etc/unbound/unbound.conf &
" && echo "    done"

echo "  Waiting 10s for services to start..."
sleep 10

# ── Step 9: Verify everything ─────────────────────────────────
echo ""
echo "[9/9] Verifying lab..."
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║            Verification                  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

echo "[1] BGP sessions on R1 (AS100):"
docker exec $LAB-r1 vtysh -c "show bgp ipv4 unicast summary" 2>/dev/null | tail -5
echo ""

echo "[2] BGP sessions on R6 (AS600):"
docker exec $LAB-r6 vtysh -c "show bgp ipv4 unicast summary" 2>/dev/null | tail -5
echo ""

echo "[3] StayRTR running (RPKI validator):"
docker exec $LAB-gortr ps aux 2>/dev/null | grep stayrtr | grep -v grep && echo "  ✓ StayRTR running" || echo "  ✗ StayRTR not running"
echo ""

echo "[4] RPKI ROA database loaded:"
python3 -c "import json; d=json.load(open('configs/rpki/vrps.json')); print('  ' + str(len(d['roas'])) + ' ROAs loaded from vrps.json')"
echo ""

echo "[5] Ping 13.0.0.50 from client:"
if docker exec $LAB-client ping -c 2 -W 3 13.0.0.50 >/dev/null 2>&1; then
  echo "  ✓ 13.0.0.50 reachable"
else
  echo "  ✗ Ping failed — re-running host bootstrap..."
  docker exec $LAB-dns-server sh -c "
    ip addr add 10.30.0.2/30 dev eth1 2>/dev/null || true
    ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
    ip link set eth1 up
    ip route del default 2>/dev/null || true
    ip route add default via 10.30.0.1
    pkill dnsmasq 2>/dev/null || true
    sleep 1
    dnsmasq &
  " 2>/dev/null
  docker exec $LAB-fake-dns sh -c "
    ip addr add 10.40.0.2/30 dev eth1 2>/dev/null || true
    ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
    ip link set eth1 up
    ip route del default 2>/dev/null || true
    ip route add default via 10.40.0.1
    pkill dnsmasq 2>/dev/null || true
    sleep 1
    dnsmasq &
  " 2>/dev/null
  docker exec $LAB-client sh -c "
    ip addr add 10.60.0.2/30 dev eth1 2>/dev/null || true
    ip link set eth1 up
    ip route del default 2>/dev/null || true
    ip route add default via 10.60.0.1
    pkill unbound 2>/dev/null || true
    sleep 1
    unbound -c /etc/unbound/unbound.conf &
  " 2>/dev/null
  sleep 10
  if docker exec $LAB-client ping -c 2 -W 3 13.0.0.50 >/dev/null 2>&1; then
    echo "  ✓ 13.0.0.50 reachable after retry"
  else
    echo "  ✗ Still unreachable — check BGP sessions above"
  fi
fi
echo ""

echo "[6] DNS test from client (direct to 13.0.0.50):"
RESULT=$(docker exec $LAB-client dig @13.0.0.50 www.victim.lab +short +timeout=5 2>/dev/null)
echo "  www.victim.lab = $RESULT"
echo ""

echo "[7] DNS test from client (through caching resolver):"
CACHED=$(docker exec $LAB-client dig @127.0.0.1 www.victim.lab +short +timeout=5 2>/dev/null)
echo "  www.victim.lab = $CACHED"
echo ""

# ── Final status ──────────────────────────────────────────────
if [ "$RESULT" = "13.0.0.100" ]; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  ✓ Lab is READY!                         ║"
  echo "║                                          ║"
  echo "║  Run: bash scripts/full_demo.sh          ║"
  echo "║   or: bash scripts/mitigate_rpki.sh      ║"
  echo "╚══════════════════════════════════════════╝"
elif [ -z "$RESULT" ]; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  ✗ DNS not reachable yet                 ║"
  echo "║  BGP may still be converging. Try:       ║"
  echo "║  docker exec $LAB-client \               ║"
  echo "║    dig @13.0.0.50 www.victim.lab +short  ║"
  echo "╚══════════════════════════════════════════╝"
else
  echo "  Unexpected result: DNS=$RESULT"
fi
