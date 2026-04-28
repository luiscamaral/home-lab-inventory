#!/bin/bash
# deploy-network-overrides.sh — push the canonical systemd-networkd override
# files from this repo to a homelab host.
#
# Usage: ./deploy-network-overrides.sh <host>
#   <host> must be one of: dockermaster, dockerserver-1, dockerserver-2
#
# The files under hosts/<host>/etc/systemd/network/ are the authoritative
# source of truth for the macvlan shim interface + ens19 static IP. If these
# drift between hosts (e.g., after a VM clone), services on the docker-
# servers-net macvlan will get the wrong host alias and traffic breaks.
#
# This script scp's the three files, compares md5, and reloads systemd-networkd
# only if something changed. Safe to run repeatedly — it's a no-op if the host
# already matches the repo.

set -euo pipefail

HOST="${1:?usage: $0 <dockermaster|dockerserver-1|dockerserver-2>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_DIR="$SCRIPT_DIR/$HOST/etc/systemd/network"

[ -d "$HOST_DIR" ] || { echo "ERROR: no repo config for host '$HOST' at $HOST_DIR" >&2; exit 1; }

CHANGED=0

for file in 10-ens19.network 10-server-net-shim.network 10-server-net-shim.netdev; do
  SRC="$HOST_DIR/$file"
  DST="/etc/systemd/network/$file"
  [ -f "$SRC" ] || { echo "WARN: $SRC not present in repo, skipping" >&2; continue; }

  # Compare md5 (local) vs current-on-host
  LOCAL_MD5=$(md5sum "$SRC" 2>/dev/null | awk '{print $1}' || md5 -q "$SRC" 2>/dev/null)
  # shellcheck disable=SC2029  # intentional: expand $DST on the remote
  REMOTE_MD5=$(ssh "$HOST" "md5sum '$DST' 2>/dev/null | awk '{print \$1}'" || echo "")

  if [ "$LOCAL_MD5" = "$REMOTE_MD5" ]; then
    echo "[$HOST] $file already up to date"
    continue
  fi

  echo "[$HOST] $file differs — deploying ($REMOTE_MD5 -> $LOCAL_MD5)"
  scp -q "$SRC" "$HOST:/tmp/$file"
  # shellcheck disable=SC2029  # intentional: expand $file and $DST on the remote
  ssh "$HOST" "SUDO_ASKPASS=\$HOME/.config/bin/answer sudo -A install -m 644 -o root -g root /tmp/$file $DST && rm /tmp/$file"
  CHANGED=1
done

if [ "$CHANGED" -eq 1 ]; then
  echo "[$HOST] reloading systemd-networkd"
  ssh "$HOST" "SUDO_ASKPASS=\$HOME/.config/bin/answer sudo -A systemctl restart systemd-networkd"
  echo "[$HOST] reloaded — verify with: ssh $HOST 'ip -4 -o addr show | grep -E \"ens19|shim\"'"
else
  echo "[$HOST] nothing to do"
fi
