# 📡 ESP32-C5 WiFi Probe

A dual-band (2.4/5 GHz, Wi-Fi 6) **ESP32-C5** acting as a synthetic WiFi client
that measures what a real client experiences and exposes Prometheus metrics —
closing the "client-side wireless probe" 0% gap from
[monitoring plan §2.6](monitoring-plan-2026-05-26.md). It was motivated by the
[2026-05-25 WiFi quality incident](wifi-internet-quality-2026-05-25.md).

## Firmware

Lives in the **submodule** `monitoring/esp32-c5-wifi-probe/` (repo
`github.com/luiscamaral/esp32-c5-wifi-probe`, private). ESP-IDF v6.0.1, target
`esp32c5`. Design spec:
`docs/superpowers/specs/2026-06-06-esp32-c5-wifi-probe-design.md`; metric surface:
the submodule's `docs/METRICS.md`.

## Metrics

`/metrics` on `:9100` — device (`wifi_probe_build_info`, uptime, heap), link
(`wifi_client_rssi_dbm`/`channel`/`bssid_info`, band-labeled), and reachability
probes (`probe_success`, `probe_*_total`, `probe_duration_seconds_*`,
`probe_http_status_code`) for gateway / LAN DNS / internet IP / internet HTTPS.

## Prometheus scrape job (TODO — pending deployment)

Once the device is on the IoT VLAN with a stable IP and a HOME→IoT firewall
carve-out so Prometheus (server VLAN) can reach it:

```yaml
- job_name: wifi-probe
  static_configs:
    - targets: ['<iot-vlan-ip>:9100']
      labels: { instance: 'esp32c5-wifi-probe' }
```

Not yet applied — needs provisioning (firmware Phase 6) + an assigned IP first.

## Status

Core firmware (P0–P4: boot, WiFi, `/metrics`, link stats, reachability probes)
implemented, built clean under `-Werror` (CI: GitHub Actions, esp32c5 / IDF
v6.0.1), and boot-verified on hardware. On-air verification + band-alternating
scheduler, captive-portal provisioning, and OTA are pending.

## JTAG note (eco2 board)

The bench board is an `esp32c5-eco2` engineering sample: openocd attaches and
examines the RISC-V core, but reliable halt-debug is flaky (early-silicon debug
module). Override config: `tools/esp32c5/esp32c5-eco2.cfg`.
