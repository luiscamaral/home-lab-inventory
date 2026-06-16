# Design: Vault ⇄ Kubernetes Auth Wiring (ESO)

**Date:** 2026-06-15
**Status:** Draft (post-review; pending sign-off)
**Owner:** Luis Amaral
**Relationship:** Addendum to `docs/iac-audit-2026-04-30.md` item **I3** (the unconfigured `kubernetes` auth backend)
and prerequisite for secrets in `2026-06-15-k8s-talos-proxmox-iac-design.md`.

---

## 1. Problem

`terraform/vault/auth.tf` declares `vault_auth_backend.kubernetes` as an **unconfigured zombie** — no `kubernetes_host`,
no CA, no token-reviewer JWT, **no roles**. The existing `kubernetes-secrets` policy grants `secret/data/kubernetes/*`,
which is the **wrong path** (the cluster's ESO needs `secret/homelab/*`). So bring-up step "apply vault → k8s auth + ESO
role" currently has **nothing to apply**. This spec defines exactly what to add.

---

## 2. Resources to add (in `terraform/vault/`)

**Mount (cluster-scoped path, future-proof):**

- Re-path the backend to `kubernetes/lab-cluster` (so a future cluster gets its own mount).

**`vault_kubernetes_auth_backend_config`:**

- `kubernetes_host` = cluster API VIP `https://192.168.30.5:6443` (from `terraform_remote_state` of the cluster root).
- `kubernetes_ca_cert` = cluster CA (from `data.talos_cluster_kubeconfig`).
- `token_reviewer_jwt` = the token-reviewer SA token (see §3). _(Or use Vault ≥1.21 short-lived JWT / no-reviewer
  mode.)_

**`vault_kubernetes_auth_backend_role` (ESO):**

- `bound_service_account_names = ["external-secrets"]`
- `bound_service_account_namespaces = ["external-secrets"]`
- `audience = "vault"` (**required for Vault ≥1.21** — verify live Vault version)
- `token_policies = ["eso-homelab-reader"]`

**`vault_policy "eso-homelab-reader"` — least-privilege, enumerated (NOT wildcard):**

```hcl
path "secret/data/homelab/cloudflare"          { capabilities = ["read"] }
path "secret/data/homelab/dreamhost"           { capabilities = ["read"] }
path "secret/data/homelab/proxmox/csi"         { capabilities = ["read"] }
path "secret/data/homelab/minio/velero"        { capabilities = ["read"] }
path "secret/data/homelab/k8s/argo-deploy-key" { capabilities = ["read"] }
# add only paths cluster workloads actually consume
```

> Do **not** grant `secret/data/homelab/*` — that path also holds Twingate, FreeSWITCH, the Vault operational token,
> etc. Enumerate leaves.

**Cleanup (same apply):** fix the two dangling bindings flagged in `iac-audit` I3
(`project-dockermaster-home-lab-inventory` typo; non-existent `app-developer`/`db-reader`/`pki-user` userpass policies).
Repurpose or delete the misscoped `kubernetes-secrets` policy.

---

## 3. Token-reviewer ServiceAccount (in-cluster)

Vault validates incoming SA JWTs by calling the cluster's TokenReview API as a delegated reviewer:

- Create SA `vault-auth` (ns `kube-system` or `external-secrets`) + `ClusterRoleBinding` to `system:auth-delegator`.
- Managed declaratively by **Argo** (wave 0/1), **before** ESO (wave 1) so the auth path is live when ESO first
  authenticates.

---

## 4. Ordering (acyclic — no circle)

```text
cluster bootstrap (kubernetes root)            # produces API endpoint + CA
        │ terraform_remote_state
        ▼
terraform/vault apply (this spec)              # consumes endpoint+CA, writes auth config + role + policy
        │
        ▼
Argo wave 0/1: vault-auth SA + ESO             # ESO authenticates → reads secret/homelab/* → native Secrets
```

Vault pre-exists the cluster, so there is no dependency cycle. The cluster root never needs this auth to come up (its
own provider creds come from Vault KV directly, as today).

---

## 5. Notes / open items

- **Vault is HTTP** (`http://vault.d.lcamaral.com`) — ESO↔Vault is cleartext on SVR L2. Accept (documented L2 trust
  boundary) or issue a Vault TLS cert (ACME) — decide at plan time.
- Confirm live **Vault version** (≥1.21 ⇒ `audience` mandatory).
- This closes `iac-audit` I3; cross-link both documents on implementation.
