# 🛡️ LAN resilience redesign — replaces the ECMP/BGP multipath plan

**Date:** 2026-10-24 · **Status:** DESIGN (nothing applied) · **Supersedes:**
[`2026-06-26-internal-ecmp-multipath-design.md`](2026-06-26-internal-ecmp-multipath-design.md)

Written during the 2026-10-24 `ix0` hard outage (all LAN VLANs down, 23:41 → about 00:16, restored
by a physical reseat plus pfSense reboot). After restoration the link was **still degraded** (0.1 %
loss, about 260 remote faults/s), so the hardware fault remains. Every claim below was checked
against the repo or the live network that night.

**Design principle:** the **ADMIN network (`igc3`, 192.168.32.32/27)** is the only network that
survived both outages. It becomes the independent **management and control plane** (§3A). The
**data plane** gets its own second link (§3) so the two never share a failure.

---

## 1. Why the old plan is replaced

The 2026-06-26 plan was **never applied**. A live check on 2026-10-24 found one BGP neighbor
(`192.168.48.2`, state `Active`, `never` established). Even if it had been applied, it would not
have helped in either real outage:

| Gap | Evidence |
|---|---|
| Both BGP sessions ride **the same physical link** (`ix0.28` + `ix0.10`, both on `ix0`) | Its own §7 says this. Both outages (2026-06-18 STP block, 2026-10-24 no-carrier) killed every `ix0` VLAN at once. |
| It only covers the **Talos lab cluster** (`192.168.30.0/24`) | No Pi-hole, DNS, VM or client routing is in scope. |
| BGP cannot reroute **clients** | Clients have one default gateway (pfSense `.1` per VLAN). If pfSense's LAN side is gone, no BGP path between routers can reach them. |
| No DNS fallback reachable from ADMIN | 2026-10-24, from ADMIN: `192.168.100.254`, `.59.50`, `.4.236` and `.4.1` all failed. Only pfSense `192.168.32.33` answered. |

**What actually failed, both times:** the single pfSense ↔ switch24a cable (`ix0` ↔ `Te1/0/27`).
Fixing that one link is the highest-value change. BGP multipath is a later, optional step.

## 2. Failure model (what we design for)

| # | Failure | Seen? | Covered by |
|---|---|---|---|
| F1 | Trunk link hard down: cable, optic, port, NIC port | **Yes ×2** (2026-06-18, 2026-10-24) | §3 P0 |
| F2 | Trunk link up but lossy (remote faults, 0.1–55 % loss) | **Yes**, ongoing since 2026-06 | §3 P0 + §6 P3 |
| F3 | Local names/DNS lost when pfSense's LAN side is down | **Yes** (2026-10-24) | §3A + §4 P1 |
| F4 | Credentials needed to recover are unreachable (Vault is behind `ix0`) | **Yes** (switch admin password) | §3A + §5 P2 |
| F4b | Servers (dockermaster, Vault, cluster) unreachable for management when `ix0` is down | **Yes** (2026-10-24) | §3A |
| F5 | Automation makes an outage worse (watchdog bounces) | **Yes** (2026-10-24) | §6 P3 |
| F6 | pfSense box dead (power, disk, OS) | No | §7 P4 (optional, expensive) |
| F7 | switch24a dead | No | Out of scope: accepted single point of failure |

## 3. P0 — Second physical LAN link: `lagg0` failover (`ix0` + `igc2`)

### Constraint
switch24a has only **4× SFP+** ports and all are in use (`Te1/0/25` AP, `26` HomeOffice,
`27` Firewall, `28` main-servers). A 10G LACP pair `ix0`+`ix1` is **not possible** without freeing
an SFP+ port or replacing the switch.

### Design
- pfSense: create `lagg0`, **protocol `failover`**, members **`ix0` (primary, 10G)** and
  **`igc2` (secondary, 2.5G NIC → 1G switch port)**. `igc2` is spare today (no carrier).
- Re-parent the four VLANs `10, 28, 105, 205` from `ix0` to `lagg0`. Interface names change
  (`ix0.10` → `lagg0.10`), but the IPs, rules and DHCP stay the same.
- switch24a: a free 1G port (candidates: `Gi1/0/19–22`; confirm in the UI) configured **the same
  as `Te1/0/27`**: tagged `10,28,105,205`, no VLAN 1, same port-isolation list, `spanning-tree`
  plus `guard loop`. **Do not** put it in a LACP channel-group. Failover mode needs no switch-side LAG.
