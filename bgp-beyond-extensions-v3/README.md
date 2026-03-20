# BGP Hijacking Lab — Beyond Initial Project
### Advanced Extensions | Real RPKI | Forged-Origin | Deaggregation | MaxLength

---

## Overview

This package extends the main `bgp-hijack-lab` with novel attack and defense
scenarios that go beyond the initial project scope. These additions bring the
project to genuine grad-level research contribution by demonstrating the
**generational limitations of RPKI Route Origin Validation (ROV)**.

**Do NOT replace your main lab files.** These scripts run alongside the
existing lab topology and require it to be deployed first.

## Current status

- Validation state: **not validated yet**.
- Topology ownership: this package has no standalone `topology.yaml`.
- Runtime dependency (current): v3 scripts target the main v1 deployment (`bgp-hijack`), not v2 (`bgp-hijack-rpki`).

## Architecture Direction (Important)

See the top-level policy summary in `../README.md` under **v3 Validation and Migration Policy** for the canonical validation order.

Current behavior:

- v3 runs as an extension layer on top of **v1 topology**.
- Most scripts assume lab/container names based on `bgp-hijack`.

Recommended direction:

- Evolve v3 to extend **v2 (RPKI topology)** instead of v1.
- This keeps advanced scenarios aligned with validator-backed routing and avoids maintaining two divergent integration paths.

Validation order policy:

- First validate each v3 script against the current v1 integration path.
- After scripts are confirmed working in v1, port and validate it in the v2 integration path.
- Treat v2 as the long-term target baseline once parity is achieved.

Migration plan to make v3 extend v2:

1. Update script defaults from `LAB="bgp-hijack"` to v2-aware targeting (`bgp-hijack-rpki`) or add a `LAB` argument.
2. Update README command paths so integration examples use `bgp-hijack-lab-rpki-v2/` first.
3. Validate all v3 scenarios against v2 end-to-end (exact, subprefix, forged-origin, maxLength, deaggregation, extended evaluate).
4. Keep v1 compatibility as optional only after v2-first path is stable.

---

## Prerequisites

Current prerequisite (as implemented today): deploy v1 before running v3 scripts.

```bash
cd ~/bgp-hijack-lab
sudo containerlab deploy -t topology.yaml
bash scripts/verify.sh
```

Preferred target state (after migration): deploy v2 first, then run v3 extensions.

```bash
cd ~/bgp-hijack-lab-rpki-v2
sudo containerlab deploy -t topology.yaml
bash scripts/verify.sh
```

Current expected baseline for v1 path:

```bash
# All 4 routers should show BGP tables with 13.0.0.0/24 via AS path 200 300
```

---

## What Is Added

### 1. Real RPKI via GoRTR (`setup_gortr.sh`)
Replaces the simulated route-map filter with actual RPKI Route Origin
Validation using FRR's native RTR protocol. GoRTR is a lightweight RTR
server by Cloudflare that serves a local VRP (Validated ROA Payload) file.

**Why this matters:** Your original mitigation was a prefix-list filter
that blocked AS400's announcements. Real RPKI uses cryptographic ROAs
and produces actual validation states (V/I/N) visible in the BGP table.
This is what production networks actually deploy.

### 2. MaxLength Vulnerability (`maxlength_demo.sh`)
Demonstrates the RPKI MaxLength misconfiguration documented by Chung et al.
(IMC 2019), who found 84% of RPKI prefixes using MaxLength had it set
incorrectly.

**Why this matters:** A ROA with `maxLength: /25` authorizes both /24 and
/25 announcements from the legitimate AS. This creates an attack surface
where a forged-origin /25 hijack appears RPKI-Valid.

### 3. Forged-Origin Attack (`forged_origin_attack.sh`)
Type-1 hijack where AS400 announces the victim prefix with AS300 appended
as the last hop: `AS_PATH: [400, 300]`. RPKI validates only the rightmost
AS (origin), sees AS300 = authorized, and marks the route as **Valid**.

