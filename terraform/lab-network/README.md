# `terraform/lab-network` — VyOS inter-segment router

Creates the cluster bridge (`vmbr30`) and the **VyOS router** (BGP, DHCP, NAT, NTP, MSS clamp) per
`docs/superpowers/specs/2026-06-15-lab-network-vyos-design.md`. Companion runbook:
`docs/superpowers/plans/2026-06-16-talos-lab-cluster.md` (Sprint 1).

## Status (2026-06-16)

**Schema-valid and plan-validated** (`terraform plan` → `4 to add, 0 to change, 0 to destroy`, even with
the read-only token). **NOT applied.** Apply is gated on the prerequisites below — and on a deliberate
go-ahead, because applying reconfigures production (Proxmox host network reload + the pfSense BGP peer).

## Apply prerequisites

1. **Write-capable Proxmox token** (the only existing token, `prometheus@pam!metrics`, is read-only).
   On the Proxmox node:

   ```bash
   pveum role add LabIaC -privs "VM.Allocate VM.Config.Disk VM.Config.CPU VM.Config.Memory \
     VM.Config.Network VM.Config.Cloudinit VM.Config.Options VM.PowerMgmt VM.Audit \
     Datastore.AllocateSpace Datastore.Audit Sys.Modify Sys.Audit SDN.Use"
   pveum user token add terraform@pam labiac --privsep 0
   pveum acl modify / -role LabIaC -token 'terraform@pam!labiac'
   ```

   Store `token_id`/`token_secret` in Vault `secret/homelab/proxmox/iac_token`, then set
   `-var proxmox_token_vault_path=homelab/proxmox/iac_token`.
2. **pfSense FRR installed** (Sprint 1.1 — manual GUI step) so the BGP neighbor comes up.
3. **Pin `var.vyos_image_url`** to a specific VyOS rolling build (image downloads on the Proxmox node).
4. **SSH from the apply host to the Proxmox node** for bpg file ops (`ssh` block, `root`).

> **Recommended:** run from a LAN host (`docker-servers-net`) — direct MinIO/Proxmox/GitHub access avoids
> the workstation's proxy/cert/download problems (see `LIVE-FACTS.md`).

## Apply order (staged, with rollback) — design §6

1. `terraform apply` → `vmbr30` + VyOS up (cluster leg + DHCP). Rollback: `terraform destroy`.
2. Verify VyOS reachable on `192.168.30.1`; bring up **BGP** to pfSense; confirm `192.168.30.0/24` in the
   pfSense FIB. Rollback: `shutdown` the BGP neighbor.
3. Enable pfSense **sloppy-state** for the cluster CIDRs (asymmetric-routing fix). Rollback: disable it.
4. Tighten the **zone firewall** (the documented TODO in `vyos-config.tftpl`).

> **Verify the VyOS config syntax on first boot** — `vyos-config.tftpl` content is from the design, but
> VyOS `set` syntax evolves across rolling builds (esp. firewall zones, DHCP `subnet-id`, `bgp system-as`).