- No loop risk: pfSense does not bridge, and failover mode transmits on the active port only.
  Keep the FreeBSD default `net.link.lagg.failover_rx_all=0`.

### Behaviour
| Event | Result |
|---|---|
| `ix0` loses carrier (both outages) | Traffic moves to `igc2` within about 1 s. LAN stays up at **1 Gb/s**. No bounce needed. |
| `ix0` up but lossy (F2) | lagg does **not** fail over by itself (it sees carrier). The watchdog **demotes** `ix0` with `ifconfig ix0 down` instead of bouncing it (§6). |
| `ix0` repaired | Traffic returns to the primary automatically. |

1 Gb/s is enough for a degraded state: WAN1 delivers about 200–300 Mb/s in practice and the
igc0 link is 2.5G. Only NAS/inter-VLAN bulk transfers notice.

### Future upgrade
If an SFP+ port is freed (or a switch with more SFP+ ports is bought), change to
`lagg0 = LACP(ix0, ix1)` at 20G and keep `igc2` as a third member in a separate failover lagg.

### IaC (rule 1 — no hand edits)
pfSense interfaces and laggs have **no IaC path today**. Add one before applying:
`pfsense/interfaces.yml` (lagg + VLAN parents) and `scripts/sync-pfsense-interfaces.py` using
REST API v2 (check its lagg/VLAN endpoint coverage first; fall back to a reviewed, versioned
php script if it lacks them). Record the switch port change in `docs/network/switch24a/`.
**Prerequisite from the old plan still applies:** check whether `write_config()` is still
broken (`cleanup_backupcache`) and fix it first.

### Cut-over (maintenance window, about 2–5 min LAN outage)
1. Watchdog `nobounce` flag set. Take a config backup.
2. Configure the switch port. Patch `igc2` and confirm link with no VLANs on it yet.
3. Apply `interfaces.yml`: create lagg0 and move the VLANs. **Run it from ADMIN (`igc3`)**, which
   is not affected.
4. Verify: `ifconfig lagg0` (both members, `ix0` ACTIVE); clients on every VLAN; BGP to `.48.2`.
5. **Failover test:** pull the `ix0` cable. Expect under 2 s loss and traffic on `igc2`. Re-plug.
6. Rollback: re-parent the VLANs to `ix0` from the backup or the previous `interfaces.yml`, then
   apply from ADMIN.

## 3A. P0b — ADMIN network as the independent management and control plane

### Why ADMIN qualifies (verified 2026-10-24)

| | Data plane (today) | ADMIN plane |
|---|---|---|
| pfSense port | `ix0` (VLANs 10/28/105/205) | **`igc3`** `192.168.32.33/27` |
| Switch port | `Te1/0/27` | **`Gi1/0/23`**, VLAN 1 untagged |
| Proxmox port | `Te1/0/28` → `ens1f0` | **`eno1`** → `vmbr01` `192.168.32.61` |
| Isolation | `Te1/0/27-28`: `no switchport general allowed vlan 1` | VLAN 1 never touches the data trunks |
| 2026-10-24 outage | ❌ down | ✅ Mac `.32.59` → pfSense `.33`, switch `.39` reachable throughout |

Already on ADMIN: pfSense `.33`, switch24a `.39`, UniFi controller `.41`, Omada `.55`,
Proxmox `.61` (`vmbr01`/eno1) and `.62` (`vmbr1`). DHCP pool `.55–.59`.

### What moves onto ADMIN (management and control plane only)

| Add | How | Covers |
|---|---|---|
| **dockermaster management NIC** | Add a `vmbr01` NIC to the VM with a static IP in `.32.40–.54`; sshd listens there | F4b: manage Docker when `ix0` is down |
| **Vault on ADMIN** | Publish Vault also on dockermaster's ADMIN IP (`8200`, TLS), or a small Vault standby/raft follower on a Proxmox VM `vmbr01` NIC | F4: break-glass secrets reachable |
| **ADMIN Pi-hole** (on-link resolver) | A small Pi-hole LXC/VM with a `vmbr01` NIC, static `.32.53`; same local records as the others | F3 for ADMIN clients and recovery work |
| **lab-router ADMIN leg + BGP backup session** | lab-router gets a `vmbr01` NIC (`.32.50`); eBGP `192.168.32.33` ⇄ `.32.50` as a **floating backup** (lower local-pref / AS-path prepend, never ECMP) | Cluster `192.168.30.0/24` reachable from pfSense/ADMIN when `ix0` is down |
| **switch24a SSH** | `user access-control ip-based 192.168.32.32 255.255.255.224 ssh` | Read port and error state from the CLI |
| Monitoring of `ix0` | Scrape the `ix0` metrics over ADMIN (Prometheus target on pfSense `.33`) | Alerts keep flowing during a trunk outage |

