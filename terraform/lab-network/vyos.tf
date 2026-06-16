# VyOS rolling image — downloaded ON the Proxmox node (node-side connectivity applies, not the
# workstation's). Proxmox rejects a `.qcow2` import file name, so it is stored as `.img`.
resource "proxmox_download_file" "vyos" {
  content_type = "import"
  datastore_id = var.datastore_images
  node_name    = var.proxmox_node
  url          = var.vyos_image_url
  file_name    = "vyos-rolling.img"
  overwrite    = false
}

# Cloud-init payload (#cloud-config with vyos_config_commands) rendered from the contract.
resource "proxmox_virtual_environment_file" "vyos_cloud_init" {
  content_type = "snippets"
  datastore_id = var.datastore_images
  node_name    = var.proxmox_node

  source_raw {
    file_name = "vyos-lab-cloud-init.yaml"
    data = templatefile("${path.module}/vyos-config.tftpl", {
      legs              = var.vyos_legs
      cluster_cidr      = var.cluster_cidr
      asn               = var.asn
      pfsense_peer_ip   = var.pfsense_peer_ip
      lb_pool_cidr      = var.lb_pool_cidr
      gateway_lb_ip     = var.gateway_lb_ip
      ntp_upstream      = var.ntp_upstream
      node_reservations = var.node_reservations
    })
  }
}

# The VyOS router. Legs map to eth0..eth3 in declared order: cluster, svr, home, lab.
resource "proxmox_virtual_environment_vm" "vyos" {
  name        = "vyos-lab"
  description = "VyOS inter-segment router for the Talos lab cluster (terraform/lab-network)"
  node_name   = var.proxmox_node
  tags        = ["terraform", "lab-cluster", "router"]

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.datastore_disks
    import_from  = proxmox_download_file.vyos.id
    interface    = "virtio0"
    size         = 10
  }

  dynamic "network_device" {
    for_each = ["cluster", "svr", "home", "lab"]
    content {
      bridge = var.vyos_legs[network_device.value].bridge
      mtu    = var.vyos_legs[network_device.value].mtu
    }
  }

  initialization {
    datastore_id      = var.datastore_disks
    user_data_file_id = proxmox_virtual_environment_file.vyos_cloud_init.id
  }

  # vmbr30 must exist before the VM attaches to it (bridge is referenced by name string).
  depends_on = [proxmox_network_linux_bridge.cluster]
}
