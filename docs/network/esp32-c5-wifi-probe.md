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

## Reliability (fw 0.12.0, 2026-11-08)

- **Restart causes:** every boot reports `wifi_probe_boot_info{reset_reason,restart_cause}`
  and an NVS boot counter `wifi_probe_boot_count`. Shown on the dashboard (Device
  Health) and alerted by `WifiProbeFrequentReboots` (3+ boots in 6 h). Details:
  the submodule's `docs/RELIABILITY.md`.
- **Hangs:** 0.12.0 adds a liveness supervisor (restart on scheduler stall 600 s,
  no link 900 s with back-off, OTA overrun 1200 s) and bounded Wi-Fi scans. On
  0.11.1 a probe could wedge off the network with a healthy heap (home-office was
  silent ~21.5 h until power-cycled by hand).
- **Heap fragmentation (open):** probes still reboot every ~3.5–4.9 h via the heap
  watchdog (`restart_cause="heap_wd"`). Fix in progress (0.13.0: dedicated TLS
  arena, static Wi-Fi TX buffers, fewer allocations).
- On the C5, `esp_restart()` reports `reset_reason="sw_reset"` (verified on
  garage); `power_on` means a real power cycle.

## JTAG note (eco2 board)

The bench board is an `esp32c5-eco2` engineering sample: openocd attaches and
examines the RISC-V core, but reliable halt-debug is flaky (early-silicon debug
module). Override config: `tools/esp32c5/esp32c5-eco2.cfg`.
