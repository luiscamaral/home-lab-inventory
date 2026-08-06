# 🔍 RCA — Grafana slow/intermittent + LAN packet loss

**Date:** 2026-08-05 → 06
**Status:** ✅ **RCA established.** Two independent faults identified and separated by
measurement. **No remediation performed by me.**
**Reported:** "not able to open Grafana" (recurring); HOME-VLAN client 192.168.0.49
reporting bandwidth dropping below 500 kbps.

> ⚠️ **A pfSense reboot occurred mid-investigation at 18:22:30 MDT (00:22:30Z).** I did not
> issue it and no command I ran restarts a router — I was running 100-packet pings at the
> time. It was **clean, not a crash**: `dumpdev` is configured (`gpt/swap1`) and
> `/var/crash` is empty. That reboot became the single most informative event in this
> investigation (§4), but it also destroyed the faulted state before the exact mechanism
> could be captured (§6).

---

## 1. 🎯 Conclusion

Two **separate** faults, proven independent because one cleared on reboot while the other
continued:

| | Fault A | Fault B |
|---|---|---|
| **What** | pfSense runtime-state degradation | `github-runner-homelab` crash-loop |
| **Symptom** | 1–5 % one-directional packet loss (pfSense → LAN), `ix0 link_irq` at 33/s | macvlan ARP storm on 192.168.59.4 |
| **Impact** | Grafana 2–12 s loads, LAN clients capped 5–10 Mbps, Twingate connectors dropping | ARP table churn on ix0.28 |
| **Onset** | accumulated over ~4 d 20 h uptime | 12,979 container restarts |
| **State now** | ✅ **cleared by reboot** (0.0 % loss) | ❌ **ongoing** (462 ARP moves since boot) |

**Grafana itself was never at fault.** It served HTTP 200 at ~1.8 ms throughout.

---

## 2. ✅ Fault A — the evidence chain

### 2.1 Loss existed and was reproducible

200-packet pings **from pfSense** (pre-reboot, `E4`):

| Target | Loss | RTT avg / stddev |
|---|---|---|
| 192.168.59.39 `grafana` | **5.0 %** | 0.401 / 0.072 ms |
| 192.168.48.46 ds-2 | 2.5 % | 0.357 / 0.064 ms |
| 192.168.59.49 rproxy-3 | 2.0 % | 0.357 / 0.064 ms |
| 192.168.59.28 rproxy | 1.5 % | 0.403 / 0.148 ms |
| 192.168.48.45 ds-1 | 1.0 % | 0.386 / 0.076 ms |

Excellent latency with tiny stddev ⇒ clean loss, not congestion.

### 2.2 Only paths involving pfSense were affected

Same test **from ds-2** (`E5`) — never touches pfSense:

```text
ds-2 -> grafana .39    200/200   0% loss
ds-2 -> rproxy  .28    200/200   0% loss
ds-2 -> ds-1    .45    200/200   0% loss
ds-2 -> pfSense .48.1  196/200   2% loss   <-- only this one
```

TCP-level, 60 connects each (`E7`), >100 ms on a 0.4 ms path = SYN retransmit:

```text
same VLAN : grafana:3000 0/60 slow | rproxy:443 0/60 slow
via pfSense: tnas:5000   4/60 slow | pfSense:443 2/60 slow
```

⇒ Switch fabric, macvlan, and the Docker hosts are **clean**.

### 2.3 The loss was one-directional — proven by ICMP counter accounting

`E16b` — pfSense pinged `grafana` while reading the container's own kernel counters via
`nsenter -t <pid> -n grep -A1 '^Icmp:' /proc/net/snmp`:

```text
pfSense sent (echo requests)        : 194
container InEchos      (arrived)    : 189   <-- 5 lost INBOUND
container OutEchoReps  (replied)    : 189   <-- replied to 100% of what it got
pfSense received                    : 189   <-- return path 100% clean
container InErrors                  : 0
```

**The loss is entirely pfSense → container. The return path and the container are blameless.**

### 2.4 Packets left pfSense and no counter recorded a drop

