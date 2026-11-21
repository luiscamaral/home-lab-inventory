# 🌐 Internet & Network — Overview Dashboard

**Date:** 2026-06-02 · **Status:** built + validated, deploy in progress
**Artifact:** `terraform/portainer/stacks/grafana-dashboards/internet-network-overview.json`
**Generator:** `scripts/grafana/build_internet_network_overview.py`
**Grafana uid:** `internet-network-overview` · **Folder:** Homelab

## 🎯 Purpose

A single-pane "NOC wall" for the home network: answer _"is my internet healthy,
where is traffic flowing, is DNS/ad-blocking working, and is anything down?"_ at a
glance, with collapsible rows for drill-down. It is an **overview hub** — the
header links out to the existing deep dashboards (`pfsense-wan-quality`,
`pihole-v6`, `blackbox-overview`, `node-exporter-full`).

All panels read the `thanos` Prometheus datasource. Every metric/label name and
all 42 PromQL expressions were verified live against Thanos Query
(`192.168.59.26:10902`) before authoring — 42/42 return data.

## 🔌 Interface map (verified via SNMP `ifAlias`)

| ifAlias | ifName | Role |
|---------|--------|------|
| WAN1 | igc0 | ISP uplink 1 — dpinger → 8.8.8.8 (`WAN1GW`) |
| WAN2 | igc1 | ISP uplink 2 — dpinger → 192.168.12.1 (`WAN2_DHCP`) |
| HOME | ix0.10 | VLAN 10 |
| SRVAN | ix0.28 | VLAN 28 |
| GUEST | ix0.105 | VLAN 105 |
| IoT | ix0.205 | VLAN 205 |
| ADMIN | igc3 | management |

## 🧱 Layout

**Verdict strip (always visible, 8 stat tiles):** WAN1 RTT · WAN1 loss · WAN2 RTT
· WAN2 loss · WAN ↓ total · DNS resolvers up · Pi-hole block % · soonest cert
expiry.

| Row | State | Panels |
|-----|-------|--------|
| 🌐 Internet / WAN | open | gateway RTT, loss, jitter (per gateway); WAN throughput in↑/out↓; external DNS lookup time |
| 🔀 Throughput & Errors | open | in/out bits/s per `$interface`; errors+discards; interface summary table; per-host top talkers rx/tx |
| 🧭 DNS & Pi-hole | collapsed | resolver up state-timeline; lookup time; query-status donut; block %, gravity domains, clients; queries by instance |
| 🛡️ Firewall (pflog) | collapsed | pass vs block pkt/s; logged bytes/s; block/pass rate stats |
| 🩺 Reachability | collapsed | `probe_success` UP matrix (state-timeline); probes-up %; probe duration; HTTP status table; **SSL cert-expiry table** (soonest first) |

**Template vars:** `$interface` (multi, `label_values(ifHCInOctets{job="snmp-pfsense"}, ifAlias)`),
`$pihole` (multi, `label_values(pihole_query_count, instance)`).

**Thresholds:** RTT 30/80 ms · loss 1/2 % · jitter 10/30 ms · cert 14/30 d · DNS
lookup 50/200 ms.

## ⚠️ Findings baked into the design

- **Firewall is global, not per-interface.** `pfLogInterface*` exposes a single
  pflog interface with no usable index label, so Row 4 shows aggregate pass-vs-block
  only (not per-VLAN). Verified live.
- **WebSocket false-positive excluded.** `rustdesk.home` / `rustdesk-relay.home`
  report `probe_success=0` on plain-GET probes (WS-only upstreams answer `101`, not
  `200`). They are excluded from the _Probes Up %_ tile and called out in a note
  panel. (See memory `blackbox-rproxy WebSocket false positive`.)
- **PromQL regex escaping.** Literal dots in device exclusions use RE2 `[.]`, not
  `\.` — a backslash is eaten by both JSON and PromQL's string parser (caused a 400).

## 🚀 Deployment

IaC only — the JSON is auto-rendered into the `grafana` Portainer stack's
`configs:` via the `fileset` glob in `terraform/portainer/stacks.tf`. Deploy:

```bash
cd terraform/portainer
terraform apply -target=portainer_stack.grafana
# configs-only change does NOT auto-redeploy the running container
# (Portainer TF provider limitation) → force redeploy:
python3 ../../scripts/portainer-redeploy.py grafana   # or stop+start via Portainer API
```

## 🧱 Blocker for live verification

Grafana's SQLite DB is currently **corrupted** (`database disk image is malformed`,
`disk I/O error`, repeated `SQLITE_BUSY`). Provisioning writes the dashboard into
that DB on reload, so the board **cannot render until the DB is repaired**. The
dashboard artifact is valid regardless (proven against live Thanos). Repairing the
DB and resolving the NFS-vs-local volume question (the tftpl currently binds the
SQLite DB onto an NFS path — a likely root cause) are data/infra decisions tracked
separately.
