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

DOMAIN="${1:-d.lcamaral.com}"
DEST_HOST="192.168.48.44"
DEST_USER="lamaral"
DEST_PATH="/nfs/dockermaster/docker/nginx-rproxy/config/cert"
ACME_PATH="/cf/conf/acme"
LOG_TAG="acme-push"

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

# Single scp to the NFS-shared cert dir reaches all 3 rproxy peers.
# SSH_OPTS is intentionally unquoted so the flags split into separate
# argv entries; sh has no arrays, so this is the standard idiom.
# shellcheck disable=SC2086
if ! scp $SSH_OPTS -q "$ACME_PATH/$DOMAIN.crt" "$ACME_PATH/$DOMAIN.key" \
       "$ACME_PATH/$DOMAIN.fullchain" "$ACME_PATH/$DOMAIN.ca" \
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
