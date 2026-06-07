# 📊 Network & Internet Quality Monitoring — Implementation Plan

**Date:** 2026-05-26
**Status:** living plan; phases listed in execution order
**Trigger:** WiFi outage on 2026-05-25 (see `wifi-internet-quality-2026-05-25.md`)
that exposed how little of the network we actually observe 24×7.

---

## 0. Where we are today (already shipped)

These landed in commits `14028e6`, `63231dd`, `921c56e`, `bf5791f`, `71f0359`
on `main`:

- ✅ **`snmp-pfsense` fixed** — slimmed `pfsense` snmp_exporter module, walk
  went from 10s timeout to 70ms. ~1,888 metric lines flowing.
- ✅ **`node{instance=pfsense}` added to Prometheus** — ~620 host-level
  series (CPU, mem, fs, per-VLAN NIC errs/drops/bytes, conntrack, netstat).
- ✅ **dpinger textfile exporter** on pfSense — `pfsense_gateway_delay_seconds`,
  `_loss_ratio`, `_stddev_seconds`, `_scrape_unixtime` for the 3 dpinger
  gateways (HOMELAB, WAN1GW, WAN2_DHCP). Refresh every 30s.
- ✅ **IaC primitives** for pfSense lifecycle:
  - `pfsense/scripts/*.sh` + `scripts/sync-pfsense-scripts.py` (with
    per-script `# pfsync-dest:` headers)
  - `pfsense/cron-jobs.yml` + `scripts/sync-pfsense-cron-jobs.py`
- ✅ **Grafana dashboard `pfsense-wan-quality`** — 8 panels on dpinger
  metrics (folder: Homelab).

### What's still uncovered

| Source | Series in Prom | Series with a Grafana panel | Coverage |
|---|---:|---:|---:|
| dpinger textfile | ~12 | ~12 | 100% |
| pfSense node_exporter | ~620 | 0 | 0% |
| pfSense snmp-pfsense | ~1,888 | 0 | 0% |
| **WiFi air-link / APs** | **0** | **0** | **0%** |
| **Client-side / wireless probes** | **0** | **0** | **0%** |
| External-internet probes | 0 | 0 | 0% |
| WAN bandwidth (speedtest) | 0 | 0 | 0% |
| Per-client / per-flow attribution | 0 | 0 | 0% |

The WiFi-side blind spot is the same one that hid the 2026-05-25 outage.

---

## Phase 1 — Quick wins (this week, no external blockers)

Highest ROI / smallest effort items. Every one is IaC-clean (Terraform +
existing sync scripts). Total effort estimate: **~6–8 hours.**

### 1.1 Enable `--collector.uname` on pfSense's node_exporter

**Why:** unlocks the community **Node Exporter Full** dashboard (31 panels,
already in this repo as `grafana-dashboards/node-exporter-full.json`) for
`instance=pfsense`. Today it auto-discovers via `node_uname_info`, which
pfSense's package strips by default. One toggle gives us:

- CPU per-core utilization
- Memory pool breakdown (active / inactive / wired / buffer / free)
- Filesystem usage per mount
- Per-interface bandwidth, errors, drops (every VLAN sub-interface)
- TCP/UDP/IP counters and retransmit rates
- Conntrack saturation

**How:** pfSense GUI → Status → Services → Node Exporter → enable `uname`
collector → save. OR edit `/usr/local/etc/rc.conf.d/node_exporter`
directly (less clean — survives until next pkg update).

**Effort:** 5 minutes (clicks)
**Dependencies:** none — no Vault, no API creds, no code

### 1.2 External blackbox probes (was rec #2 from earlier brainstorm)

**Why:** every existing blackbox target is _internal_. If our upstream
ISP loses 10% of packets to Cloudflare, we wouldn't see it.

**How:** edit `terraform/portainer/locals.tf`:

```hcl
blackbox_icmp_targets = jsonencode([{
  targets = [
    # existing 7 internal targets...
    "1.1.1.1",       # Cloudflare anycast
    "8.8.8.8",       # Google DNS anycast
    "9.9.9.9",       # Quad9 anycast (provider diversity)
    "208.67.222.222" # OpenDNS / Cisco (4th provider)
  ]
}])

blackbox_dns_targets = jsonencode([{
  targets = [
    # existing 4 internal resolvers...
    "1.1.1.1:53", "8.8.8.8:53", "9.9.9.9:53"
  ]
}])

blackbox_http_targets = jsonencode([{
  targets = [
    # existing 8 internal HTTPS endpoints...
    "https://1.1.1.1/cdn-cgi/trace",
    "https://www.google.com/generate_204",
    "https://detectportal.firefox.com/success.txt"
  ]
}])
```

