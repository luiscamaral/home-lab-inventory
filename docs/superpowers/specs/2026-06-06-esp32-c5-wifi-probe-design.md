# 📡 ESP32-C5 WiFi Probe — Firmware Submodule

**Date:** 2026-06-06 · **Status:** design refined (FSM + cache); HIL toolchain provisioning
**Submodule (this repo):** `monitoring/esp32-c5-wifi-probe/`
**Firmware repo:** `github.com/luiscamaral/esp32-c5-wifi-probe` (private)
**Toolchain floor:** ESP-IDF **v6.0.1** (stable) · target `esp32c5`

## 🎯 Purpose

Close the **0%-covered "client-side / wireless probe"** gap from
`docs/network/monitoring-plan-2026-05-26.md` §2.6. Every existing WiFi metric
comes from the AP's side; this is a **dedicated wireless device that measures
what a real WiFi client experiences** end-to-end and exposes it to Prometheus.

The motivating incident (`docs/network/wifi-internet-quality-2026-05-25.md`):
wired paths were pristine while anything crossing the air-link degraded sharply
(an 80%-loss episode). A probe like this would have rendered that as a step in
`probe_success{job="wifi-probe"}`.

## 🛰️ Why ESP32-C5

The C5 is Espressif's **first dual-band 2.4/5 GHz Wi-Fi 6** RISC-V part. The
ESP32-S3 listed as an option in §2.6 is 2.4 GHz-only Wi-Fi 4 — blind to the
5 GHz band where most real home traffic lives. The C5 reached **full
(non-preview) support in ESP-IDF v6.0**, which is why v6.0.1 is the floor.

## 🏗️ Architecture — provisioning approach A (unified captive portal)

On first boot (or after a config-button reset) with no stored WiFi creds, the
device raises an **open SoftAP + DNS-hijack captive portal** serving one web
page that configures **WiFi creds, probe targets, device label, and OTA
manifest URL** — all persisted to NVS. The AP is short-lived (10-min timeout)
and only on the IoT VLAN. Rejected alternative: ESP-IDF `wifi_provisioning`
manager (PoP-secured but only covers WiFi creds, not app config — two
mechanisms).

## 🔁 Monitoring state machine

**Single-radio reality:** the C5 is dual-band but **band-switching, not
concurrent** (one RF path, `ANT_2G`/`ANT_5G` via an external switch) — it
associates to exactly **one AP on one band** at a time. So the probe runs a
**band-alternating cycle** (default period 60 s, configurable; survey can be
disabled).

**Operational FSM (connection lifecycle):**
`BOOT → PROVISIONING → CONNECTING → CONNECTED → DISCONNECTED → RECONNECT_BACKOFF → CONNECTING`

`DISCONNECTED` is **keyed on the 802.11 reason code**: `NO_AP_FOUND` /
`BEACON_TIMEOUT` (RF/AP problem) keep retrying and report
`wifi_client_connected 0` — the device must **never** silently reprovision during
an outage. Only `AUTH` / `4WAY_HANDSHAKE` failures are reprovision candidates, and
only via the physical config button. Exposed: `wifi_client_disconnect_reason`,
`wifi_client_disconnect_total`.

**Band-alternating measurement cycle (inside `CONNECTED`):**

```text
Phase A:  ASSOCIATE_5G(closest) → PROBE_5G (active, on-channel) → SURVEY_2G (passive)
Phase B:  ASSOCIATE_2G(closest) → PROBE_2G (active, on-channel) → SURVEY_5G (passive)
          → loop
```

- **Active reachability** (the probe suite) runs through whichever band is
  anchored; the **other** band gets a **passive survey only** (AP list + per-BSSID
  RSSI). You cannot actively test through a 2.4 GHz AP while anchored on 5 GHz —
  that needs a re-association.
- **Order within a phase is load-bearing:** associate → active probes first (clean
  RTT on the home channel) → _then_ the off-band passive survey (the disruptive
  step) → switch. This quarantines scan blips away from latency samples.
- **"closest" = best-RSSI BSSID** for the SSID on that band, from that band's most
  recent survey; first boot seeds both with an initial dual-band scan.
- If a band has no AP for the SSID, its phase is skipped and
  `wifi_band_available{band}` → 0. Survey-disabled mode skips the `SURVEY_*` steps.
- Every per-band series carries a `band="2g|5g"` label.

