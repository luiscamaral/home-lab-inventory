# Keychain backup of network credentials

## Why

On 2026-11-16, `ix0` lost carrier. The server VLAN went down with it, so Vault
was unreachable. Vault holds the Omada and switch logins. Those logins were
needed to reset the switch port. The repair path depended on the failed network.

## What is stored

Vault stays the source of truth. These macOS Keychain items are backup copies.

| Keychain item | Account | Vault source |
| --- | --- | --- |
| `omada-controller-backup` | `lamaral` | `secret/homelab/omada-controller`, field `password` |
| `switch24a-backup` | `admin` | `secret/homelab/switch24a`, field `password` |
| `switch24a-snmp-backup` | `snmp_community` | `secret/homelab/switch24a`, field `snmp_community` |

The Keychain account names match the Vault `username` fields. The SNMP item uses
a fixed account name.

## When to use

If Vault does not answer, use a backup item. Try `http://192.168.59.25:8200`
first. Reach the Omada controller on ADMIN at `https://192.168.32.55:8043`.

```sh
security find-generic-password -s omada-controller-backup -a lamaral -w
```

Never print the value into logs, evidence files or chat. Pass it to the tool
that needs it.

## Refresh after a rotation

After a password or community change in Vault, update the copy. Run the
command without a value. It asks for the secret, so the value does not appear
in the process list or shell history:

```sh
security add-generic-password -U -a lamaral -s omada-controller-backup -w
```

Paste the new value from Vault when asked. Do the same for the other two items
with their own account and item names from the table.

## Limits

A Keychain copy is only as current as its last refresh. It lives on one Mac.
It is not part of the IaC pipeline and has no rollback record. Remove an item
with `security delete-generic-password -s <item> -a <account>`.
