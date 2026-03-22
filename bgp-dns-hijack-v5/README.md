# BGP Hijack → DNS Cache Poisoning Attack Chain (v5)

**FRRouting v9.1 + Containerlab | Ubuntu 22.04**

A controlled demonstration of how a BGP sub-prefix hijack enables DNS cache
poisoning with persistent application-layer impact. The attack chain shows
that a brief routing-layer attack (seconds) produces DNS poisoning that
persists for hours after the BGP hijack ends.

This v5 scenario extends the DNS attack-chain lab with validator-assisted ROA/ROV checks. It is not a full RPKI deployment study; it focuses on ROA-based route-origin validation behavior in this controlled topology.

## Scope and Limitations

This lab is intentionally scoped to ROA/ROV behavior in an emulated environment.
It should not be presented as a full Internet-scale RPKI deployment.

- Uses lab-local ROA assertions (via SLURM JSON) to model origin authorization behavior.
- Uses a local validator and RTR cache session inside the lab topology.
- Demonstrates practical ROV policy outcomes, not full global trust-chain operations.

---

## Automated Workflow (Recommended)

This lab now includes two reliable, end-to-end automation paths:

- `rebuild.sh`: Fully rebuilds and redeploys the lab from a clean state,
    reconfigures all containers, waits for convergence, and performs verification.
- `scripts/full_demo.sh`: Runs the full attack and mitigation narrative in order
    (baseline -> hijack -> poisoning -> withdrawal -> persistence -> mitigation check).

These scripts are the recommended way to run the project for reproducible results.
Use the manual steps only if you need fine-grained debugging or custom experiments.

## Topology (6 ASes + 3 Host Containers)

```
  dns-server ─── R3 (AS300 Victim)
  13.0.0.50           |
                 R2 (AS200 Transit)
                /           \
        R1 (AS100)      R5 (AS500 Transit2)
            |                   |
        R4 (AS400)         R6 (AS600 Client)
            |                   |
        fake-dns            client
        (attacker)      (caching resolver)
```

| Link | Subnet |
|---|---|
| AS100 ↔ AS200 | 10.12.0.0/30 |
| AS200 ↔ AS300 | 10.23.0.0/30 |
| AS100 ↔ AS400 | 10.14.0.0/30 |
| AS200 ↔ AS500 | 10.25.0.0/30 |
| AS500 ↔ AS600 | 10.56.0.0/30 |
| R3 ↔ dns-server | 10.30.0.0/30 |
| R4 ↔ fake-dns | 10.40.0.0/30 |
| R6 ↔ client | 10.60.0.0/30 |

**DNS Infrastructure:**
- **dns-server** (13.0.0.50): Legitimate authoritative DNS for `victim.lab`, TTL=300s
- **fake-dns** (responds as 13.0.0.50): Attacker's spoofed DNS, all records → 14.0.0.66, TTL=86400s
- **client**: Runs `unbound` caching resolver forwarding to 13.0.0.50

---

## Attack Chain Summary

| Phase | Action | DNS Result | Routing State |
|---|---|---|---|
| 1. Baseline | No attack | `www.victim.lab` → 13.0.0.100 ✓ | Normal via AS200→AS300 |
| 2. Hijack | AS400 announces 13.0.0.0/25 | `www.victim.lab` → 14.0.0.66 ✗ | Hijacked via AS400 |
| 3. Poisoned | Resolver caches attacker response | Cache: 14.0.0.66 (TTL=86400) | Still hijacked |
| 4. Withdrawal | AS400 withdraws /25 | Direct: 13.0.0.100 ✓ | Restored |
| 5. Persistence | Check cached entry | **Cache: STILL 14.0.0.66** ✗ | Clean routing, poisoned cache |

**Key finding:** Phase 5 — routing is clean but DNS is still poisoned. A seconds-long
BGP hijack causes 24 hours of DNS poisoning via TTL manipulation.

---

## Quick Start

```bash
# 1. Run the setup to generate all configs
bash setup.sh

# 2. Build the DNS container image
sudo docker build -t dns-lab:latest -f Dockerfile.dns .

# 3. Deploy the lab
sudo containerlab deploy -t topology.yaml

# 4. Wait 60 seconds for BGP convergence
sleep 60

# 5. Verify everything is working
bash scripts/verify.sh

# 6. Run the full interactive demo
bash scripts/full_demo.sh
```

---

## Switching Between v4 and v5

v4 and v5 use the same containerlab topology name (`bgp-dns-hijack`).
If you switch folders without cleanup, name/state conflicts can prevent
correct deployment or reconfiguration.

Always run this sequence when switching versions:

```bash
# From the version you used last
sudo containerlab destroy -t topology.yaml --cleanup

# Move to the other version folder (v4 or v5)
# Rebuild/reconfigure from that folder
sudo bash rebuild.sh
```

Do not deploy v4 and v5 concurrently with the same topology name.

---

## Running Individual Phases

