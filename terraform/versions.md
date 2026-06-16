# Lab Cluster — Pinned Versions (2026-06-16)

Confirm each at the sprint that uses it (Context7 + registry). Installed tooling is via mise.

## Tooling (installed, verified)

| Tool | Version |
|---|---|
| `terraform` | 1.13.3 |
| talosctl / talos (mise) | 1.12.0 / 1.13.4 |
| kubectl | 1.36.2 |
| helm | 4.2.1 |
| vault (cli) | 1.20.4 |
| `mc` · `aws` · `jq` · `yq` · `python3` | present (jq 1.8.1, yq 4.53.3, py 3.12) |

## Terraform providers

| Provider | Constraint | Notes |
|---|---|---|
| `bpg/proxmox` | `~> 0.109` | needs `ssh {}` block for image/file ops |
| `siderolabs/talos` | `~> 0.11` | data sources for `machine_configuration` + `cluster_kubeconfig`; not 0.12-alpha |
| `aminueza/minio` | `~> 3.2` | matches existing `terraform/minio` root |
| `hashicorp/vault` | `~> 4.0` | matches repo |
| `cloudflare/cloudflare` | `~> 5.0` | ACME CNAME (with dreamhost) |
| `adamantal/dreamhost` | latest | `_acme-challenge` delegation record |
| `hashicorp/helm` | `~> 2.13` | Cilium + Argo bootstrap |
| `hashicorp/kubernetes` | `~> 2.31` | Gateway API CRDs pre-Cilium |

## Cluster components (pin at Sprint 2–5)

| Component | Target | Notes |
|---|---|---|
| Talos OS | v1.13.4 | mise-pinned |
| Kubernetes | Talos default for 1.13.x | — |
| Cilium | ≥ 1.19 | BGP v2 API + Gateway-API LB advertisement fix |
| Argo CD · ESO · cert-manager | latest stable | pin at Sprint 3 |
| Velero · Kyverno · csi-driver-nfs · proxmox-csi-plugin | latest stable | pin at Sprint 4–5 |
