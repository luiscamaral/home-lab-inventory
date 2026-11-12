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
  # Portainer keeps a separate PublicURL field (matches agent address).
  # Provider can't clear it once set, so declare it explicitly to match live.
  public_ip = "tcp://192.168.59.34:9001"
}

# ──────────────────────────────────────────────
# dockerserver-2 — App Plane B (VM 124)
# Portainer agent at 192.168.59.59:9001 (macvlan IP)
# Moved .46 → .42 on 2026-06-28: .46 collided with the otel-collector
# stack (dm). .42 was not free either: pihole-exporter-2 (ds-1) is pinned
# there, and Portainer's ARP cache picked the exporter ("connection
# refused"). Moved .42 → .59 on 2026-11-05 after a repo grep, a live
# container scan of all hosts and arping showed .59 unused.
# ──────────────────────────────────────────────
resource "portainer_environment" "ds2" {
  name                = "dockerserver-2"
  environment_address = "tcp://192.168.59.59:9001"
  type                = 2 # Docker agent (EndpointCreationType=2)
  tls_skip_verify     = true
  public_ip           = "tcp://192.168.59.59:9001"
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