**Why this matters:** This is the fundamental limitation of ROV documented
in ARTEMIS (Sermpezis et al. 2018) and ROV++ (Morillo et al. NDSS 2021).
Your lab now empirically demonstrates what those papers proved theoretically.
Only BGPsec or ASPA can prevent this class of attack.

### 4. Victim Deaggregation Defense (`victim_deaggregation.sh`)
The victim AS300 announces more specific /25 sub-prefixes to win back
traffic hijacked via an exact prefix attack. Uses BGP's longest-prefix-match
rule as a self-operated reactive mitigation (as described in ARTEMIS).

**Why this matters:** Adds a third defense type to your comparison:
proactive (ROV) vs reactive (deaggregation) vs combined. Also demonstrates
why deaggregation **fails** against subprefix hijacks.

### 5. Extended Evaluation (`evaluate_extended.sh`)
Automated measurement of all attack types against all defense generations,
producing a CSV table for your report charts.

### 6. Peerlock-Style Defense (`apply_peerlock.sh` / `remove_peerlock.sh`)
Adds an operator-style filter on R1 that blocks **forged-origin hijacks** from
AS400 even when RPKI-ROV marks them as **Valid**.

**Why this matters:** This gives you a practical “Generation 3” mitigation to
contrast with ROV (origin-only) and with reactive deaggregation. It also
connects directly to the forged-origin detection theme in NSDI'24 (DFOH).

---

## Integration Steps

### Step 1 — Copy scripts to your main lab

```bash
# From inside the bgp-beyond directory
cp scripts/*.sh ~/bgp-hijack-lab/scripts/
chmod +x ~/bgp-hijack-lab/scripts/*.sh

# Copy GoRTR VRP configs
mkdir -p ~/gortr-data
cp gortr/vrps_safe.json ~/gortr-data/vrps.json
cp gortr/vrps_unsafe_maxlength.json ~/gortr-data/
```

### Step 2 — Run GoRTR (Real RPKI)

```bash
cd ~/bgp-hijack-lab
bash scripts/setup_gortr.sh
```

This will:
- Pull the GoRTR Docker image
- Start GoRTR connected to your Containerlab network
- Configure R1 and R2 to use real RPKI RTR protocol
- Verify the connection shows V/I/N states in the BGP table

### Step 3 — Verify RPKI is active

```bash
docker exec clab-bgp-hijack-r1 vtysh -c "show rpki cache-connection"
docker exec clab-bgp-hijack-r1 vtysh -c "show bgp ipv4 unicast"
```

The BGP table should now show an additional column with V/I/N:
```
   Network          Next Hop    ...  Path
V> 11.0.0.0/24      0.0.0.0         i        ← Valid (ROA matches)
V> 13.0.0.0/24      10.12.0.2       200 300 i ← Valid (ROA matches)
```

---

## Recommended Demo Order


