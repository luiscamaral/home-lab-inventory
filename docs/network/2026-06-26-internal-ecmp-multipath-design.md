# Internal multipath (ECMP) design — pfSense ↔ lab-router

Status: **DESIGN / PLAN** (nothing applied). Authored 2026-06-26.

Goal (user): internal networks should have **more than one path** — not every internal route
funnelled through pfSense as a single chokepoint. Build real path redundancy (and, where the
topology allows, equal-cost load-sharing) on the BGP fabric.

## 1. Current state (verified live 2026-06-26)

- pfSense (AS65000) ⇄ lab-router (AS65010): **one** eBGP session over the SVR leg
  (`192.168.48.1` ⇄ `192.168.48.2`, `ix0.28`). Established.
- pfSense learns **`192.168.30.0/24` (cluster) via `192.168.48.2`** — single next-hop.
- pfSense reaches **`192.168.100.0/24` (LAB)** via a static FRR route to Proxmox `192.168.7.10`
  (distance 1, beats BGP). Single path, no backup.
- lab-router has **three** homelab-facing legs: SVR `192.168.48.2`, HOME `192.168.7.2`,
  LAB `192.168.100.2` — but only the SVR leg carries BGP today.
- `filter/bypassstaticroutes = true` already set on pfSense (tolerates same-interface
  asymmetric replies — relevant for ECMP).
- pfSense **advertises nothing**; it only accepts `CLUSTER-IN` (`192.168.30.0/24`,
  `10.244.0.0/16`).

So every internal prefix has exactly **one** path today. That is what the user wants to change.

## 2. The hard topology constraint (read this first)

ECMP needs ≥2 equal-cost next-hops to the **same** prefix. The leaf segments are **single-homed**:

- **Cluster `192.168.30.0/24`** lives on `vmbr30`, an internal Proxmox bridge whose **only**
  router is the lab-router (`.30.1`). Nothing else legs into `vmbr30`.
- **LAB `192.168.100.0/24`** lives on `vmbr0`, whose gateway is **Proxmox `.100.1`** (not the
  lab-router).

You cannot ECMP **into** a segment that has one gateway. What you _can_ multipath is the
**inter-router fabric** — the pfSense ↔ lab-router transit. That removes pfSense as the single
path to the cluster and gives link/router failover. That is the achievable, high-value win.

## 3. Design — dual BGP sessions (SVR + HOME legs)

Bring up a **second** eBGP session between the same two routers over a **different L2 path**:

| Session | pfSense end | lab-router end | L2 path |
| ------- | ----------- | -------------- | ------- |
| A (exists) | `192.168.48.1` (`ix0.28` SVR) | `192.168.48.2` | SVR VLAN 28 |
| B (new) | `192.168.4.1` (`ix0.10` HOME) | `192.168.7.2` | HOME VLAN 10 |

Both are eBGP to AS65010 with equal AS_PATH length ⇒ the cluster prefix `192.168.30.0/24` is
learned over **both** → genuine ECMP across two physically distinct links, with automatic
failover if either link/session drops.

### 3.1 pfSense FRR additions (`frrglobalraw`)

```text
router bgp 65000
 bgp bestpath as-path multipath-relax        # eBGP multipath across same neighbor-AS
 neighbor 192.168.7.2 remote-as 65010
 address-family ipv4 unicast
  maximum-paths 2                            # install up to 2 eBGP next-hops
  neighbor 192.168.7.2 activate
  neighbor 192.168.7.2 soft-reconfiguration inbound
  neighbor 192.168.7.2 prefix-list CLUSTER-IN in
 exit-address-family
```

`multipath-relax` is **required**: without it FRR treats differing AS_PATHs as non-multipath;
even with the same neighbor-AS it is the safe switch for eBGP ECMP.

### 3.2 lab-router FRR additions (`cloud-init/lab-router.yaml` → `frr.conf`)

```text
router bgp 65010
 bgp bestpath as-path multipath-relax
 neighbor 192.168.4.1 remote-as 65000
 address-family ipv4 unicast
  maximum-paths 2
  neighbor 192.168.4.1 activate
 exit-address-family
```

For **bidirectional** ECMP the return traffic must also have two paths. Today the lab-router
default-routes to pfSense `.48.1` (SVR only). To make returns multipath, pfSense should
**advertise** the homelab prefixes (or a default) to the lab-router over **both** sessions, and
the lab-router runs `maximum-paths 2`. Decision needed (see §6): advertise a `0.0.0.0/0` default
vs. specific homelab supernets.

