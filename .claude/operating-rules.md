# ⛔ Operating non-negotiables — homelab inventory

Read this before ANY infrastructure change. It overrides speed/convenience.
Auto-loaded at session start and re-surfaced by the IaC-guard hook on risky commands.
This file is the single source of truth — CLAUDE.md and the hooks point here.

## 1. IaC only — never touch a host/router config directly
Every change goes through a declarative source in the repo, then a tool applies it.
**IaC is NOT only Terraform.** Map of surface → source → apply:

| Surface | Declarative source | Apply with |
|---|---|---|
| Portainer stacks, Cloudflare, Vault config | `terraform/<domain>/` | `terraform apply` |
| pfSense (cron, scripts, ACME, host-overrides) | `pfsense/*.yml`, `pfsense/scripts/` | `scripts/sync-pfsense-*.py`, `scripts/sync-host-*.py` |
| Rundeck jobs | `rundeck/jobs/*.yaml` | API import (see `rundeck/README.md`) |
| DNS zones | pihole `dnsmasq.d/*.conf` via Compose `configs:` | `terraform/portainer` |
| Grafana dashboards | `terraform/portainer/stacks/grafana-dashboards/*.json` | terraform + `scripts/portainer-redeploy.py` |

**Never** SSH in and edit `config.xml`, run `write_config`, hand-place a cron/script,
or scp config to a host. If a surface has no IaC path yet, **add one** (declarative
source + sync) — do not make the change manually.

## 2. Destructive / host / network changes need approval FIRST
Link bounces (`ifconfig down/up`), `pfctl -F/-d`, `docker rm -f`, VM/LXC stop, reboots,
disk ops: present options + rollback, get explicit user approval **before** acting.

## 3. Before any mutating action, state four things
which IaC mechanism · is it destructive/host-level? · rollback · approved?

## 4. Re-ground when context gets polluted
When scope grows past the original ask, or several changes pile up, **STOP and re-read
this file** before continuing. Long sessions dilute these rules — re-anchor deliberately.

## 5. Secrets: Vault only
`vault.d.lcamaral.com` round-robins across rproxy IPs and flaps if one is dead — use the
direct address `http://192.168.59.25:8200` when it times out. Never hardcode secrets.
