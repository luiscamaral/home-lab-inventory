#!/usr/bin/env bash
# gdb-attach.sh — Attach riscv32-esp-elf-gdb to a running openocd session
# Usage: tools/esp32c5/gdb-attach.sh [elf_file]
#
# Connects to openocd GDB server at :3333.
# Optionally pass the ELF binary for symbol resolution.
# openocd must already be running (start with jtag-openocd.sh).
#
# Common GDB commands:
#   target remote :3333
#   monitor reset halt
#   backtrace
#   info threads
#   thread apply all bt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Activate toolchain (sets PATH to include riscv32-esp-elf-gdb)
# shellcheck source=idf-env.sh
source "${SCRIPT_DIR}/idf-env.sh" || exit 1

ELF_FILE="${1:-}"

# Verify openocd is reachable
if ! nc -z localhost 3333 2>/dev/null; then
  echo "ERROR: Cannot reach openocd GDB server at :3333" >&2
  echo "       Start openocd first: tools/esp32c5/jtag-openocd.sh" >&2
  exit 1
fi

echo "==> Attaching riscv32-esp-elf-gdb to openocd at :3333"
if [ -n "$ELF_FILE" ]; then
  echo "    ELF: ${ELF_FILE}"
fi
echo ""

GDB_CMD=(riscv32-esp-elf-gdb)

if [ -n "$ELF_FILE" ]; then
  GDB_CMD+=("$ELF_FILE")
fi

# Startup commands: connect and halt
GDB_INIT=(
  "-ex" "target remote :3333"
  "-ex" "monitor reset halt"
  "-ex" "backtrace"
)

"${GDB_CMD[@]}" "${GDB_INIT[@]}"
