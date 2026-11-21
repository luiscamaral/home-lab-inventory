# Grafana Dashboard Audit & Remediation — Design

**Date:** 2026-05-27
**Status:** Draft for review
**Scope:** All 12 Grafana dashboards under
`terraform/portainer/stacks/grafana-dashboards{,-observability}/`
plus provisioning, scrape, and alerting layers

---

## 1. Motivation

The homelab Grafana stack runs 12 dashboards spanning infrastructure, apps,
network, and observability. A full audit revealed three problem classes:

- **Silent data failures** — `pfsense.json` hardcodes IPs in PromQL; if the
  gateway IP ever changes, panels go blank with no error.
- **IaC drift surface** — 9 of 12 dashboards lack a `uid`, all are
  `editable: true`, several have stale `version` numbers carried over from
  UI edits. Re-imports may create duplicates; UI edits get silently
  overwritten on next `terraform apply`.
- **Maintenance debt** — deprecated panel types (`graph`, `singlestat`,
  `grafana-piechart-panel`) across 5 dashboards. Grafana auto-migrates on
  load but the migration is silent and lossy, and Grafana 14+ may remove
  these types entirely.

Beyond those, scope expansion uncovered: missing alert↔dashboard pairing,
unmaintained tag taxonomy, no folder structure beyond "junk drawer +
Observability", zero dashboard interlinking, and no observability for
Grafana itself.

## 2. Goals

1. Every dashboard validates against a defined schema (UID present, refresh
   set, no hardcoded IPs in `expr` fields, `editable: false`).
2. No deprecated panel types remain.
3. Each dashboard's critical signals have a paired alert rule.
4. Folder structure reflects the actual taxonomy (infra / apps / network /
   observability) rather than a single junk drawer.
5. Validation runs locally via `make` target and catches regressions
   before `terraform apply`.

## 3. Non-Goals

- Replacing Thanos with another query frontend (datasource handling stays
  abstracted via a single variable name so this stays possible).
- Migrating Grafana off SQLite to Postgres.
- RBAC / per-user dashboard scoping (single-user homelab).
- Building dashboards for services not yet exporting metrics (Phase C
  items from `monitoring-coverage-gap-2026-05-07.md` — UniFi, Omada, iLO,
  Twingate, etc. — remain blocked on exporter deployment).

## 4. Current State (Audit Summary)

| Dashboard | UID | Refresh | Issues |
|-----------|-----|---------|--------|
| `node-exporter-full` | ❌ | 1m | deprecated `graph` (11+), dead datasource var |
| `vault` | ❌ | false | deprecated `graph`/`singlestat`/`piechart-panel`, dead vars (`$node`, `$port`, `$mountpoint`) |
| `proxmox-pve` | ❌ | 10s | 3 panels missing titles |
| `keycloak-quarkus` | ❌ | 1m | non-standard datasource var name, tag typo (`keycloak x`) |
| `pihole-v6` | ❌ | `""` | empty refresh, null-title panel |
| `minio-cluster` | ❌ | `""` | empty refresh |
| `pfsense` | ✅ `pfsense-availability` | 30s | **hardcoded IP `192.168.4.1` in 3 expressions** |
| `home-assistant` | ✅ `home-assistant-stats` | 30s | no template vars, table missing `friendly_name`/`domain`, no process health panel |
| `blackbox-overview` | ❌ | 1m | deprecated `graph` |
| `cadvisor` | ❌ | null | deprecated `graph`, non-standard `$host` (should be `$instance`) |
| `tls-cert-expiry` | ❌ | 1m | clean except missing UID |
| `thanos-prometheus` (obs) | ✅ `thanos-prometheus-infra` | 1m | clean |

**Common to all 12:** `editable: true` (wrong for IaC-managed),
`schemaVersion` varies (oldest community imports likely 27–32 vs Grafana
13.0.1 native 39), no `links` for drill-down, no annotations.

**Alerting parity gaps:**

- No alert for `homeassistant_entity_available == 0` sustained
- No alert for `probe_success{instance="192.168.4.1"} == 0` (pfSense
  reachability) — dashboard exists, alert doesn't
- No alert for cadvisor container restart loops
  (`container_start_time_seconds` deltas)

**Folder structure:** `Homelab` (11 dashboards, mixed domains) + `Observability` (1).

## 5. Approach

Single feature branch `feat/grafana-dashboard-audit`, phases as separate
commits. Selected over per-phase PRs because the JSON changes don't
conflict between phases and one `terraform apply` is simpler to
coordinate. Selected over bulk `jq` scripting because phases 2 and 3 mix
mechanical and business-logic changes that need human eyes.

Considered but rejected:

- **Re-import all community dashboards from Grafana.com** — would
  surface free fixes for deprecated panel types and add new panels, but
  panel IDs shift (breaking bookmarks) and the diff is hard to review.
  Decision: re-import only where local modifications are negligible
  (handled per-dashboard in Phase 2).

