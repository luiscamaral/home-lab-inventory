# Thanos Network-Metrics Anomaly Scan — 2026-05-27

## Methodology

- **Window**: 2026-05-27 02:49 → 14:49 UTC (last 12 h, 721 samples per series at 60s step).
- **Endpoint**: `http://192.168.59.26:10902/api/v1/query_range` reached via
  `ssh dockermaster 'curl ...'` (laptop reached endpoint indirectly; direct Twingate
  path not tested for this run).
- **Approach**: 24 PromQL queries covering 8 metric families. JSON dumps captured to
  `/tmp/thanos-scan/`. Findings ranked by severity. Thresholds per metric:
  - dpinger delay > 3× per-gateway median or > 30 ms absolute
  - blackbox `probe_success == 0` for any sample; duration p95 > 1 s
  - node_network err/drop rate > 0 sustained
  - conntrack ratio > 0.8
  - SNMP `if*Errors/Discards` rate > 0
  - pf `MemDrop` > 0; state table > 80 % of limit
  - `up{}` flap detection via `changes(up[5m]) ≥ 4`
  - karma `_up == 1`, `_errors_total` flat
- Time references throughout are UTC.

## Findings

Ranked: 🔴 critical / 🟡 warning / 🟢 informational.

### 🔴 1. blackbox: five probes failing 100 % of the window (target config drift)

- Metric: `probe_success{} == 0` for the entire 12 h window.
- Affected:

  | job | instance | duration profile | likely cause |
  |---|---|---|---|
  | `blackbox-tcp`  | `freeswitch.d.lcamaral.com:5060` | up to 5 s (timeout) | TCP/5060 not exposed at this name; FreeSWITCH SIP listener probably bound elsewhere |
  | `blackbox-http` | `https://s3.d.lcamaral.com`      | up to 5 s (timeout) | MinIO migration in-flight; vhost not (yet) terminating TLS at `s3.d` |
  | `blackbox-ssl`  | `registry.cf.lcamaral.com:443`   | mean 0.08 s, fast-fail | TLS handshake refused; cf-tunnel ingress may not advertise this hostname |
  | `blackbox-ssl`  | `auth.cf.lcamaral.com:443`       | mean 0.04 s, fast-fail | same pattern — fast-fail = SNI/cert mismatch or no ingress |
  | `blackbox-ssl`  | `login.cf.lcamaral.com:443`      | mean 0.06 s, fast-fail | same pattern |

- **Hypothesis**: these targets pre-date the recent karma/rproxy/minio churn or were
  copy-pasted with the wrong scheme. The two `cf.lcamaral.com` `blackbox-ssl` probes
  fast-fail in <100 ms (clean TLS refusal), while the `*.d.lcamaral.com` probes time
  out at 5 s (no listener / no SNI match). Worth pruning or fixing because they
  fire `karma_collected_alerts_count == 8` continuously and mask real outages.
