# switch24a — TP-Link TL-SG3428X (core L2+ switch)

Config backup + access notes for `switch24a.admin.lcamaral.com` (`192.168.32.39`, admin VLAN).

## Files

- `sysConfigBackup-2026-06-18.cfg` — full text config exported from the switch UI (System Tools →
  Backup & Restore), **sanitized**: the two `user … secret 5 …` password hashes are redacted.
  Use it for reference / diff / Omada Site pre-build. The raw export (with hashes) is kept
  offline; the **admin password is in Vault `secret/homelab/switch24a`**. To restore: apply the
  config, then re-set the admin password from Vault.

## Credentials & SSH

- Login creds: **Vault `secret/homelab/switch24a`** (user `admin`) — no plaintext file.
- SSH needs **legacy algorithms** (its IPSSH stack):

  ```sh
  ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa \
      -o Ciphers=+aes128-cbc,3des-cbc -o RequiredRSASize=1024 admin@192.168.32.39
  ```

## ⚠️ Why SSH is currently blocked (found in this config)

```text
user access-control ip-based enable
user access-control ip-based 192.168.32.60 255.255.255.224 https
```

IP-based management access-control is **enabled** and only permits the admin `/27`
(`192.168.32.32–.63`) over **HTTPS** — **SSH/Telnet are not in the allow-list**, so every SSH
login is denied regardless of credentials. This is _not_ a lockout; it survived the reboot and
password reset because it is saved config. **To enable SSH:** add an SSH entry for the admin
subnet — GUI SECURITY → Access Security → Access Control, or
`user access-control ip-based 192.168.32.60 255.255.255.224 ssh`.

## Config summary (2026-06-18)

- **VLANs:** 10 Home, 21 WAN1-GoogleFiber, 22 WAN2-Verizon, 28 Servers, 105 GuestWifi, 205 IoT.
- **Mgmt:** `interface vlan 1` = `192.168.32.39/27`; default-gateway `192.168.32.33` (pfSense);
  static routes for HOME/SVR/etc. via `.32.33`.
- **STP:** `mstp` with **`spanning-tree guard loop`** on ports (the loop protection enabled
  2026-06-18); **loopback-detection** also configured per-port.
- **LAG:** `port-channel 2` (NAS LAG), tagged VLAN 1,10.
- **Ports:** "general" mode with tagged VLAN sets (trunks to pfSense/Proxmox/APs).
- **Other:** SNMP (engineID only), LLDP, RMON, NTP (`192.168.32.33/.35`), syslog `192.168.1.50`,
  jumbo 9216; users `admin` + `lamaral`.

## Related

- Omada-adoption plan: [`../switch24a-omada-integration-plan.md`](../switch24a-omada-integration-plan.md)
- LAN-trunk outage RCA: [`../2026-06-18-lan-trunk-ix0-outage-rca.md`](../2026-06-18-lan-trunk-ix0-outage-rca.md)
