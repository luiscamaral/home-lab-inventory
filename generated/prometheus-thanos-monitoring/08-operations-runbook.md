# 08 — Operations Runbook

Day-2 operations for the completed monitoring stack. Each section
answers "what do I do when X?"

## Health check (5-minute morning routine)

1. Open Grafana "Home Overview". Panel **Targets Up** should show 100%
   of expected targets. Red means new breakage overnight.
2. Check Thanos self-dashboard: Compactor last-run < 6h, sidecars both
   connected to MinIO, bucket size trend not exponential.
3. Alertmanager "Active alerts" panel: anything unsilenced that
   wasn't there yesterday.
4. Run `vault status` on any one host (part of your existing
   morning pattern). Vault unsealed = metrics chain healthy.

## Backup

| Data | Location | Backup method | Restore test frequency |
|---|---|---|---|
| Grafana dashboards | Git (`terraform/portainer/stacks/grafana/dashboards/`) | Git is source of truth | Per deploy |
| Grafana DB (if Postgres) | Postgres → NAS dump | Nightly cron, 7-day retention | Quarterly |
| Prometheus config | Git | Git | Per deploy |
| Alertmanager config | Git | Git | Per deploy |
| Thanos blocks | MinIO bucket `thanos` | MinIO → `minio-2` replication + nightly snapshot to NAS | Annual |
| Vault secrets (tokens used here) | Vault integrated backup (existing) | Out of scope for this plan; covered by main Vault backup strategy | |

**Restore test** (quarterly): pick a 30-day-old block from MinIO, copy
to a test bucket, point a fresh Store Gateway at it, confirm query
returns data.

## Upgrade order (when upgrading the stack)

Follow this sequence to avoid breaking the compatibility chain:

1. **Compactor first** — it reads blocks; upgrading it first ensures
   new-version blocks never end up unreadable.
2. **Store Gateway** — same reason.
3. **Sidecars** — they write new-format blocks.
4. **Prometheus** — after sidecars, in case new Prom writes formats the
   old sidecars can't ship.
5. **Querier last** — consumers.
6. **Grafana** independently.

Always bump ONE release at a time. Read the changelog for breaking
changes to `external_labels` behaviour or dedup semantics.

## Capacity planning

**Frugal-retention baseline (Q1=B):** ~110 GB year 1 raw growth;
budget 200 GB on MinIO. Alert at 80% (160 GB).

**Monthly:** look at MinIO bucket growth.

- If growth > linear projection → new cardinality somewhere. Find it:
  ```
  topk(10, count by (__name__)({__name__=~".+"}))
  ```
- If storage at 80% of budget → either drop raw retention from 90d to
  60d (cheap, low impact) or provision more MinIO disk.

**Annually:** review retention policy. At frugal settings (2y for
1h downsample) this is probably stable — revisit only if new scrape
jobs significantly change the series count.

## Common incidents

### Alert: "Thanos compactor hasn't run in 6h"

- SSH to **ds-2**, `docker logs thanos-compactor` — look for:
  - Object-store auth failure → rotate creds
  - Block corruption → search for `halted` message; follow Thanos
    halt-recovery procedure (a manual file move in the bucket).
  - Disk full on compactor's `--data-dir` → extend volume.
  - ds-2 itself unhealthy (memory pressure, disk full) → address host
    first, compactor resumes automatically.

### Alert: "Thanos Ruler evaluation errors"

- SSH to **ds-2**, `docker logs thanos-ruler` — look for:
  - Query timeouts → thanos-query reachability, store-gw health.
  - Alertmanager unreachable → confirm both AMs on ds-1 and ds-2 are up.
  - Rule file syntax errors → check the latest `rules/thanos/*.yml`
    commit.

### Alert: "Prometheus replica down"

- Check the OTHER replica is up.
- `docker logs prometheus-{1,2}` on the down side.
- If dead host: restart the VM, then the Portainer stack.
- **Do not** restart both at once.

### Alert: "Sidecar not shipping to object store"

- `curl <sidecar>:10902/api/v1/status/flags` — confirm objstore.yml
  readable.
- `docker logs thanos-sidecar-N` — MinIO reachability, policy issues.
- While broken, data is buffered in Prometheus local TSDB. Fix within
  the local-retention window (15d default) or lose the gap
  permanently.

### Alert: "Bucket size growing unexpectedly"