Plus 3 alert rules in `prometheus_rules_yml`:

- `ExternalInternetReachabilityDegraded` — ≥2 of 4 anycast ICMP probes down
  for 3m
- `ExternalDNSDegraded` — avg DNS lookup > 200ms over 5m
- `ExternalHTTPLatencyHigh` — P95 HTTP duration > 500ms over 10m

**Effort:** 30 min (edit + apply + redeploy + verify)
**Dependencies:** none

### 1.3 blackbox-exporter on NAS (HOME VLAN vantage point)

**Why:** today's only blackbox-exporter runs on dockermaster at
`192.168.59.45` — the **server** VLAN, behind the firewall, on the wrong
side of every WiFi link. Adding a second instance on NAS (`192.168.7.11`,
HOME VLAN, already running node_exporter) gives us the **first probe
vantage from the user network.**

**How:** new Portainer stack `blackbox-exporter-nas`. Compose stack file
mirroring the existing `blackbox-exporter.yml.tftpl`, but deployed via
NAS's Container Manager. Prometheus scrape job
`blackbox-icmp-home`/`blackbox-http-home` reuses the same target lists
but sources from the NAS instance.

**Effort:** 1 h (write stack, deploy, add scrape jobs)
**Dependencies:** none

### 1.4 Speedtest exporter

**Why:** detects WAN-bandwidth degradation that latency-only probes miss.
Critical for "is my Fiber actually delivering its rated speed?"

**How:** new Portainer stack with
`miguelndecarvalho/speedtest-exporter:latest`. Default schedule: every
hour (Ookla rate-limits below that). Exposes
`speedtest_download_bits_per_second`, `_upload_*`, `_ping_seconds`.

**Effort:** 30 min
**Dependencies:** none

### 1.5 Ship pfSense logs to Loki + derive metrics from `promtail`

**Why:** `promtail` is already running. `dhcpd.log`, `filter.log`, and
`system.log` on pfSense contain WiFi flap signals, blocked-traffic
patterns, and dpinger state changes that we miss today. Promtail's
`pipeline_stages: metrics:` can turn log events into counters with zero
new infrastructure.

**Derived metrics worth building:**

- `pfsense_dhcp_decline_total` — every WiFi-client that fails association
- `pfsense_dhcp_nak_total` — DHCP NAKs (client reuse attempts)
- `pfsense_filter_block_total{src_vlan, dst}` — per-VLAN blocked-traffic rate
- `pfsense_dpinger_alarm_total{gateway, state}` — gateway alarms (going up / down)

**How:** ship logs via syslog forwarder (pfSense Services → Syslog →
remote target) to a Loki ingester, with promtail's
`pipeline_stages` adding `match` + `metrics` blocks.

**Effort:** 2 h (configure pfSense syslog, write promtail pipelines,
verify metrics flow)
**Dependencies:** Loki must be running (verify in this phase)

### 1.6 Refresh existing `pfsense-availability` Grafana dashboard

**Why:** its panel #10 is literally a TODO marker saying "needs SNMP
module fix" — that's now done. Replace TODO with:

- pf state-table size + churn (`pfStateTableCount`,
  `pfStateTableSearchesPerSec`)
- Global pf counters (`pfCounterMatch`, `pfCounterMemDrop`,
  `pfCounterFragment`)
- Per-interface PASS vs BLOCK bytes
  (`pfInterfacesIfDescrIn4PassBytes`, `..._BlockBytes`)
- Interface up/down via `ifOperStatus`
- 64-bit interface bandwidth via `ifHCInOctets` / `ifHCOutOctets`

**Effort:** 2 h (5–8 new panels)
**Dependencies:** §1.1 not required, but helpful for context panels

### 1.7 Alert rules to catch what we now collect

Add Thanos rules (`terraform/portainer/stacks/thanos-rules.yml`):

