#!/usr/bin/env bash
# idf-env.sh — Activate ESP-IDF v6.0.1 idempotently
# Usage: source tools/esp32c5/idf-env.sh
#
# Safe to source multiple times; skips re-activation when already active.
# Sets IDF_PATH, updates PATH, and activates the Python venv.

_IDF_ROOT="${HOME}/esp/esp-idf"
_IDF_EXPECTED_VERSION="6.0.1"

if [ ! -d "${_IDF_ROOT}" ]; then
  echo "ERROR: ESP-IDF not found at ${_IDF_ROOT}" >&2
  echo "       Clone with: git clone --branch v6.0.1 --recursive https://github.com/espressif/esp-idf.git ~/esp/esp-idf" >&2
  return 1
fi

# Check if already activated with the right version
if [ "${IDF_PATH}" = "${_IDF_ROOT}" ] && command -v idf.py >/dev/null 2>&1; then
  _active_ver=$(idf.py --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ "${_active_ver}" = "${_IDF_EXPECTED_VERSION}" ]; then
    # Already active — silent success
    return 0
  fi
fi

# Activate ESP-IDF
# shellcheck source=/dev/null
source "${_IDF_ROOT}/export.sh"

# Verify activation
_active_ver=$(idf.py --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ "${_active_ver}" != "${_IDF_EXPECTED_VERSION}" ]; then
  echo "WARNING: Expected ESP-IDF v${_IDF_EXPECTED_VERSION}, got v${_active_ver:-unknown}" >&2
fi
