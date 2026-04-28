# DECISIONS — prometheus-thanos-monitoring

**Status:** Locked 2026-04-24. Supersedes defaults in 09-open-questions.md.

## Q1 Retention — **B (frugal)**

| Tier | Keep for |
|---|---|
| Local Prometheus | 7 d |
| Thanos raw | 90 d |
| Thanos 5m downsample | 365 d (1 y) |
| Thanos 1h downsample | 730 d (2 y) |

Estimated MinIO footprint: **~200 GB year 1**.

## Q2 Scrape cadence — **B (mixed)**

- **15s** for infra (tiers T0 / T1 / T2): hosts, services, network fabric.
- **60s** for tier T3 (IoT + HA entities) and tier T4 (blackbox probes).

## Q3 HA topology — **B (move one replica to NAS)**

- `prometheus-1` + `thanos-sidecar-1` + `alertmanager-1` + `thanos-store-gateway` stay on **ds-1**.
- `prometheus-2` + `thanos-sidecar-2` + `alertmanager-2` move to **NAS** (Synology, Docker container, home-net macvlan).
- `thanos-compactor` + `thanos-ruler` stay on **ds-2** (batch plane).
- `thanos-query` stays on **dockermaster**.
- `grafana` stays on **ds-1**.

Net: scrape path + Alertmanager HA both survive a Proxmox outage.
Batch plane (compactor + ruler) does not — acceptable per §06 rule
placement policy.

## Q4 Object store — **A (reuse existing MinIO)**

Bucket `thanos` in the existing `minio` (ds-1) instance, replicated to
`minio-2` (ds-2). Revisit when the bucket hits 75% of its MinIO-side
budget.

## Q5 Alert channels — **Email** (via existing postfix-relay)

- All severities go to email. Routing via the existing `postfix-relay`
  on dockermaster.
- Recipient: **`luiscamaral+homelab@gmail.com`** (Gmail `+`-tagged
  inbox; lets you filter homelab alerts into a folder server-side).
- Routing tree still splits by severity so a second channel can be
  added later without re-authoring rules.

## Q6 SSO — **A (Keycloak OIDC)**

- Realm `homelab`, client `grafana`.
- Client secret in Vault at `secret/homelab/grafana/oidc`.

## Q7 Thanos Ruler — **B (deploy)**

- Single instance on **ds-2** (already reflected in the architecture).

## Q8 HA scrape token — **A (dedicated)**

- New HA long-lived access token under a dedicated user
  (e.g., `prometheus-scrape`) with minimal scope.
- Stored at `secret/homelab/home-assistant/metrics_token`.
- **NOT** a reuse of the existing `HA-TOKEN` in Keychain (that one has
  broader write scope).

## Q9 pfSense 15-min reload — **B (proceed; investigate later)**

- Phase 0 does not block on fixing the 15-min filter-reload cron.
- We expect visible "blip" patterns in nascent dashboards; this is
  noise to acknowledge, not to chase.
- A follow-up issue is filed to identify and remove the cron after
  Phase 6.

## Q10 Existing Prometheus disposition — **DELETE** (clean slate)

The existing Prometheus on `ds-1` (deployed by an earlier plan) is
**decommissioned**, not extended. Rationale:

- Image version, scrape config, and TSDB layout are unknown / unaudited
  — a clean install on pinned versions is faster than reverse-engineering.
- This plan introduces `external_labels.replica`, Thanos sidecar mount
  semantics, and a different retention policy. Hand-merging those into
  an existing instance risks subtle inconsistencies vs. `prometheus-2`
  on the NAS.
- Local TSDB on the existing instance contains <15 days of data we do
  not have a written purpose for. Acceptable loss.

**Phase 0** captures the existing scrape-config (for transcription into
the new Prom config) and **Phase 1** stops + removes the existing
container/stack before deploying the fresh pinned `prometheus-1` from
`VERSIONS.md`.

## Versions — **PINNED** (see [VERSIONS.md](./VERSIONS.md))

All container images are pinned to specific tags. Re-check before each
phase deploy and bump deliberately. No `latest` tags in any stack.

## Phase 3 default decisions (locked 2026-04-25, can be overridden later)

These were the four open questions in `PHASE-3-REVIEW.md`. Applying defaults to keep momentum:

### HA cardinality budget — START PERMISSIVE

Keep all metric classes initially. Apply `metric_relabel_configs: drop` ONLY for the obvious noise (`sun`, `update`, `weather` integrations, per-device `*_diagnostics` entities). Refine after first scrape against real cardinality numbers.

### MinIO scrape svcacct — DEDICATED `metrics` (not reuse `thanos`)

`thanos` is a write-path account; conflating it with read-only metrics scraping enlarges blast-radius if either credential leaks. Create `metrics` svcacct with read-only on the metrics endpoints.

### Proxmox role — PVEAuditor (minimum-privilege)

Sufficient for `pve-exporter` to read VM state, CPU/mem, storage. Replication and backup metrics need higher role; defer until a real need surfaces.

### Sub-phase order — 3a → 3b → 3c → 3d → 3e → 3f → 3h → 3g → 3i

Reasoning:
- 3a–3f are highest-value-per-effort + don't need new exporter binaries
- 3h (blackbox) is independent, single new container, fast
- 3g (network fabric) and 3i (snmp regen) are research-heavy; saved for last
