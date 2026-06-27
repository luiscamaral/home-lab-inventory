# Plan — integrate switch24a into the Omada Controller (VM #100)

**Status:** ✅ **Executed 2026-06-19** — switch adopted into Omada V6, standalone port config was
wiped on adoption (caused a LAN outage), then **fully restored** via the Omada controller API + UI.
See [Outcome](#outcome-executed-2026-06-19) for what was actually done and the V6 API gotchas.

## Goal

Bring **switch24a** (TP-Link **TL-SG3428X**, currently **standalone**) under management of the
**Omada Software Controller** on **VM #100** (`omada-controller`, `192.168.32.55`, Omada
**v5.15.8.2**), which runs today but does not yet manage this switch.

## Current state (examined 2026-06-18)

- **Controller (VM #100):** running, `tpeap` active, on `vmbr01` / `192.168.32.55` (admin VLAN),
  2 vCPU / 4 GB, `onboot: 1`. Listening on Omada ports `8088`/`8843`/`8043` (web) and
  `29811-29814` (device management / adoption).
- **Switch:** `192.168.32.39` on the **same admin L2** as the controller (✓ L2 discovery will
  find it). MSTP root bridge; loopback-detection in "alert" mode. Carries VLANs 10 (HOME) /
  28 (SVR) / 105 / 205 + admin. Key ports: `Te1/0/27` = pfSense uplink ("Firewall"),
  `Te1/0/28` = Proxmox ("main-servers"), `Gi1/0/23` = pfSense admin, `Po2` (`Gi1/0/4,6,8`) =
  NAS LAG, `Gi1/0/14` = HomeLAN-UpLink1, `Te1/0/25` = AP-2.5G switch, plus AP/server ports.

## ⚠️ Critical risk — adoption OVERWRITES the switch config

On Omada controllers **before V6** (we run **v5.15.8.2**), adopting a standalone switch
**applies the controller's default config and overwrites all standalone pre-configuration**.
For the core switch that means the VLANs, the pfSense trunk (`Te1/0/27`), the NAS LAG, the port
labels, and the STP/loop settings get **replaced at adoption** → **adopting it would cause
another full LAN outage** unless the Omada Site is pre-built to match the current config exactly.
(V6+ controllers retain standalone config on adoption.)

This is why the **full config backup is mandatory and comes first** — it is both the
source-of-truth for pre-building the Omada Site and the rollback.

## Recommended approach

Because this is the **core switch** (the one behind the recent outages) and v5.15 adoption wipes
config:

- **Option A (recommended): upgrade VM #100 to Omada V6 first**, then adopt with config
  retention → far lower blast radius.
- **Option B: adopt on v5.15 in a planned maintenance window**, with the Omada Site **fully
  pre-built** to match today's config and a tested rollback.

Either way, **do not adopt ad-hoc** — this is a maintenance-window change on the core switch.

## Steps

1. **Backup** the standalone running-config — rollback + the exact VLAN/port/LAG map needed to
   pre-build the Omada Site. _(Blocked on SSH access — see Open items.)_
2. **Firmware** — confirm the switch runs an Omada-SDN-capable build (update if needed; itself a
   maintenance event).
3. **Controller version decision** — upgrade VM #100 to **Omada V6** (recommended) or stay on
   v5.15 (full pre-build required).
4. **Pre-build the Omada Site** from the backup: VLANs (10/28/105/205/admin), per-port profiles
   matching today (pfSense trunk `Te1/0/27`, Proxmox `Te1/0/28`, NAS LAG `Po2`, AP/edge ports),
   and apply the **loop best practice** — STP on uplink/switch-link ports, Loopback-Detection on
   **edge ports only** (this also fixes the root cause of the recent outages).
5. **Maintenance window — adopt:** controller discovers the switch on `.32.x`; enter the switch
   admin credentials; adopt. Expect a brief switch reconfigure/reboot → short LAN disruption.
6. **Verify:** VLAN/trunk forwarding (pfSense uplink up; HOME/SVR/internet), STP topology, no
   loop, every port role correct.
7. **Rollback:** if broken, restore the standalone config from the step-1 backup (and/or
   reset-to-standalone on the switch).

## Benefits

- Centralized, **versioned** config management (history + rollback in the controller).
- Enables the **`omada-exporter`** (Phase C.2 in `docs/monitoring-coverage-gap-2026-05-07.md`).
- Consistent STP/LPD profiles → addresses the loop root cause structurally.

## Open items / decisions needed

- **Full running-config backup (step 1)** — blocked: the switch's Access-Security block survived
  the password reset. Clear the block, or paste `show running-config`, so the backup + Site
  pre-build can be built.
- **Option A (upgrade to V6)** vs **Option B (pre-build on v5.15)**.
- **Maintenance-window timing** (core-switch change, expect a brief outage during adoption).

## Sources

- [Omada — adopting a switch overwrites pre-V6 standalone config](https://support.omadanetworks.com/us/document/13032/)
- [Omada — how to adopt a switch to the controller](https://support.hostifi.com/en/articles/8001422-omada-how-to-adopt-a-switch-to-the-controller)
- [TP-Link — TL-SG3428X downloads / Omada compatibility](https://www.tp-link.com/us/support/download/tl-sg3428x/)

## Outcome (executed 2026-06-19)

Upgraded the controller VM #100 to Omada V6 (6.2.10.17), then adopted switch24a. **V6 "config
retention" did NOT apply** — the switch was standalone (no prior Omada config), so adoption pushed
the default profile and **wiped all port/VLAN/LAG config**, isolating the pfSense `ix0` trunk →
full LAN outage (HOME/SVR/IoT + Vault unreachable).

### Recovery (Omada controller API, then UI for the LAG)

1. **Created the VLANs** as `purpose: "vlan"` networks (10 Home, 28 Servers, 105 GuestWifi,
   205 IoT, 4094 None). The site's "All" port profile auto-tags every network, so creating them
   immediately re-tagged the uplinks and **ended the outage** (pfSense trunk back).
2. **Per-port restore** — created custom port profiles and assigned each port per the
   `sysConfigBackup-2026-06-18.cfg` map:

   | Profile | Native | Tagged | Ports |
   |---|---|---|---|
   | `Trunk-v2` | v1 | 10,28,105,205 | 27 pfSense, 28 Proxmox, 25 AP-switch, 1 AP |
   | `Access-v10` | v10 | — | 2 Synology-0, 14 HomeLAN, 24 |
   | `AP-105-205-v2` | v1 | 105,205 | 3,5,7 APs |
   | `Isolation-4094` | v4094 | — | 9,11,13,15,17–21 |
   | `Default` | v1 | — | 10 xen0, 16 XS-iLO, 22, 23 pfSense-Admin |
   | `Xen1-v2` | v10 | 28 | 12 xenserver-1 |
   | `HomeOffice-v2` | v10 | 4094 | 26 HomeOffice |
   | `NAS-LAG` | v4094 | 1,10 | LAG2 members 4,6,8 |

3. **NAS LAG (`Po2` → `LAG2`)** — `Gi1/0/4,6,8`, **Active LACP**, profile `NAS-LAG` (native v4094,
   tagged v1+v10 to match the Synology bond's `bond0.1`=.32.50 admin + `bond0.10`=.1.50). The bond
   re-aggregated: all slaves on one Aggregator ID, churn cleared, all four NAS IPs reachable.

### Omada V6 controller API gotchas (internal `/api/v2`, not the Open API)

- **Networks** must be `purpose: "vlan"` (no Omada gateway in the site); `purpose: "interface"`
  fails with `-33515 "LAN interfaces could not be none"`. Required field: `igmpSnoopEnable`.
- **Port VLANs are driven by the profile (`profileId`), not per-port override fields** —
  `profileVlanOverrideEnable` / `tagNetworkIds` set on a port silently revert. Assign a profile.
- **`networkTagsSetting`: `0` = tag All, `1` = tag None, `2` = Custom list.** A custom-tagged
  profile needs `2`; `1` ignores `tagNetworkIds` (this silently re-broke the trunk once mid-restore).
- **Auto-created per-network profiles** (Home, Servers, None, …) are **not port-assignable**
  (`-1001`); make custom equivalents.
- **LAGs are GET-only via the API** — `POST/PATCH/PUT /switches/{mac}/lags` return
  `-1600 Unsupported request path` (or a no-op "Success"). Create LAGs in the **UI**: port edit →
  Port Configuration = Custom → Operation = Aggregating → LAG ID + LACP mode + member ports.
- UI cert is self-signed; navigate via `http://<host>:8088` (redirects to `:8043`) to avoid the
  Chromium cert block.

Creds: Vault `secret/homelab/omada-controller` (`lamaral`); switch login `secret/homelab/switch24a`.

### Post-restore gap review + Tier-1 hardening (2026-06-19)

An exhaustive 9-dimension review (Omada live vs backup, each finding adversarially verified) found
the **data plane correct** (VLANs/trunks/LAG match, network healthy) but gaps in the layers adoption
silently dropped. **Tier-1 fixes applied and verified (no outage):**

| Fix | Detail |
|---|---|
| STP + loop-guard | `spanningTreeEnable + edgePort + loopProtect` on all 8 assigned profiles. Edge = no link-up blip on host-facing ports; a port that receives BPDUs auto-converts to non-edge so real uplinks/loops are STP-blocked. Loopback-detection remains the fast backstop. |
| Jumbo frames | switch jumbo `1518` → **`9216`** (restores NAS / 10G storage throughput) |
| IGMP snooping | enabled on Home / Servers / GuestWifi / IoT networks |
| NTP | controller VM 100 `systemd-timesyncd` → **pfSense `192.168.32.33`** (public fallback kept). The switch gets pfSense time via the controller — Omada SDN has no per-device NTP UI. |
| SNMP | SNMPv1/v2c enabled; community in Vault `secret/homelab/switch24a` field `snmp_community` — feeds the homelab `snmp_exporter` |
| Syslog | remote log → **`192.168.1.50:514`** |
| LLDP | enabled (topology) |

API notes for next time: networks/profiles PATCH need the **minimal create-style body** (full GET
object → `-1001`); jumbo via the switch-object PATCH; **SNMP/NTP are not writable via `/api/v2`**
(`-1600`/`-1001`) — SNMP set in the UI (Network Config → Site Settings → SNMP; community must be
10–64 chars with letters+numbers+symbol and no consecutive repeats), NTP at the controller OS.

**Deferred (Tier 2/3 — confirm-before-change, can touch live devices):** port labels still `PortN`;
tagged-only trunks (27/28) carry native VLAN 1; port 12/24 VLAN edge cases; per-port isolation +
flow-control; device hostname. WAN VLANs 21/22 and the switch's old `Admin` DHCP pool are
intentionally **not** restored (orphan VLANs never on a port / pfSense owns DHCP).
