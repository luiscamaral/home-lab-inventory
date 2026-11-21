# ESP32-C5 HIL Harness

Hardware-in-the-loop tooling for the ESP32-C5 WiFi probe project.
See the design spec: `docs/superpowers/specs/2026-06-06-esp32-c5-wifi-probe-design.md`

## Two-port mapping

The ESP32-C5 devkit has two USB connectors:

| Port | VID/PID | macOS device | Purpose |
|------|---------|-------------|---------|
| CH340 UART | `0x1a86` / `0x7523` | `/dev/cu.usbserial-*` | Flash + serial monitor |
| Native USB-JTAG | `0x303a` / any | `/dev/cu.usbmodem*` | OpenOCD, JTAG debug |

Detection is VID/PID-based (not by hardcoded suffix). The usbserial suffix (e.g., `-10`) changes
between USB insertions.

**Currently connected:** only CH340 UART (`/dev/cu.usbserial-10` at time of setup).
**Pending:** native USB-JTAG requires a second USB-C cable to the "USB" port on the devkit.

## Toolchain setup and activation

### First-time fix (already done)

The ESP-IDF Python venv was recreated using Python 3.12 (mise) because 3.14 failed:

```bash
cd ~/esp/esp-idf
/Users/lamaral/.local/share/mise/installs/python/3.12.13/bin/python3 \
  ~/esp/esp-idf/tools/idf_tools.py install-python-env
```

### Activate for each shell session

```bash
source tools/esp32c5/idf-env.sh
idf.py --version   # must print: ESP-IDF v6.0.1
```

The script is idempotent — safe to source multiple times.

## Scripts

### `idf-env.sh`

Activates ESP-IDF v6.0.1. Source it before any other command.

```bash
source tools/esp32c5/idf-env.sh
```

### `detect-ports.sh`

Exports `UART_PORT` and `JTAG_PORT`. Warns if JTAG absent.

```bash
source tools/esp32c5/detect-ports.sh
echo "UART: $UART_PORT, JTAG: ${JTAG_PORT:-absent}"
```

### `flash.sh`

Builds and flashes a project to the CH340 UART port.

```bash
tools/esp32c5/flash.sh tools/esp32c5/smoke
```

### `monitor.sh`

Opens idf.py monitor on the CH340 UART port. Press `Ctrl-]` to exit.

```bash
tools/esp32c5/monitor.sh tools/esp32c5/smoke
```

### `jtag-openocd.sh`

Starts openocd using `board/esp32c5-builtin.cfg`. No-op if JTAG port absent.

```bash
tools/esp32c5/jtag-openocd.sh &
# GDB server: :3333, Telnet: :4444
```

### `gdb-attach.sh`

Attaches `riscv32-esp-elf-gdb` to a running openocd at `:3333`.

```bash
tools/esp32c5/gdb-attach.sh tools/esp32c5/smoke/build/esp32c5-smoke.elf
# GDB commands: target remote :3333 / monitor reset halt / backtrace
```

### `metrics-assert.sh`

Curls `/metrics` and greps for required Prometheus metric names.

```bash
# Check all 11 default metric families (v0 spec)
tools/esp32c5/metrics-assert.sh 192.168.4.50

# Check specific metrics
tools/esp32c5/metrics-assert.sh 192.168.4.50 wifi_client_connected probe_success
```

Exits non-zero if any metric is missing.

## Smoke test

`tools/esp32c5/smoke/` is a minimal ESP-IDF project that validates the build+flash pipeline.

```bash
# Build the smoke test
source tools/esp32c5/idf-env.sh
cd tools/esp32c5/smoke
idf.py set-target esp32c5
idf.py build

# Flash and monitor (look for "ESP32C5-SMOKE-BANNER-OK")
tools/esp32c5/flash.sh tools/esp32c5/smoke
tools/esp32c5/monitor.sh tools/esp32c5/smoke
```

Expected serial output:

```text
ESP32C5-SMOKE-BANNER-OK
Chip: model=... cores=... features=... revision=...
I (123) smoke: Smoke test running on esp32c5
I (124) smoke: IDF version: v6.0.1
I (126) smoke: Heartbeat: 0
```

## JTAG debugging

Both ports are connected (`/dev/cu.usbmodem11201` = USB-JTAG `0x303a`). To debug:

```bash
# Terminal 1: start openocd
tools/esp32c5/jtag-openocd.sh

# Terminal 2: attach gdb
tools/esp32c5/gdb-attach.sh tools/esp32c5/smoke/build/esp32c5-smoke.elf
```

## File layout

```text
tools/esp32c5/
  idf-env.sh          — toolchain activation
  detect-ports.sh     — VID/PID port detection
  flash.sh            — build + flash wrapper
  monitor.sh          — serial monitor wrapper
  jtag-openocd.sh     — openocd launcher (JTAG)
  gdb-attach.sh       — gdb attach to openocd
  metrics-assert.sh   — Prometheus /metrics validator
  README.md           — this file
  smoke/              — minimal smoke test project
    CMakeLists.txt
    sdkconfig.defaults
    main/
      CMakeLists.txt
      smoke_main.c
```

## Future migration

These scripts will migrate to `monitoring/esp32-c5-wifi-probe/tools/` when the firmware submodule
is created (per the design spec §Submodule mechanics).