## 🧩 Components (`main/`, each a bounded unit)

| Unit | Responsibility | Key ESP-IDF APIs |
|------|----------------|------------------|
| `app_main` | NVS init, **`psa_crypto_init()`**, event loop, ordered bring-up | `nvs_flash`, `esp_event` |
| `config_store` | NVS-backed config: creds, targets[], metrics port, OTA URL, label | `nvs` |
| `wifi_mgr` | STA connect from stored creds; on no-creds/fail → `provisioning` | `esp_wifi` |
| `provisioning` | SoftAP captive portal (DNS hijack + config UI) → writes `config_store` | `esp_http_server`, `esp_netif` |
| `link_stats` | periodic AP-info poll → RSSI/channel/BSSID/connected gauges | `esp_wifi_sta_get_ap_info` |
| `band_scheduler` | drives the band-alternating cycle + activity mutex (associate→probe→survey→switch) | `esp_wifi`, FreeRTOS |
| `probe_engine` | typed checks (gateway/DNS/internet-IP/internet-HTTPS + custom) → counters + gauges, `band`-labeled | `esp_ping`, `esp_http_client`, lwIP DNS |
| `survey` | passive off-band scan → AP-list metrics (top-N BSSID, `band`) | `esp_wifi_scan_*` |
| `metrics_server` | httpd: `/metrics`, `/` status, `/config` POST, `/healthz` | `esp_http_server` |
| `ota_updater` | pull from manifest URL; `/ota` trigger + optional periodic check | `esp_https_ota`, `esp_tls` |
| `metrics_format` | Prometheus text exposition helpers (HELP/TYPE/labels) | — |

## 📊 Metrics (`/metrics`, Prometheus text v0)

```text
# link (labeled by anchored band)
wifi_client_connected{band="5g"} 1
wifi_client_rssi_dbm{band="5g"} -57
wifi_client_channel{band="5g"} 36
wifi_client_bssid_info{band="5g",bssid="aa:bb:..",ssid="HOME",auth="wpa3"} 1
wifi_client_disconnect_total{band="5g"} 3
wifi_client_disconnect_reason{band="5g"} 8
wifi_band_available{band="2g"} 1
# probe suite — counters (window in PromQL) + last-value gauges, by probe/type/band
probe_attempts_total{probe="gateway",type="icmp",band="5g"} 412
probe_success_total{probe="gateway",type="icmp",band="5g"} 410
probe_duration_seconds_sum{probe="gateway",type="icmp",band="5g"} 5.1
probe_duration_seconds_count{probe="gateway",type="icmp",band="5g"} 412
probe_success{probe="gateway",type="icmp",band="5g"} 1
probe_last_success_timestamp_seconds{probe="gateway",type="icmp",band="5g"} 1.749e9
probe_dns_lookup_seconds{probe="lan_dns",type="dns",band="5g"} 0.018
probe_http_status_code{probe="internet_https",type="http",band="5g"} 200
# survey (passive, OTHER band, top-N BSSID)
wifi_ap_rssi_dbm{band="2g",bssid="aa:bb:..",ssid="HOME",channel="6"} -61
wifi_ap_count{band="2g",ssid="HOME"} 2
# device + freshness
wifi_probe_link_last_update_timestamp_seconds{band="5g"} 1.749e9
wifi_probe_uptime_seconds 8123
wifi_probe_heap_free_bytes 142000
wifi_probe_build_info{version="0.1.0",idf="v6.0.1",chip="esp32c5"} 1
```

`tx_rate` is **best-effort / omitted in v0** — instantaneous TX PHY rate is not a
stable public ESP-IDF API. RSSI / channel / BSSID / connected are reliable.

## 🗃️ Metrics cache (collection ≠ scrape)

Probes and surveys are **slow + blocking**, so they never run inside the
`/metrics` handler. A **shared snapshot** (small struct + a variable-length AP
table) is mutex-guarded: background tasks (`band_scheduler`, `probe_engine`,
`survey`) write their fields on their own cadence; `/metrics` takes a quick
consistent snapshot, releases the lock, then renders Prometheus text (chunked) —
fast and non-blocking.

- **Windowing = counters + PromQL.** The cache holds monotonic counters
  (`probe_attempts_total`, `probe_success_total`,
  `probe_duration_seconds_{sum,count}`) plus last-value gauges. Loss %, rate, and
  averages are computed in Prometheus via `rate()`/`increase()` — no window logic
  baked into firmware. Counters reset on reboot (Prometheus handles it);
  `wifi_probe_uptime_seconds` makes resets visible. Metrics are **not** persisted
  to NVS (only config is).
