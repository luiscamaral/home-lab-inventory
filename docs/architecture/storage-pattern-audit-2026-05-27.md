# 💾 Storage-Pattern Audit — 2026-05-27

**Trigger:** discovered during the shim re-IP work that `minio-2` on
ds-2 was using `/var/lib/minio-data` (LOCAL disk, 73 GB) while its
sibling `minio-1` on ds-1 correctly bound `/nfs/dockermaster/docker/
MinIO/minio-data`. The asymmetry was the symptom; the underlying issue
is that ds-1 and ds-2 generally drifted from the dockermaster
"all-persistence-on-NAS" pattern.

## The pattern (as practiced on dockermaster)

Every container's persistent data lives on the NAS NFS export
`tnas:/volume2/servers/dockermaster`, mounted at `/nfs/dockermaster/`
on each Docker host (dm / ds-1 / ds-2 — confirmed today).

Two equivalent wiring techniques are used:

1. **Bind-mount directly** in the Compose `volumes:` block:
   `/nfs/dockermaster/docker/<svc>/<subdir>:/<container path>`.
   Used for: rproxy, vault, pihole-2/3, ollama, calibre-web, rundeck,
   freeswitch, `github-runner`, **minio-1** (the reference).
2. **Named volume with bind driver options** — Compose `volumes:`
   block declares `driver: local` and `driver_opts: { type: none,
   device: /nfs/dockermaster/..., o: bind }`. Same effect, looks
   like a regular Docker volume from inside the container. Used on
   dockermaster for `grafana_grafana_data` (confirmed via
   `docker volume inspect`).

Either form keeps data on the NAS, so:

- A host disk failure doesn't lose container data.
- Containers can be re-scheduled to another host with the same
  Compose stack (data is already in the shared location).
- Backups happen once (on the NAS, via Synology Hyper Backup) and
  cover everything.
- Host root FS stays small and disposable.

## Migration that landed in this commit series

| Service | Host | Was | Now |
| --- | --- | --- | --- |
| **minio-2** | ds-2 | bind `/var/lib/minio-data` (73 GB) | bind `/nfs/dockermaster/docker/MinIO/minio-2-data` |

That alone frees ~73 GB on ds-2's 113 GB root disk (from 100% full
back to ~30% used).

## Outstanding deviations — per-host inventory

