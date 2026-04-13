# hosts/

Host-level system configuration files for the three Docker VMs
(`dockermaster`, `dockerserver-1`, `dockerserver-2`). These files live
**outside** Docker and are not managed by any Portainer stack — they shape
how the underlying Ubuntu host wires its network interfaces, specifically
the static ens19 IP + the `server-net-shim` macvlan used by the
`docker-servers-net` macvlan bridge.

## Why this exists

On 2026-04-12, during a rolling reboot of the HA cluster, `dockerserver-2`
came back with `dockerserver-1`'s IP (`192.168.48.45` on `ens19`,
`192.168.59.33` on the shim) instead of its own (`.46` / `.46`). Root cause:
when VM 124 was cloned from VM 123 earlier in the project, the files
`/etc/systemd/network/10-ens19.network` and `/etc/systemd/network/10-server-net-shim.network`
were carried along verbatim from ds-1 and never updated to ds-2's IPs. The
VMs had been running fine until then because the IPs had been fixed at
runtime via `ip addr` without being persisted. The reboot revealed the drift
the hard way — two hosts collided on the LAN.

Netplan (`/etc/netplan/00-installer-config.yaml`) also defines ens19 with
the correct IP, but it's shadowed by these override files — which also
own the `MACVLAN=server-net-shim` declaration that creates the host-side
alias on the `docker-servers-net` macvlan. Netplan alone can't create that
alias, so the override files are necessary, not redundant.

## Files per host

| Path | Purpose |
|---|---|
| `10-ens19.network` | Static IP on the primary interface + declares macvlan child |
| `10-server-net-shim.netdev` | Creates the macvlan virtual interface (identical on all 3 hosts) |
| `10-server-net-shim.network` | Assigns the host-side macvlan IP (one per `docker-servers-net` subnet) |

## Canonical values

| Host | ens19 | macvlan shim |
|---|---|---|
| dockermaster | `192.168.48.44/20` | `192.168.59.1/32` |
| dockerserver-1 | `192.168.48.45/20` | `192.168.59.33/32` |
| dockerserver-2 | `192.168.48.46/20` | `192.168.59.46/32` |

## Deploy

```bash
# From the repo root
./hosts/deploy-network-overrides.sh dockermaster
./hosts/deploy-network-overrides.sh dockerserver-1
./hosts/deploy-network-overrides.sh dockerserver-2
```

The script md5-compares each file against the target host and only touches
what's different. Safe to run repeatedly. If any file changes, it restarts
`systemd-networkd` at the end.

## Verify

```bash
ssh dockerserver-2 'ip -4 -o addr show | grep -E "ens19|shim"'
```

Expected output for ds-2:

```text
ens19            inet 192.168.48.46/20 ...
server-net-shim  inet 192.168.59.46/32 ...
```

## When cloning a new VM from one of these hosts

If you clone VM 120/123/124 to make a new Docker VM in the future, run this
script immediately after the clone (with the new hostname set) so the
network override files get the correct IPs for the new host. Otherwise the
new VM will show up on the LAN with the source VM's IP and cause an ARP
collision. Today's incident was the canonical example.