```yaml
- alert: PfsenseGatewayLossHigh
  expr: pfsense_gateway_loss_ratio > 0.05
  for: 5m

- alert: PfsenseGatewayRTTSpike
  expr: pfsense_gateway_delay_seconds > 0.100
  for: 5m

- alert: PfsenseConntrackSaturation
  expr: node_nf_conntrack_entries{instance="pfsense"} / node_nf_conntrack_entries_limit{instance="pfsense"} > 0.8
  for: 5m

- alert: PfsenseInterfaceErrors
  expr: rate(node_network_receive_errs_total{instance="pfsense"}[10m]) > 0
  for: 10m

- alert: ExternalInternetReachabilityDegraded
  # (from §1.2)
```

**Effort:** 1 h
**Dependencies:** §1.1, §1.2 ideally landed first

---

## Phase 2 — WiFi visibility (next 1–2 weeks)

**This is the gap that hid the 2026-05-25 outage.** Phase 2 makes WiFi
problems visible from both the AP side and the client side.

### 2.1 Verify Omada controller status

**Why:** SSH to `omada-controller` timed out from laptop today. Need to
confirm whether the controller is still online (and reachable from where
the exporter would run, which is the server VLAN).

**How:** SSH from dockermaster, check service status, verify port 8043
listens, log into UI. If dead, decide: revive, decommission, or replace.

**Effort:** 30 min — 1 h
**Dependencies:** none

### 2.2 Generate UniFi Open API credentials

**Why:** UniFi controller is alive at `192.168.32.41:8443` (Ubiquiti
TLS cert confirmed today). Vault path `secret/homelab/unifi/controller_api`
exists with placeholder `username` / `password`. Need real read-only
credentials.

**How:** UniFi UI → Settings → Admins → add read-only admin "Prometheus".
Store in Vault:

```bash
vault kv put secret/homelab/unifi/controller_api \
  url=https://192.168.32.41:8443 \
  username=prometheus \
  password='<real-password>'
```

**Effort:** 15 min
**Dependencies:** none

### 2.3 Deploy `unifi-poller` (a.k.a. `unpoller`)

**Why:** the standard scraper for UniFi. Image:
`ghcr.io/unpoller/unpoller:v2.39.0`. Pulls site / device / client metrics
from the UniFi controller API on a schedule and exposes them on `:9130`.

**What we'd get** (sample, varies by AP model):

| Metric | What it shows |
|---|---|
| `unpoller_device_uptime_seconds{name, mac, type}` | per-AP uptime |
| `unpoller_device_state{name}` | up / down / disconnected |
| `unpoller_device_clients{name, radio}` | client count per radio |
| `unpoller_device_channel{name, radio}` | current channel (catches roams) |
| `unpoller_device_tx_power_dbm{name, radio}` | TX power |
| `unpoller_device_utilization_pct{name, radio}` | channel utilization |
| `unpoller_client_signal_dbm{name, mac, ap_mac}` | RSSI per client |
| `unpoller_client_tx_retries_pct{name, mac}` | retry rate per client |
| `unpoller_client_rx_rate_mbps{name, mac}` | MCS rate per client |
| `unpoller_dpi_traffic_bytes{name, app}` | per-application bandwidth |

**How:** new stack `terraform/portainer/stacks/unpoller.yml.tftpl`:

```yaml
services:
  unpoller:
    image: ghcr.io/unpoller/unpoller:v2.39.0
    networks:
      servers-net:
        ipv4_address: 192.168.59.4X  # pick free
    environment:
      UP_UNIFI_DEFAULT_URL:  ${unifi_url}
      UP_UNIFI_DEFAULT_USER: ${unifi_user}
      UP_UNIFI_DEFAULT_PASS: ${unifi_pass}
      UP_PROMETHEUS_HTTP_LISTEN: 0.0.0.0:9130
    expose: ["9130"]
```

Plus `vault_kv_secret_v2` data source in `terraform/portainer/vault.tf`
and a new Prometheus scrape job in `locals.tf`.

**Effort:** 1.5 h
**Dependencies:** §2.2 (real Vault creds)

### 2.4 Build Grafana dashboard for UniFi metrics

**Why:** `unifi-poller` ships a comprehensive Grafana dashboard JSON
that auto-discovers sites/devices/clients. Adapt it (replace datasource
UID with `thanos`) and drop into `terraform/portainer/stacks/grafana-dashboards/`.

**Killer panels** for the next outage:

