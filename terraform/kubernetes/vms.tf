# Task 2.1 — 5 Talos VMs (ISO-boot into maintenance mode; self-install to thin-pool-ssd).
# SCAFFOLD: validates the structure + the hardcoded contract; tune disk/agent/boot specifics before apply.
# MACs/IPs come from local.node_map and MUST equal the lab-router dhcpd reservations (no dynamic range).

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.node_map

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = 200 + tonumber(regex("\\d+$", each.value.mac)) # stable id from the MAC suffix; TODO(2.1) confirm range free
  tags      = ["talos", "lab-cluster", each.value.role]

  agent { enabled = true }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }
  memory { dedicated = each.value.ram }

  # Boot the Talos ISO (maintenance mode), then the freshly-installed system disk.
  cdrom {
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide2"
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
  }

  network_device {
    bridge      = local.cluster_bridge
    mac_address = upper(each.value.mac)
    model       = "virtio"
  }

  # Maintenance-mode IP is assigned by the lab-router DHCP reservation keyed on the MAC above.
  boot_order = ["ide2", "scsi0"]

  serial_device {} # Talos console

  lifecycle {
    ignore_changes = [cdrom] # don't churn the VM when the ISO is later detached post-install
  }
}

# TODO(2.2): talos.tf — machine_secrets, data.talos_machine_configuration (endpoint = local.cluster_endpoint,
#   kubernetes_version = local.kubernetes_version, podSubnets=[local.pod_cidr], serviceSubnets=[local.service_cidr],
#   cni:none, proxy.disabled, VIP, install image = factory installer, registry mirror, NTP = local.node_ntp),
#   machine_configuration_apply ×5, machine_bootstrap (cp-1 IP, NOT the VIP), cluster_kubeconfig → Vault.
# TODO(2.3): cilium.tf + argo.tf — Gateway API CRDs (experimental channel, vendored) → Cilium helm_release
#   (nativeRoutingCIDR=local.pod_cidr, BGP localASN=local.asn_cluster) → BGP v2 CRDs → Argo CD.