The lists below are everything currently sitting on local
`/var/lib/docker/volumes/` (Docker's default storage path) on ds-1 and
ds-2. Bind-mount services that already point at `/nfs/dockermaster/`
are correctly placed and not listed.

### ds-2 (after minio-2 migration)

| Container / volume | Size class | Should it stay local? | Rationale |
| --- | ---:| --- | --- |
| `prometheus_prometheus_data` | ~5 GB | **STAY** | TSDB writes are constant; NFS latency hurts ingest. Thanos sidecar already ships durable copies to MinIO. Loss of this replica is recoverable. |
| `thanos_compact_data` | < 1 GB | **STAY** | Compactor's scratch dir; rebuilt from the bucket on restart. NFS doesn't help. |
| `thanos_rule_data` | < 1 GB | **STAY** | Rule WAL; only matters per-host; ephemeral. |
| `vault-3_vault_raft` + `vault_vault_raft` | < 1 GB | **STAY** | Raft state replicated 3-way (vault-1/-2/-3). NFS latency would trip Raft heartbeats. Losing one node's data is the failure mode Raft was _designed_ to survive. |
| `o11y_grafana_data` | small | move | UI state for a secondary o11y stack. NAS is fine. |
| `o11y_loki_data` | size unknown | move | Log chunks; NAS handles the write rate fine. |
| `o11y_mimir_data` | size unknown | **STAY?** | TSDB workload — same logic as `prometheus`. Verify retention/scale. |
| `o11y_prometheus_data` | size unknown | **STAY?** | Same. |
| `o11y_pyroscope_data` | size unknown | move (probably) | Profile blocks; write-once-read-rare. Like Loki. |
| `o11y_signoz-query-data` | size unknown | move | UI cache. |
| `o11y_tempo_data` | size unknown | move (probably) | Trace blocks; same pattern as Loki/Pyroscope. |
| `litellm_postgres_data` | size unknown | **STAY** | Postgres on NFS is a known perf footgun; small DB so NAS _would_ probably work but the project handoff memory flags repmgr quirks. Match the keycloak-db pattern (local). |
| `litellm_prometheus_data` | size unknown | **STAY** | Same TSDB logic. |
| `synology-search_postgres-data` | size unknown | **STAY** | Postgres — same reasoning. |
| `synology-search_solr-data` / `solr_data` | size unknown | move (probably) | Lucene indexes; SOLR tolerates NAS. Two volumes suggests a leftover from a rename — audit + dedupe. |
| `synology-search_neo4j-data` | size unknown | **STAY?** | Neo4j on NFS is officially unsupported. |
| `synology-search_qdrant-storage` | size unknown | move | Vector store; mostly read. |
| `synology-search_nas-mount` | size unknown | move (or already?) | Name suggests it's supposed to be on NAS already — verify it isn't a misconfigured local volume. |
| `synology-search_crawler-state` | small | move | Just JSON state files. |
| `queue-services_rabbitmq-lib` | size unknown | **STAY** | RabbitMQ on NFS hangs under load (mnesia locks). |
| `queue-services_rabbitmq-log` | size unknown | move | Logs, write-only. |
| `ollama_ollama` | (orphan) | **DELETE** | Container moved to ds-1 per commit `a80888b`. Volume is orphaned ~10 GB potential reclaim. |
| `docker-registry_registry_data` | size unknown | move | Blob store; NFS is fine. |
| `portainer-ce_portainer_data` + `portainer_data` + `dockermaster-portainer_portainer_data` | small | move | UI state. The three names suggest leftover renames; audit + dedupe. |
| GUID-named anon volumes (×6) | unknown | **DELETE** | Pruned during earlier cleanup; recheck for stragglers. |

### ds-1 (51 GB free; less urgent)

Same inventory as ds-2 (mirror), plus:

| Container / volume | Should it stay local? | Notes |
| --- | --- | --- |
| `alertmanager_data` | move | AM notification log; cheap to put on NAS. |
| `thanos_store_cache` | **STAY** | Bucket-cache; rebuilt on restart anyway. |
| **`keycloak-db-1` bind `/var/lib/keycloak-ha/db-1`** | **STAY** (current pattern) | Postgres; matches the project handoff memory's repmgr config. Don't change without a coordinated plan for repmgr replication. |
| `prometheus_data` (older volume?) | **DELETE if orphan** | Two `prometheus_data` names; one is likely a leftover. |

## Recommended classification

| Category | Move to NAS? | Why |
| --- | --- | --- |
| **TSDB write-paths** (Prometheus, Mimir) | No | Latency-sensitive ingest; Thanos ships durable copies elsewhere. |
| **Raft / Mnesia consensus** (Vault, RabbitMQ) | No | NFS latency breaks the protocol. |
| **Relational DB write WAL** (Postgres) | No | Performance footgun + repmgr quirks. Use a separate local disk if outgrowing root FS. |
| **Object/blob stores** (MinIO, Registry, Solr, Qdrant) | YES | Designed for the access pattern. minio-1 already proves it works. |
| **Log shippers / trace stores** (Loki, Pyroscope, Tempo) | YES | Write-once-read-rare; size-driven, not latency-driven. |
| **UI / state caches** (Grafana, Portainer, Signoz UI) | YES | Tiny, no perf issues. |
| **Ephemeral scratch** (compactor, ruler, store cache) | No (but don't matter either way) | Rebuilt on restart. |
| **Orphaned volumes** | DELETE | Audit + remove with `docker volume rm`. |

## Phased migration plan (recommendation)

| Phase | Scope | Why this order | Est. effort |
| --- | --- | --- | --- |
| **0** ✅ done | minio-2 → NAS | Already a 73 GB unblock; sibling pattern obvious. | ~30 min |
| **1** (next) | Orphan cleanup: ollama_ollama on ds-2, GUID anon vols, dedupe portainer_data names | Pure reclaim with zero migration risk. May free another 5-15 GB. | 30 min |
| **2** | Object/blob movers: `docker-registry`, solr, qdrant | Same pattern as minio. Stops, rsync, change Compose `volumes:`, redeploy. | ~1 h each |
| **3** | UI / state caches: `grafana_data`, `portainer_data`, `signoz-query-data` | Trivial; small + no live writes during migration. | ~30 min each |
| **4** | Log/trace stores: loki, pyroscope, tempo | Same as Phase 2 if running. | ~1 h each |
| **5** | Decision branch: `o11y_mimir` + `o11y_prometheus` | TSDB workload — local vs NAS perf measurement first. Skip if local is OK. | research + decision |

**Phases 1 and 3 are pure-win zero-risk** and could ship together.
**Phase 2 takes the most calendar time** because each blob store has
its own data set to rsync, but the per-migration risk is low (the
sibling pattern is already proven by minio-1).

## What stays local — long-term decision

Postgres + Vault + RabbitMQ + TSDB on the Docker hosts' root disks is
the right call (not the deviation it looks like at first glance). The
real protection against host disk loss for these is:

- Raft replication across the cluster (Vault — already done)
- Streaming replication / repmgr (Postgres — already configured per
  project memory)
- Cluster mode + mirroring (RabbitMQ — verify configuration)
- Thanos shipping to MinIO (Prometheus — already done)

The action item for these isn't to move them off local disk, it's to
verify the replication / shipping side actually works and has tested
recovery procedures.

## How "should it move?" was decided

For each volume, the answer turns on three questions:

1. **Is the write pattern latency-sensitive?** (commits, WAL, Raft
   heartbeats — yes; blob uploads — no)
2. **Is there already off-host durability?** (Raft replication,
   Postgres streaming, Thanos sidecar — local is fine; otherwise NAS
   is the durability story)
3. **Does NFS work for the workload?** (some tools refuse to run on
   NFS — Postgres warns, Neo4j refuses, etc.)

If any of (1)/(2)/(3) say "stay local," the volume stays. If all
three say "NAS is fine," it moves.

## Process going forward

When deploying a new stack on ds-1 / ds-2:

- Default to a bind mount under `/nfs/dockermaster/docker/<svc>/`.
- Use a Docker named volume only if there's a specific reason
  (latency, Raft, Postgres, etc.), and document the reason in the
  stack file comment.
- Anytime you see a `/var/lib/docker/volumes/<name>` path in a new
  Compose, ask whether NAS would work instead.

## Open items at end of this audit

- Recover orphaned `ollama_ollama` volume on ds-2 (commit `a80888b`
  context).
- Decide whether `synology-search_*` is even still wanted — it has
  10+ volumes suggesting an active service, but no rproxy vhost
  surfaces the search UI publicly.
- Decide whether `o11y_*` is the same stack as the main `prometheus`,
  `grafana`, and `thanos`, or a parallel one. If parallel, why? If a
  duplicate, retire one.
- Measure ds-2 root FS usage trajectory after Phase 1 cleanup —
  expect ~30 GB used. If it climbs again, something else is
  growing on local disk (likely `/var/log/journal/...` stale-machine-id
  remnant flagged earlier — 3.1 GB recoverable).
