# Internal cluster bridge — no physical ports, no host IP. VyOS is its only gateway, so the
# CLUSTER segment L2 is isolated (collision-proof) and reaches everything else only via VyOS.
#
# NOTE: applying this triggers a network reload on the Proxmox host (which runs every homelab VM).
# Adding a port-less bridge is non-disruptive, but treat it as a production change.
resource "proxmox_network_linux_bridge" "cluster" {
  node_name = var.proxmox_node
  name      = var.cluster_bridge
  comment   = "CLUSTER segment — internal, routed by VyOS (lab cluster)"
  # No ports (internal L2 only); no address (VyOS holds the gateway .30.1).
}
