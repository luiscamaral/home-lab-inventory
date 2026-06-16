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

## Sprint 0 outcome + Sprint 1 blockers (2026-06-16)

- **Proxmox is PVE 9.1.7** (not 8.3.5 as the inventory says) — `bpg/proxmox` targets 9.x, so fine.
- **Proxmox API token is READ-ONLY.** `secret/homelab/proxmox/api_token` = `prometheus@pam!metrics`
  with only `*.Audit` perms — it **cannot create VMs or bridges**. Sprint 1.2 needs a NEW token with
  `VM.Allocate`/`VM.Config.*`/`Datastore.AllocateSpace`/`Sys.Modify`, created via `pveum` (Proxmox root).
- **MinIO writes via the workstation proxies are unreliable** (Cloudflare `502`, internal Nginx mangled
  responses). Buckets exist; manage them from a LAN host with direct `:9000`. New TF roots use **local
  state** (matches existing roots); S3 backend deferred.
- **`siderolabs/talos` provider binary download hangs** from this workstation (GitHub releases /
  `objects.githubusercontent.com` unreachable) — blocks the `kubernetes` root init (Sprint 2). Pre-stage
  the provider or init from a better-connected host.
- **`terraform/minio` root has lost its primary local state** (only a `.backup` remains; would try to
  recreate live Keycloak OIDC + policies) — pre-existing; flagged, not touched.
- VyOS rolling image still to be sourced (downloads on Proxmox, so its connectivity applies, not the
  workstation's).

### Apply attempt (2026-06-16) — token RESOLVED, two environmental blockers remain

- ✅ **Write-capable Proxmox token created + verified.** `sudo pveum` works (askpass helper). Created role
  `LabIaC` + user `terraform@pve` (already had `Administrator`) + token `terraform@pve!labiac` (privsep 0);
  stored at Vault `secret/homelab/proxmox/iac_token`. API auth confirmed (node `proxmox` online,
  `VM.Allocate`/`Sys.Modify` present). Apply with `-var proxmox_token_vault_path=homelab/proxmox/iac_token`.
- ✅ Leg IPs `.48.2`/`.7.2`/`.100.2` confirmed FREE (no ARP/ping reply).
- 🛑 **No root SSH to Proxmox** (`root@192.168.32.61` denied; I am `lamaral` + sudo). bpg needs root-level
  SSH to write `local:snippets` (root-owned) and import disks. Options: give bpg proper SSH (root key or a
  user with write access), OR create the VM via `sudo qm` + `terraform import`.
- 🛑 **VyOS image not freely downloadable** — `downloads.vyos.io/...qcow2` returns **403** (VyOS dropped
  free rolling downloads). Build from source (ISO→qcow2) or use a community nightly mirror, then set
  `var.vyos_image_url` (or pre-stage the disk on Proxmox via sudo).