- Run Thanos' `thanos tools bucket inspect --objstore.config-file=...`
  to see block stats.
- Usually a new high-cardinality label. Use
  `metric_relabel_configs: drop` rules in the scrape config to trim.

### Alert: "pfSense gateway flap" (existing issue)

- Confirm with pfSense gateway page.
- Check if same `HOMELAB` gateway to `192.168.7.10` (proxmox) — if
  yes, separate infrastructure issue (see session notes).

## Re-shard Prometheus (add a 3rd instance)

When to do this: single replica's scrape job takes > 50% of scrape
interval; cardinality too high for one instance.

Procedure:

1. Decide split axis (by job? by subnet? by sensitivity?). Simplest:
   move `home-assistant` (highest-cardinality job) to a dedicated
   `prometheus-ha` instance with `external_labels.shard: ha`.
2. Both other Prometheus still scrape everything *except* HA.
3. Add `prometheus-ha` sidecar to Thanos Query.
4. Thanos Query deduplicates across replicas as before; each shard
   contributes its own jobs.

## Recover from MinIO bucket loss (worst case)

If the `thanos` bucket is destroyed and the replica is also gone:

1. Everything older than local Prometheus retention is **lost**. Only
   what's on disk in Prometheus (last 15d raw) is recoverable.
2. Re-create the bucket.
3. Restart sidecars — they'll upload the blocks they still have
   locally.
4. Compactor picks up where it can.

This is why the NAS nightly snapshot exists: it's the escape hatch
against accidental bucket deletion.

## Rotating credentials

- **MinIO `thanos` user key:** rotate annually.
  1. Generate new secret, store in `secret/homelab/thanos/s3` (new
     version of the KV entry).
  2. Restart sidecars + store-gw + compactor — they re-read Vault.
- **HA metrics token:** rotate if ever leaked; otherwise when HA
  changes auth schema.
- **Vault metrics token:** use a short TTL (7d) and renew via Vault
  agent so leaked tokens age out fast.

## Decommissioning / outage per host

### If ds-2 goes down or is decommissioned

ds-2 carries **only the batch plane** (compactor + ruler) under the
Q3=B topology. Order matters.

1. **Stop `thanos-ruler` first.** Ruler-evaluated alerts go silent.
   Acceptable — they are long-window rules.
2. **Stop `thanos-compactor` second.** No compaction/downsampling while
   it's off; blocks accumulate in MinIO but nothing breaks.
3. If ds-2 stays down >2w: stand up compactor + ruler elsewhere
   (dockermaster or ds-1). **Never** run two compactors pointed at
   the same bucket.

### If ds-1 goes down

ds-1 carries `prometheus-1`, `sidecar-1`, `thanos-store-gw`, `grafana`,
`alertmanager-1`. This is the BIG outage.

1. `prometheus-2` on NAS keeps scraping — no data loss for reachable
   targets.
2. `alertmanager-2` on NAS keeps delivering email alerts (via
   postfix-relay, so also depends on dockermaster; if dockermaster is
   up, email flows; if dockermaster is also down, alerts buffer in AM).
3. Thanos Query queries go blank for **historical data** (store-gw is
   on ds-1). Short-term data from sidecar-2 still returns.
4. Grafana is down; use Prometheus-2 direct (`:9090`) on the NAS for
   debug queries.
5. When ds-1 returns: start prometheus-1 first, confirm sidecar-1
   resumes block uploads (anything queued up to ~7d of raw data will
   push).

### If the NAS goes down

NAS carries `prometheus-2`, `sidecar-2`, `alertmanager-2`, `pihole-3`.

1. `prometheus-1` on ds-1 keeps running — **no scrape interruption.**
2. `alertmanager-1` on ds-1 keeps running — AM cluster runs at N=1
   (no dedupe if anything else sends alerts, but Prometheus-1 goes
   direct so that's fine).
3. pihole-3 being down means DHCP option clients fall through to
   other piholes (or pfSense). Separate concern, not monitoring.
4. Restore: bring the NAS up, stacks restart automatically
   (Portainer edge endpoint manages this).

## Logs to always tail during a change

- `thanos-query` logs (for dedupe warnings)
- `thanos-compactor` logs (for halted blocks)
- Prometheus `/api/v1/status/flags` (for config drift)

Grafana should have a "Monitoring Stack Self" dashboard specifically
for this — built in Phase 4.