```bash
# Phase 1: Verify baseline DNS works
bash scripts/dns_baseline.sh

# Phase 2: Launch the sub-prefix hijack
bash scripts/start_dns_hijack.sh

# Phase 3: Verify DNS is poisoned during hijack
bash scripts/verify_dns_poison.sh

# Phase 4: Withdraw the hijack
bash scripts/stop_dns_hijack.sh

# Phase 5: Verify cache poisoning persists
bash scripts/verify_cache_persistence.sh
```

---

## Automated Evaluation

Runs all phases automatically and produces CSV + log:

```bash
bash scripts/evaluate_dns_chain.sh
```

Output files:
- `evaluation_dns_<timestamp>.csv` — structured results
- `evaluation_dns_<timestamp>.log` — full output

ROA/ROV validation-focused evaluation:

```bash
bash scripts/verify_rpki.sh
bash scripts/evaluate_mitigation_strict.sh
```

Output files:
- `evaluation_mitigation_<timestamp>.csv` — strict evidence checks
- `evaluation_mitigation_<timestamp>.log` — full trace

---

## How the Attack Works

### Sub-Prefix Hijack Mechanism
AS400 announces `13.0.0.0/25`, a more specific prefix than AS300's `13.0.0.0/24`.
Due to BGP's longest-prefix-match rule, all traffic to IPs in `13.0.0.0–13.0.0.127`
(including the DNS server at 13.0.0.50) is routed to AS400.

### DNS Poisoning Mechanism
The fake-dns behind AS400 is configured to respond to all `victim.lab` queries
with `14.0.0.66` (attacker's server) and a TTL of 86400 seconds (24 hours).
When the client's caching resolver (`unbound`) queries during the hijack window,
it caches this poisoned response.

### Persistence Mechanism
After AS400 withdraws the BGP announcement:
- **Direct DNS queries** to 13.0.0.50 correctly reach AS300's legitimate server again
- **Cached queries** through unbound still return the poisoned 14.0.0.66 for up to 24 hours
- Any application using the cached resolver sees the attacker's IP until TTL expires

### Real-World Implications (from Birge-Lee et al., USENIX Sec 2018)
- Attacker obtains bogus TLS certificates by passing CA domain validation
- Credential theft via impersonation of login pages
- Cryptocurrency theft (MyEtherWallet incident, April 2018)
- Email interception via MX record poisoning

---

## Manual Router Access

```bash
docker exec -it clab-bgp-dns-hijack-r1 vtysh   # AS100
docker exec -it clab-bgp-dns-hijack-r2 vtysh   # AS200 Transit
docker exec -it clab-bgp-dns-hijack-r3 vtysh   # AS300 Victim
docker exec -it clab-bgp-dns-hijack-r4 vtysh   # AS400 Attacker
docker exec -it clab-bgp-dns-hijack-r5 vtysh   # AS500 Transit2
docker exec -it clab-bgp-dns-hijack-r6 vtysh   # AS600 Client

# DNS containers
docker exec -it clab-bgp-dns-hijack-dns-server sh
docker exec -it clab-bgp-dns-hijack-fake-dns sh
docker exec -it clab-bgp-dns-hijack-client sh

# Useful commands inside client
dig @13.0.0.50 www.victim.lab           # Direct query to DNS server
dig @127.0.0.1 www.victim.lab           # Query through caching resolver
traceroute -n 13.0.0.50                 # Check routing path to DNS
```

---

## Troubleshooting

**DNS server not reachable from client:**
Wait 60s for BGP convergence. Verify with `bash scripts/verify.sh`.

**Unbound not running on client:**
```bash
docker exec clab-bgp-dns-hijack-client unbound -c /etc/unbound/unbound.conf
```

**Cache not poisoned after attack:**
Flush the cache first, then query during the attack:
```bash
docker exec clab-bgp-dns-hijack-client pkill unbound
docker exec clab-bgp-dns-hijack-client unbound -c /etc/unbound/unbound.conf
# Now run verify_dns_poison.sh while hijack is active
```

**Docker image `dns-lab:latest` not found:**
```bash
sudo docker build -t dns-lab:latest -f Dockerfile.dns .
```

---

## Teardown

```bash
sudo containerlab destroy -t topology.yaml --cleanup
```

---

## References

- Birge-Lee et al., "Bamboozling Certificate Authorities with BGP" (USENIX Security 2018)
- Kowalski & Mazurczyk, "Routing Security Survey" (Computer Networks 2023), §3.4
- Apostolaki et al., "Hijacking Bitcoin: Routing Attacks on Cryptocurrencies" (IEEE S&P 2017)
- Sermpezis et al., "ARTEMIS: Neutralizing BGP Hijacking" (IEEE/ACM ToN 2018)
- Chung et al., "RPKI is Coming of Age" (ACM IMC 2019)
- Morillo et al., "ROV++: Improved Deployable Defense" (NDSS 2021)
- Holterbach et al., "DFOH: Detecting Forged-Origin BGP Hijacks" (NSDI 2024)
- Schulmann & Zhao, "Stealth BGP Hijacks with uRPF" (WOOT 2025)

## Environment

- OS: Ubuntu 22.04
- FRRouting: v9.1.0
- Containerlab: v0.54+
- Docker: CE 28.x
- DNS: dnsmasq (server/attacker), unbound (client resolver)
