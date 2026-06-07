# 📡 WiFi Probes — Grafana Dashboard & Per-Room Deployment

How to deploy ESP32-C5 WiFi probes one-per-room and see them on the
**📡 WiFi Probes — Household Coverage** Grafana dashboard
(`uid: wifi-probes-overview`).

- Firmware/submodule: `monitoring/esp32-c5-wifi-probe/` (see its `docs/METRICS.md`).
- Dashboard generator: `scripts/grafana/build_wifi_probes_overview.py`.
- Dashboard JSON: `terraform/portainer/stacks/grafana-dashboards/wifi-probes-overview.json`.
- Design: `docs/superpowers/specs/2026-06-06-wifi-probes-dashboard-design.md`.

## How rooms are separated

Each metric a probe exposes is stamped at scrape time with a `room` label (and a
friendly `instance`) by the `wifi-probe` Prometheus job. The dashboard's `room`
template variable and every per-room panel key off that label, so adding probes
scales automatically — no dashboard edits. The firmware also self-reports a
`location` label on `wifi_probe_build_info`; the identity table shows it beside the
scrape `room` so you can confirm a probe is physically where its target says.

## Deploy a probe in a new room

### 1. Flash and set the room on the device

```bash
cd monitoring/esp32-c5-wifi-probe
# either bake it in:
idf.py menuconfig   # WiFi Probe → Device location/room  → e.g. living-room
# or leave it and set it at provisioning time via the captive portal's
# "Room / location" field (stored in NVS, survives reflash of app code).
idf.py -p <port> flash
```

Confirm the label once it joins WiFi:

```bash
curl -s http://<probe-ip>:9100/metrics | grep wifi_probe_build_info
# wifi_probe_build_info{version="…",idf="…",chip="esp32c5",location="living-room"} 1
```

### 2. Add the scrape target (both replicas)

Edit the `wifi-probe` job in `terraform/portainer/locals.tf` — it appears in **both**
`prometheus_scrape_config_a` and `prometheus_scrape_config_b`. Replace the empty
`static_configs: []` with one entry per probe:

```yaml
- job_name: wifi-probe
  metrics_path: /metrics
  static_configs:
    - targets: [192.168.59.80:9100]
      labels: { instance: wifi-probe-living-room, room: living-room }
    - targets: [192.168.59.81:9100]
      labels: { instance: wifi-probe-bedroom, room: bedroom }
```

Keep `room` lowercase-kebab and consistent with the device's `location`.

### 3. Apply

```bash
cd terraform/portainer
terraform fmt && terraform plan
terraform apply            # renders prometheus + grafana stacks
# Portainer TF provider may not redeploy on a configs-only change; force it:
python3 ../../scripts/portainer-redeploy.py prometheus
python3 ../../scripts/portainer-redeploy.py prometheus-2
python3 ../../scripts/portainer-redeploy.py grafana
```

Verify the targets are up at the Prometheus targets page, or:

```promql
up{job="wifi-probe"}            # 1 per probe
label_values(up{job="wifi-probe"}, room)   # populates the dashboard's Room picker
```

## Regenerating the dashboard

The JSON is generated — never hand-edit it. Change panels in the generator and re-run:

```bash
python3 scripts/grafana/build_wifi_probes_overview.py
```

Then `terraform apply` + redeploy Grafana as above.

## Requirements & gotchas

- **Reachability:** probes must be on a network Prometheus (`192.168.48.45`) can reach.
  A probe parked on an isolated/guest SSID will show `up == 0`.
- **Empty job is fine:** with no targets the dashboard reads "No data" and the `room`
  picker is empty — that is the shipped default until you add probes.
- **Band-alternating cadence:** per-band link/probe series update once per ~50–110 s
  cycle. The dashboard already compensates (generous `$window`, `last_over_time`,
  `clamp_min`); don't be alarmed by stair-stepped lines or brief gaps.
- **Grafana SQLite-on-NFS issue:** provisioning may lag until that known issue is fixed;
  the JSON artifact itself is correct.
