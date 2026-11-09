# 📡 ESP32-C5 WiFi Probe

A dual-band (2.4/5 GHz, Wi-Fi 6) **ESP32-C5** acting as a synthetic WiFi client
that measures what a real client in a room experiences. It closes the
"client-side wireless probe" gap from
[monitoring plan §2.6](monitoring-plan-2026-05-26.md), and was motivated by the
[2026-05-25 WiFi quality incident](wifi-internet-quality-2026-05-25.md).

## Fleet

| Room | IP (VLAN 10) | Instance |
|---|---|---|
| home-office | 192.168.1.42 | `HOME-OFFICE-WIFI-PROBE` |
| master-bedroom | 192.168.1.43 | `MASTER-BEDROOM-WIFI-PROBE` |
| garage | 192.168.1.44 | `GARAGE-WIFI-PROBE` |

Running version: `wifi_probe_build_info{version}` (or `GET http://<ip>:9100/status`).

## Firmware

Lives in the **submodule** `monitoring/esp32-c5-wifi-probe/` (repo
`github.com/luiscamaral/esp32-c5-wifi-probe`, private). ESP-IDF v6.0.1, target
`esp32c5`. The submodule tracks the firmware repo's `main`. Release history:
the submodule's `docs/CHANGELOG.md`. Feature docs: its `README.md`, `docs/API.md`,
`docs/METRICS.md`, `docs/OTA.md`. Original design:
`docs/superpowers/specs/2026-06-06-esp32-c5-wifi-probe-design.md`.

Releases are signed (ECDSA-P256, key in Vault `secret/homelab/esp32-fw-signing`),
uploaded to MinIO (`s3.d.lcamaral.com/firmware`) and installed per device with
the submodule's `tools/ota-release.sh <device-ip>`.

## Metrics pipeline

Probes **push** OTLP/HTTP to the otel-collector (`192.168.59.46:4318`), which
caches each series for 30 min and serves them on `:8889`. Prometheus scrapes the
collector (`job="wifi-probe"`), not the probes; see
[OTLP push pipeline](../architecture/otlp-push-pipeline.md). Each probe also
serves `/metrics` on `:9100` for ad-hoc checks.

Dashboard, liveness and alerts: [esp32-c5-wifi-probe-dashboard.md](esp32-c5-wifi-probe-dashboard.md).

## Status (fw 0.14.1, 2026-11-09)

All three probes run **0.14.1** (ESP-IDF v6.0.3) (verified-TLS signed OTA with anti-downgrade,
liveness supervisor, restart causes, TLS arena, SNTP via the gateway, Vault-managed
tokens). Release notes: the submodule's `docs/CHANGELOG.md`.

- **Restart causes:** `wifi_probe_boot_info{reset_reason,restart_cause}` + NVS
  `wifi_probe_boot_count`; dashboard Device Health; alert `WifiProbeFrequentReboots`.
- **Liveness:** restart on scheduler stall (600 s), no link (900 s, back-off),
  OTA overrun (1200 s); bounded Wi-Fi scans. On the C5, `esp_restart()` reports
  `sw_reset`; `power_on` is a real power cycle.
- **OTA:** `tools/ota-release.sh <ip>` (token from Vault `secret/homelab/wifi-probe`).
  Result of the last attempt: `/status.ota`, `wifi_probe_ota_last_result{stage,err}`.
  **Rescue path** when HTTPS OTA cannot complete: set `ota_url` to
  `http://s3.d.lcamaral.com/firmware/esp32-c5-wifi-probe.bin` (port 80 serves
  `/firmware/` read-only; the probes' pfSense alias `Wifi_Probes` only allows TCP
  80/443, so MinIO's `:9000` is unreachable). Used on 2026-11-08 to recover two
  probes without USB.
- **Heap leak fixed in 0.14.1.** Root cause: ESP-IDF v6.0.1's cross-signed
  certificate-bundle path leaked the CA subject (~120 B in 7 blocks) on every HTTPS
  handshake to Google (`internet_https`, once per round), which is the ~18–21 KB/h
  decline behind the ~4-hourly heap-watchdog reboots. Fixed by building with v6.0.3.
  Canary: free heap and live blocks flat over 1 h while 0.14.0 lost ~15 KB and
  gained ~500 blocks. Details: the submodule's `docs/RELIABILITY.md#leak`.

## JTAG note (eco2 board)

The bench board is an `esp32c5-eco2` engineering sample: openocd attaches and
examines the RISC-V core, but reliable halt-debug is flaky (early-silicon debug
module). Override config: `tools/esp32c5/esp32c5-eco2.cfg`.
