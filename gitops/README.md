# `gitops/` — Argo CD app-of-apps source

Argo CD (bootstrapped by `terraform/kubernetes` in Sprint 2.3) syncs this tree. Layout:

| Dir | Sync wave | Holds |
|---|---|---|
| `bootstrap/` | root | The app-of-apps `Application` that points Argo at `infra/` then `apps/`. |
| `infra/` | 0–1 | Cluster services: ESO + `ClusterSecretStore`, cert-manager + `ClusterIssuer`, Kyverno, the Cilium `Gateway`, storage drivers. |
| `apps/` | 2+ | Workloads. |

> Authored across Sprints 2–4. The read-only GitHub deploy key Argo uses lives in Vault at
> `secret/homelab/k8s/argo-deploy-key` (see the plan's Sprint 2 pre-flight). Repo is private, so the key
> is required. `.gitkeep` files hold the empty dirs until the manifests land.