```bash
# ── Phase 1: Establish baseline ────────────────────────────
bash scripts/verify.sh
# Screenshot: all routes valid, legitimate path 200 300

# ── Phase 2: Attack without any defense ────────────────────
bash scripts/start_exact_hijack.sh
# Screenshot: AS400 wins, hijack successful
bash scripts/stop_attack.sh

bash scripts/start_subprefix_hijack.sh
# Screenshot: /25 and /24 coexist, /25 hijacked
bash scripts/stop_attack.sh

# ── Phase 3: ROV (Generation 1 defense) ────────────────────
bash scripts/apply_mitigation.sh
bash scripts/start_exact_hijack.sh
# Screenshot: AS400 blocked by route-map filter
bash scripts/stop_attack.sh
bash scripts/remove_mitigation.sh

# ── Phase 4: Real RPKI (Generation 2 defense) ──────────────
# GoRTR must be running (setup_gortr.sh)
bash scripts/start_exact_hijack.sh
docker exec clab-bgp-hijack-r1 vtysh -c "show bgp ipv4 unicast"
# Screenshot: AS400 route shows (I) INVALID in RPKI column
bash scripts/stop_attack.sh

# ── Phase 5: Forged-origin — THE KEY FINDING ───────────────
bash scripts/forged_origin_attack.sh
docker exec clab-bgp-hijack-r1 vtysh -c "show bgp ipv4 unicast"
# Screenshot: forged route shows (V) VALID — ROV bypassed!
bash scripts/stop_forged_origin.sh

# ── Phase 5b: Peerlock-style defense against forged-origin ──
bash scripts/apply_peerlock.sh
bash scripts/forged_origin_attack.sh
docker exec clab-bgp-hijack-r1 vtysh -c "show bgp ipv4 unicast 13.0.0.0/24"
# Screenshot: forged route from AS400 no longer wins/appears
bash scripts/stop_forged_origin.sh
bash scripts/remove_peerlock.sh

# ── Phase 6: MaxLength vulnerability ───────────────────────
bash scripts/maxlength_demo.sh
# Screenshot: Shows safe vs unsafe maxLength configurations

# ── Phase 7: Victim deaggregation ──────────────────────────
bash scripts/start_exact_hijack.sh
bash scripts/victim_deaggregation.sh
# Screenshot: /25 from AS300 outcompetes /24 from AS400
bash scripts/stop_deaggregation.sh
bash scripts/stop_attack.sh

# ── Phase 8: Full extended evaluation ──────────────────────
bash scripts/evaluate_extended.sh
# Takes 10-15 minutes, produces log + CSV
```

---

## Understanding the Results

### The Three-Generation Defense Framework

Your project now demonstrates three generations of BGP hijack defense:

```
Generation 0 — No Defense
  Exact prefix hijack:     SUCCEEDS (shorter path wins)
  Subprefix hijack:        SUCCEEDS (longest prefix match)
  Forged-origin hijack:    SUCCEEDS (undetectable)

Generation 1 — ROV (Route-Map / Real RPKI)
  Exact prefix hijack:     BLOCKED  ← ROV works here
  Subprefix hijack:        BLOCKED  ← ROV works here
  Forged-origin hijack:    BYPASSED ← ROV's fundamental limitation

Generation 2 — ROV + Victim Deaggregation
  Exact prefix hijack:     RECOVERED (victim /25 outbids attacker /24)
  Subprefix hijack:        INEFFECTIVE (can't outbid /25 with /25)
  Forged-origin hijack:    PARTIAL (depends on path length tie-break)
```

### What Each Attack Demonstrates in Literature Terms

| Attack | ARTEMIS Type | ROV++ Coverage | Real-world Example |
|--------|-------------|----------------|-------------------|
| Exact prefix | Type-0 | Blocked by ROV | Pakistan Telecom/YouTube 2008 |
| Subprefix | Type-0 Sub | Blocked by ROV | AWS Route 53/MyEtherWallet 2018 |
| Forged-origin | Type-1 | ROV++ needed | Visa/Mastercard Russia 2017 |

### The Critical Finding

```
BGP Table entry for forged-origin attack with RPKI active:

V> 13.0.0.0/24   10.14.0.2   400 300   ← RPKI: VALID (!)
*> 13.0.0.0/24   10.12.0.2   200 300   ← RPKI: VALID

ROV sees AS300 as the origin in both announcements.
ROV cannot determine that the path 400 300 is forged.
Only BGPsec (full path signing) or ASPA would catch this.
```

This empirically confirms what Morillo et al. (ROV++, NDSS 2021) showed
via simulation: ROV with partial deployment provides limited protection,
and even full deployment cannot prevent forged-origin attacks.

---

## Report Framing

Use this paragraph structure in your novelty section:

> *"While prior work [Morillo et al. 2021, Sermpezis et al. 2018] has
> demonstrated via simulation that RPKI Route Origin Validation (ROV)
> is ineffective against Type-N forged-origin hijacks, no controlled
> emulation-environment study has empirically demonstrated this limitation
> using modern routing infrastructure. This work implements a three-attack,
> three-generation defense evaluation using FRRouting 9.1 and real RPKI
> via GoRTR, empirically confirming the theoretical findings of ROV++:
> ROV successfully prevents Type-0 origin hijacks but is blind to attacks
> where the legitimate origin AS appears anywhere in the forged AS path.
> We further demonstrate that victim-side prefix deaggregation recovers
> traffic from exact prefix hijacks but is structurally ineffective against
> subprefix attacks, as the attacker's announcement is already more
> specific than any deaggregation the victim can deploy within IETF-
> recommended prefix length limits."*

