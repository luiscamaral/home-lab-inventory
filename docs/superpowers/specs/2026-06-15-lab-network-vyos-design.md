# Design: Lab Network — VyOS Inter-Segment Router (BGP)

**Date:** 2026-06-15
**Status:** ⚠️ **PIVOTED — implemented as FRR-on-Debian, not VyOS** (VyOS rolling images are now
paywalled → HTTP 403). FRR is the same routing engine VyOS wraps, so the BGP / zone-firewall / DHCP /
NAT design below all holds — only the OS + config syntax changed. Live reality, config, and runbook:
`terraform/lab-network/{LIVE-FACTS.md,cloud-init/lab-router.yaml,pfsense-frr-bgp.md,README.md}`.
**Owner:** Luis Amaral
**Relationship:** Prerequisite for `2026-06-15-k8s-talos-proxmox-iac-design.md` (the Talos cluster). Split out per
review because it **touches production routing** (SVR/HOME/LAB) and warrants its own staged rollout + rollback.

> ⚠️ **Blast radius:** this introduces a second router (VyOS) onto live segments and a BGP peering on pfSense. A
> misconfiguration can partition SVR/HOME from the internet. Roll out **leg-by-leg** (§7) with validation gates and a
> rollback at each step.

---

## 1. Goal & scope

Stand up **VyOS rolling** as a fully IaC, declarative **inter-segment router + zone firewall** that:

- Owns and routes the new isolated **CLUSTER** segment (`192.168.30.0/24`).
- Legs onto **SVR, HOME, LAB** so it can route/filter east-west between them and the cluster.
- **eBGP-peers with pfSense (FRR)** so cluster pod/LB routes are reachable homelab-wide without per-host changes.
- Provides the cluster's **self-contained edge** (DNAT), **DHCP** (Talos maintenance-mode bring-up), and **NTP relay**.

pfSense **remains the default gateway** for SVR/HOME and the internet edge. LAB keeps **Proxmox (`192.168.100.1`)** as
its gateway (confirmed live). VyOS supplements, it does not replace, those gateways.

**Non-goals:** re-homing SVR/HOME/LAB default gateways to VyOS (deferred); VyOS HA/VRRP (single instance now).

---

## 2. Shared network contract (authoritative — referenced by the cluster spec)

| Item | Value | Notes |
|---|---|---|
| CLUSTER segment | `192.168.30.0/24`, GW `192.168.30.1` (VyOS) | new internal bridge `vmbr30` (no uplink) |
| Control-plane IPs | cp-1 `.30.11`, cp-2 `.30.12`, cp-3 `.30.13` | static (Talos machineconfig) |
| Worker IPs | wk-1 `.30.21`, wk-2 `.30.22` | static |
| API VIP | `192.168.30.5` | Talos L2 VIP |
| LB pool (Cilium) | `192.168.30.128/25` | BGP-advertised |
| Edge DNAT target | `192.168.30.128` | first LB IP = Cilium Gateway |
| Pod / Service CIDR | `10.244.0.0/16` / `10.96.0.0/12` | internal |
| Node MAC scheme | `bc:24:11:30:00:1X` (nodes), `…:30:00:01` (VyOS cluster leg) | stable; drives DHCP reservations |
| BGP ASNs | pfSense **65000** · VyOS **65010** · cluster **65011** | private range |
| VyOS↔pfSense peer | `192.168.48.2` (VyOS SVR leg) ↔ `192.168.48.1` (pfSense) | session on SVR/VLAN28 |
| VyOS legs | SVR `192.168.48.2` · HOME `192.168.7.2` · LAB `192.168.100.2` · CLUSTER `192.168.30.1` | **verify free** via `pfsense-manage` before commit |
| Service hostnames | `*.lab.lcamaral.com` | Pi-hole split-horizon → LB IP |
| ACME challenge | `_acme-challenge.lab.lcamaral.com` → CNAME → `_acme-challenge.lab.cf.lcamaral.com` | DreamHost static record; Cloudflare-authoritative target |
| NTP source | pfSense `192.168.4.1` (relayed by VyOS) | etcd needs clean time |

---

## 3. VyOS VM & bridge (`bpg/proxmox`)

- **`vmbr30`** — `proxmox_network_linux_bridge` (confirmed supported), **no `ports`** (internal L2 only), no address.
  All Talos VMs + VyOS cluster-leg attach here. `depends_on` for every downstream VM.
- **VyOS VM** — 2 vCPU / 2 GB / 10 GB, **4 NICs** (vmbr28, vmbr10, vmbr0, vmbr30).
- **Provider** — `bpg/proxmox ~> 0.109`, **with an `ssh {}` block** (required for image/file ops) + API token; both from
  Vault.
- **Image** — VyOS rolling qcow2 imported via `proxmox_virtual_environment_download_file` (pin URL + SHA256).
- **Config** — native VyOS cloud-config (NOT generic user-data) uploaded as a `proxmox_virtual_environment_file`
  **snippet** and referenced via `user_data_file_id`; rendered by `templatefile()` from the contract above.

---

## 4. Routing & firewall

### 4.1 BGP (eBGP, 3-tier)

- Cilium (AS65011) advertises **per-node pod /24s** + LB pool to VyOS.
- VyOS (AS65010) **aggregates** to `10.244.0.0/16 summary-only` + originates `192.168.30.0/24`, re-advertises to pfSense
  (AS65000) over the **SVR session** (`.48.2 ↔ .48.1`).
- pfSense (AS65000) FRR: inbound prefix-list accepting only `10.244.0.0/16` + `192.168.30.0/24`; `redistribute bgp` into
  the kernel FIB.

**pfSense prerequisites (one-time, documented bootstrap exceptions — no IaC path):**