- Per-AP **channel-utilization heatmap** — would have shown channel 120
  saturating
- **DFS-event counter** (where supported) — would have shown channel
  changes
- **Per-client retry %** time series — would have shown the laptop
  retry-capping
- **Per-radio TX power** + **client count** trends

**Effort:** 1 h
**Dependencies:** §2.3

### 2.5 Decide on Omada exporter

**Why:** if the Omada controller is alive (after §2.1) AND running APs
that UniFi doesn't see, we need the parallel `omada_exporter`
(`ghcr.io/charlie-haley/omada_exporter:v0.13.1`). If everything's UniFi
or Omada is being retired, skip.

**Open question:** are you running a mixed AP environment? If yes,
both exporters are needed; if no, pick one.

**Effort:** 2 h (parallel work to §2.3)
**Dependencies:** §2.1, plus Vault creds at `secret/homelab/omada/api`

### 2.6 Wireless probe host (synthetic WiFi client)

> ✅ **Implemented as the ESP32-C5 WiFi probe** — see
> [esp32-c5-wifi-probe.md](esp32-c5-wifi-probe.md). The dual-band Wi-Fi 6 C5
> supersedes the ESP32-S3 option below and exposes `/metrics` natively (no
> blackbox-exporter). Core (P0–P4) built clean + boot-verified on hardware.

**Why:** even with §2.3-2.5, all the data is from the AP's side. A
**dedicated wireless device running blackbox-exporter** measures what an
actual WiFi client experiences end-to-end. Yesterday's 80%-loss event
would have been a step in `probe_success{job="blackbox-icmp-wifi"}`.

**Hardware options (in increasing order of fidelity):**

| Option | Pros | Cons |
|---|---|---|
| Repurpose `rpi-zero-1` (already in SSH config) | Free; works today if alive | WiFi card is single-band 2.4 GHz only |
| Pi 4 or Pi 5 (dual-band) | Cheap; full-featured Linux | Need spare hardware |
| ESP32-S3 with custom firmware | Mimics IoT-device class | More work to write client |
| Spare phone running Termux | Free; mimics real client | Battery / restart story |

**Software:** node_exporter + blackbox-exporter + a tiny "WiFi link
state" textfile collector that reads `iw dev wlan0 link` and emits
`wifi_client_rssi_dbm`, `wifi_client_tx_rate_mbps`, `wifi_client_bssid`,
`wifi_client_channel`.

**Effort:** 2–3 h
**Dependencies:** spare hardware; firewall rule allowing scrape from
Prometheus to the WiFi VLAN

### 2.7 Per-WAN forced-routing blackbox probes

**Why:** today's blackbox-exporter goes out **whichever WAN pfSense's
gateway policy picks** — usually WAN1. We can't independently measure
WAN2's quality unless WAN1 fails over to it. Per-WAN visibility lets
us answer "is WAN1 degrading?" without waiting for failover.

