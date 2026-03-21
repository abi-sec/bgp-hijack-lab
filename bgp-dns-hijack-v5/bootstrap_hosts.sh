#!/bin/bash
# Run this AFTER containerlab deploy completes
# Configures the 3 host containers (dns-server, fake-dns, client)
# and enables IP forwarding on all routers

set -e
LAB="clab-bgp-dns-hijack"

echo "=== Post-Deploy Bootstrap ==="
echo ""

# Enable IP forwarding on all routers
echo "[1/5] Enabling IP forwarding on routers..."
for r in r1 r2 r3 r4 r5 r6; do
  docker exec $LAB-$r sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
  echo "  $r: ip_forward enabled"
done

# Configure dns-server (behind R3/AS300)
echo ""
echo "[2/5] Configuring dns-server (legitimate, AS300)..."
docker exec $LAB-dns-server sh -c "
  ip addr add 10.30.0.2/30 dev eth1 2>/dev/null || true
  ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
  ip link set eth1 up
  ip route add default via 10.30.0.1 2>/dev/null || true
  pkill dnsmasq 2>/dev/null || true
  sleep 1
  dnsmasq
"
echo "  dns-server: configured + dnsmasq started"

# Configure fake-dns (behind R4/AS400)
echo ""
echo "[3/5] Configuring fake-dns (attacker, AS400)..."
docker exec $LAB-fake-dns sh -c "
  ip addr add 10.40.0.2/30 dev eth1 2>/dev/null || true
  ip addr add 13.0.0.50/32 dev lo 2>/dev/null || true
  ip link set eth1 up
  ip route add default via 10.40.0.1 2>/dev/null || true
  pkill dnsmasq 2>/dev/null || true
  sleep 1
  dnsmasq
"
echo "  fake-dns: configured + dnsmasq started"

# Configure client (behind R6/AS600)
echo ""
echo "[4/5] Configuring client (resolver, AS600)..."
docker exec $LAB-client sh -c "
  ip addr add 10.60.0.2/30 dev eth1 2>/dev/null || true
  ip link set eth1 up
  ip route add default via 10.60.0.1 2>/dev/null || true
  mkdir -p /var/log
  pkill unbound 2>/dev/null || true
  sleep 1
  unbound -c /etc/unbound/unbound.conf 2>/dev/null || echo 'unbound start failed - will retry in verify'
"
echo "  client: configured + unbound started"

# Quick sanity check
echo ""
echo "[5/5] Quick sanity checks..."

echo -n "  R3 can reach dns-server: "
docker exec $LAB-r3 ping -c 1 -W 2 10.30.0.2 >/dev/null 2>&1 && echo "✓" || echo "✗"

echo -n "  R4 can reach fake-dns:   "
docker exec $LAB-r4 ping -c 1 -W 2 10.40.0.2 >/dev/null 2>&1 && echo "✓" || echo "✗"

echo -n "  R6 can reach client:     "
docker exec $LAB-r6 ping -c 1 -W 2 10.60.0.2 >/dev/null 2>&1 && echo "✓" || echo "✗"

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Wait 30-60s for BGP convergence, then run:"
echo "  bash scripts/verify.sh"