- `E11` tcpdump on ix0.28: **195/195** echo requests observed leaving; 187 replies returned.
- `E9` counter deltas across a run that lost 4.7 %: `no_bufs=0`, `no_route=0`.
- `E17` ix0 TX: **`Oerrs=0` across 1,496,220,200 output packets**; zero pause frames
  (`xon/xoff_txd/recvd` all 0); `txd_head == txd_tail` on every queue; `watchdog_events=0`.
- ix0 RX: `Ierrs=1` per 1.48 **billion**, `Idrop=0`, `crc_errs=0`, `rx_missed=0`,
  `queue*.rx_discarded=0`. pf: `congestion=0`.

**Packets vanished with every counter in the system reading zero.**

### 2.5 The one abnormal counter: `ix0 link_irq`

| NIC | link_irq |
|---|---|
| **ix0 (LAN trunk)** | **3,747,869 total — incrementing 33/s** |
| igc0 (WAN) | 9 total, static |
| igc1 / igc2 / igc3 | 3 / 0 / 2, static |

After reboot: **6 total, 0/s**. This is the only telemetry that tracked the fault.

---

## 3. 📉 Why the router was fast and every client slow

Same destination IP (5.161.7.195), same minute:

| Source | Throughput |
|---|---|
| pfSense (router-originated) | **315 Mbps** (100 MB in 2.66 s) |
| ds-2 / dockermaster / NAS / proxmox host | 5.6 – 10.5 Mbps |

pfSense's own internet traffic uses `igc0` only; LAN clients must additionally cross `ix0`,
where the loss lived. Throughput scaled as **1/RTT** — the signature of loss-driven TCP
collapse (Mathis): Cloudflare 2.3 ms → 580 Mbps, Hetzner 51 ms → 7 Mbps, OVH 147 ms →
0.8 Mbps. Client `ss -ti` showed `cwnd:10` pinned with a 1.4 MB receive window ⇒ not
window-limited.

> ⚠️ Because throughput scales with 1/RTT, **Cloudflare-fronted services stayed fast and
> masked the fault** — the homelab's own pages felt fine while distant hosts crawled.

---

## 4. 🔄 The reboot — the decisive natural experiment

| Metric | Pre-reboot (4 d 20 h uptime) | Post-reboot (1 h 43 m) |
|---|---|---|
| Loss → `grafana` .39 | 5.0 % | **0.0 %** |
| Loss → rproxy .28 | 1.5 % | **0.0 %** |
| Loss → ds-2 .48.46 | 2.5 % | **0.0 %** |
| Loss → rproxy-3 .49 | 2.0 % | **0.0 %** |
| `ix0 link_irq` rate | 33/s | **0/s** |
| ARP moves | ongoing | **still ongoing (462)** |

This establishes three things:

1. **The fault was accumulated runtime state on pfSense, not physical.** A failing SFP+,
   fibre, cable or switch port is not repaired by a software reboot.
2. **It was not a kernel panic.** `dumpdev=gpt/swap1` is configured and `/var/crash` is
   empty; `last reboot` shows prior reboots months apart (Jun 27, Jun 18, May 28) — not a
   crash loop.
3. **Fault B is independent** — the ARP storm survived the reboot while the loss did not.

---

## 5. 🐛 Fault B — `github-runner-homelab` crash-loop (ongoing)

`E24` — container states across the Docker hosts:

```text
dockerserver-1: github-runner-homelab  restarts=12979  state=restarting
dockerserver-1: cadvisor-ds1-cadvisor-1 restarts=10    state=running
dockerserver-1: ollama                  restarts=0     state=exited
dockerserver-2: minio-2-minio-1         restarts=13    state=running
```

ARP moves observed on ix0.28, by IP:

```text
370  192.168.59.4    <-- 394 DISTINCT MACs
 63  192.168.59.33
 12  192.168.48.44
 10  192.168.48.45
```

`terraform/portainer/stacks/github-runner.yml:21` pins
`ipv4_address: 192.168.59.4` with `restart: unless-stopped`. Every crash-restart draws a
**new random MAC** on the macvlan network, so pfSense logs an `arp: 192.168.59.4 moved
from … to …` each time — 394 distinct MACs for one IP.

This is a genuine defect worth fixing (it churns the ARP table and the switch MAC table, and
a runner has been dead for 12,979 restarts) but it is **not** the cause of Fault A.

---

## 6. ❓ What is still NOT known

