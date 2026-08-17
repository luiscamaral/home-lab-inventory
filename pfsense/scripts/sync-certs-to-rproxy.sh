#!/bin/sh
# Push renewed ACME certs from pfSense to dockermaster's rproxy cert dir
# (NFS-shared, visible to all 3 rproxy HA peers), then reload nginx on
# each instance so the new cert takes effect immediately.
#
# Called by the pfSense ACME package's "actionlist" feature as a
# post-renewal `shellcommand`. Configured via the pfSense REST API:
#   /services/acme/certificate/action  (POST)
#
# Source-of-truth: terraform/pfsense/scripts/sync-certs-to-rproxy.sh
# Sync to /root/sync-certs-to-rproxy.sh on pfSense via:
#   scripts/sync-pfsense-scripts.py --apply
#
# NOTE: NAS pihole-3 (192.168.4.236) does not currently receive certs.
# When pihole-3 needs HTTPS admin UI, add NAS as a fourth target here.
# See IaC audit N6.

DOMAIN="${1:-d.lcamaral.com}"
DEST_HOST="192.168.48.44"
DEST_USER="lamaral"
DEST_PATH="/nfs/dockermaster/docker/nginx-rproxy/config/cert"
ACME_PATH="/cf/conf/acme"
LOG_TAG="acme-push"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# All 3 nginx-rproxy HA peers — every instance needs to be reloaded so
# clients hitting any node get the new cert. The cert dir is NFS-shared
# from the NAS, so a single scp-to-dockermaster reaches all 3 hosts;
# only the per-instance `nginx -s reload` requires per-host action.
# Using mgmt-VLAN IPs (192.168.48.0/20) directly because pfSense's
# resolver does not have FQDNs for these internal hosts and host keys
# are not pre-populated for hostname forms.
RPROXY_HOSTS="192.168.48.44 192.168.48.45 192.168.48.46"
RPROXY_NAMES="rproxy rproxy-2 rproxy-3"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=5"

log() { logger -t "$LOG_TAG" "$1"; echo "$1"; }

log "Starting cert push for $DOMAIN"

for ext in crt key fullchain ca; do
  if [ ! -f "$ACME_PATH/$DOMAIN.$ext" ]; then
    log "ERROR: Missing $ACME_PATH/$DOMAIN.$ext"
    exit 1
  fi
done

# Let's Encrypt's Generation Y roots (ISRG Root YR/YE, live since 2026-05-13)
# aren't in OS trust stores yet, and no ACME profile or --preferred-chain
# value currently returns a chain anchored to the old, universally-trusted
# ISRG Root X1 (confirmed against Let's Encrypt's own community forum and
# certificates page — this is a CA-side limitation, not a client/acme.sh
# version issue). They do publish the X1 cross-sign of Root YR as a static
# artifact though, so we append it ourselves to the served fullchain —
# verified with `openssl verify -untrusted <extended chain> <leaf>` -> OK.
# Source: https://letsencrypt.org/certs/gen-y/root-yr-by-x1.der
cat > "$WORK_DIR/root-yr-by-x1.pem" <<'PEMEOF'
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
PEMEOF

cat "$ACME_PATH/$DOMAIN.fullchain" "$WORK_DIR/root-yr-by-x1.pem" > "$WORK_DIR/$DOMAIN.fullchain"

# Single scp to the NFS-shared cert dir reaches all 3 rproxy peers.
# SSH_OPTS is intentionally unquoted so the flags split into separate
# argv entries; sh has no arrays, so this is the standard idiom.
# shellcheck disable=SC2086
if ! scp $SSH_OPTS -q "$ACME_PATH/$DOMAIN.crt" "$ACME_PATH/$DOMAIN.key" \
       "$WORK_DIR/$DOMAIN.fullchain" "$ACME_PATH/$DOMAIN.ca" \
       "$DEST_USER@$DEST_HOST:$DEST_PATH/"; then
  log "ERROR: scp to $DEST_HOST failed"
  exit 1
fi

# Restrict permissions on the key (NFS-shared so this fixes it everywhere).
# Variables expanding on the LOCAL side is intentional (DOMAIN/DEST_PATH
# are local script vars, not remote env).
# shellcheck disable=SC2086,SC2029
if ! ssh $SSH_OPTS "$DEST_USER@$DEST_HOST" "chmod 600 $DEST_PATH/$DOMAIN.key"; then
  log "WARN: chmod 600 on key failed (non-fatal)"
fi

# Reload nginx in each rproxy container; failures are logged but do not
# block other peers — partial success is better than partial failure.
i=1
for host in $RPROXY_HOSTS; do
  name=$(echo "$RPROXY_NAMES" | cut -d ' ' -f $i)
  # $name expands on the local side intentionally (it's the rproxy
  # container name from RPROXY_NAMES, not a remote shell var).
  # shellcheck disable=SC2086,SC2029
  if ssh $SSH_OPTS "$DEST_USER@$host" "docker exec $name nginx -t && docker exec $name nginx -s reload"; then
    log "  reloaded $name on $host"
  else
    log "  ERROR: reload failed on $host ($name)"
  fi
  i=$((i + 1))
done

log "Cert push complete for $DOMAIN"
