# 📡 ESP32-C5 WiFi Probe — Firmware Submodule

**Date:** 2026-06-06 · **Status:** design approved, not yet built
**Submodule (this repo):** `monitoring/wifi-probe-esp32c5/`
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

## 🧩 Components (`main/`, each a bounded unit)

| Unit | Responsibility | Key ESP-IDF APIs |
|------|----------------|------------------|
| `app_main` | NVS init, **`psa_crypto_init()`**, event loop, ordered bring-up | `nvs_flash`, `esp_event` |
| `config_store` | NVS-backed config: creds, targets[], metrics port, OTA URL, label | `nvs` |
| `wifi_mgr` | STA connect from stored creds; on no-creds/fail → `provisioning` | `esp_wifi` |
| `provisioning` | SoftAP captive portal (DNS hijack + config UI) → writes `config_store` | `esp_http_server`, `esp_netif` |
| `link_stats` | periodic AP-info poll → RSSI/channel/BSSID/connected gauges | `esp_wifi_sta_get_ap_info` |
| `probe_engine` | per target: ICMP + HTTP on schedule → success/duration/status | `esp_ping`, `esp_http_client` |
| `metrics_server` | httpd: `/metrics`, `/` status, `/config` POST, `/healthz` | `esp_http_server` |
| `ota_updater` | pull from manifest URL; `/ota` trigger + optional periodic check | `esp_https_ota`, `esp_tls` |
| `metrics_format` | Prometheus text exposition helpers (HELP/TYPE/labels) | — |

## 📊 Metrics (`/metrics`, Prometheus text v0)

```text
wifi_client_connected 1
wifi_client_rssi_dbm -57
wifi_client_channel 36
wifi_client_bssid_info{bssid="aa:bb:..",ssid="HOME",auth="wpa2"} 1
wifi_client_disconnect_total 3
probe_success{target="1.1.1.1",type="icmp"} 1
probe_duration_seconds{target="1.1.1.1",type="icmp"} 0.012
probe_success{target="https://home.lcamaral.com",type="http"} 1
probe_http_status_code{target="https://home.lcamaral.com"} 200
wifi_probe_uptime_seconds 8123
wifi_probe_heap_free_bytes 142000
wifi_probe_build_info{version="0.1.0",idf="v6.0.1",chip="esp32c5"} 1
```

`tx_rate` is **best-effort / omitted in v0** — instantaneous TX PHY rate is not a
stable public ESP-IDF API. RSSI / channel / BSSID / connected are reliable.

## 📁 Firmware repo layout (ESP-IDF project)

```text
README.md  LICENSE  .gitignore  CMakeLists.txt
sdkconfig.defaults        # CONFIG_IDF_TARGET=esp32c5, OTA partition layout
partitions.csv            # nvs + factory + ota_0 + ota_1
Kconfig.projbuild         # default metrics port, AP SSID prefix, probe intervals
main/                     # the 9 units above (.c/.h) + CMakeLists.txt
docs/  METRICS.md  PROVISIONING.md  OTA.md
.github/workflows/build.yml   # idf.py build for esp32c5 on espressif/idf:v6.0.1
```

## 🔗 Submodule mechanics & doc integration (this repo)

1. Create the private GitHub repo, push the scaffold, then
   `git submodule add <url> monitoring/wifi-probe-esp32c5` → creates
   `.gitmodules` (this repo's first submodule).
2. **New pointer doc** `docs/network/wifi-probe-esp32c5.md`: what it is, the
   metric surface, that firmware lives in the submodule, and a **TODO Prometheus
   scrape-job stub** (static target, pending IoT-VLAN IP + HOME→IoT firewall
   carve-out).
3. **Update** `docs/network/monitoring-plan-2026-05-26.md` §2.6: promote the
   ESP32-C5 as recommended HW (dual-band Wi-Fi 6 rationale), replace the
   "blackbox-on-Pi" note with firmware-native `/metrics`, link the submodule +
   new doc.
4. **Forward-link** in `wifi-internet-quality-2026-05-25.md` → "mitigation: see
   wifi-probe-esp32c5".

## 🧪 ESP-IDF v6 specifics baked into the design

- **PSA Crypto.** v6 ships Mbed TLS v4 — most legacy `mbedtls_*` primitives are
  gone, PSA is primary. `app_main` calls `psa_crypto_init()` before any TLS use;
  OTA (`esp_https_ota`) and HTTPS probes go through `esp_tls`/`esp_https_ota`
  (PSA-backed), never raw `mbedtls_*`.
- **Warnings-as-errors** are on by default in v6 → the scaffold must compile
  clean or CI fails. Accepted as a forcing function.
- Picolibc replaces Newlib (no impact); legacy RMT/MCPWM drivers removed (unused).

## ⚠️ Verification limits

- I can write structurally-correct ESP-IDF v6 C and wire CI to **compile for
  `esp32c5`** (`espressif/idf:v6.0.1` image) — green build is the achievable bar.
- I **cannot flash or runtime-test** without the C5 hardware, and cannot compile
  locally (ESP-IDF v6 not in the mise toolset here). Flash + field-test is a
  hardware-time follow-up.
- The **Prometheus scrape job is documented as a TODO**, not applied — it needs
  the device on the IoT VLAN with a stable IP and a firewall rule allowing
  Prometheus (server VLAN) to scrape it.

## 🚫 Out of scope (v0)

BLE/802.15.4 (Thread/Zigbee) radios, mDNS auto-discovery of the scrape target,
TLS _on the device's own_ `/metrics` endpoint (plain HTTP on the trusted IoT
VLAN), and battery/power management. All are candidate v1+ items.
