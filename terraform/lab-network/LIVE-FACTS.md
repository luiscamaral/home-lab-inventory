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

> Legs labelled "router" = the live FRR-on-Debian `lab-router` (VM 130), not VyOS (pivoted, see below).

| Leg / node | IP | Bridge |
|---|---|---|
| router SVR leg ↔ pfSense BGP | 192.168.48.2 ↔ 192.168.48.1 | `vmbr28` |
| router HOME leg | 192.168.7.2 (1500 — see note) | `vmbr10` |
| router LAB leg | 192.168.100.2 | `vmbr0` |
| router CLUSTER leg / gw | 192.168.30.1 | `vmbr30` (new) |
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

### RESOLVED — pivoted to FRR-on-Debian; router VM LIVE (2026-06-16)

- Pivoted to **FRR-on-Debian** (freely-available Debian 12 cloud image). Created VM **130 `lab-router`**
  via `sudo qm` (bpg can't root-SSH for snippet/disk ops): 4 NICs on vmbr30/28/10/0 → eth0-3 with
  `.30.1`/`.48.2`/`.7.2`/`.100.2`, default route via pfSense `.48.1`. cloud-init at
  `terraform/lab-network/cloud-init/lab-router.yaml` installs frr/isc-dhcp/nftables + loads BGP (AS65010;
  peers pfSense `.48.1`/AS65000 + 5 cluster nodes/AS65011) + masquerade for cluster egress.
- **Verified LIVE:** FRR/DHCP/nftables active; BGP config loaded; peers Active/Connect (waiting for pfSense
  FRR + the cluster — correct). Debug access: Proxmox root key → `debian@192.168.7.2`.
- Remaining for full Sprint 1: pfSense FRR + BGP neighbor (1.3, production, back up config first),
  sloppy-state + zone-firewall tighten (1.4). Reconcile the bpg VyOS TF → FRR, or keep qm-managed + import.

### Sprint 1.5 hardening + review fixes (2026-06-16)

Zone firewall enforced; reproducible `bootstrap-lab-router.sh`; stale VyOS TF removed. A 3-lens
adversarial review then surfaced fixes, all applied LIVE (BGP stayed Established throughout) + in
`cloud-init/lab-router.yaml`:

- **DNS (was a Sprint-2 blocker):** cluster DHCP resolver moved `192.168.4.1` (HOME, on the dropped
  path) → **`192.168.100.254`** (LAB Pi-hole, permitted by the CLUSTER→LAB :53 rule).
- **Masquerade (was a Sprint-2 blocker):** scoped from "all non-cluster" → **internet-only**
  (`ip daddr != {RFC1918}`). RFC1918 east-west now rides the BGP `/24` with real node source IPs.
- **Firewall matrix:** added pod-CIDR transit (`10.244.0.0/16`), Alertmanager-B (`.4.238:9093` above
  the HOME drop), and SVR→CLUSTER ports for Talos apid (50000/50001), Cilium/Hubble (4244/9962/9965),
  and KSM (8080). MSS clamp switched to **clamp-to-PMTU** (`rt mtu`).
- **NTP relay:** router runs **chrony** — `server 192.168.4.1` + `pool pool.ntp.org` + `local stratum 10`
  floor + `allow 192.168.30.0/24`; DHCP offers `ntp-servers 192.168.30.1`. Verified live: synced **stratum 3**,
  and **pfSense `.4.1` NTP is reachable + a selected source** (so the Sprint-2 "verify pfSense NTP" item is
  closed). The `local stratum 10` floor lets the relay keep serving the isolated cluster if all upstreams drop.
- **As-built corrections:** disk **8G** (spec §3 said 10G); HOME leg MTU **1500** — the _bridge_ `vmbr10`
  is 9000 but the VM virtio NIC was never set jumbo, so the design's "HOME MTU 9000" is **not** as-built
  (the MSS clamp is general PMTUD safety, not a jumbo-boundary guard). `local` storage `snippets`
  content-type enabled (bootstrap now does this idempotently).
- **Access contract:** key-only as `debian@` via the Proxmox host `/root/.ssh/id_ed25519` (matches the
  `root@proxmox` key in cloud-init); console fallback `qm terminal 130` (serial0 configured).
