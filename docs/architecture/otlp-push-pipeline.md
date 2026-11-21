# 📡 ESP32-C5 WiFi Probes — OTLP Push Pipeline

Gap-free metrics for single-radio WiFi probes via push-to-collector caching.

## 🎯 Problem

Each ESP32-C5 probe has one radio, time-multiplexed between 5 GHz and 2.4 GHz
(~45–110 s per band). Prometheus scrapes `/metrics` every 30 s. When a scrape lands
during a band's off-air window, the direct `:9100` scrape misses that band's data,
producing the gaps in the probe success matrix. A longer scrape interval cannot fix
it — the off-band is simply not connected at scrape time.

## 🏗️ Architecture

Probes _push_ OTLP/HTTP to an OpenTelemetry Collector that _caches_ each series for
30 min; Prometheus scrapes the collector (always serving the last-pushed value)
instead of the probes — bridging the dark windows.

```text
ESP32-C5 probe (fw 0.10.4)                   otel-collector (192.168.59.46)
  band_scheduler.do_phase():                  OTLP/HTTP receiver  :4318
    after each probe round ->                   | batch processor
    otlp_exporter_push()      -- plain HTTP --> prometheus exporter :8889
    chunked OTLP/JSON (~7 POSTs)                 |  metric_expiration 30m
    20 KB static buffer                          |  resource_to_telemetry -> room/instance
                                                 self-telemetry      :8888
                                                      |
                              Prometheus x2  scrape :8889 (honor_labels)
                                             + scrape :8888 (job=otel-collector)
                                                      | Thanos -> Grafana
```

## 🧩 Components

- _Firmware exporter_ — `main/otlp_exporter.c` (fw 0.10.4). Serializes the full
  `/metrics` surface to OTLP/JSON in a 20 KB static `.bss` buffer, chunked (flush at
  13 KB, ~7 POSTs/cycle). Plain HTTP only; gates: connected + `http://` endpoint +
  5 s throttle. Called after each probe round.
- _Collector_ — `terraform/portainer/stacks/otel-collector.yml.tftpl`
  (opentelemetry-collector-contrib:0.110.0, `192.168.59.46`). Pipeline:
  `otlp.http :4318` -> `batch` -> `prometheus :8889` (`metric_expiration: 30m`,
  `resource_to_telemetry_conversion` maps OTLP resource attrs to `room`/`instance`).
  Self-telemetry on `:8888`.
- _Firewall_ — pfSense rule on HOME (`opt2`/`ix0.10`):
  `pass tcp from <Wifi_Probes> to 192.168.48.0/20 port 4318`. Required — the
  `<Wifi_Probes>` alias is otherwise allowed only `:80`/`:443`, so push SYNs are
  silently dropped.
- _Prometheus cutover_ — `terraform/portainer/locals.tf`
  (`prometheus_scrape_config_a`/`_b`). The `wifi-probe` job scrapes
  `192.168.59.46:8889` with `honor_labels: true` (keeps the collector's
  `room`/`instance`/`job` from OTLP resource attrs). New `otel-collector` job
  scrapes `:8888`.
- _Alerts_ — `locals.tf` (`prometheus_rules_yml`). `OtelCollectorDown`
  (`up{job="otel-collector"}==0`) and `WifiProbeNoData`
  (`changes(wifi_probe_uptime_seconds[10m])==0`, push-freshness, since `up` now
  reflects the collector). `WifiProbeInternetDown`/`ProbeFailing`/`Stale`/`HeapLow`
  are unchanged.
- _Dashboard_ — `scripts/grafana/build_wifi_probes_overview.py`. Freshness-based
  and cutover-agnostic (uses `changes(wifi_probe_uptime_seconds)`, not `up`), plus an
  OTLP Push Pipeline row (collector up/RAM, ingest/export throughput, refused and
  send-fail rates, per-room push freshness).

## ⚠️ Gotchas & lessons

- _New internal push service needs a pfSense rule._ Adding the collector required
  opening `<Wifi_Probes> -> SRVAN:4318`. "No firewall state" is ambiguous — it can
  mean _not sent_ or _sent-and-dropped_. Capture on the ingress interface
  (`tcpdump -i ix0.10 host <probe> and port 4318`): retransmitted SYNs with no
  SYN-ACK = dropped en route.
- _OTA regression — `CONFIG_MBEDTLS_DYNAMIC_BUFFER`._ Added in fw 0.9.1 to fix the
  small HTTPS probe's heap, it makes mbedtls allocate a fresh ~16 KB block per TLS
  record — ~81 allocs for the 1.3 MB OTA image, which fails on a fragmented heap
  (download stalls dead at ~34 KB). Fix: `tls_dyn_buf_strategy =
  HTTP_TLS_DYN_BUF_RX_STATIC` in `ota_updater.c` for both the image download and the
  `.sig` fetch (commits 9cb08c8, ffc7b99). `tools/ota-release.sh` also reboots the
  target first for a fresh heap.
- _Static buffer vs OTA heap._ A large `.bss` buffer permanently shrinks the runtime
  heap and starves the OTA TLS download — a 64 KB OTLP buffer made the device
  effectively un-OTA-able. Keep on-device buffers small; chunk instead.
- _Portainer TF provider does not redeploy on `configs:`-only changes._
  `terraform apply` updates state and the stack file, but the running container keeps
  the old config. Force a stop+start via the Portainer API
  (`POST /api/stacks/{id}/stop` then `/start`).
- _pfSense REST API (`/api/v2`) is not installed_ (the repo CLAUDE.md note is stale —
  returns 404). Manage rules via SSH: `easyrule` (IP sources only) or the PHP config
  API (`write_config()` + `filter_configure()`, which supports alias sources).

## 🔧 Operations

- _Add a probe:_ provision `location` + WiFi creds; ensure its IP is in the pfSense
  `<Wifi_Probes>` alias (grants `-> :4318`). It auto-pushes (Kconfig default
  `otlp_endpoint`). No Prometheus change needed — the collector + `honor_labels` pick
  up new `room`s automatically.
- _Deploy firmware:_ `tools/ota-release.sh <ip> <ota-token>` (build, sign, upload,
  reboot, OTA). Confirm with
  `curl -s http://<ip>:9100/metrics | grep wifi_probe_build_info`.
- _Change collector/Prometheus config:_ edit `locals.tf`, `terraform apply`, then
  force a stop+start of the affected Portainer stacks.

## 📌 Status

- _home-office_ (`192.168.1.42`) and _master-bedroom_ (`192.168.1.43`): fw 0.10.4,
  full chunked push.
- _garage_ (`192.168.1.44`): fw 0.10.0 — pushes fine now that the firewall is open,
  but is stuck on the pre-fix image (un-OTA-able). A one-time USB flash to 0.10.4 is
  recommended for chunking robustness and future OTA-ability
  (`build/esp32-c5-wifi-probe.bin` is the signed 0.10.4 image).
- Cutover verified: both Prometheus replicas scrape the collector; 48 `probe_success`
  series across 3 rooms; 6/6 room×band slots present (gap-free coverage).
