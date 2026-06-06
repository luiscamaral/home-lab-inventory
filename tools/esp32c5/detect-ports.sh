#!/usr/bin/env bash
# detect-ports.sh — Detect ESP32-C5 USB ports by VID/PID
# Usage: source tools/esp32c5/detect-ports.sh
#
# Exports:
#   UART_PORT   — CH340 UART bridge (/dev/cu.usbserial-*), VID=0x1a86 PID=0x7523
#   JTAG_PORT   — ESP32-C5 native USB-JTAG (/dev/cu.usbmodem*), VID=0x303a
#
# Port detection is VID/PID-based via ioreg. Never hardcodes the usbserial-N suffix.

_CH340_VID=6790    # 0x1a86
_CH340_PID=29987   # 0x7523
_JTAG_VID=12346    # 0x303a

unset UART_PORT JTAG_PORT

# Detect CH340 UART (VID=0x1a86 / PID=0x7523)
# ioreg lists the IODialinDevice node under the USB device entry
_find_port_by_vid_pid() {
  local vid=$1 pid=$2
  # Extract the IODialinDevice value near the matching idVendor/idProduct pair
  ioreg -p IOUSB -l 2>/dev/null | awk -v vid="$vid" -v pid="$pid" '
    /idVendor/ { v = $NF }
    /idProduct/ {
      p = $NF
      if (v == vid && p == pid) { found=1 }
    }
    found && /IODialinDevice/ {
      # value looks like: "IODialinDevice" = "/dev/cu.usbserial-10"
      gsub(/.*= "/, ""); gsub(/".*/, "");
      print; found=0
    }
  '
}

# CH340 UART
_uart=$(_find_port_by_vid_pid $_CH340_VID $_CH340_PID)
if [ -n "$_uart" ] && [ -e "$_uart" ]; then
  export UART_PORT="$_uart"
else
  # Fallback: scan for any usbserial device if ioreg IODialinDevice not populated
  _uart=$(ls /dev/cu.usbserial-* 2>/dev/null | head -1)
  if [ -n "$_uart" ]; then
    export UART_PORT="$_uart"
    echo "INFO: CH340 IODialinDevice not in ioreg; using first usbserial: $UART_PORT"
  fi
fi

# Native USB-JTAG (VID=0x303a — Espressif)
_jtag=$(_find_port_by_vid_pid $_JTAG_VID "")
if [ -z "$_jtag" ]; then
  # Broader search: any 0x303a device → /dev/cu.usbmodem*
  _jtag=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)
fi
if [ -n "$_jtag" ] && [ -e "$_jtag" ]; then
  export JTAG_PORT="$_jtag"
fi

# Report results
if [ -n "$UART_PORT" ]; then
  echo "UART_PORT=${UART_PORT}  (CH340, VID=0x1a86/PID=0x7523)"
else
  echo "WARNING: CH340 UART port (VID=0x1a86/PID=0x7523) not found." >&2
  echo "         Is the CH340 USB cable connected?" >&2
fi

if [ -n "$JTAG_PORT" ]; then
  echo "JTAG_PORT=${JTAG_PORT}  (Espressif USB-JTAG, VID=0x303a)"
else
  echo "NOTE: Native USB-JTAG port (VID=0x303a) not found."
  echo "      Connect the native USB port (second cable) to enable JTAG debugging."
  echo "      UART-only mode active — flash and monitor still work."
fi