## 6. Phased Design

### Phase 0 — Validator first

Build the objective measure of "done" before changing dashboards.

Add `scripts/validate-grafana-dashboards.py` and a `make
validate-grafana` target. Validator scans every JSON matching
`terraform/portainer/stacks/grafana-dashboards*/` (glob — survives the
folder reorg in Phase 5 without code changes):

1. `uid` is non-null and matches `^[a-z]+(-[a-z0-9]+)*$`, ≤40 chars
2. `uid` is unique across all dashboards
3. `refresh` is non-empty string (e.g., `"30s"`, `"1m"`)
4. `editable` is `false`
5. `schemaVersion` ≥ 39
6. No `expr` field contains a literal IP (regex
   `\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b`)
7. No panel uses deprecated `type`: `graph`, `singlestat`,
   `grafana-piechart-panel`
8. Every `$variable` referenced in expressions is defined in
   `templating.list`
9. Every panel has a non-null `title`
10. `description` field is non-empty

Optional stretch: spin up an ephemeral Grafana container via Docker, POST
each dashboard to `/api/dashboards/db`, fail on non-200. Defer to later
if it complicates CI.

Baseline run: capture current violations as
`docs/grafana-audit-baseline.txt` for diffability.

### Phase 1 — Correctness

Per-dashboard JSON edits:

- **`pfsense.json`** — add template variable `$instance` (type `query`,
  query `label_values(probe_success{job="blackbox-icmp"}, instance)`,
  default `192.168.4.1`). Rewrite 3 expressions to
  `instance=~"$instance"`.
- **9 dashboards missing UIDs** — assign per convention `<domain>-<purpose>`:
  - `node-exporter-full`, `vault-metrics`, `proxmox-pve`,
    `keycloak-metrics`, `pihole-dns`, `minio-cluster`,
    `blackbox-overview`, `cadvisor-containers`, `tls-cert-expiry`
- **All 12** — set `editable: false`, strip `version` field entirely
  (Grafana provisioning manages it), normalize `schemaVersion` to 39.
- **Empty refresh fixes** — `pihole-v6` → `"30s"`, `minio-cluster` →
  `"1m"`, `cadvisor` → `"30s"`, `vault` → `"1m"`.

Acceptance: validator passes Phase 1 checks (1–6).

### Phase 2 — Refresh community dashboards from upstream

