# Talos lab cluster — root locals, variables, providers.
#
# The lab-network router is SCRIPT-managed (FRR-on-Debian, no Terraform state/outputs), so the network
# contract below is HARDCODED from terraform/lab-network/cloud-init/lab-router.yaml (the sole MAC source)
# and LIVE-FACTS.md. A typo'd MAC yields NO DHCP lease at all (the dhcpd subnet has no dynamic range) —
# keep `node_map` in lock-step with the cloud-init reservations.

variable "proxmox_endpoint" {
  type        = string
  default     = "https://192.168.32.32:8006/"
  description = "Proxmox VE API endpoint (ADMIN iface)."
}

variable "proxmox_node" {
  type        = string
  default     = "proxmox"
  description = "Proxmox node name (pvenode)."
}

variable "proxmox_token_vault_path" {
  type        = string
  default     = "homelab/proxmox/iac_token"
  description = "Vault KV-v2 path (under mount `secret`) holding the bpg API token (terraform@pve!labiac)."
}

variable "iso_datastore" {
  type        = string
  default     = "pve-servers-shared"
  description = "Proxmox store for the Talos ISO. Must allow content-type `iso` (NFS pve-servers-shared does; `local` does NOT until `pvesm set local --content ...,iso,import`)."
}

variable "vm_datastore" {
  type        = string
  default     = "thin-pool-ssd"
  description = "Proxmox store for VM system disks (LVM-thin SSD)."
}

locals {
  # ---- Pinned version triangle (verified 2026-06-16) — see cluster spec §2 ----
  talos_version      = "v1.13.4" # avoid v1.13.2 (scheduler bug #13350)
  kubernetes_version = "v1.36.1" # pin EXPLICITLY — Talos v1.13 defaults to 1.36
  cilium_version     = "1.19.5"

  # ---- Network contract (as-built; hardcoded from lab-network cloud-init) ----
  cluster_bridge = "vmbr30"
  cluster_cidr   = "192.168.30.0/24"
  cluster_gw     = "192.168.30.1" # the FRR lab-router
  api_vip        = "192.168.30.5"
  lb_pool        = "192.168.30.128/25"
  pod_cidr       = "10.244.0.0/16" # MUST equal pfSense CLUSTER-IN + Cilium nativeRoutingCIDR/podSubnets
  service_cidr   = "10.96.0.0/12"
  node_dns       = "192.168.100.254" # LAB Pi-hole (handed by router DHCP)
  node_ntp       = "192.168.30.1"    # router chrony relay

  # ---- BGP ASNs ----
  asn_pfsense = 65000
  asn_router  = 65010
  asn_cluster = 65011

  # ---- 5-node map — MAC/IP MUST equal cloud-init dhcpd reservations (grep `bc:24:11:30:00:1`) ----
  node_map = {
    cp-1 = { role = "controlplane", mac = "bc:24:11:30:00:11", ip = "192.168.30.11", cpu = 2, ram = 4096 }
    cp-2 = { role = "controlplane", mac = "bc:24:11:30:00:12", ip = "192.168.30.12", cpu = 2, ram = 4096 }
    cp-3 = { role = "controlplane", mac = "bc:24:11:30:00:13", ip = "192.168.30.13", cpu = 2, ram = 4096 }
    wk-1 = { role = "worker", mac = "bc:24:11:30:00:21", ip = "192.168.30.21", cpu = 8, ram = 32768 }
    wk-2 = { role = "worker", mac = "bc:24:11:30:00:22", ip = "192.168.30.22", cpu = 8, ram = 32768 }
  }

  cluster_endpoint = "https://${local.api_vip}:6443"
}

# Proxmox bpg API token from Vault (no SSH block — ISO-boot is API-only; see cluster spec §3).
data "vault_kv_secret_v2" "proxmox_token" {
  mount = "secret"
  name  = var.proxmox_token_vault_path
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = true
  # bpg api_token format: "USER@REALM!TOKENID=UUID". Stored split as token_id/token_secret in Vault.
  api_token = "${data.vault_kv_secret_v2.proxmox_token.data["token_id"]}=${data.vault_kv_secret_v2.proxmox_token.data["token_secret"]}"
}

provider "talos" {}

# `vault` reads VAULT_ADDR + VAULT_TOKEN from the environment (Keychain bootstrap; see terraform/README).
provider "vault" {}

# NOTE: the `helm` and `kubernetes` providers are configured in Task 2.3 from the
# talos_cluster_kubeconfig output (no kubeconfig exists until 2.2). Left unconfigured here on purpose.
