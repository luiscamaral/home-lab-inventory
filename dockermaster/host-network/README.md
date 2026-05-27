# 🌐 Host-network IaC — `server-net-shim`

This directory is the authoritative source for each Docker host's
`server-net-shim` macvlan interface. The shim is what lets each host's
process namespace (and `nginx-rproxy` in particular) reach containers
that live on the `docker-servers-net` macvlan.

## Layout

```text
host-network/
├── dm/                  # dockermaster (192.168.48.44)
├── ds-1/                # dockerserver-1 (192.168.48.45)
└── ds-2/                # dockerserver-2 (192.168.48.46)
    ├── 10-server-net-shim.netdev   (creates the macvlan iface + MAC)
    └── 10-server-net-shim.network  (assigns IP + adds route)
```

Each file mirrors `/etc/systemd/network/<filename>` on the host.

## Shim IP allocations

Pick LOW IPs (well below `192.168.59.10`) so they don't fight Docker
IPAM's allocation pool. Docker hands out from `192.168.59.0/26` for
containers attached to `docker-servers-net`; shim IPs in that range
silently collide and route traffic to the wrong host. Lesson
documented in `feedback_macvlan_ip_collisions.md`.

| Host | Shim IP | MAC |
| --- | --- | --- |
| dockermaster | `192.168.59.1` | `02:00:00:00:00:01` |
| ds-1 | `192.168.59.6` | `02:00:00:00:00:06` |
| ds-2 | `192.168.59.7` | `02:00:00:00:00:07` |

History:

- 2026-04-XX: initial deploy gave ds-1 `.33` and ds-2 `.46` — both
  inside the IPAM pool. Created two latent collisions tracked in
  memory:
  - `watchtower-dm` at `.33` collided with ds-1 shim (1 DOWN
    Prometheus target until re-IP)
  - `karma` at `.46` collided with ds-2 shim (UI randomly served
    cAdvisor `/containers/` via ARP race)
- 2026-05-27: re-IP'd both shims to `.6` and `.7`, freed the
  IPAM pool, captured configs in this directory.

## Sync workflow

Edits here → push to live hosts via:

```bash
scripts/sync-host-network.py            # dry-run, shows diff
scripts/sync-host-network.py --apply    # SSH push + systemctl restart
```

The sync restarts `systemd-networkd` on each host **only if its files
changed**. Restart cost: ~1-3 s of host↔macvlan disruption per host
(container-to-container traffic via VLAN is unaffected).

## Manual smoke-test after `--apply`

```bash
# Per host: shim has expected IP
ssh <host> ip -br addr show server-net-shim

# From a peer: shim reachable on its new IP
ping -c 2 <new IP>

# Spot-check that nginx-rproxy on the host can still reach a
# macvlan container upstream (karma is a good canary):
curl -sk http://192.168.59.47:8080/health   # expect "Pong"
```