- The `karma_collected_alerts_count{state="active"} = 8` (steady) almost certainly
  corresponds to this set + the watchtower-dm outage (item #4).

### 🔴 2. minio job: `minio-2` dropped at 14:35 UTC, still down at scan end (14:49)

- Metric: `up{job="minio", instance="minio-2"} == 0`, last value `0`.
- `up=706, down=15` — went down ~15 min before scan ended.
- **Hypothesis**: this is the user's in-progress minio-2 migration. Expected to be
  state-changing right now; should come back up once migration finishes. Note
  `minio-1` also flapped 13× across the window (max 6 changes per 5 min) — likely
  related (re-sync, reconfig, etc.).

### 🟡 3. blackbox: keycloak / vault HTTPS slow (8 s SSL probe, intermittent failures)

- Metrics:
  - `probe_duration_seconds{job="blackbox-ssl", instance=~"(keycloak|vault).d.lcamaral.com:443"}`
    p95 ≈ 8.0 s, max 8.0 s (timeout).
  - `probe_dns_lookup_time_seconds` on the same targets: max **8 s**, mean
    **1.5–1.7 s** — DNS resolution itself is dominating the probe budget.
  - `probe_success{job="blackbox-http"}` corresponding HTTP probes: 65–87
    failures (~9–12 %) on Prometheus / vault / keycloak / portainer / s3 /
    login over the window.
- **Hypothesis**: blackbox-exporter's resolver is stalling. Note that
  `blackbox-dns` itself failed against `192.168.4.1:53` (pfsense Unbound)
  in 135/721 samples — three contiguous 6–7 min outages at 04:52, 05:23, 10:35
  UTC. Whatever made pfSense DNS go quiet for those windows is the same root
  cause behind the slow SSL probes (blackbox resolver upstream = pfSense).
  See also #6 (snmp-pfsense flapping) — pfSense itself is the common factor.

### 🟡 4. pihole-2 unreachable for 5.5 hours (02:49 → 08:23 UTC)

- Metric: `up{job="pihole", instance="pihole-2"}` — 154 contiguous down samples,
  recovered at 08:24. Did not flap since.
- Co-incident: `blackbox-dns{instance="192.168.59.50:53"}` failed 166 samples
  02:49 → 11:28 UTC. (.50 and .51 likely map to pihole-1/2/3 instances; the
  longer probe-side outage suggests another DNS host stayed flaky into the
  morning even after pihole-2 itself recovered.)
- **Hypothesis**: pihole-2 container crashed/restarted overnight. Recovery time
  (08:23) is consistent with a watchtower update cycle or manual touch. Cross-
  check: watchtower-dm itself was down 03:00 → 06:42 (#5), so it didn't do the
  pihole restart. Probably manual.

### 🟡 5. watchtower-dm down 03:00 → 06:42 UTC (3 h 42 min)

- Metric: `up{job="watchtower", instance="watchtower-dm"}` — 223 contiguous down
  samples, single outage, fully recovered at 06:43.
- **Hypothesis**: matches the documented "watchtower-dm IP collision" punch-list
  item from yesterday's session handoff (server-net-shim re-IP on ds-1/ds-2
  could have collided with a pinned macvlan address). Recovery at 06:43 hints
  at either a scheduled cron-restart or a noticing-and-fixing event. Verify
  current IP assignment against `terraform/portainer/` state.

### 🟡 6. snmp-pfsense flapping (88 down samples across 36 contiguous outages)

- Metric: `up{job="snmp-pfsense", instance="pfsense"}` had 36 separate outage
  runs, mostly 1–3 min, longest 9 min at 09:49 → 09:58 UTC. `changes(up[5m])`
  peaked at 14 (highest in the dataset).
- All flaps occurred from **06:30 onward**; before then the job was solid.
- **Hypothesis**: the snmp-pfsense fix you just landed got the metric flowing,
  but the SNMP scrape is brittle. Either:
  1. pfSense's `bsnmpd` is rate-limiting / queueing under load (those minutes
     also include high traffic — see #9 — peak 2.3 Gbps on ix0.10 at 06:46),
     **or**
  2. the scrape timeout is too tight for the OID walk size,
  3. transient packet loss on the scrape path (macvlan → pfsense).
- Worth bumping `scrape_timeout` to 30 s in the snmp-exporter job and observing.

### 🟡 7. postgres-rundeck: most-flappy target (243 down / 77 runs)

- Metric: `up{job="postgres", instance="postgres-rundeck"}` — `changes(up[5m])`
  peak 12, mean 4.78 (consistently flapping). Down 33 % of the window.
- Outage runs are short (most ≤ 1 min) and recover immediately. Pattern
  suggests a misconfigured/missing exporter rather than a real outage —
  postgres itself is probably fine; the scrape target/auth/credential or the
  exporter container itself is the broken bit.
- **Hypothesis**: known issue (we have seen "container 'healthy' hides defunct
  process" type problems on rundeck before). Check the postgres-exporter
  sidecar's DSN/credentials and connection-pool tunables.

### 🟢 8. dpinger gateway monitoring: clean except for a one-shot freshness gap at deploy

- All three gateways well under thresholds:
  - HOMELAB: median 0.22 ms, p95 0.47 ms, max 0.73 ms; 5 jitter spikes
    (stddev > 3× median, max 1.74 ms). All sub-millisecond. **Clean.**
  - WAN1GW: **median 15.19 ms** (note: high baseline — that's the ISP
    next-hop, not a fault; p99 also 15.6 ms = very stable). Stddev spikes
    at 05:36 (31 ms), 08:58 (22 ms), 10:18 (11 ms), 10:53 (13 ms). Single-
    sample jitter, no sustained degradation, zero packet loss.
  - WAN2_DHCP: median 1.02 ms, p95 1.48 ms, max 2.14 ms. Zero packet loss.
- Loss events: HOMELAB 2 % at 09:53, 1 % at 12:27 — single-sample blips
  (one missed ICMP each). WAN1/WAN2 had **zero** loss in the entire 12 h.
- **Freshness oddity**: `time() - pfsense_dpinger_scrape_unixtime` peaked at
  2076 s at 03:23 UTC during a single early window (02:51 → 03:23, ascending
  monotonic — i.e. the exporter went silent for 33 min). It then resumed and
  has held 26 s since. **One-shot, looks like a deploy/reload window** for the
  textfile exporter — not an ongoing problem, but worth confirming the
  systemd timer survived.

### 🟢 9. SNMP if_mib: zero interface errors / discards, traffic peaks make sense

- `ifInErrors`, `ifOutErrors`, `ifInDiscards`, `ifOutDiscards` — **all zero**
  across every interface and every sample.
- Bandwidth peaks (highest 5 min):
  - `ix0.10` HOME — IN  max **2.26 Gbps** at 06:46 UTC; matching mean 430 Mbps
  - `ix0.28` SRVAN — OUT max **2.26 Gbps** at 06:46 UTC; matching mean 430 Mbps
  - WAN1: peak 13.5 Mbps in, 1.45 Mbps out — quiet day
- The HOME-in / SRVAN-out flow at 06:44–06:47 is a **~3 minute, ~2 GB/s
  internal east-west burst**: a client on HOME pushed roughly 50 GB toward the
  server VLAN. Given the minio-2 migration in progress, this is almost certainly
  the migration backfill (consistent shape, runs into low-throughput tail at
  07:29 = 1.6 Gbps). 10 Gbit uplink utilised ~23 % at peak; not concerning.

### 🟢 10. pf MIB: nominal

- `pfStateTableCount`: 15.4 k–20.3 k, mean 17.5 k. **Limit is 1.6 M**, so
  we're at 1.1 % utilisation. Comfortable.
- `pfCounterMemDrop` rate: **zero** across window (no state-table exhaustion).
- `pfCounterMatch` rate: 30–55 rules/s — quiet, no rule explosion.
- Per-interface PASS/BLOCK byte ratios all under 1 % blocked, which is normal
  background scanner traffic + IoT VLAN chatter. (Per-pf-index → name mapping
  not resolved here because `pfInterfacesIfDescr` is a string-label, not
  numeric — would need an SNMP walk to label cleanly; not worth doing for the
  current volumes seen.)

### 🟢 11. node_network: tiny consistent rx_drop, zero everywhere else

- `node_network_receive_errs_total`, `_transmit_errs_total`,
  `_transmit_drop_total` — **all zero rate** on every host/interface.
- `node_network_receive_drop_total` non-zero only:
  - `ens19` on dockermaster/ds-1/ds-2: 0.10–0.11 drops/s (matches the
    Proxmox-internal vmbr interface — typical IPv6 RA / multicast noise on
    a shared bridge).
  - `server-net-shim` on dockermaster/ds-1/ds-2: 0.032–0.035 drops/s,
    constant ratio across all three hosts.
- **Hypothesis**: these are not "real" drops — they're the macvlan shim
  filtering out broadcast / ARP traffic it doesn't need. The exact match
  across three hosts (0.035 ± 0.003 /s) confirms it's a structural rate
  tied to LAN broadcast volume, not a host-specific fault. Safe to ignore;
  if it ever becomes asymmetric across the three hosts, something changed.

### 🟢 12. conntrack: low utilisation everywhere

- `node_nf_conntrack_entries / _limit`: max 0.3 % on `nas`, all Docker
  hosts < 0.1 %. Limits are healthy.

### 🟢 13. karma: green

- `karma_alertmanager_up{alertmanager="alertmanager-1"}` == 1 throughout.
- `karma_alertmanager_errors_total{endpoint=alerts|silences}` == 0 throughout
  (no scrape errors against alertmanager).
- `karma_collected_alerts_count{state="active"}` held at **7–8 active alerts**
  for the entire window — these are the persistent failures from #1+#4+#5,
  not anything new firing.

### 🟢 14. SSL certificate TTLs

- Nothing under the 14-day threshold. Nearest expiry: `ha.home.lcamaral.com:443`
  at **37.5 days**, then a cluster of `*.cf.lcamaral.com` certs at 41–42 days
  (Cloudflare 90-day rotation — normal mid-cycle). Reissue handled by ACME;
  no action.

## Checks for the human to follow up on

1. **Always-failing blackbox targets** (item #1): confirm whether
   `freeswitch.d.lcamaral.com:5060`, `s3.d.lcamaral.com`, and the three
   `*.cf.lcamaral.com:443` SSL probes were intended to work — if yes, fix
   listener/SNI/ingress; if no, prune them. They're inflating the karma alert
   count to 7–8 permanent alerts and would mask a real outage.
2. **minio-2** went down at **14:35 UTC**. Confirm it's the migration in
   progress (expected) and not a side-effect (e.g. service mesh re-routing).
3. **keycloak / vault HTTPS probes**: the 8 s timeouts are DNS-bound
   (`probe_dns_lookup_time` ≈ 1.5–8 s). Verify blackbox-exporter's upstream
   resolver — likely pointing at pfSense Unbound, which itself failed for
   three 6-7 min windows (04:52, 05:23, 10:35 UTC) on `192.168.4.1:53`.
   Consider giving blackbox a second resolver via Docker DNS or `/etc/resolv.conf`.
4. **pihole-2 was down 02:49 → 08:23** UTC (5.5 h). It's back, but no automatic
   monitor noticed for hours. Watchtower-dm wasn't running during most of that
   window — verify whether anything besides watchtower is meant to alert on
   pihole liveness. Worth a quick `journalctl -u docker` look on whichever host
   runs pihole-2 to identify the crash cause.
5. **watchtower-dm** down 03:00 → 06:42. Cross-reference with the IP collision
   you flagged in yesterday's punch-list. The 3h42m self-recovery suggests
   something (re-pull, container restart) eventually un-stuck it.
6. **snmp-pfsense scrape** has been flapping since 06:30 UTC. The longest run
   (9 min at 09:49) is borderline-alertable. Most likely a scrape timeout
   issue. Try bumping `scrape_timeout` for the snmp-pfsense job to 30 s and
   re-observe; if that doesn't fix it, instrument with the `tcpdump` snippet
   on the exporter side.
7. **postgres-rundeck exporter** flaps every few minutes (243/721 down).
   The pattern (frequent micro-outages with instant recovery) is classic
   exporter or auth-token issue. Investigate the exporter sidecar logs and
   verify the DSN credentials match what's in Vault.
8. **dpinger textfile exporter** had one 33-min silent window very close to
   deploy (02:51 → 03:23 UTC) before going steady. Verify the systemd timer
   that drives the textfile collector is enabled and started, not just
   one-shot.
9. **WAN1 baseline latency 15 ms** is unusually high if WAN1 is supposed to
   be the primary fiber path (typical ISP next-hop is 1–5 ms). It is stable
   (p99 also 15.6 ms), so probably just the topology of that uplink — but
   if you expected lower, that's a conversation to have with the ISP.
   WAN2 is on 1 ms, so failover-via-policy would actually be **faster**.
10. **No data found** for pf-interface index → name mapping (`pfInterfacesIfDescr`
    is a string-label, not parseable from query_range). If you ever care about
    per-interface block/pass ratios, add an SNMP walk-time relabel rule that
    materialises descr as a label on the `pfInterfacesIf4*` series. Not urgent;
    current block volumes are negligible.

## What "boring" looks like across the 8 families

Six of the eight families came back essentially clean (dpinger, node_network,
conntrack, SNMP if_mib, pf MIB, karma). The two with real noise are:

- **blackbox** — 5 permanently-broken probes (config drift), plus correlated
  intermittent failures driven by DNS via pfSense.
- **up{}** — 6 of the 74 monitored targets had > 1 down sample, and three of
  those (postgres-rundeck, snmp-pfsense, minio-1) were flapping.

Nothing is on fire, nothing is bandwidth-saturated, nothing is exhausting
state-table or conntrack capacity, no SSL certs are anywhere near expiry, and
the new dpinger exporter is producing clean, high-quality data after a brief
deploy-time gap. The 2.3 Gbps east-west spike at 06:46 lines up with the
minio-2 migration the user already knows about.
