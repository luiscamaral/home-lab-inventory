# Omada controller DNS and access evidence

## Scope

Collected on 2026-11-16 at 15:28:51 MST from the Mac and Proxmox.
These checks did not change network or host settings.
They did not inspect the controller guest network configuration.

## DNS

Source: Mac. Command: `dig +time=2 +tries=1 +short @<server> <name>`.
The system resolver used `dig +noall +answer <name>`.

| Resolver | Name | A records |
| --- | --- | --- |
| System | `omada-controller.admin.lcamaral.com` | `192.168.32.40` |
| `192.168.100.254` | `omada-controller.admin.lcamaral.com` | `192.168.32.40` |
| `192.168.59.50` | `omada-controller.admin.lcamaral.com` | `192.168.32.40`, `192.168.32.55` |
| `192.168.4.1` | `omada-controller.admin.lcamaral.com` | `192.168.32.40`, `192.168.32.55` |
| System and all three servers | `omada-controller.home.lcamaral.com` | `192.168.4.9` |

The system resolver returned a zero-second TTL for the ADMIN answer.
These results do not identify why the DNS servers gave different answers.

## Controller and HTTP checks

Source: Proxmox. Commands: `qm status 100`, `qm agent 100 network-get-interfaces`,
and `qm config 100`. The guest agent reported:

```text
status: running
ens18 12:32:f0:cc:79:e5 192.168.32.55/27
name: omada-controller
net0: virtio=12:32:f0:cc:79:e5,bridge=vmbr01,firewall=1
```

Source: Mac. Command: `curl --noproxy '*' -ksS --connect-timeout 3 --max-time 5`.
The `-k` option skips TLS certificate verification.

```text
https://omada-controller.admin.lcamaral.com:8043/ timeout, status 000
http://omada-controller.admin.lcamaral.com/ timeout, status 000
https://192.168.32.55:8043/ status 200
http://192.168.32.55:8088/ status 302, redirect https://192.168.32.55:8043/
```

The two name-based requests used the system resolver.
A timeout does not prove the address is unused.
A successful HTTP response does not verify browser login or certificate trust.

## IaC review

Reviewed on 2026-11-16 at 15:30 MST. The local branch was
`fix/ds2-portainer-agent-ip-collision` at `6104e15`. The local
`origin/main` reference was at `091e018`. It was not refreshed for this review.

- `pfsense/host-overrides.yml` declares the ADMIN name as `192.168.32.40`.
- `pihole/dnsmasq.d/06-host-overrides.conf` contains the generated `.40` record.
- `git show origin/main:<path>` showed the same records in both files.
- `docs/network/switch24a-omada-integration-plan.md` records `.55` for VM 100.
- `rg` found no Omada entry in `pfsense/dhcp-static-mappings.yml`.
  That manifest manages only listed reservations. It is not a full inventory.
- `scripts/sync-host-overrides.py` renders the Pi-hole file and reconciles
  pfSense. Its diff includes deletion of live overrides absent from the YAML.
- `pihole/README.md` describes the Pi-hole 2 and 3 Terraform deployment.
  Parts of the README and YAML comments disagree about Pi-hole 1 deployment.
  The script currently includes Pi-hole 1 in its apply path.

No sync or Terraform plan ran during this review.
The repo history and live DNS checks do not establish why `.40` was chosen.

## DHCP reservation review

Collected on 2026-11-16 at 15:33 MST. The source was the pfSense DHCP
section of `/cf/conf/config.xml`, read over SSH and parsed locally.
The query selected the ADMIN range and mappings for the VM MAC or `.55`.

```text
ADMIN range: 192.168.32.55 - 192.168.32.59
TARGET: opt2 12:32:f0:cc:79:e5 192.168.4.9 omada-controller
ADMIN static mappings: .38 xoa-srv, .41 unifi-controller, .43 Unifi-Nano-1
```

There was no ADMIN mapping for the Omada MAC. The HOME mapping still existed.
The lease file showed `.55` active for the Omada MAC. It also showed an
active `.57` lease for another client. The ADMIN pool includes `.55`.

The command `python3 scripts/sync-pfsense-dhcp-static-mappings.py` failed
before its dry run because that Python environment lacked the `yaml` module.
No mapping or pool change was applied.

The local `origin/main` operating rules require a PR and merge before apply.
This review did not refresh the remote reference.

## Static address preparation

Collected on 2026-11-16 at 15:36 MST from the Mac, pfSense, and Proxmox.
The user selected `192.168.32.40` for the controller.

- The pfSense DHCP configuration had no mapping for `.40`.
- An ICMP probe to `.40` received no replies. The pfSense ARP entry was incomplete.
  These checks do not prove the address is free.
- The guest agent reported Ubuntu 20.04.6 and `ens18` at `.55/27` using DHCP.
- The default gateway and DNS server were both `192.168.32.33`.
- `systemd-networkd` was active. Netplan generated its network file.
- `/etc/netplan/01-netcfg.yaml` was the only file listed under `/etc/netplan`.
- A direct request to `https://192.168.32.55:8043/` returned HTTP 200.

No guest or pfSense configuration was changed during this collection.

## Reservation preparation

Collected on 2026-11-16 after 15:36 MST. In the reservation worktree, the
full DHCP dry run showed the Omada creation and an unrelated description update.
The targeted dry run showed only the Omada creation. Two local tests passed.
The existing sync script does not call the DHCP apply endpoint. The DHCP custom
options sync says that endpoint restarts the service.

The Mac rejected SSH to `.55` because its stored host key differed. The guest
agent reported an ED25519 fingerprint matching the key offered over SSH. The
stored key was not changed. No SSH host-key check was bypassed.

PR 144 merged as `2815ecc`. At 15:43 MST, the targeted sync attempted the
reservation through the pfSense API. It returned HTTP 504 after three attempts.
A fresh read of pfSense configuration showed no ADMIN mapping for the MAC.
The running DHCP configuration still showed only its HOME mapping.

The controller returned HTTP 200 at `.55:8043`. The guest configuration did
not change. The error does not prove that a timed-out request cannot complete
later. Check pending requests and live state before repeating the write.

At 15:44 MST, the targeted dry run still showed the reservation as missing.
The nginx access log showed three HTTP 499 entries for the attempted POSTs.
The DHCP daemon process was running and its log showed successful DHCP replies.
The static mapping model contains an `apply()` method that can spawn a DHCP
apply process. The conditions that call it were not established in this review.

## Limits

The VM has `192.168.32.55` now. This check does not prove how it gets that address.
A DHCP lease observed earlier does not rule out a fixed address via DHCP.
The checks do not establish who set the address or when.
The switch adoption and the far end of port 25 were not checked in this collection.
