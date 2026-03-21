# BGP Hijacking Attack & Mitigation Lab
**FRRouting v9.1 + Containerlab | Ubuntu 22.04**

A controlled simulation of BGP prefix hijacking attacks and RPKI-based
mitigations across a multiple topologies. Built for reproducibility on any
Ubuntu 22.04 machine.

---

## Workspace Organization (Simple View)

Use the repository as it is currently organized:

- `bgp-hijack-lab/` -> **v1 (base lab: 4 AS)**
- `bgp-hijack-lab-rpki-v2/` -> **v2 (RPKI-enabled lab)**
- `bgp-beyond-extensions-v3/` -> **v3 (advanced extensions)**
- `bgp-dns-hijack-v4/` -> **v4 (BGP → DNS cache-poisoning chain)**
- `bgp-dns-hijack-v5/` -> **v5 (v4 extension with ROA/ROV checks)**

You do not need to rename or move folders to run the project.

### Which folder should I use?

| Goal | Folder | Topology used |
|------|--------|---------------|
| Run validated baseline lab | `bgp-hijack-lab/` | `bgp-hijack-lab/topology.yaml` |
| Test RPKI lab (still being validated) | `bgp-hijack-lab-rpki-v2/` | `bgp-hijack-lab-rpki-v2/topology.yaml` |
| Run advanced extension scripts | `bgp-beyond-extensions-v3/` | Uses **v1 topology** (`bgp-hijack-lab/topology.yaml`) |
| Run DNS hijack/poisoning chain | `bgp-dns-hijack-v4/` | `bgp-dns-hijack-v4/topology.yaml` |
| Run DNS chain + ROA/ROV checks | `bgp-dns-hijack-v5/` | `bgp-dns-hijack-v5/topology.yaml` |

This file is the main overview. Scenario-specific commands stay in each scenario README.

### Optional future cleanup (not required)


- `labs/base/` -> v1
- `labs/rpki/v2/` -> v2
- `labs/rpki/v3/` -> v3
- `docs/results/evaluations/` -> CSV outputs
- `docs/sessions/` -> session notes/transcripts

---

## Validation Status

| Version | Folder | Status | Notes |
|--------|--------|--------|------|
| v1 | `bgp-hijack-lab/` | Validated | Baseline attacks, mitigation flow, and evaluation are complete and reproducible. |
| v2 (RPKI) | `bgp-hijack-lab-rpki-v2/` | Validated | |
| v3 (Beyond Extensions) | `bgp-beyond-extensions-v3/` | Working | |
| v4 (DNS chain) | `bgp-dns-hijack-v4/` | Working baseline | Demonstrates BGP hijack to DNS cache poisoning chain. |
| v5 (DNS + ROA/ROV) | `bgp-dns-hijack-v5/` | Working | Extends v4 with validator-assisted ROA/ROV checks (not a full RPKI deployment study). |

---

## Important: Switching Between v4 and v5

`bgp-dns-hijack-v4` and `bgp-dns-hijack-v5` both use the topology name `bgp-dns-hijack`.
Switching without cleanup can cause name/state conflicts and failed deployments.

Use this sequence whenever switching versions:

```bash

# In the version folder you used last
sudo containerlab deploy -t topology.yaml --reconfigure
sudo containerlab destroy -t topology.yaml --cleanup

# Move to the other folder (v4 or v5)
# Rebuild/reconfigure there
sudo bash rebuild.sh
```



## Environment

- OS: Ubuntu 22.04
- FRRouting: v9.1.0 (`quay.io/frrouting/frr:9.1.0`)
- Containerlab: v0.54.2
- Docker: CE 28.x

---

## References

- RFC 4271 — BGP-4
- RFC 6811 — BGP Prefix Origin Validation
- Sermpezis et al., ARTEMIS (IEEE/ACM ToN 2018)
- Chung et al., RPKI is Coming of Age (ACM IMC 2019)
- Morillo et al., ROV++ (NDSS 2021)
- Kowalski & Mazurczyk, Routing Security Survey (Computer Networks 2023)

## Acknowledgements
Built using FRRouting (https://frrouting.org) and 
Containerlab (https://containerlab.dev).

Topology concept inspired by the BGP hijacking demonstration originally
described in the Mininet project wiki (2014). This implementation uses
FRRouting 9.1 and Containerlab — entirely different tooling with
original attack scripts, ROV mitigation, and automated evaluation.
