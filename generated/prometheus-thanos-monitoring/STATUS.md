# Phase 0/1/2 Implementation Status

**Date:** 2026-04-24
**Branch:** `feature/prometheus-thanos-plan`
**Latest commit:** `a433bf1` (authoring) — plus this STATUS doc.

## What's done (no further input needed)

### Recon (5 parallel agents)
- ✅ Existing Prometheus audited — `prom/prometheus:latest` (resolves v3.11.1), bundles 5 services, 15d default retention, no rules, no real alerting, only `prometheus.d.lcamaral.com` consumes it. Snapshot saved to `legacy-prom-snapshot/`.
- ✅ MinIO audited — site-replication mesh, 3 existing buckets, m1 has 1 TiB free, m2 has 76 GiB free, OIDC-only auth model.
- ✅ Keycloak audited — realm `homelab` exists, no `grafana` client yet, no groups/roles, version 26.3.5, mirror the `minio` client pattern.
- ✅ Terraform inventory — all 11 Vault paths free, both new policies free, NAS endpoint is `portainer_environment.nas.id`, pihole-3.yml.tftpl is the gold-standard pattern.
- ✅ NAS Portainer — endpoint id=14 (NOT 6), type=Agent (NOT Edge), pihole-3 stack confirmed compose-style. NAS macvlan free IPs `.237/.238/.239`. Disk 7.2 TB free.

### Authoring (3 parallel agents + reconciliation)
- ✅ Phase 1 stacks: `prometheus.yml.tftpl`, `thanos-query.yml`, `thanos-store.yml.tftpl`, `alertmanager.yml.tftpl`, `node-exporter-ds1.yml`, `cadvisor-ds1.yml`, `snmp-exporter.yml`, `objstore-ds1.yml.tftpl`
- ✅ Phase 2 stack: `prometheus-2.yml.tftpl`, `objstore-nas.yml.tftpl`
- ✅ `terraform/portainer/locals.tf` — both `prometheus_scrape_config_a/_b` (proper YAML external_labels) and `alertmanager_config`
- ✅ `terraform/portainer/stacks.tf` — old `portainer_stack.prometheus` body replaced; 6 new resources added
- ✅ `terraform/portainer/vault.tf` — 2 new data sources (`thanos`, `alertmanager_smtp`)
- ✅ `terraform/portainer/outputs.tf` — 7 new outputs
- ✅ `terraform validate` clean in the worktree

### Live reversible operations (3 parallel agents)
- ✅ Vault: 11 paths created with placeholders + 2 new policies (`prometheus-scrape`, `thanos-storage`).
- ✅ MinIO: bucket `thanos`, policy `thanos-bucket-rw`, svcacct `thanos` created. Real access/secret keys patched into `secret/homelab/thanos/s3`. Tested with PUT/GET/DELETE.
- ✅ pfSense: 5 firewall rules + 4 port aliases for NAS prom-2 + AM-2 cross-VLAN scrape. Smoke test confirms reachability.

## Known caveats (recorded; not blocking)

1. **MinIO site-replication of `thanos` bucket cannot be disabled.** MinIO has no per-bucket exclude in cluster-level site-replication. The `thanos` bucket is mirrored to m2 (76 GiB free). Mitigation: monitor capacity — when m2 hits ~80%, reduce raw retention from 90d to 60d (`--retention.resolution-raw=60d` on compactor). Acceptable trade-off.
2. **Alertmanager DNS names** (`alertmanager-1.d.lcamaral.com`, `alertmanager-2.home.lcamaral.com`) used in `--cluster.peer` flags don't yet exist in DNS. AM tolerates an unreachable peer; gossip will work once both names resolve. Add to `pfsense/host-overrides.yml` later or rely on the IP-based scrape in the alerting block (which IS plumbed).
3. **NAS Portainer agent** snapshotter not refreshing (last refresh 2026-04-22). Stack deploys still work; UI just doesn't show live container state. Cosmetic — not blocking.

## Remaining gates (REQUIRE YOUR APPROVAL)

These are NOT reversible without rebuilding from scratch. Detailed below.

### Gate 1 — Decommission of bundled legacy services

The existing `portainer_stack.prometheus` bundle on ds-1 contains 5 services: prometheus, node-exporter, snmp-exporter, alertmanager, cadvisor. The new authoring **replaces** the body of that resource with just `prometheus-1` + `thanos-sidecar-1`. When `terraform apply` runs the update:

- The 5 old services are stopped.
- The 2 new services start.
- The host volume `prometheus_prometheus_data` on ds-1 (3.1 GB of TSDB blocks) is left in place but is no longer referenced — Terraform will not delete it. To free the space later: `docker volume rm prometheus_prometheus_data` on ds-1.