**How:** two blackbox-exporter containers, each with a `route-to` rule
in pfSense (or static route inside the container's netns) forcing
outbound traffic through a specific WAN gateway IP. Scrape each
independently with labels `wan="1"` / `wan="2"`.

**Effort:** 2–3 h (most of which is policy-routing testing)
**Dependencies:** firewall rule additions on pfSense

---

## Phase 3 — Strategic investments (next month+)

Larger projects. None block daily ops; all sharpen the long-term
observability posture.

### 3.1 Phase E — SNMP image bake (drop bind-mount)

**Why:** the snmp-exporter today bind-mounts `snmp.yml` from the NFS
share. The README has tracked this as an IaC-first violation since
2026-05-08. The fix is a runtime Dockerfile that `COPY`s the slimmed
`snmp.yml` into the image.

**How:** as documented in `dockermaster/docker/snmp-exporter/README.md`
under "Phase E: bake into a custom image":

1. Create `dockermaster/docker/compose/snmp-exporter/Dockerfile`
2. `FROM quay.io/prometheus/snmp-exporter:v0.30.1`
3. `COPY snmp.yml /etc/snmp_exporter/snmp.yml`
4. Wire into `.github/workflows/build-images.yml` (already auto-globs
   `dockermaster/docker/compose/**/Dockerfile`)
5. CI pushes to `registry.cf.lcamaral.com/snmp-exporter:<sha>`
6. Update `terraform/portainer/stacks/snmp-exporter.yml` to use the
   new image and drop the bind-mount
7. Vault-inject the community string via env var (not file
   substitution), matching every other stack

**Effort:** 2–3 h
**Dependencies:** none

### 3.2 iperf3 throughput baseline (scheduled)

**Why:** detects gradual throughput regression that ping-style probes
miss (e.g., a flapping 10GbE cable that's degrading but not failing).

**How:** dockermaster runs `iperf3 -s` continuously. A scheduled
cron (or systemd timer) on each peer (NAS, ds-1, ds-2, proxmox) runs
`iperf3 -c dockermaster -t 10 -J` nightly at low-traffic time and
pipes the JSON to a textfile collector via node_exporter.

**Metrics:** `homelab_iperf3_throughput_bits_per_second{src, dst}` —
direction-aware, per-pair.

**Effort:** 3 h
**Dependencies:** firewall rule allowing iperf3 port 5201 between hosts

### 3.3 Netflow / sFlow / Suricata for per-client bandwidth attribution

**Why:** "who's using the bandwidth?" is currently unanswerable. pfSense
can export Netflow v5/v9 / IPFIX or sFlow to a collector; that gives us
**per-flow** byte/packet counters with `src_ip`, `dst_ip`, `proto`,
`src_port`, `dst_port`.

**Collector options:**

- `goflow2` + Loki/Prometheus (lightweight)
- `pmacct` (most flexible)
- Suricata (already does IDS; adds flow telemetry)
- `ntopng` (heavyweight; rich UI but separate stack)

**Effort:** 4–8 h (varies wildly by collector choice)
**Dependencies:** pfSense Netflow package; storage budget for high-volume
flow data; Cardinality plan (drop short flows, keep aggregates)

### 3.4 SLO definitions + multi-window burn-rate alerts

**Why:** raw alerts page on absolute thresholds. SLO-based alerts (Google
SRE-style) page when the **error budget** burns faster than sustainable
— catches creeping degradation before crisis.

**Initial SLOs to define:**

- **WAN reachability:** 99.9% / 30d on
  `probe_success{job="blackbox-icmp", instance=~"1.1.1.1|8.8.8.8|9.9.9.9"}`
- **DNS latency:** 99% of queries < 200ms over 30d
- **HTTP availability:** 99.5% / 7d on each `.cf.lcamaral.com` and
  `.d.lcamaral.com` endpoint
- **WiFi reachability** (after §2.6): 99% / 7d on
  `probe_success{instance="wifi-canary-rpi"}`

Implement via the `pyrra` SLO controller or hand-rolled recording rules
in `thanos-rules.yml`. Multi-window burn-rate alerts (1h fast,
24h+30d slow) catch both incidents and slow leaks.

**Effort:** 4 h initial + recurring tuning
**Dependencies:** Phase 1 + Phase 2 metrics flowing for ≥7 days
(burn-rate alerts need a stable baseline)

### 3.5 External / 3rd-party uptime monitoring

**Why:** every probe in this plan lives **inside our own network.** If
our entire homelab is unreachable from the internet, we wouldn't know
until users tell us. A separate, **externally hosted** probe answers
"can the world reach my services?"

**Options:**

- **Free tier:** UptimeRobot, BetterStack (formerly Better Uptime),
  Healthchecks.io (push-style)
- **Self-hosted but off-network:** Uptime Kuma on a cheap VPS
- **DIY:** GitHub Actions workflow running blackbox probes against
  public endpoints from a free GH-hosted runner

**Effort:** 1 h (free tier) — 4 h (self-hosted)
**Dependencies:** decision on which targets are "public-promise"

### 3.6 WiFi-client metrics on personal devices

**Why:** the laptop is the device most affected by yesterday's outage
and we have zero metrics from it. If we run `node_exporter` (or a tiny
WiFi-stats textfile script) on the laptop and any personal Linux/Mac
devices, we'd have **end-user-experienced** WiFi quality continuously.

**How (macOS):** launchd job running every 30s:

```sh
#!/bin/sh
INFO=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I)
# parse RSSI, noise, channel, BSSID, txRate, MCS
# emit /var/lib/node_exporter/wifi.prom
```

Then a `node_exporter` instance on the laptop, accessible only from the
homelab (or behind Twingate).

**Effort:** 2 h per device
**Dependencies:** Phase 1 / 2 — get the easy wins first; this is
gold-plating

---

## Quick-reference priority matrix

| Item | Phase | Effort | Impact | Blockers |
|---|:---:|:---:|---|---|
| Enable `--collector.uname` on pfSense | 1.1 | 5min | Unlocks 31 panels for free | None |
| External blackbox probes | 1.2 | 30min | Catches ISP-level issues | None |
| blackbox on NAS (HOME vantage) | 1.3 | 1h | First user-VLAN probe | None |
| Speedtest exporter | 1.4 | 30min | WAN bandwidth visibility | None |
| Promtail pfSense logs → Loki | 1.5 | 2h | DHCP/filter/dpinger event metrics | None |
| Refresh pfsense-availability dashboard | 1.6 | 2h | Surfaces SNMP data | 1.1 helpful |
| Phase 1 alert rules | 1.7 | 1h | Pages on new metrics | 1.1, 1.2 |
| Verify Omada status | 2.1 | 30min | Decision input | None |
| UniFi Vault credentials | 2.2 | 15min | Unblocks UniFi exporter | None |
| Deploy unifi-poller | 2.3 | 1.5h | **Per-AP / per-client WiFi metrics** | 2.2 |
| UniFi Grafana dashboard | 2.4 | 1h | Visualize 2.3 | 2.3 |
| Omada exporter (if needed) | 2.5 | 2h | Parallel for Omada APs | 2.1 + Vault |
| Wireless probe host | 2.6 | 2-3h | **Client-side WiFi visibility** | Spare hardware |
| Per-WAN forced-routing | 2.7 | 2-3h | Per-WAN-independent metrics | Firewall changes |
| Phase E (SNMP image bake) | 3.1 | 2-3h | Closes the last IaC violation | None |
| iperf3 baseline | 3.2 | 3h | Throughput regression detection | None |
| Netflow per-client | 3.3 | 4-8h | "Who's eating the bandwidth" | Storage budget |
| SLO definitions + burn alerts | 3.4 | 4h+ | Page on creeping degradation | Phases 1-2 baseline |
| External 3rd-party uptime | 3.5 | 1-4h | Detects total-homelab outage | Decision |
| Per-laptop wifi metrics | 3.6 | 2h/device | End-user-experienced metrics | Phase 2 first |

---

## Recommended execution order

**Week 1 (Phase 1, ~6-8 h total):**
Day 1: 1.1 + 1.2 (30 min combined — quick visible wins)
Day 2: 1.3 + 1.4 (probe diversity + bandwidth)
Day 3: 1.5 (Loki pipeline — biggest derived-metric unlock)
Day 4-5: 1.6 + 1.7 (dashboards + alerts; consolidates work)

**Week 2-3 (Phase 2, ~8-12 h total):**
Day 1: 2.1 + 2.2 (verification + credentials — gating items)
Day 2: 2.3 + 2.4 (UniFi exporter + dashboard — biggest single win)
Day 3: 2.5 (Omada if needed)
Day 4-5: 2.6 (wireless probe host — depends on hardware availability)
Day 6+: 2.7 (per-WAN — defer until needed by an incident)

**Month 2+ (Phase 3):**
Pick from §3.1-3.6 based on what hurts that month. None are urgent.

---

## What "done" looks like at the end of Phase 2

A recurrence of the 2026-05-25 WiFi outage would produce:

1. `pfsense_gateway_loss_ratio` stays at 0 (router is fine) — confirms
   it's not a WAN/router issue
2. `probe_success{job="blackbox-icmp-home", instance="192.168.4.1"}` from
   NAS goes red briefly — confirms HOME-VLAN-side issue
3. `probe_success{job="blackbox-icmp-wifi"}` from the wireless probe
   tanks to ~20% — confirms it's WiFi-side
4. `unpoller_device_utilization_pct{ap="<name>", radio="5g"}` spikes
   and/or `unpoller_device_channel{}` value changes — confirms DFS event
   on the AP

The alert rules from §1.7 + §2 page within ~5 minutes. Total observed
delay between outage onset and Slack/email page: < 5 min. Compare with
the actual 2026-05-25 detection delay: hours, only because a human
noticed "WiFi is slow."

---

_Plan generated 2026-05-26. Update as items ship; mark each subsection
with a status banner once landed. Open items at end of each phase
become a candidate for the next monthly handoff memory._
