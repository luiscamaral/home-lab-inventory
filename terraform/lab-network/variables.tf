# ── Proxmox connection ───────────────────────────────────────────────
variable "proxmox_endpoint" {
  description = "Proxmox API base URL"
  type        = string
  default     = "https://192.168.32.61:8006/"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "proxmox"
}

variable "proxmox_insecure" {
  description = "Skip TLS verify for the Proxmox API (LE *.d cert chain / mgmt IP)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "SSH user for bpg file operations (image upload); matches `ssh proxmox`"
  type        = string
  default     = "root"
}

variable "vault_addr" {
  type    = string
  default = "http://vault.d.lcamaral.com"
}

variable "vault_token" {
  type      = string
  sensitive = true
}

# ── VyOS VM ──────────────────────────────────────────────────────────
variable "vyos_image_url" {
  description = "VyOS rolling qcow2 (downloaded ON the Proxmox node). Pin a specific build at apply."
  type        = string
  default     = "https://downloads.vyos.io/rolling/current/generic/qemu/vyos-rolling-latest.qcow2"
}

variable "datastore_images" {
  description = "Proxmox datastore for the downloaded image"
  type        = string
  default     = "local"
}

variable "datastore_disks" {
  description = "Proxmox datastore for VM disks"
  type        = string
  default     = "thin-pool-ssd"
}

# ── Network contract (authoritative copy in LIVE-FACTS.md) ───────────
variable "cluster_bridge" {
  type    = string
  default = "vmbr30"
}

variable "cluster_cidr" {
  type    = string
  default = "192.168.30.0/24"
}

variable "vyos_legs" {
  description = "VyOS interface legs: bridge -> {address, mtu}"
  type = map(object({
    bridge  = string
    address = string
    mtu     = number
  }))
  default = {
    cluster = { bridge = "vmbr30", address = "192.168.30.1/24", mtu = 1500 }
    svr     = { bridge = "vmbr28", address = "192.168.48.2/20", mtu = 1500 }
    home    = { bridge = "vmbr10", address = "192.168.7.2/20", mtu = 9000 }
    lab     = { bridge = "vmbr0", address = "192.168.100.2/24", mtu = 1500 }
  }
}

variable "asn" {
  type = object({ pfsense = number, vyos = number, cluster = number })
  default = {
    pfsense = 65000
    vyos    = 65010
    cluster = 65011
  }
}

variable "pfsense_peer_ip" {
  type    = string
  default = "192.168.48.1"
}

variable "lb_pool_cidr" {
  type    = string
  default = "192.168.30.128/25"
}

variable "gateway_lb_ip" {
  description = "Cilium Gateway LB IP that VyOS DNATs :443/:80 to"
  type        = string
  default     = "192.168.30.128"
}

variable "ntp_upstream" {
  type    = string
  default = "192.168.4.1"
}

# MAC -> final static IP reservations for Talos maintenance-mode bring-up (cluster segment)
variable "node_reservations" {
  description = "Talos node DHCP reservations on vmbr30 (MAC must match the kubernetes root VM map)"
  type        = map(string) # mac => ip
  default = {
    "bc:24:11:30:00:11" = "192.168.30.11" # cp-1
    "bc:24:11:30:00:12" = "192.168.30.12" # cp-2
    "bc:24:11:30:00:13" = "192.168.30.13" # cp-3
    "bc:24:11:30:00:21" = "192.168.30.21" # wk-1
    "bc:24:11:30:00:22" = "192.168.30.22" # wk-2
  }
}