### What does NOT go on ADMIN

- **Not the data-plane backup trunk.** Making `igc3` a lagg member (or carrying VLANs 10/28/… on
  it) would make ADMIN share failures with the data plane: a lagg or VLAN mistake would cut off the
  out-of-band path we just relied on. ADMIN is also only 1G and a /27. The data plane uses `igc2` (§3).
- **No user or IoT traffic.** ADMIN stays a small trusted /27. Every new leg is firewalled:
  - pfSense ADMIN rules: allow only SSH/HTTPS/DNS/Vault/BGP to the new IPs.
  - lab-router nftables: allow only BGP from `.33` on the ADMIN leg, with **no forwarding**
    between ADMIN and the cluster except pfSense-sourced traffic.
  - Multi-homed VMs (dockermaster, lab-router) must **not route or forward** between ADMIN and
    their other legs (`net.ipv4.ip_forward` scoped, `rp_filter=1` on the ADMIN NIC).
- **Address plan:** reserve `.32.40–.54` for static infra (outside DHCP `.55–.59`); record it in
  `pfsense/host-overrides.yml` and `inventory/`.

### Asymmetric routing caveat
A host with legs on ADMIN and SVR replies to ADMIN clients through its default route (SVR) unless
configured otherwise. Give each multi-homed VM **source-based policy routing** (a separate table
for the ADMIN source address) so ADMIN replies leave by ADMIN. Without this, ADMIN access to
the VM breaks exactly when SVR is down, which defeats the purpose.

### IaC
- Proxmox VM NICs: `terraform/` (bpg provider; see LIVE-FACTS for the root-SSH limitation).
- lab-router: `terraform/lab-network/cloud-init/lab-router.yaml` (FRR + nftables).
- Pi-hole and Vault publishing: `terraform/portainer`.
- pfSense ADMIN rules and BGP neighbor: add to the new pfSense IaC path (§3) — no hand edits.
- switch24a: config change recorded in `docs/network/switch24a/` (plus a config backup).

## 4. P1 — DNS that does not need pfSense to route

Goal: **local** names and cached answers keep working when pfSense's LAN side is down. Internet
names will fail anyway in that state, because the WAN is behind pfSense too.

1. **One reachable resolver per VLAN, handed out first by DHCP.** A client should reach its first
   DNS server without routing through pfSense:
   - HOME `ix0.10`: `192.168.4.236` (on-link) ✅ already exists; make it DNS #1.
   - SVR `ix0.28`: `192.168.59.50` (on-link) ✅.
   - ADMIN `igc3`: **none on-link today.** After §3A, use the ADMIN Pi-hole `192.168.32.53` as #1
     and pfSense `192.168.32.33` as #2 (the only resolver that worked on 2026-10-24).
   - LAB `192.168.100.254` is reached **through pfSense** (`ix0.10` → Proxmox `.7.10`). Never list
     it as anyone's first resolver outside LAB.
   - IoT / GUEST: confirm in `scripts/sync-pfsense-dhcp-options.py`.
2. **pfSense resolver as #2 everywhere**, at its address on the client's own VLAN.
3. Pi-holes keep local records and conditional forwarding so `*.lcamaral.com` names resolve from
   cache and local data during a pfSense outage. Verify the Pi-hole upstream order.
4. **Not recommended:** BGP-announced shared (anycast) DNS addresses. Clients still need pfSense to
   reach any non-on-link address, so it adds complexity without covering F3.

IaC: DHCP DNS options go through `scripts/sync-pfsense-dhcp-options.py` and Pi-hole config through
`terraform/portainer`.

## 5. P2 — Out-of-band recovery access

2026-10-24 showed recovery depends on the outage itself: the switch password lives in Vault, and
Vault (`192.168.59.25`) sits on SVR behind `ix0`.

