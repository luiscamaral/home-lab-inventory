# ──────────────────────────────────────────────
# Portainer Environments (endpoints)
# ──────────────────────────────────────────────
# endpoint_id = 3 (local/dockermaster) is pre-existing, not managed here.

# ──────────────────────────────────────────────
# dockerserver-1 — App + HA Plane A (VM 123)
# Portainer agent at 192.168.59.34:9001 (macvlan IP)
# ──────────────────────────────────────────────
resource "portainer_environment" "ds1" {
  name                = "dockerserver-1"
  environment_address = "tcp://192.168.59.34:9001"
  type                = 2 # Docker agent (EndpointCreationType=2)
  tls_skip_verify     = true
}

# ──────────────────────────────────────────────
# dockerserver-2 — App Plane B (VM 124)
# Portainer agent at 192.168.59.46:9001 (macvlan IP)
# ──────────────────────────────────────────────
resource "portainer_environment" "ds2" {
  name                = "dockerserver-2"
  environment_address = "tcp://192.168.59.46:9001"
  type                = 2 # Docker agent (EndpointCreationType=2)
  tls_skip_verify     = true
}

# ──────────────────────────────────────────────
# NAS — Synology NAS (Docker Agent, macvlan)
# Portainer agent at 192.168.4.235:9001 (home-net macvlan IP)
# Switched from Edge Agent (type=4, endpoint 6) to Direct Agent
# (type=2) on 2026-04-16 to eliminate the flaky Edge tunnel that
# prevented reliable terraform applies. See task #38 investigation.
# ──────────────────────────────────────────────
resource "portainer_environment" "nas" {
  name                = "nas"
  environment_address = "tcp://192.168.4.235:9001"
  type                = 2 # Docker agent (EndpointCreationType=2)
  tls_skip_verify     = true
}
