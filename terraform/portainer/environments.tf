# ──────────────────────────────────────────────
# Portainer Environments (endpoints)
# ──────────────────────────────────────────────
# endpoint_id = 3 (local/dockermaster) is pre-existing, not managed here.
# endpoint_id = 6 (nas edge agent) is pre-existing, not managed here.

# ──────────────────────────────────────────────
# ds-1 — App + HA Plane A (VM 123)
# Regular Portainer agent at 192.168.59.34:9001
# ──────────────────────────────────────────────
resource "portainer_environment" "ds1" {
  name                = "ds-1"
  environment_address = "192.168.59.34:9001"
  type                = 2  # Docker agent (EndpointCreationType=2)
  tls_skip_verify     = true
}