- **ADMIN `igc3` is the out-of-band path.** It worked (Mac `192.168.32.59` → pfSense `.32.33`,
  switch24a `.32.39`). Document it as the official break-glass path, and extend it to
  dockermaster, Vault and the cluster (§3A).
- Add `ssh` aliases in `~/.ssh/config` that use the ADMIN IPs (`pfsense-oob`, `dockermaster-oob`,
  `proxmox-oob`) so recovery never depends on HOME/SVR DNS or routing.
- **Break-glass credentials** must be available offline: switch24a admin, pfSense console, Proxmox,
  and the Vault unseal/root details. Keep them in macOS Keychain or a password manager, synced
  from Vault by a script and noted in `secret/homelab/*` README. Never commit them to the repo.
- Enable switch24a **SSH** from ADMIN (add the `ssh` entry to `user access-control`, see
  `switch24a/README.md`) so port state can be read without the web UI.
- Physical: keep a spare **Intel-coded 10G DAC/SR pair** at the rack.

## 6. P3 — `ix0-watchdog.sh` fixes (bugs found 2026-10-24)

| Bug | Evidence (pfSense log 2026-10-24) | Fix |
|---|---|---|
| `testbounce` does not coordinate with the running daemon | Manual bounce at 23:41; the daemon bounced again at **23:44:45** (inside the 10-min floor, during testbounce's settle) | Shared lock file; the daemon re-reads `LAST_BOUNCE_TS` from state each loop; `testbounce` pauses the daemon until its verdict |
| Blackout bounces ignore `DISARMED` and have **no cap** | Bounces at 23:44:45 and 23:55:03, then every 10 min indefinitely | Blackout bounces count toward the daily cap; stop after N with no carrier |
| Bouncing on a hard **no-carrier** link has no upside | Reboot and bounces did not restore the link; remote faults kept rising | If there is still no carrier after one bounce, stop and raise an alert |
| `testbounce` "healthy" check under-samples | Tool: 0 % loss; 5,000-packet sample: **0.1–0.7 %** | Larger or longer sample, or use `remote_faults` rate as a second signal |
| After P0 | — | Change the degraded action from **bounce** to **demote `ix0`** (lagg fails over to `igc2`); never bounce the only active lagg member |

Code lives in `pfsense/scripts/ix0-watchdog.sh` and is deployed with `scripts/sync-pfsense-scripts.py`.

## 7. P4 (optional) — surviving a dead pfSense box

Only a **second firewall** covers F6: pfSense HA, with two boxes, CARP VIPs as each VLAN's `.1`,
and pfsync. Expensive (hardware, WAN handling, config sync). BGP or anycast cannot replace it,
because clients only know one gateway. Consider it only after P0–P3, if F6 ever happens.

## 8. Old ECMP/BGP plan — what survives

**Replaced by the §3A ADMIN backup session.** Session B moves from HOME (`ix0.10`, same physical
link) to ADMIN (`igc3` ⇄ lab-router `vmbr01`/eno1), which gives a physically separate path. Make it
a **floating backup**, not ECMP: ADMIN must not carry cluster bulk traffic while `ix0`/`lagg0` is
healthy. Keep `multipath-relax`/`maximum-paths` out unless load-sharing is ever needed.

Also found 2026-10-24: the existing session A (`.48.1` ⇄ `.48.2`) shows `Active / never`, which
means it is **not established** regardless of tonight's outage. Fix it before adding session B.

## 9. Order and effort

| Step | Change | Outage | Effort |
|---|---|---|---|
| 0 | Repair `ix0` (cable, switch port, or X520 port); set `nobounce` | done in the incident | — |
| 1 | P3 watchdog fixes (branch + sync) | none | S |
| 2 | P2 break-glass credentials + switch SSH from ADMIN + `*-oob` SSH aliases | none | S |
| 3 | §3A ADMIN legs: dockermaster mgmt NIC, ADMIN Pi-hole, Vault on ADMIN (with policy routing + firewall) | short per-VM NIC hot-add | M |
| 3b | P1 DHCP DNS ordering (ADMIN Pi-hole first on ADMIN) | none (applies at lease renewal) | S |
| 3c | Fix BGP session A; add lab-router ADMIN leg + floating backup session | none | M |
| 4 | P0 IaC path for interfaces (`interfaces.yml` + sync) | none | M |
| 5 | P0 lagg0 cut-over + failover test | **2–5 min**, window + approval | M |
| 6 | Re-evaluate §8 / §7 | — | — |
