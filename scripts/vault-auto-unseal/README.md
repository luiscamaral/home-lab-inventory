# vault-auto-unseal

Automatic Vault unseal on host reboot for the homelab vault raft cluster
(vault-1 on dm, vault-2 on ds-1, vault-3 on ds-2).

## Why

The homelab Vault cluster does not use cloud KMS or HSM seal wrapping, so every
host reboot leaves the local Vault node sealed. Before this script existed,
every reboot required a human operator with the unseal key present to manually
run `vault operator unseal` on each node, which is impractical during unattended
maintenance windows. The 2026-04-12 rolling reboot exposed this: three Vault
nodes sealed simultaneously meant raft lost quorum and refused writes until a
human came back with keys.

## How

A systemd oneshot unit (`vault-auto-unseal.service`) runs once at boot after
`docker.service`. It invokes `/usr/local/bin/vault-auto-unseal.sh`, which:

1. Waits up to 180 seconds for the `vault` container to enter Running state
2. Waits up to 180 seconds for the Vault API to respond (sealed or unsealed)
3. If already unsealed, exits 0
4. Otherwise, reads `/etc/vault/unseal.key` and POSTs it via
   `vault operator unseal -` (stdin, so the key never appears in `ps aux`)

The unit has `ConditionPathExists=/etc/vault/unseal.key`, so it silently
no-ops on hosts where the key file isn't present.

## Security trade-off

Storing the unseal key on the host file system is **not** cryptographically
stronger than manual unsealing, but it **is** equivalent in practice:

- The unseal key is at `/etc/vault/unseal.key`, mode 600, root-owned
- Anyone with root on the host can already `docker exec vault ...` and read
  tokens directly from the container
- Anyone with root can also read the contents of the raft volume at
  `/var/lib/vault/raft/`
- Host-level root is therefore the effective trust boundary, and the unseal
  key file sits on the same side of that boundary as everything else

The **real** protection is host access control (SSH keys, pfSense firewall
rules, admin VLAN isolation), not key storage obscurity. If you need a
cryptographic improvement, move to cloud KMS or transit auto-unseal against a
separate vault instance — both out of scope for this homelab.

## Deploy

From your laptop, with the unseal key already stored in macOS Keychain under
service name `vault-unseal-key`:

```bash
./deploy.sh dockermaster
./deploy.sh dockerserver-1
./deploy.sh dockerserver-2
```

Each run installs the script and unit, writes the key file, enables the unit,
and reloads systemd.

## Test

After deployment, validate without rebooting:

```bash
# On the target host
sudo systemctl start vault-auto-unseal.service
sudo systemctl status vault-auto-unseal.service
sudo journalctl -u vault-auto-unseal.service -n 30 --no-pager
```

To test the boot-time path for real, seal + restart a vault container and
watch the unit fire:

```bash
# Example: test on ds-2 (vault-3)
ssh dockerserver-2 'docker exec vault-3 vault operator seal'
ssh dockerserver-2 'docker restart vault-3'
# Wait 30 seconds
ssh dockerserver-2 'docker exec vault-3 vault status | grep Sealed'
```

Note: `docker restart` does not trigger systemd unit re-runs. To validate the
full boot path, reboot the VM: `ssh proxmox 'sudo qm reboot 124'`.

## Files

| File | Destination | Mode | Owner |
|---|---|---|---|
| `vault-auto-unseal.sh` | `/usr/local/bin/vault-auto-unseal.sh` | 755 | root:root |
| `vault-auto-unseal.service` | `/etc/systemd/system/vault-auto-unseal.service` | 644 | root:root |
| _Keychain_ `vault-unseal-key` | `/etc/vault/unseal.key` | 600 | root:root |