1. Install **`pfSense-pkg-frr-2.1.2`** (confirmed available in the Plus 26.03 repo; not yet installed). Manual via
   Package Manager.
2. Firewall **pass rule TCP/179** from `192.168.48.2` on the SVR interface (pfSense is default-deny/TCP-only).
3. **Sloppy state** for the cluster CIDRs — enable _"Bypass firewall rules for traffic on the same interface"_ (or a
   sloppy-state rule) so HOME/SVR→cluster flows survive the asymmetric return path (replies come back via VyOS on-link,
   bypassing pfSense state). _This is the agreed asymmetric-routing fix._

### 4.2 Zone firewall (default-drop; explicit allows only)

| From → To | Allow |
|---|---|
| CLUSTER → SVR | Vault `:8201`, MinIO `:9000`, registry `:443`, Prometheus/Thanos endpoints |
| CLUSTER → LAB | Pi-hole DNS `:53`, NAS NFS `:2049` (new `/volume2` export) |
| CLUSTER → HOME | **drop** (no cluster→home need) |
| SVR → CLUSTER | Prometheus scrape into cluster, kube-API `:6443` (ops) |
| HOME → CLUSTER | only the LB IP `:443`/`:80` (published services) |
| any → internet (via SVR→pfSense) | egress for image pulls, ACME, NTP |

### 4.3 DHCP (cluster segment only)

VyOS serves DHCP on `vmbr30` with **host reservations keyed to each node's stable MAC → its final static IP**. This
makes Talos maintenance-mode IPs deterministic so `talos_machine_configuration_apply.node` is known at plan time (closes
the hidden-imperative gap). No DHCP on any other segment.

### 4.4 Edge (DNAT) & NTP

- **DNAT** `:443`/`:80` arriving on the relevant leg → `192.168.30.128` (Cilium Gateway), with `inbound-interface`
  qualifier to avoid hairpin on in-transit traffic.
- **NTP relay** so isolated cluster nodes reach pfSense NTP (`192.168.4.1`); Talos `machine.time.servers` =
  `[192.168.30.1]` (VyOS) or pfSense directly.

### 4.5 MTU

HOME leg pinned **MTU 9000** (matches `vmbr10`); CLUSTER/`vmbr30` **1500**; **TCP MSS clamp 1460** on the HOME ingress
to guard the jumbo→1500 boundary (PMTUD-safe).

---

## 5. IaC structure

```text
terraform/lab-network/        # NEW root
  providers.tf                # bpg/proxmox (+ssh), vault data; MinIO s3 backend
  bridge.tf                   # vmbr30 (proxmox_network_linux_bridge)
  vyos.tf                     # VyOS VM, NICs, cloud-init snippet (templatefile)
  vyos-config.tftpl           # native VyOS config: interfaces, BGP, zones, DHCP, DNAT, NTP, MSS
  variables.tf / outputs.tf   # exports leg IPs, ASNs for cross-ref
```

- **State:** MinIO S3 backend (`bucket=tfstate`, `key=lab-network`), `use_lockfile=true` + MinIO flags
  (`use_path_style`, `skip_credentials_validation`, `skip_requesting_account_id`, `skip_metadata_api_check`,
  `skip_region_validation`, `skip_s3_checksum`, `endpoints.s3`). Backend creds via `AWS_*` env at init (not Vault data
  source).
- **No `null_resource`** — bridge, VM, and config are all declarative resources; pfSense steps are the only (documented)
  manual bootstrap exceptions.

---

## 6. Bring-up — staged, leg-by-leg (with rollback)

| Step | Action | Validate | Rollback |
|---|---|---|---|
| 0 | Install FRR on pfSense; add TCP/179 rule; **do not peer yet** | FRR service up | uninstall pkg |
| 1 | `vmbr30` + VyOS VM, CLUSTER leg only + DHCP | VyOS reachable on `.30.1`; DHCP leases | destroy root |
| 2 | Add SVR leg `.48.2` | ping/route SVR↔VyOS | remove NIC/leg |
| 3 | Establish **BGP** VyOS↔pfSense (SVR) with prefix-lists | `show ip bgp` both sides; `192.168.30.0/24` in pfSense FIB | shut BGP neighbor |
| 4 | Enable **sloppy state** for cluster CIDRs on pfSense | HOME host → a test `.30.x` TCP works | disable setting |
| 5 | Add HOME `.7.2` (MTU 9000) + LAB `.100.2` legs + zone firewall | east-west matrix behaves; MSS clamp verified | remove leg/zone |
| 6 | DNAT + NTP relay | (after cluster up) edge + `chrony` sync | remove rules |

A failure at any step rolls back only that step; production segments keep pfSense/Proxmox routing throughout.

---

## 7. Risks & validation

- **VyOS SPOF for cluster segment** → single now, VRRP later.
- **BGP partition risk** → staged peer-up with prefix-lists; rollback = `shutdown` neighbor.
- **Asymmetric routing** → pfSense sloppy-state (step 4) — explicitly tested.
- **Validation tooling:** `vtysh -c 'show ip bgp'`, `conntrack -L` on pfSense for state, `tcpdump`/Cilium Hubble for
  path symmetry, `mtr` across the HOME jumbo boundary.

## 8. Open items (verify live before apply)

1. Free IPs for VyOS legs on SVR/HOME/LAB (DHCP scopes via `pfsense-manage`).
2. Exact pfSense FRR redistribution/prefix-list config + whether REST API can install packages (else manual).
3. How Proxmox currently routes/NATs LAB (`192.168.100.0/24`) so VyOS coexists cleanly with `.100.1`.
4. VyOS rolling image URL + SHA256; cloud-init snippet format validation.
