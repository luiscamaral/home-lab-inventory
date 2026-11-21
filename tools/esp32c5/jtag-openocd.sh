#!/usr/bin/env bash
# jtag-openocd.sh — Launch openocd for ESP32-C5 via native USB-JTAG port
# Usage: tools/esp32c5/jtag-openocd.sh [openocd extra args]
#
# Requires the native USB port (VID=0x303a) to be connected.
# Uses board config: board/esp32c5-builtin.cfg
# GDB server listens on :3333, telnet on :4444
#
# If JTAG port is absent, prints a clear message and exits 0 (non-fatal).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Activate toolchain (sets PATH to include openocd)
# shellcheck source=idf-env.sh
source "${SCRIPT_DIR}/idf-env.sh" || exit 1

# Detect ports
# shellcheck source=detect-ports.sh
source "${SCRIPT_DIR}/detect-ports.sh"

if [ -z "${JTAG_PORT:-}" ]; then
  echo ""
  echo "NOTE: Native USB-JTAG port (VID=0x303a) not found."
  echo "      Connect the native USB port (second USB cable on the ESP32-C5 board)"
  echo "      to enable JTAG debugging with openocd."
  echo "      UART-only mode: flash + serial monitor still work via CH340."
  echo ""
  exit 0
fi

echo "==> Starting openocd for ESP32-C5 on ${JTAG_PORT}"
echo "    GDB server: :3333  |  Telnet: :4444"
echo "    Attach gdb with: tools/esp32c5/gdb-attach.sh"
echo "    Press Ctrl-C to stop openocd"
echo ""

# Use the board/esp32c5-builtin.cfg which configures esp_usb_jtag interface + esp32c5 target
# This is the standard config for boards with the built-in USB-Serial-JTAG peripheral
EXTRA_ARGS="${*:-}"

# shellcheck disable=SC2086
openocd \
  -f board/esp32c5-builtin.cfg \
  -c "adapter serial ${JTAG_PORT}" \
  ${EXTRA_ARGS}