**Lost data:** the 14 days of TSDB history on the old Prometheus.
**No alerting impact:** the old Alertmanager only had a commented-out Slack config — no live alerts today.
**Brief monitoring gap:** between stop-old and start-new, plus the time before node-exporter-ds1 / cadvisor-ds1 / snmp-exporter come up as separate stacks. Estimated 1–3 minutes.

### Gate 2 — Apply must be run from the main checkout, not the worktree

Terraform state for `terraform/portainer/` lives in the **main checkout** (`/Users/lamaral/.../inventory/`), not the worktree. The worktree's `terraform plan` shows "everything will be created" because it's running with empty state — that's misleading.

**Procedure:**

1. From the main checkout, fetch the feature branch:
   ```bash
   cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
   git fetch origin
   # Or if running locally only:
   ```
2. Decide how to bring the changes in — three options:
   - **a.** Merge `feature/prometheus-thanos-plan` into your working branch.
   - **b.** Cherry-pick `a433bf1` (and this commit) onto your working branch.
   - **c.** Switch to `feature/prometheus-thanos-plan` directly in the main checkout (will require `git stash` of the SynologyDrive exec-bit noise first).
3. From the main checkout (with the changes present):
   ```bash
   cd terraform/portainer
   export VAULT_ADDR=http://vault.d.lcamaral.com
   export VAULT_TOKEN=$(security find-generic-password -w -a "$USER" -s vault-root-token)
   export TF_VAR_portainer_password=$(vault kv get -field=admin_password secret/homelab/portainer)
   export TF_VAR_vault_token=$VAULT_TOKEN
   terraform plan -out=phase1-2.tfplan
   ```
4. Review the plan output. Expect:
   - 1 update to `portainer_stack.prometheus` (the bundle → fresh prometheus-1 + sidecar-1)
   - 7 new resources created (thanos-query, thanos-store, alertmanager_1, node_exporter_ds1, cadvisor_ds1, snmp_exporter, prometheus_2)
5. Apply: `terraform apply phase1-2.tfplan`

### Verification checklist (after apply)

- [ ] `docker ps` on ds-1 shows: `prometheus-1`, `thanos-sidecar-1`, `thanos-store-gw`, `alertmanager-1`, `node-exporter-ds1`, `cadvisor-ds1`, `snmp-exporter`. No `prometheus-prometheus-1` (legacy) anymore.
- [ ] `docker ps` on dockermaster shows: `thanos-query`.
- [ ] `docker ps` on NAS shows: `prometheus-2`, `thanos-sidecar-2`, `alertmanager-2`.
- [ ] `curl http://192.168.59.26:10902/api/v1/stores` (Thanos Query) returns sidecar-1, sidecar-2, store-gw — all healthy.
- [ ] `curl http://192.168.59.26:10902/api/v1/query?query=up` returns >0 series.
- [ ] After ~2h, MinIO `mc ls m1/thanos` shows at least one ULID-named block dir.
- [ ] **Repoint nginx vhost** `prometheus.d.lcamaral.com.conf` upstream from `192.168.48.45:9090` to `192.168.59.19:9090` (the new prometheus-1 macvlan IP). Or update to point at thanos-query.

## Files changed (worktree, branch `feature/prometheus-thanos-plan`)

```
generated/prometheus-thanos-monitoring/RECON-FINDINGS.md
generated/prometheus-thanos-monitoring/STATUS.md  (this file)
generated/prometheus-thanos-monitoring/legacy-prom-snapshot/  (new directory)
terraform/portainer/locals.tf  (new)
terraform/portainer/outputs.tf
terraform/portainer/stacks.tf
terraform/portainer/stacks/alertmanager.yml.tftpl  (new)
terraform/portainer/stacks/cadvisor-ds1.yml  (new)
terraform/portainer/stacks/node-exporter-ds1.yml  (new)
terraform/portainer/stacks/objstore-ds1.yml.tftpl  (new)
terraform/portainer/stacks/objstore-nas.yml.tftpl  (new)
terraform/portainer/stacks/prometheus-2.yml.tftpl  (new)
terraform/portainer/stacks/prometheus.yml  (deleted)
terraform/portainer/stacks/prometheus.yml.tftpl  (new — replaces deleted .yml)
terraform/portainer/stacks/snmp-exporter.yml  (new)
terraform/portainer/stacks/thanos-query.yml  (new)
terraform/portainer/stacks/thanos-store.yml.tftpl  (new)
terraform/portainer/vault.tf
```

## Live state changes summary (already applied to live infrastructure)

- pfSense: 4 port aliases + 5 firewall rules added (deletable via API)
- Vault: 11 paths + 2 policies created (deletable via API)
- MinIO: 1 bucket + 1 policy + 1 svcacct created (deletable via mc admin)

If the gates are not approved, these can be cleanly rolled back. None of them affect existing services today.
