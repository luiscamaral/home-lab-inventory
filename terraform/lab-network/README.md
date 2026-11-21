# `lab-network` — FRR-on-Debian inter-segment router

The lab cluster's inter-segment router: an FRR-on-Debian VM that owns the isolated CLUSTER segment,
BGP-peers with pfSense, and filters east-west traffic. Design:
`docs/superpowers/specs/2026-06-15-lab-network-vyos-design.md` (written for VyOS; **see the pivot note
below**). Runbook for the pfSense side: `pfsense-frr-bgp.md`. Live facts: `LIVE-FACTS.md`.

## Status (2026-06-16): LIVE + verified

- **VM 130 `lab-router`** on Proxmox — FRR / isc-dhcp / nftables active; 4 legs
  (`.30.1` cluster · `.48.2` svr · `.7.2` home · `.100.2` lab); IP-forwarding + masquerade.
- **BGP Established** with pfSense (`192.168.48.1` AS65000 ↔ router `.48.2` AS65010); pfSense learned
  `192.168.30.0/24` in its FIB.
- **Zone firewall enforced** — nftables FORWARD `policy drop` + the design §4.2 allow-matrix.

## Why a script, not Terraform (the bpg pivot)

Two pivots happened during bring-up, both recorded in `LIVE-FACTS.md`:

1. **VyOS → FRR-on-Debian.** VyOS rolling images are now paywalled (HTTP 403). FRR is the same routing
   engine VyOS wraps, on a freely-downloadable Debian cloud image — and it satisfies the project's
   no-paywall rule. The router config lives in `cloud-init/lab-router.yaml`.
2. **bpg/proxmox → `sudo qm`.** bpg needs **root-level SSH** to Proxmox (to upload the cloud-init snippet
   into the root-owned `local:snippets` and import the disk). This host disables direct root SSH
   (escalate via `sudo` only), and bpg has no sudo passthrough. So the VM is provisioned by
   **`bootstrap-lab-router.sh`** — idempotent and version-controlled (re-runnable). Note: the Debian
   image tracks `bookworm/latest` (unpinned) and cloud-init runs `apt`, so two runs months apart can land
   slightly different package versions — re-runnable, not bit-reproducible.

## Provision / reproduce

```sh
./bootstrap-lab-router.sh          # creates vmbr30 + downloads image + stages cloud-init + builds VM 130
```

**Prerequisites / access contract:**

- Proxmox `local` storage must allow the `snippets` content-type (the script enables it idempotently;
  otherwise `qm --cicustom` aborts after the VM+disk are created).
- The router is **key-only** login as `debian@`, reached via the Proxmox host's `/root/.ssh/id_ed25519`
  (the private key matching the `root@proxmox` key authorized in `cloud-init/lab-router.yaml`). There is
  no password. Console fallback if the key path breaks: `qm terminal 130` (serial0 is configured).

## Move it into Terraform (the gated next step)

To make this bpg-managed Terraform instead of a script, **authorize an SSH path bpg can use** — a
security-posture change I did not make unilaterally. Cleanest: a dedicated `terraform` deploy user with a
key + scoped perms (preferred over re-enabling root login). Then either `terraform import` VM 130 + vmbr30,
or destroy+recreate via bpg. Sketch of the target resource:

```hcl
resource "proxmox_virtual_environment_vm" "lab_router" {
  vm_id = 130
  name  = "lab-router"
  # cpu 2 / mem 2048 / scsi0 8G on thin-pool-ssd / 4 NICs vmbr30,28,10,0
  # initialization { user_data_file_id = "local:snippets/lab-router-user.yaml"; ip_config × 4 }
}
```

## Network contract (authoritative copy in `LIVE-FACTS.md`)

| Item | Value |
|---|---|
| CLUSTER segment | `192.168.30.0/24`, gw `.30.1`, bridge `vmbr30` (internal) |
| Cluster nodes / VIP / LB | cp `.11-.13`, wk `.21-.22`, VIP `.5`, LB pool `.128/25` |
| BGP ASNs | pfSense 65000 · router 65010 · cluster 65011 |
| Router legs | svr `.48.2` · home `.7.2` (MTU 1500) · lab `.100.2` |

## Rollback

```sh
ssh proxmox 'SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A qm stop 130 && qm destroy 130 --purge'
# bridge: remove the vmbr30 stanza from /etc/network/interfaces (backup at .bak-labrouter) + ifreload -a
# pfSense side: see pfsense-frr-bgp.md
```

## TODO (Sprint 2)

- Cluster BGP peers (`.30.11-.22`) light up when Talos exists (router already peers them).
- Swap `isc-dhcp-server` (retired by ISC) → Kea.
- Enable the parked edge DNAT once the Cilium Gateway LB IP exists.