For each of: `node-exporter-full` (Grafana.com #1860), `vault`,
`keycloak-quarkus`, `cadvisor`, `blackbox-overview`:

1. Download current upstream JSON.
2. Run a `jq` diff against our local version. If local modifications are
   ≤3 panels, take the upstream version + re-apply local diffs. Else,
   stay with hand-edit path in Phase 3.
3. In all cases: replace datasource references with our
   `$DS_THANOS` variable pattern (see Phase 3).

Acceptance: no deprecated panel types remain in this set (validator
check 7).

### Phase 3 — Hand-edit remaining

For dashboards either kept from Phase 2 or never upstream-sourced:

- **Datasource variable consistency** — define `$DS_THANOS` (type
  `datasource`, query `prometheus`) in every dashboard with multiple
  panels. Replace hardcoded `uid: "thanos"` and ad-hoc names
  (`PROMETHEUS_DS`, `ds_prometheus`, `datasource`) with `$DS_THANOS`.
  Rationale: single replace if Thanos is ever swapped.
- **Instance variable naming** — rename `$host` → `$instance` in
  `cadvisor`. Standardize as `$instance` everywhere.
- **Dead vars** — remove `$node`, `$port`, `$mountpoint` from `vault.json`.
- **Panel titles** — add titles to 3 panels in `proxmox-pve`, 1 panel
  in `pihole-v6`.
- **Tag vocabulary** — controlled list: `homelab`, `infra`, `app`,
  `network`, `security`, `observability`, plus per-domain
  (`pfsense`, `vault`, etc.). Fix the `keycloak x` typo.
  Apply to every dashboard's `tags` field.
- **Dashboard links** (top bar drill-down) — at minimum:
  - `pfsense` → `blackbox-overview`, `tls-cert-expiry`
  - `node-exporter-full` → `cadvisor-containers` (same `$instance`)
  - `vault-metrics` → `thanos-prometheus-infra`
  - `minio-cluster` → `node-exporter-full`
- **home-assistant JSON improvements**:
  - Add `$instance` template var (currently hardcoded)
  - Unavailable Entities table: surface `friendly_name`, `domain`,
    `entity_id` columns; hide `job`, `instance`, `__name__`, `Time`,
    `Value` (current behavior preserves all)
  - New panel row: HA process health using
    `process_resident_memory_bytes{job="home-assistant"}`,
    `process_cpu_seconds_total`, `python_gc_objects_collected_total`

Acceptance: validator passes checks 8–10.

### Phase 4 — Alerting parity

Add alert rules to `terraform/portainer/stacks/thanos-rules.yml` (or
`prometheus-rules.yml` for short-window alerts):

```yaml
# Short-window (prometheus-rules.yml)
- alert: HomeAssistantEntityUnavailableSustained
  expr: homeassistant_entity_available == 0
  for: 30m
  labels: { severity: warning }
  annotations:
    summary: "HA entity {{ $labels.entity }} unavailable for 30m+"

- alert: PfSenseGatewayUnreachable
  expr: probe_success{job="blackbox-icmp", instance="192.168.4.1"} == 0
  for: 2m
  labels: { severity: critical }
  annotations:
    summary: "pfSense gateway ICMP unreachable"

- alert: ContainerRestartLoop
  expr: rate(container_start_time_seconds[10m]) > 0.01
  for: 10m
  labels: { severity: warning }
  annotations:
    summary: "Container {{ $labels.name }} restarting repeatedly"
```

Acceptance: every dashboard's first-row stat panels have a corresponding
alert in `thanos-rules.yml` or `prometheus-rules.yml`. Documented as
table in `docs/monitoring-coverage-gap-2026-05-07.md` update.

### Phase 5 — Folder reorganization

New structure under `terraform/portainer/stacks/`:

- `grafana-dashboards-infrastructure/` — `node-exporter-full`,
  `proxmox-pve`, `cadvisor-containers`
- `grafana-dashboards-applications/` — `vault-metrics`,
  `keycloak-metrics`, `minio-cluster`, `home-assistant`
- `grafana-dashboards-network/` — `pfsense`, `pihole-dns`,
  `blackbox-overview`, `tls-cert-expiry`
- `grafana-dashboards-observability/` — `thanos-prometheus-infra`
  (existing), `grafana-self` (new in Phase 6)

Delete `grafana-dashboards/` (old "Homelab" junk drawer).

Update `terraform/portainer/stacks.tf` `dashboards` map: 4 entries
instead of 2. Update `grafana.yml.tftpl` provisioner config to add 2 new
folder definitions.

Acceptance: every dashboard appears in exactly one of the 4 folders;
old `Homelab` folder is empty in Grafana UI after apply.

### Phase 6 — Grafana self-observability

Add `grafana-dashboards-observability/grafana-self.json`:

- Stat row: total dashboards loaded, total users (1), total alerts
  active
- Time series: `grafana_alerting_rule_evaluation_duration_seconds`,
  `grafana_datasource_request_duration_seconds`,
  `grafana_http_request_duration_seconds`
- Table: failed datasource requests last 24h

Requires adding `grafana` scrape target to `prometheus-1` and
`prometheus-2` configs in `locals.tf`. Grafana exposes `/metrics` by
default (no auth needed in the OSS image when accessed from the
internal network).

Acceptance: dashboard renders with data after one full Prometheus
scrape interval.

## 7. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Grafana refuses a migrated dashboard | Phase 0 validator includes optional ephemeral-Grafana POST test; fall back to per-dashboard revert via git |
| Re-imported community dashboard breaks existing panel URLs | Only re-import where local diff is ≤3 panels; document UID continuity |
| `editable: false` blocks legitimate UI experimentation | Single-user homelab; if needed, set `allowUiUpdates: true` in provisioner instead |
| Folder reorg breaks bookmarked URLs | UIDs are stable; URLs use UID not folder path; the UI sidebar paths change but `/d/<uid>` works |
| Alert noise from new rules | Start each rule with `for: 30m+` and `severity: warning` (info-only routing); upgrade to critical only after observing baseline |

## 8. Success Criteria

1. `make validate-grafana` passes against the entire dashboard set.
2. Every dashboard under `terraform/portainer/stacks/grafana-dashboards*/`
   has a unique kebab-case UID, `editable: false`, non-empty refresh,
   no hardcoded IPs in `expr`, no deprecated panel types.
3. Each first-row stat panel has a matching alert rule (documented in
   monitoring-coverage doc).
4. Grafana UI shows 4 folders matching the new taxonomy; old `Homelab`
   folder is gone.
5. New `grafana-self` dashboard renders metrics from a working `grafana`
   scrape job on both Prometheus replicas.

## 9. Open Questions

1. **Re-import threshold** — is "≤3 panels of local diff" the right
   cutoff for Phase 2, or should we be more aggressive (re-import all)?
2. **Validator placement** — `make` target only, or also wire to
   `pre-commit` and CI?
3. **Annotations** — defer or include in Phase 3 (Alertmanager firing
   alerts as overlays on time-series panels)?
4. **`editable: false` vs `allowUiUpdates: false`** — both prevent UI
   drift but the latter is set at the provisioner level (current state)
   while the former adds a per-dashboard banner. Belt + suspenders, or
   pick one?
