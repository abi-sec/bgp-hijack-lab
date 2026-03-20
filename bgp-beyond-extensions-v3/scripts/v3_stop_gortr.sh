#!/bin/bash
# Stop GoRTR and remove RPKI cache configuration from R1/R2 (best-effort cleanup).
set -euo pipefail

find_node() {
  local suffix="$1"
  docker ps --format '{{.Names}}' | grep -E '^clab-.*-'"${suffix}"'$' | head -n1
}

R1="$(find_node r1)"
R2="$(find_node r2)"
GORTR_DIR="${HOME}/gortr-data"
GORTR_IP=""

if [ -f "${GORTR_DIR}/gortr_ip" ]; then
  GORTR_IP="$(cat "${GORTR_DIR}/gortr_ip" | tr -d ' \n\r\t')"
fi

echo "[INFO] Stopping gortr container (if running)"
docker stop gortr >/dev/null 2>&1 || true

docker rm gortr >/dev/null 2>&1 || true

cleanup_router() {
  local node="$1"
  local asn="$2"
  if [ -z "$node" ]; then
    return
  fi
  echo "[INFO] Cleaning RPKI config on $node"

  if [ -n "$GORTR_IP" ]; then
    docker exec -i "$node" vtysh <<EOF >/dev/null 2>&1 || true
configure terminal
rpki
 no rpki cache ${GORTR_IP} 3323 preference 1
exit
router bgp ${asn}
 no bgp bestpath prefix-validate allow-invalid
exit
end
write memory
EOF
  else
    # If we don't know the IP, do a minimal cleanup.
    docker exec -i "$node" vtysh <<EOF >/dev/null 2>&1 || true
configure terminal
router bgp ${asn}
 no bgp bestpath prefix-validate allow-invalid
exit
end
write memory
EOF
  fi
}

cleanup_router "$R1" 100
cleanup_router "$R2" 200

if [ -n "$R1" ]; then
  docker exec "$R1" vtysh -c "show rpki cache-connection" 2>/dev/null || true
fi

echo "[OK] GoRTR stopped and router config cleanup attempted"
