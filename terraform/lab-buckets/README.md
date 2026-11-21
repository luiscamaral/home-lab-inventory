# lab-buckets

Declarative record of the three MinIO buckets for the Talos lab cluster:

- `tfstate` — reserved for a future Terraform S3 backend (deferred; roots use local state for now)
- `velero-k8s-lab` — Velero filesystem backups (Sprint 5, written from inside the cluster)
- `thanos-k8s-lab` — in-cluster Prometheus Thanos-sidecar blocks (Sprint 5)

## Status

The three buckets **exist** in MinIO (verified via `s3 ls`). They were created 2026-06-16.

## ⚠️ Apply from a LAN host, not the workstation

MinIO is only reachable from the workstation via HTTPS reverse proxies
(`s3.cf.lcamaral.com` = Cloudflare, `s3.d.lcamaral.com` = internal Nginx). **Bucket _write_
operations through those proxies return mangled responses** (Cloudflare `502`, Nginx
`"…succeeded and you already own it"`), so `terraform apply` from the workstation errors even
when the operation actually succeeds. Reads (`ListBuckets`) work fine.

To manage these buckets with Terraform cleanly, run from a host with **direct MinIO `:9000`
access** on `docker-servers-net` (e.g. dockermaster/ds-1), where the S3 API is unproxied:

```bash
export TF_VAR_minio_user=...  TF_VAR_minio_password=...   # from Vault secret/homelab/minio
# point var.minio_server at the direct API, e.g. 192.168.59.x:9000, minio_ssl=false
terraform import 'minio_s3_bucket.lab["tfstate"]' tfstate   # (×3), then terraform apply
```

Versioning (declared here) should be enabled from that LAN host. Until then the buckets exist
unversioned, which is fine for their Sprint-5 use.
