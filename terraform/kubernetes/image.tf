# Task 2.1 — Talos Image Factory (ISO-boot, API-only; cluster spec §3 as-built note).
# SCAFFOLD: verify the exact `talos_image_factory_urls` attribute names against provider ~>0.11 before apply.

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = ["siderolabs/qemu-guest-agent"]
        # TODO(2.1): add Proxmox-CSI extensions only if virtio-blk needs them (likely none).
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
  architecture  = "amd64"
}

# Download the Talos ISO to an iso-capable Proxmox store (pre-flight: enable `local` content-types or use NFS).
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore
  node_name    = var.proxmox_node
  # TODO(2.1): confirm the urls attribute name (.urls.iso) for provider ~>0.11.
  url       = data.talos_image_factory_urls.this.urls.iso
  file_name = "talos-${local.talos_version}-nocloud-amd64.iso"
  overwrite = false
}