- **Staleness = serve-last + freshness stamp.** Gauges always serve their
  last-known value; every subsystem also emits a `*_last_update_timestamp_seconds`
  (node_exporter style), so "no successful gateway probe in 5 min" is a clean
  PromQL/alert expression rather than a vanishing series.

## 📁 Firmware repo layout (ESP-IDF project)

```text
README.md  LICENSE  .gitignore  CMakeLists.txt
sdkconfig.defaults        # CONFIG_IDF_TARGET=esp32c5, OTA partition layout
partitions.csv            # nvs + factory + ota_0 + ota_1
Kconfig.projbuild         # default metrics port, AP SSID prefix, probe intervals
main/                     # the units above (.c/.h) + CMakeLists.txt
docs/  METRICS.md  PROVISIONING.md  OTA.md
.github/workflows/build.yml   # idf.py build for esp32c5 on espressif/idf:v6.0.1
```

## 🔗 Submodule mechanics & doc integration (this repo)

1. Create the private GitHub repo, push the scaffold, then
   `git submodule add <url> monitoring/esp32-c5-wifi-probe` → creates
   `.gitmodules` (this repo's first submodule).
2. **New pointer doc** `docs/network/esp32-c5-wifi-probe.md`: what it is, the
   metric surface, that firmware lives in the submodule, and a **TODO Prometheus
   scrape-job stub** (static target, pending IoT-VLAN IP + HOME→IoT firewall
   carve-out).
3. **Update** `docs/network/monitoring-plan-2026-05-26.md` §2.6: promote the
   ESP32-C5 as recommended HW (dual-band Wi-Fi 6 rationale), replace the
   "blackbox-on-Pi" note with firmware-native `/metrics`, link the submodule +
   new doc.
4. **Forward-link** in `wifi-internet-quality-2026-05-25.md` → "mitigation: see
   esp32-c5-wifi-probe".

## 🧪 ESP-IDF v6 specifics baked into the design

- **PSA Crypto.** v6 ships Mbed TLS v4 — most legacy `mbedtls_*` primitives are
  gone, PSA is primary. `app_main` calls `psa_crypto_init()` before any TLS use;
  OTA (`esp_https_ota`) and HTTPS probes go through `esp_tls`/`esp_https_ota`
  (PSA-backed), never raw `mbedtls_*`.
- **Warnings-as-errors** are on by default in v6 → the scaffold must compile
  clean or CI fails. Accepted as a forcing function.
- Picolibc replaces Newlib (no impact); legacy RMT/MCPWM drivers removed (unused).

## 🧪 Build & test — hardware-in-the-loop

A C5 dev board is on USB, so this is **HIL, not CI-only**:

- **Toolchain:** ESP-IDF **v6.0.1** installed natively at `~/esp/esp-idf`
  (riscv32 toolchain + `openocd-esp32`); Python env pinned to mise Python 3.12
  (v6.0 rejects 3.14).
- **Two USB-C ports:** CH340 UART (`/dev/cu.usbserial-*`, VID `0x1a86`) for
  `idf.py flash/monitor`; native USB-Serial-JTAG (`/dev/cu.usbmodem*`, VID
  `0x303a`) for `openocd` + `gdb`. **JTAG port pending** a data cable on the
  second port; the harness degrades to UART-only until then.
- **Agent team + harness** (under `.claude/agents/` + `tools/esp32c5/`):
  `esp32c5-firmware-dev`, `-build-flash`, `-hil-tester`, `-test-orchestrator`,
  plus flash/monitor/openocd/metrics-assert scripts and a hello-world smoke test.
- **CI** still builds for `esp32c5` (`espressif/idf:v6.0.1`) as a board-independent
  gate.
- The **Prometheus scrape job stays a documented TODO** — needs the device on the
  IoT VLAN with a stable IP + a HOME→IoT firewall carve-out.

## 🚫 Out of scope (v0)

BLE/802.15.4 (Thread/Zigbee) radios, mDNS auto-discovery of the scrape target,
TLS _on the device's own_ `/metrics` endpoint (plain HTTP on the trusted IoT
VLAN), and battery/power management. All are candidate v1+ items.
