# Prometheus + Thanos Monitoring — Homelab Plan

**Status:** Plan complete; ready to execute starting at Phase 0.
**Author:** Planning session 2026-04-24.
**Branch:** `feature/prometheus-thanos-plan` (worktree
`.worktrees/prometheus-thanos-plan`) — separate from `nas-docker-server`
and `feature/nginx-ha-reverse-proxy` so other agents can work
in parallel without conflict.
**Existing Prometheus:** to be **decommissioned** in Phase 0
(see Q10 in `DECISIONS.md`); not extended.
**Versions:** all images pinned in [`VERSIONS.md`](./VERSIONS.md);
checked 2026-04-24 against each project's GitHub releases.

## Goal

A single pane of glass for every monitorable device in the homelab, with HA
Prometheus, long-term retention via Thanos + object storage, dashboards in
Grafana (Keycloak SSO), and meaningful alerting that actually pages the right
channel.

## Non-goals (scope control)

- Log aggregation (Loki / Promtail already exists separately — out of scope).
- Tracing / APM (Tempo — future, not now).
- Synthetic probes of public-internet targets unrelated to the homelab.
- Replacing Home Assistant's own history/statistics engine (we scrape, we
  don't replace).

## Read order

1. **[01-architecture.md](./01-architecture.md)** — components, HA model,
   data flow. Start here.
2. **[02-inventory-and-scope.md](./02-inventory-and-scope.md)** — every
   device, by priority tier, with the exporter that monitors it.
3. **[03-thanos-design.md](./03-thanos-design.md)** — sidecar, querier,
   store gateway, compactor, object-store layout.
4. **[04-deployment-plan.md](./04-deployment-plan.md)** — 6-phase rollout,
   Terraform-first, Portainer stacks.
5. **[05-exporters.md](./05-exporters.md)** — per-device exporter choice,
   auth, scrape interval.
6. **[06-dashboards-and-alerting.md](./06-dashboards-and-alerting.md)** —
   Grafana, dashboards, Alertmanager routes, sample rules.
7. **[07-secrets-and-security.md](./07-secrets-and-security.md)** — Vault
   paths, TLS, SSO, firewall posture.
8. **[08-operations-runbook.md](./08-operations-runbook.md)** — day-2 ops,
   backup, upgrade, capacity.
9. **[09-open-questions.md](./09-open-questions.md)** — historical record
   of the 9 decisions; all answered in `DECISIONS.md`.
10. **[VERSIONS.md](./VERSIONS.md)** — pinned image tags for every
    component, with refresh procedure.
11. **[DECISIONS.md](./DECISIONS.md)** — locked-in answers including
    Q10 (decommission existing Prometheus).

## Reuse summary (what already exists and stays)

| Component | Status | Role in plan |
|---|---|---|
| Prometheus on `ds-1` | Already running — **TO BE DELETED in Phase 0** | Replaced by a fresh pinned `prometheus-1` (see Q10) |
| MinIO on `ds-1` + `minio-2` on `ds-2` | Running | Object store for Thanos long-term blocks |
| Vault at `vault.d.lcamaral.com` | Running | All tokens / S3 creds / bearer auth for scraping |
| Keycloak at `auth.cf.lcamaral.com` | Running | OIDC for Grafana SSO |
| nginx-rproxy | Running | TLS front for `grafana.cf.lcamaral.com`, `thanos.d…` |
| Portainer + Terraform (`terraform/portainer/`) | Running | Deployment mechanism |
| Docker registry `registry.cf.lcamaral.com` | Running | For any custom exporter images |
| Home Assistant `prometheus:` integration | Already enabled in `configuration.yaml` | HA scrape endpoint ready |

## What the plan adds

- 1 × new Prometheus on **NAS** (Proxmox-independent redundancy, Q3=B)
- 2 × Thanos sidecars (one per Prometheus: ds-1 + NAS)
- 1 × Thanos Querier on `dockermaster` — fans out
- 1 × Thanos Store Gateway on `ds-1` — historical reads from MinIO
- 1 × Thanos Compactor on **`ds-2`** — downsamples + retention, single-instance only
- 1 × Thanos Ruler on **`ds-2`** — single instance, long-window alert rules
- 1 × Grafana on `ds-1` — SSO + Thanos datasource **only** (no dashboards this phase)
- 2 × Alertmanager — HA gossip pair (**ds-1 + NAS**)
- N × exporters — see `05-exporters.md`

**Locked defaults (Q1+Q2):** 7d local Prometheus, 90d / 1y / 2y Thanos
tiers, ~200 GB MinIO year 1. Scrape 15s for infra, 60s for IoT.

**Alerting (Q5):** Email via `postfix-relay`.

## Fitness tests (how we know we're done)

- [ ] Query `up == 0` returns zero results across the whole fleet (or named
      ignored targets only).
- [ ] Grafana dashboard "Home Overview" loads from Thanos and shows
      simultaneous data from `ds-1` and `ds-2`.
- [ ] Kill `prometheus-1`; Grafana stays green. Bring it back; no dashboard
      gaps (dedupe works).
- [ ] Query a metric for a time range >30d; Store Gateway serves it from
      MinIO.
- [ ] Induce a known fault (e.g., stop `freeswitch`); matching alert fires
      within 2 minutes and routes to the configured channel.

## Immediate next step

Decisions locked in [DECISIONS.md](./DECISIONS.md). Versions pinned in
[VERSIONS.md](./VERSIONS.md). Email confirmed:
**`luiscamaral+homelab@gmail.com`**.

The plan is ready to execute starting at **Phase 0** in
[04-deployment-plan.md](./04-deployment-plan.md), which begins with
auditing and then **decommissioning the existing Prometheus** before
the Phase 1 fresh deploy.
