#!/usr/bin/env bash
# Portainer API helper for the deploy and rollback workflows.
#
# Auth is Vault-first: log in with the AppRole (VAULT_ROLE_ID +
# VAULT_SECRET_ID) or use an existing VAULT_TOKEN, read the Portainer
# admin password from secret/homelab/portainer, then log in to Portainer.
#
# Subcommands:
#   list                      print "name<TAB>id<TAB>endpoint<TAB>status" per stack
#   redeploy NAME [NAME ...]  stop then start each stack (DRY_RUN=true only prints)
#
# The Portainer API is https://192.168.59.2:9443 (self-signed, -k).
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://192.168.59.25:8200}"
PORTAINER_URL="${PORTAINER_URL:-https://192.168.59.2:9443}"
PORTAINER_SECRET_PATH="secret/data/homelab/portainer"
PORTAINER_SECRET_FIELD="admin_password"
DRY_RUN="${DRY_RUN:-false}"

_err() { echo "error: $*" >&2; exit 1; }

_vault_token() {
  if [ -n "${VAULT_TOKEN:-}" ]; then
    printf '%s' "$VAULT_TOKEN"; return 0
  fi
  if [ -n "${VAULT_ROLE_ID:-}" ] && [ -n "${VAULT_SECRET_ID:-}" ]; then
    curl -sS -m 15 --request POST \
      --data "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}" \
      "$VAULT_ADDR/v1/auth/approle/login" | jq -r '.auth.client_token // empty'
    return 0
  fi
  _err "set VAULT_TOKEN or VAULT_ROLE_ID + VAULT_SECRET_ID"
}

_portainer_jwt() {
  local tok pw jwt
  tok="$(_vault_token)"
  [ -n "$tok" ] || _err "Vault login returned no token"
  pw="$(curl -sS -m 15 -H "X-Vault-Token: $tok" \
      "$VAULT_ADDR/v1/$PORTAINER_SECRET_PATH" | jq -r ".data.data.$PORTAINER_SECRET_FIELD // empty")"
  [ -n "$pw" ] || _err "could not read Portainer password from Vault"
  jwt="$(curl -skS -m 15 --request POST \
      --data "{\"username\":\"admin\",\"password\":\"$pw\"}" \
      "$PORTAINER_URL/api/auth" | jq -r '.jwt // empty')"
  [ -n "$jwt" ] || _err "Portainer auth failed"
  printf '%s' "$jwt"
}

_papi() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -skS -m 30 -X "$method" -H "Authorization: Bearer $JWT" \
      -H 'Content-Type: application/json' --data "$body" "$PORTAINER_URL$path"
  else
    curl -skS -m 30 -X "$method" -H "Authorization: Bearer $JWT" "$PORTAINER_URL$path"
  fi
}

list_stacks() {
  _papi GET /api/stacks | jq -r '.[] | [.Name, (.Id|tostring), (.EndpointId|tostring), (.Status // "unknown")] | @tsv'
}

redeploy_stack() {
  local name="$1" row sid ep
  row="$(_papi GET /api/stacks | jq -r ".[] | select(.Name==\"$name\") | \"\(.Id) \(.EndpointId)\"")"
  [ -n "$row" ] || _err "stack not found in Portainer: $name"
  sid="${row%% *}"; ep="${row##* }"
  if [ "$DRY_RUN" = "true" ]; then
    echo "would redeploy $name (id=$sid endpoint=$ep)"; return 0
  fi
  _papi POST "/api/stacks/$sid/stop?endpointId=$ep" >/dev/null
  sleep "${STOP_START_SLEEP:-4}"
  _papi POST "/api/stacks/$sid/start?endpointId=$ep" >/dev/null
  echo "redeployed $name (id=$sid endpoint=$ep)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  list) JWT="$(_portainer_jwt)"; list_stacks ;;
  redeploy) JWT="$(_portainer_jwt)"; for n in "$@"; do redeploy_stack "$n"; done ;;
  *) _err "usage: $0 {list|redeploy NAME [NAME ...]}" ;;
esac
