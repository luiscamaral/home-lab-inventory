#!/bin/bash
# deploy.sh — install vault-auto-unseal on a remote homelab host
#
# Usage: ./deploy.sh <host>
#   <host> is an ssh alias (e.g., dockermaster, dockerserver-1)
#
# Reads the unseal key from the macOS Keychain entry 'vault-unseal-key' and
# installs:
#   /usr/local/bin/vault-auto-unseal.sh           (from this directory)
#   /etc/systemd/system/vault-auto-unseal.service (from this directory)
#   /etc/vault/unseal.key                         (mode 600, from Keychain)
#
# Then: daemon-reload + enable + start (to validate immediately).

set -euo pipefail

HOST="${1:?usage: $0 <host>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEY=$(security find-generic-password -s "vault-unseal-key" -w 2>/dev/null) || {
  echo "ERROR: cannot read 'vault-unseal-key' from macOS Keychain" >&2
  exit 1
}

echo "[$HOST] copying script + unit"
scp -q "$SCRIPT_DIR/vault-auto-unseal.sh" "$HOST:/tmp/vault-auto-unseal.sh"
scp -q "$SCRIPT_DIR/vault-auto-unseal.service" "$HOST:/tmp/vault-auto-unseal.service"

echo "[$HOST] writing unseal key"
# Write the key via stdin to avoid putting it on the command line
ssh "$HOST" "SUDO_ASKPASS=\$HOME/.config/bin/answer sudo -A install -d -m 700 -o root -g root /etc/vault && SUDO_ASKPASS=\$HOME/.config/bin/answer sudo -A tee /etc/vault/unseal.key >/dev/null && SUDO_ASKPASS=\$HOME/.config/bin/answer sudo -A chmod 600 /etc/vault/unseal.key && SUDO_ASKPASS=\$HOME/.config/bin/answer sudo -A chown root:root /etc/vault/unseal.key" <<< "$KEY"

echo "[$HOST] installing script + unit"
ssh "$HOST" "SUDO_ASKPASS=\$HOME/.config/bin/answer sudo -A bash -s" <<'EOF'
set -euo pipefail
install -m 755 -o root -g root /tmp/vault-auto-unseal.sh /usr/local/bin/vault-auto-unseal.sh
install -m 644 -o root -g root /tmp/vault-auto-unseal.service /etc/systemd/system/vault-auto-unseal.service
rm -f /tmp/vault-auto-unseal.sh /tmp/vault-auto-unseal.service
systemctl daemon-reload
systemctl enable vault-auto-unseal.service
echo "enabled vault-auto-unseal.service"
EOF

echo "[$HOST] done — test by running: ssh $HOST 'sudo systemctl start vault-auto-unseal.service && sudo systemctl status vault-auto-unseal.service'"
