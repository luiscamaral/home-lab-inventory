# Vault Auto-Unseal

Systemd oneshot that unseals the local Vault container after `docker.service` starts.

## Files

| File | Destination on host |
| ---- | ------------------- |
| `vault-auto-unseal.sh` | `/usr/local/bin/vault-auto-unseal.sh` |
| `vault-auto-unseal.service` | `/etc/systemd/system/vault-auto-unseal.service` |

## Prerequisites

- `/etc/vault/unseal.key` must exist on the host (sourced from macOS Keychain at deploy time)
- Docker must be installed and running

## Deployment

Deploy to all 3 Docker hosts (dockermaster, ds-1, ds-2):

```bash
for host in dockermaster dockerserver-1 dockerserver-2; do
  scp hosts/_common/etc/vault/vault-auto-unseal.sh "$host":/tmp/
  scp hosts/_common/etc/vault/vault-auto-unseal.service "$host":/tmp/
  ssh "$host" 'SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A install -m 755 /tmp/vault-auto-unseal.sh /usr/local/bin/ && sudo -A install -m 644 /tmp/vault-auto-unseal.service /etc/systemd/system/ && sudo -A systemctl daemon-reload && sudo -A systemctl enable vault-auto-unseal.service'
done
```

## Known Limitation

The service fires on `docker.service` start, NOT on individual container recreates.
If the vault container is recreated (e.g. via Portainer stack redeploy) while
`docker.service` stays running, the service does NOT re-trigger. Manual unseal is
needed: `/usr/local/bin/vault-auto-unseal.sh`

A future improvement could use a systemd path unit or a Docker healthcheck-based
trigger instead.
