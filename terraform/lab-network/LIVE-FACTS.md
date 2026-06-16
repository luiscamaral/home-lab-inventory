# Lab Cluster — Live Facts (verified 2026-06-16)

Read-only reconnaissance captured before any change. Source of truth for IP/leg selection and version pins.

## Proxmox

| Item | Value |
|---|---|
| RAM | 251 GiB total · ~166 GiB available (85 GiB used) — 78 GiB cluster fits |
| SSH | non-root user; `qm`/`pvesm` need `SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A` |
| Bridges (with host IP) | `vmbr0` 192.168.100.1/24 (**LAB gw**) · `vmbr10` 192.168.7.10/20 (MTU 9000) · `vmbr1`/`vmbr01` mgmt · `vmbr010` |
| Bridges (L2-only, no host IP) | `vmbr28` (SVR/VLAN28) · `vmbr205` (IoT) |

## pfSense (Plus 26.03)

| Interface | Network | Gateway IP |
|---|---|---|
| `ix0.10` HOME | 192.168.0.0/20 | 192.168.4.1 |
| `ix0.28` SVR | 192.168.48.0/20 | 192.168.48.1 |
| `ix0.105` GUEST | 192.168.128.0/24 | 192.168.128.1 |
| `ix0.205` IoT | 192.168.16.0/24 | 192.168.16.1 |
| `igc0` WAN1 | — | 192.168.28.3 |
| `igc3` ADMIN | 192.168.32.32/27 | 192.168.32.33 |

| DHCP pool | Range |
|---|---|
| HOME | 192.168.15.240 – .254 |
| SVR | 192.168.63.192 – .199 |
| GUEST | 192.168.128.51 – .61 |
| IoT | 192.168.16.150 – .254 |
| ADMIN | 192.168.32.55 – .59 |

- **FRR:** not installed; `pfSense-pkg-frr-2.1.2` + `frr10-10.5.1` confirmed available in the Plus 26.03 repo.
- **LAB (192.168.100.0/24)** has no pfSense DHCP — it is a Proxmox-routed segment (gw `.100.1` on `vmbr0`).

## Vault (1.21.4 — raft HA, unsealed)

- **≥ 1.21 ⇒ `audience` is mandatory** on the Kubernetes auth role (confirms vault-wiring spec).
- Creds present: `secret/homelab/proxmox/api_token` (`token_id`/`token_secret`), `secret/homelab/minio`
  (`root_user`/`root_password`), `secret/homelab/cloudflare` (`api_token`/`tunnel_token`),
  `secret/homelab/dreamhost` (`api_token`).
- Pre-existing (treat as placeholders, do not overwrite blindly): `secret/homelab/talos`
  (`cluster_name`, `control_plane_endpoint`, `control_plane_ip`, `kubeconfig`, `talosconfig`),
  `secret/homelab/argocd` (`admin_*`, `url`).

## Chosen addressing (outside all DHCP pools; verify free at apply)

| Leg / node | IP | Bridge |
|---|---|---|
| VyOS SVR leg ↔ pfSense BGP | 192.168.48.2 ↔ 192.168.48.1 | `vmbr28` |
| VyOS HOME leg | 192.168.7.2 | `vmbr10` |
| VyOS LAB leg | 192.168.100.2 | `vmbr0` |
| VyOS CLUSTER leg / gw | 192.168.30.1 | `vmbr30` (new) |
| cp-1/2/3 | 192.168.30.11/.12/.13 | `vmbr30` |
| wk-1/2 | 192.168.30.21/.22 | `vmbr30` |
| API VIP | 192.168.30.5 | `vmbr30` |
| LB pool | 192.168.30.128/25 | (BGP) |

> `arping` is absent on Proxmox; verify each leg IP free via `ip neigh` / a live probe immediately before
> assigning. All candidates are outside the DHCP pools above and clear of the `.59.0/26` macvlan range.
