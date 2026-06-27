# RCA — LAN trunk (pfSense `ix0`) outage — 2026-06-18

**Status:** ✅ RESOLVED (link flap on `ix0`; verified end-to-end). Trigger needs switch-side
confirmation (see Follow-ups).

## Summary

All LAN-side VLANs trunked to pfSense over its 10G interface **`ix0`** — HOME (VLAN 10),
IoT, SVR (VLAN 28), VLAN 105/205 — lost connectivity to pfSense **simultaneously**, while
pfSense itself (WAN `igc0`, admin `igc3`) stayed healthy with working internet and DNS.
**Root cause: the switch held pfSense's `ix0` trunk port in a non-forwarding (STP
discarding/blocked) state.** pfSense `ix0` RX froze at ~0 pkts with the optical link up and
the NIC reporting zero errors. A **link flap on `ix0` restored it** — recovery completed
~30–50 s later (one STP listening→learning→forwarding cycle). That a flap fixed it proves the
cause was a **transient/recoverable switch-port L2 state, not a hard config error** (a
LACP/VLAN-membership mistake would not self-heal from a flap), and **not** pfSense, the NIC,
a physical event, or any lab-network (FRR/BGP/lab-router) change.

## User impact

- HOME + IoT devices: no internet (couldn't reach their gateway on pfSense).
- SVR (Docker hosts `.48.44/.45/.46`, lab-router `.48.2`): couldn't reach pfSense `.48.1`.
- pfSense admin (skynetAdmin VLAN on `igc3`) + WAN: unaffected → pfSense stayed reachable.

## Timeline (pfSense local time)

- 06-16 17:16–17:27 — FRR pkg + BGP + same-iface-bypass (lab bring-up). _L3, prior day._
- 06-17 09:42–14:03 — HOMELAB gw disable, static route disable, FRR LAB route. _L3, prior day._
- **06-18 ~08:00** — last normal LAN ARP on `ix0.28`; then silence (forwarding stopped).
- 06-18 ~08:2x — BGP pfSense↔lab-router dropped to `Connect`.
- 06-18 09:0x–09:2x — diagnosis; `ix0` RX confirmed frozen (0 in 4s).
- **06-18 ~09:2x — `ix0` flapped (down 4 s / up); STP reconverged (~30–50 s); all LAN VLANs +
  BGP + internet restored.**
- **No pfSense config change on 06-18.** Last config change: 06-17 14:03.

## Evidence (measured)

1. **pfSense healthy throughout:** WAN default via `192.168.28.1`; ping 8.8.8.8 = 0% loss;
   unbound resolved `google.com`; all `ix0` VLANs configured + active; reachable via `igc3`.
2. **`ix0` RX frozen (before):** Ipkts `836749846 → 836749846` (0 in 4 s) while sibling `igc3`
   received 41 in the same window. `dev.ix.0.watchdog_events=0`, all `queueN.rx_discarded=0`,
   `rx_missed_packets=0`, `Ierrs=0`. Link `10Gbase-SR full-duplex`, active. → NIC not hung.
3. **Bidirectional non-forwarding:** pfSense emitted its own ARP but saw no replies / no other
   host on `ix0.28`/`ix0.10`; Proxmox saw the Docker hosts' ARP on `vlan28` but never
   pfSense's `.48.1`. Frames crossed in neither direction (Docker hosts on `vmbr28`).
4. **Island = exactly `ix0`:** Docker hosts reached each other + the lab-router at 0% loss
   (intra-`vmbr28`, no switch hop); only the cross-switch path to pfSense `ix0` was dead.
5. **No `ix0` link-state event** in logs → the link never lost carrier (no cable/SFP unplug).
6. **Recovery (after flap):** `ix0` RX `2573 pkts/3 s`; pfSense → `.48.44/.45/.46/.48.2` all
   `ok`; BGP Established (up 0:00:55); from dockermaster: gateway + internet 0% loss, DNS OK,
   gateway ARP `REACHABLE`. Recovery lagged the flap by one STP convergence cycle.

## Root cause

The switch placed pfSense's `ix0` trunk port into an **STP discarding/blocking (non-forwarding)
state**. Because every LAN VLAN converges on that single trunk, all dropped at once. The link
flap forced the port to re-run STP, which returned it to **forwarding** after the standard
~30–50 s convergence — restoring service. The flap-fix + convergence-delay signature is
diagnostic of an STP/port-state issue rather than a persistent misconfiguration.

## Ruled out (with evidence)

- **pfSense NIC RX-hang** — clean driver counters (watchdog/missed/discard all 0).
- **pfSense config change** — last change 06-17 14:03; none on 06-18.
- **Physical (cable/SFP/power)** — user-confirmed; link never lost carrier.
- **lab-router / BGP / FRR / routing changes** — all L3; lab-router has one clean leg per
  bridge (no L2 loop); the break was on pfSense's switch port, upstream of every Proxmox-side
  device; L3 changes cannot stop a directly-connected ARP. No storm/MAC-flap observed.
- **HOME working-hours schedule** — schedules act on L3 egress; here pfSense received zero L2
  frames, and SVR (no HOME schedule) was equally cut.

## Trigger (NOT yet confirmed — needs switch logs)

Most consistent with an **STP topology-change / transient L2 loop** that caused the switch to
block pfSense's uplink. A **latent loop risk exists**: VLAN 10 is presented on two Proxmox
NICs — `vlan10@ens1f0 → vmbr10` and `vlan010@eno2 → vmbr010` (both VLAN id **10**) — with STP
**disabled** on the Linux bridges. If both reach the switch, a transient loop there can trip
STP to block a port (possibly the `ix0` uplink). Confirm via the switch's STP topology-change
counter / port-state history for the `ix0` port.

**Relation to the lab/BGP work (06-16/06-17):** the BGP/routing changes are L3 and cannot
block a switch port; pfSense had no config change on 06-18. The Proxmox-side L2 changes
(lab-router VM 130, new bridges) were completed **06-16** (`/etc/network/interfaces` mtime
06-16 16:44; VM 130 up since 06-16 17:07) and ran stably **~1.6 days** — a fatal loop/topology
error would have broken on 06-16, not 06-18 ~08:00. Proxmox logged **no** link/STP event in the
break window → the event was **purely switch-side**. The only plausible link to the lab work is
therefore **switch-side VLAN/trunk configuration** done for the new cluster/lab/admin segments
(not visible from pfSense/Proxmox); a spontaneous switch STP event is equally possible. The
switch's STP log decides between them.

## Prevention / follow-ups

1. **Confirm the trigger on the switch:** inspect STP state + topology-change counter + last
   block reason for the `ix0` port (the one piece this RCA can't see from pfSense/Proxmox).
2. **Eliminate the latent VLAN-10 loop:** `vlan10@ens1f0` + `vlan010@eno2` both carry VLAN 10
   with bridge STP off. Remove the redundant path, bond properly (LACP), or enable RSTP /
   BPDU-guard so a loop can't form.
3. **Protect the uplink in STP:** set switch STP priorities/root so the pfSense `ix0` trunk is
   never the port chosen for blocking; portfast/BPDU-guard on access ports only.
4. **Redundancy:** pfSense has a second 10G port `ix1` (no carrier). Configure `ix0`+`ix1` as
   an LACP `lagg` on **both** pfSense and the switch so a single blocked/faulted port can't
   island the LAN.
5. **Monitoring:** alert when pfSense `ix0` RX-rate ≈ 0 while the link is up (SNMP/textfile),
   independent of the LAN it watches. This exact signature would have flagged it immediately.
6. **Switch change-control:** snapshot/document the switch config (STP, VLAN membership, LACP)
   so VLAN-segmentation work can't silently introduce loops/topology changes.

## Recovery procedure (if it recurs)

From pfSense, over the admin NIC so the session survives:
`ssh -o HostName=192.168.32.33 pfsense 'ifconfig ix0 down; sleep 4; ifconfig ix0 up'`
Then wait ~60 s for STP to converge before verifying (RX rate, `ping 192.168.48.44`, BGP).