---

## Connecting to the Papers

| Script | Paper | What you're demonstrating |
|--------|-------|--------------------------|
| `setup_gortr.sh` | Chung et al. 2019 | Real RPKI deployment as described |
| `maxlength_demo.sh` | Chung et al. 2019 | 84% MaxLength misconfiguration finding |
| `forged_origin_attack.sh` | ARTEMIS 2018, ROV++ 2021 | Type-1 hijack evading ROV |
| `victim_deaggregation.sh` | ARTEMIS 2018 | Self-operated prefix deaggregation mitigation |
| `evaluate_extended.sh` | All papers | Empirical measurement vs theoretical claims |
| Forged + RPKI = Valid | ROV++ 2021 | Data-plane hijack despite control-plane validation |

---

## Troubleshooting

**GoRTR not connecting to FRR:**
```bash
# Check GoRTR is running and get its IP
docker inspect gortr --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}'
# Then manually configure FRR with that IP
docker exec -it clab-bgp-hijack-r1 vtysh
# > show rpki cache-connection
```

**Forged-origin route not appearing as Valid:**
- GoRTR must be running and synced (run `setup_gortr.sh`)
- Wait 30-40 seconds after GoRTR starts for FRR to sync VRPs
- Check: `docker exec clab-bgp-hijack-r1 vtysh -c "show rpki prefix-table"`

**Deaggregation not recovering traffic:**
- /25 may be filtered if Containerlab has strict prefix-length rules
- Check: `docker exec clab-bgp-hijack-r1 vtysh -c "show bgp ipv4 unicast 13.0.0.0/25"`
- The route should appear with next-hop 10.23.0.2 (R3/AS300)

**MaxLength demo VRPs not updating:**
- GoRTR refresh interval is 30 seconds — wait 35s after changing the JSON file
- Verify the update: `docker exec clab-bgp-hijack-r1 vtysh -c "show rpki prefix-table"`

---

## File Structure

```
bgp-beyond/
├── README.md                       ← This file
├── scripts/
│   ├── setup_gortr.sh              ← Deploy real RPKI via GoRTR
│   ├── maxlength_demo.sh           ← MaxLength misconfiguration demo
│   ├── forged_origin_attack.sh     ← Type-1 forged-origin hijack
│   ├── stop_forged_origin.sh       ← Clean up forged-origin attack
│   ├── victim_deaggregation.sh     ← Victim reactive defense
│   ├── stop_deaggregation.sh       ← Clean up deaggregation
│   └── evaluate_extended.sh        ← Full 3x3 evaluation matrix
└── gortr/
    ├── vrps_safe.json              ← ROAs with correct maxLength /24
    └── vrps_unsafe_maxlength.json  ← ROAs with dangerous maxLength /25
```

---

## References

These scripts empirically demonstrate findings from:

1. Chung et al., "RPKI is Coming of Age," ACM IMC 2019
   — MaxLength misconfiguration, RPKI deployment statistics

2. Sermpezis et al., "ARTEMIS: Neutralizing BGP Hijacking Within a Minute,"
   IEEE/ACM ToN 2018
   — Attack taxonomy (Type-0, Type-N), deaggregation as mitigation

3. Morillo et al., "ROV++: Improved Deployable Defense against BGP Hijacking,"
   NDSS 2021
   — Data-plane hijacks despite ROV, partial deployment limitations

4. Kowalski & Mazurczyk, "Toward the mutual routing security in wide area
   networks," Computer Networks 2023
   — Countermeasures comparison (Table 3), BGPsec/ASPA requirements

5. Schulmann & Zhao, "Stealth BGP Hijacks with uRPF Filtering," WOOT 2025
   — Security mechanisms weaponized via BGP manipulation