## 4. Optional — add LAB `192.168.100.0/24` to multipath

Lower priority and more fragile. The lab-router can advertise `192.168.100.0/24` (it has the
`.100.2` leg); add `seq 15 permit 192.168.100.0/24` to `CLUSTER-IN`. But:

- The lab-router is **not** LAB's gateway (Proxmox `.100.1` is). A flow steered via the lab-router
  gets its **return** via Proxmox `.7.10` → cross-interface asymmetry on pfSense. `bypassstaticroutes`
  helps, but this is the exact masquerade/asymmetry trap that broke LAB egress on 2026-06-17.
- Keep the **static route distance 1** so direct-via-Proxmox stays primary; the BGP path is a
  **floating backup** only (raise its distance / lower local-pref so it never load-shares, only
  takes over on failure). Do **not** ECMP LAB unless return-path symmetry is solved.

Recommendation: ship §3 first; treat LAB as **backup-path only**, not active ECMP.

## 5. Verification (after a future apply)

```sh
# pfSense — two next-hops installed for the cluster prefix
ssh pfsense 'vtysh -c "show ip route 192.168.30.0/24"'      # expect 2x via .48.2 and .7.2
ssh pfsense 'vtysh -c "show ip bgp 192.168.30.0/24"'        # expect "multipath" on both
ssh pfsense 'vtysh -c "show bgp summary"'                    # both neighbors Established
ssh pfsense 'netstat -rn4 | grep 192.168.30'                # FIB shows both / multipath
# failover test: drop session A, confirm cluster still reachable via B, then restore
```

## 6. Open decisions

1. Return-path: advertise default `0.0.0.0/0` to lab-router, or specific homelab supernets?
2. LAB `.100/24`: backup-only floating route (recommended) vs. active ECMP (needs symmetry work).
3. Per-flow vs per-packet hashing on pfSense FRR/FIB (default per-flow is correct — avoid
   per-packet reordering).

## 7. Risks + rollback

- **Critical — no physical path diversity.** Both sessions share one physical trunk at _both_
  ends: pfSense `ix0.28` (SVR) + `ix0.10` (HOME) are VLANs on the **same `ix0` 10G trunk**, and
  the lab-router's SVR + HOME legs both ride Proxmox **`ens1f0`**. The **STP-island outage
  (2026-06-18)** dropped all `ix0` LAN VLANs at once — it would kill **both** BGP sessions
  simultaneously. So this dual-session ECMP buys protection against a single BGP-session / daemon
  / per-VLAN fault, **not** against the trunk outage that actually occurred. For real link
  resilience, peer the second session over a **physically distinct NIC** (e.g. a 1G `igc*` port
  on pfSense ↔ an `eno*`-backed Proxmox bridge on the lab-router), accepting lower bandwidth on
  the backup path. Decide whether the goal is load-share (logical is fine) or survive-a-link-loss
  (needs physical diversity).
- FRR is a separate daemon; a bad config cannot break pfSense WAN/pf/SSH (proven during bring-up).
  Restart via `frr_generate_config()` — **not** `service frr restart` (hangs on this box).
- pfSense `write_config()` is **still broken** (`cleanup_backupcache` int-return); any `config.xml`
  write needs the DOMDocument bypass until that is fixed. **Fix write_config first** — it is the
  real blocker for clean changes here.
- Rollback: remove neighbor `192.168.7.2` + `maximum-paths`/`multipath-relax`, `frr_generate_config()`.
  Pre-change config backup mandatory (see `pfsense-frr-bgp.md` rollback section).

## 8. Sequencing

1. **Fix pfSense `write_config()`** (prerequisite — see `terraform/lab-network/pfsense-frr-bgp.md`).
2. Apply §3 (dual session + maximum-paths) — cluster ECMP + inter-router failover.
3. Decide §6.1, add return-path advertisement; confirm bidirectional ECMP.
4. (Optional) §4 LAB backup-path floating route.

> Not part of this work: the UniFi-controller outage (2026-06-26) was **L2** (tagged-VID1/eno2
> dead after the switch24a Omada rebuild), unrelated to BGP — already restored by re-homing VM 122
> to the untagged ADMIN bridge. See `inventory/virtual-machines.md`.
