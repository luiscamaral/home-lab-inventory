# 03 — Thanos Design

## Why Thanos (vs plain Prometheus)

Plain Prometheus has two structural limits for this homelab:

1. **No HA read.** Dashboards query one Prometheus. If it's down, nothing.
2. **Short retention by design.** Prometheus's TSDB is sized for weeks,
   not years. Keeping 2 years on local disk means either a large SSD
   budget or aggressive recording rules + manual pruning.

Thanos solves both without replacing Prometheus — sidecars upload blocks
to object storage, a Querier fans out reads, a Store Gateway serves
historical data from S3.

## Components to run

All Thanos roles run from the same image
**`quay.io/thanos/thanos:v0.41.0`** (see `VERSIONS.md`); only the
subcommand differs.

| Component | Instances | Host | Resources (initial) |
|---|---|---|---|
| Thanos Sidecar (`thanos sidecar`) | 2 | colocated with each Prometheus (ds-1 + NAS) | 128 MB RAM each |
| Thanos Querier (`thanos query`) | 1 | dockermaster | 256 MB RAM |
| Thanos Store Gateway (`thanos store`) | 1 | ds-1 | 512 MB RAM, ~5 GB local cache |
| **Thanos Compactor** (`thanos compact`) | 1 | **ds-2** | 1 GB RAM, ~20 GB local working dir |
| **Thanos Ruler** (`thanos rule`) | 1 | **ds-2** | 256 MB RAM |

**Do NOT run two Compactors against the same bucket.** The Thanos
documentation is explicit: compactor assumes it's the only writer for
compact/downsample operations. Running two corrupts blocks.

## Object-storage layout

### Bucket

- Name: `thanos`
- Location: **existing MinIO** (`minio` on ds-1 + `minio-2` on ds-2)
- Replication: MinIO bucket-level replication `minio → minio-2` (or
  active-active if supported by our MinIO version)

### Credentials

A dedicated MinIO user `thanos` with a bucket-scoped policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ],
    "Resource": ["arn:aws:s3:::thanos", "arn:aws:s3:::thanos/*"]
  }]
}
```

Stored in Vault as `secret/homelab/thanos/s3` with fields:

- `access_key` — `thanos`
- `secret_key` — generated, rotated yearly
- `endpoint` — `minio.d.lcamaral.com:9000` (internal)
- `bucket` — `thanos`

Thanos consumes this via an `objstore.yml` rendered from a Vault data
source (same pattern as existing `terraform/portainer/vault.tf`).

### Block layout in the bucket

```
thanos/
├── <ulid-of-block-1>/
│   ├── meta.json
│   ├── chunks/
│   └── index
├── <ulid-of-block-2>/
│   └── …
└── debug/  (Thanos writes diagnostics here)
```

Blocks are immutable. Compactor rewrites them into downsampled versions
(separate ULIDs); the originals are deleted once downsampling is confirmed.

## External labels (the dedupe contract)

Each Prometheus MUST have:

```yaml
external_labels:
  cluster: homelab
  replica: A       # or 'B' on ds-2
  region: local
