#!/bin/bash
# vault-auto-unseal.sh — unseal the local vault container at boot
#
# Runs as a systemd oneshot after docker.service. Waits for the vault container
# to be up and its API to respond, then unseals using the key in $KEY_FILE.
#
# Exits 0 if vault is already unsealed or gets unsealed successfully.
# Exits non-zero if the key file is unreadable, the container doesn't start,
# or the unseal API call fails.

set -euo pipefail

KEY_FILE="${KEY_FILE:-/etc/vault/unseal.key}"
MAX_WAIT="${MAX_WAIT:-180}"

log() {
  logger -t vault-auto-unseal "$*" 2>/dev/null || true
  echo "[vault-auto-unseal] $*" >&2
}

# Auto-detect the local vault container. Matches names: vault, vault-1,
# vault-2, vault-3, ... — the homelab convention. Override with
# VAULT_CONTAINER env if needed.
detect_container() {
  if [ -n "${VAULT_CONTAINER:-}" ]; then
    echo "$VAULT_CONTAINER"
    return
  fi
  docker ps -a --format '{{.Names}}' | grep -E '^vault(-[0-9]+)?$' | head -1
}

[ -r "$KEY_FILE" ] || { log "FAIL: cannot read key file $KEY_FILE"; exit 1; }

# Wait for a vault container to exist (it may be created late during boot)
waited=0
CONTAINER=""
while [ -z "$CONTAINER" ]; do
  CONTAINER=$(detect_container || true)
  if [ -n "$CONTAINER" ]; then
    break
  fi
  sleep 3
  waited=$((waited + 3))
  if [ "$waited" -ge "$MAX_WAIT" ]; then
    log "FAIL: no vault container found after ${MAX_WAIT}s (tried names: vault, vault-N)"
    exit 1
  fi
done
log "detected container: $CONTAINER"

# Wait for it to enter Running state
waited=0
while ! docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; do
  sleep 3
  waited=$((waited + 3))
  if [ "$waited" -ge "$MAX_WAIT" ]; then
    log "FAIL: container $CONTAINER not running after ${MAX_WAIT}s"
    exit 1
  fi
done
log "container $CONTAINER is running"

# Wait for vault API to respond. `vault status` exit codes:
#   0 = unsealed + initialized
#   1 = error (API down, cannot connect, not initialized, etc.)
#   2 = sealed (API up but vault is sealed — that's a valid response)
# We want to break out on 0 OR 2, keep retrying on 1.
# NOTE: keep the status call in `||` form so `set -e` doesn't kill us on exit 2.
waited=0
api_rc=1
while :; do
  docker exec "$CONTAINER" vault status -address=http://127.0.0.1:8200 >/dev/null 2>&1 && api_rc=0 || api_rc=$?
  if [ $api_rc -eq 0 ] || [ $api_rc -eq 2 ]; then
    break
  fi
  sleep 3
  waited=$((waited + 3))
  if [ "$waited" -ge "$MAX_WAIT" ]; then
    log "FAIL: vault API not responding after ${MAX_WAIT}s (last rc=$api_rc)"
    exit 1
  fi
done
log "vault API responding (status rc=$api_rc)"

if [ $api_rc -eq 0 ]; then
  log "vault already unsealed"
  exit 0
fi

log "unsealing..."
# Read the first line of the key file, stripping trailing whitespace/newline.
# We pass the key as a positional arg (briefly visible in `ps` inside the
# container) because `vault operator unseal -` reading from stdin is
# finicky with piped content and can reject a trailing newline as malformed.
IFS= read -r UNSEAL_KEY < "$KEY_FILE" || {
  log "FAIL: could not read key from $KEY_FILE"
  exit 1
}
if docker exec -e VAULT_ADDR=http://127.0.0.1:8200 "$CONTAINER" vault operator unseal "$UNSEAL_KEY" >/dev/null 2>&1; then
  log "unseal successful"
  exit 0
else
  log "FAIL: unseal command failed"
  exit 1
fi