1. **The exact mechanism inside pfSense.** We know it was runtime state, one-directional,
   invisible to every counter, and correlated with an `ix0 link_irq` storm at 33/s. We do
   **not** know the precise driver/stack condition — the reboot cleared the evidence before
   it could be captured.
2. **Who or what triggered the reboot.** Clean shutdown, no panic, not initiated by me.
3. **Whether it recurs, and on what interval.** Prior uptime was 4 d 20 h. If the mechanism
   is uptime-correlated, expect recurrence around 2026-08-10.
4. **Switch-side counters were never obtained** — a Vault read for the Omada credentials was
   blocked by the tooling sandbox. Still worth pulling to fully exonerate the switch port.

---

## 7. ⏭️ Recommended next steps

**Do not "fix" Fault A yet — it is currently not reproducible.** The correct action is to
instrument for its return.

1. **Add monitoring for the leading indicator.** Alert on `ix0 link_irq` rate > 1/s and on
   LAN ping loss > 0.5 %. Both were unambiguous while the fault was active and both are
   cheap to scrape. This gives a definitive answer on recurrence and interval.
2. **If it recurs, capture BEFORE rebooting:** `sysctl dev.ix.0`, `vmstat -i`, `netstat -s`,
   `pfctl -si`, and a `nsenter` ICMP-counter run. That is the missing §6.1 evidence.
3. **Fix Fault B independently** — it is reproducible now and clearly defective. Either
   repair the runner's startup failure or stop the stack; 12,979 restarts is pure churn.
   Route through `terraform/portainer/stacks/github-runner.yml`.
4. **Pull switch24a port counters** for the pfSense uplink to close §6.4.

---

## 8. 🪤 Methodology traps (8 hit — all produced confidently wrong intermediate results)

| Trap | Wrong result it produced | Correct approach |
|---|---|---|
| `wget` absent in `nginx:1.29-otel` | "all upstreams unreachable" | `command -v` first; `curl` is present |
| dash has no `/dev/tcp` | "ports BLOCKED from container" | use a real client binary |
| Twingate connector is distroless | "empty resolv.conf ⇒ DNS broken" | `docker inspect`, not in-container tools |
| **`tcpdump` not installed on dockermaster** | 3 netns captures returned 0 packets | verify the binary exists; use `/proc/net/snmp` counters instead |
| `tcpdump -i any` on macvlan | 0 packets | capture in the container netns, or use counters |
| `dnctl list` (wrong subcommand) | "no shaper queues exist" | `dnctl pipe\|queue\|sched list` |
| **`curl --interface <ip>`** | invalidated an entire WAN2 comparison | sets source IP only, not routing — verify `route -n get <dst>` |
| seq-based reorder metric | conflated reordering with retransmits | count only genuine OOO, or trust `rcv_ooopack` |

Also: pinging a router measures its own ICMP path — confirm `net.inet.icmp.icmplim` (here
`0`, disabled) before trusting the result.

---

## 9. ❌ Ruled out (with the measurement that killed each)

Grafana app (10/10 200s @1.8 ms) · rproxy→Grafana upstream (1.8 ms via bridge and macvlan) ·
switch/macvlan fabric (host↔host 200/200, TCP 60/60) · macvlan **IP collision as cause of
loss** (unique MACs for .28/.39/.48/.49; storm is on .59.4 and outlived the loss) · MTU
(DF 1472 B passes) · ICMP rate-limit artifact (`icmplim=0`) · NIC/optic/cabling (`crc_errs=0`,
`Ierrs=1` per 1.48 B, and a reboot fixed it) · `checksum_errs` (grew 3 in 30 s) · dummynet
shaper (27 MB → ~63 KB in queues, 0 drops) · pfSense resources (96 % idle, 0 mbuf denials,
35 k/1.6 M states) · IDS/pfBlockerNG (not installed) · IPv6 (no v6 route) · Proxmox VM
networking (bare metal equally slow) · gateway/NAT selection (single default route).

---

## 10. 📎 Raw artifacts

`raw/E1 … E24`, collected 2026-08-05T23:22Z → 2026-08-06T02:08Z. Each section above cites
the artifact backing it.

## 11. 🔗 Related

- `reference_lan_forwarding_reordering_collapse` (memory)
- `docs/network/switch24a-omada-integration-plan.md`
- `docs/network/pfsense.md`