```

Thanos Querier is started with `--query.replica-label=replica`, which tells
it to treat metrics differing only by that label as duplicates.

**If the external_labels differ in any other way** between replicas, the
dedupe breaks and you see double-counted series.

## Retention policy (locked — Q1=B frugal)

Stored on the Compactor side:

| Tier | Keep for | Rationale |
|---|---|---|
| Raw (15s / 60s samples) | **90 days** | Troubleshooting window |
| 5-minute downsampled | **365 days (1y)** | Year-over-year comparison |
| 1-hour downsampled | **730 days (2y)** | Long-term capacity trends |

Local Prometheus retains **7 days** raw as a shock absorber for network
blips to MinIO and for realtime queries.

**Storage math (frugal scenario):**

- T0+T1+T2 (15s): ~70k active series × (86400/15) × 1.2 B = ~480 MB/day/replica
- T3+T4 (60s): ~30k active series × (86400/60) × 1.2 B = ~52 MB/day/replica
- **Per replica per day:** ~530 MB
- **Two replicas, 90 days raw in S3:** `2 × 90 × 530 MB = ~95 GB`
- 5m-downsampled 1y: ~12× smaller = ~10 GB
- 1h-downsampled 2y: ~72× smaller = ~3 GB
- **Year 1 MinIO footprint: ~110 GB raw growth.** Budget 200 GB with
  headroom for cardinality creep and new exporters.

User decision: locked to B in `DECISIONS.md`.

## Querier configuration highlights

```yaml
# thanos-query args (partial)
--store=dnssrv+_grpc._tcp.thanos-sidecar-1.internal
--store=dnssrv+_grpc._tcp.thanos-sidecar-2.internal
--store=thanos-store-gw.d-servers-net:10901
--query.replica-label=replica
--query.auto-downsampling   # lets Query pick best-resolution block
--web.external-prefix=/     # if behind nginx path-routing
--http-address=0.0.0.0:10902
--grpc-address=0.0.0.0:10901
```

- **Auto-downsampling**: when a dashboard asks for "last 30 days", Query
  will pull the 1h-downsampled block (smaller, faster) instead of raw.

## Sidecar configuration highlights

```yaml
# thanos-sidecar args (partial)
--prometheus.url=http://localhost:9090
--tsdb.path=/prometheus
--objstore.config-file=/etc/thanos/objstore.yml
--http-address=0.0.0.0:10902
--grpc-address=0.0.0.0:10901
--shipper.upload-compacted=false   # sidecar does NOT pre-compact
```

- `--shipper.upload-compacted=false` is important: we want the Compactor
  to own all compaction. Sidecars only ship raw blocks.

## Store Gateway highlights

- `--index-cache-size=256MB` (in-memory LRU of index chunks)
- `--chunk-pool-size=2GB` (buffer pool for chunk reads)
- `--data-dir=/var/thanos/store` (local disk cache for recently-read blocks)
- Network: talks to MinIO over HTTP on the `docker-servers-net`.

## Compactor highlights

- **Host:** `ds-2` (single instance — two compactors corrupt blocks).
- `--wait` (run continuously)
- `--retention.resolution-raw=90d`
- `--retention.resolution-5m=365d`
- `--retention.resolution-1h=730d`
- `--deduplication.replica-label=replica` (optional: Compactor-side
  dedup; reduces stored size at the cost of CPU)
- **Why ds-2:** colocated with `minio-2` — reads during downsampling hit
  the local MinIO first (saves cross-host bandwidth). Also keeps the
  heaviest batch job off the dockermaster control plane.

## Ruler (deployed)

- **Host:** `ds-2` (single instance per decision — no HA pair).
- Evaluates alert rules **over Thanos data** (via the Querier), meaning
  rules can span time windows longer than any local Prometheus retention
  (e.g., "disk growth > 5 GB/month for the last 6 months").
- **Rules placement policy** (matters — read carefully):
  - **Prometheus-native rules:** short-window, high-urgency alerts
    (node down, container restart, disk 85% full). These fire from BOTH
    prometheus-1 and prometheus-2 and dedupe at Alertmanager cluster —
    **no SPOF.**
  - **Ruler-evaluated rules:** long-window, trend-based alerts (capacity
    growth, SLO burn-rate, cert-expiry soon). Single instance on ds-2 →
    if ds-2 is down, these rules do not evaluate.
- **Alertmanager wiring:** Ruler sends alerts to both `alertmanager-1`
  AND `alertmanager-2` (via its `--alertmanagers.url` flag, repeated).
  The AM cluster dedupes.
- **Rule file layout:**
  - `rules/prometheus/*.yml` — loaded by both Prometheus replicas.
  - `rules/thanos/*.yml` — loaded by Ruler only. Rules here MUST be
    ones that require >15d history or cross-replica queries.

## Why not Thanos Receive

Receive is a push-based write path. Useful when:

- You have many short-lived Prometheus instances (not us).
- You want tenant isolation on write (not us yet).
- Remote networks where pulling is hard (not us).

We're better served by the sidecar model. Revisit if any of the above
change.
