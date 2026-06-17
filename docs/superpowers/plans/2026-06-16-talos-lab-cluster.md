# Talos Lab Cluster — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (recommended)
> or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Stand up an IaC Talos Kubernetes lab cluster on Proxmox behind a VyOS BGP router, end-to-end
from `terraform apply` + GitOps, integrated with existing Vault / MinIO / Thanos / registry / Pi-hole.

**Architecture:** VyOS inter-segment router (BGP-peered with pfSense) fronts an isolated cluster segment;
Talos (declarative, immutable) provides the nodes; Terraform bootstraps Cilium + Argo CD; Argo owns all
workloads. See the three committed design specs (`docs/superpowers/specs/2026-06-15-*`).

**Tech Stack:** Terraform (`bpg/proxmox`, `siderolabs/talos`, `vault`, `cloudflare`, `adamantal/dreamhost`,
`helm`, `kubernetes`), VyOS rolling, Talos Linux, Cilium, Argo CD, External Secrets Operator, cert-manager,
Proxmox-CSI + csi-driver-nfs, Velero, Kyverno, MinIO (S3 state + backups).

---

## ⏱️ Live status — last updated 2026-06-16

> **This table is the tracker.** The per-step checkboxes below are VyOS-centric and predate the live
> **FRR-on-Debian pivot** (VyOS rolling images are now paywalled → HTTP 403), so track real progress here.
> Authoritative live-status docs: `terraform/lab-network/LIVE-FACTS.md` (facts + execution outcomes) and
> `terraform/lab-network/pfsense-frr-bgp.md` (pfSense BGP runbook + rollback). Branch
> `feat/k8s-talos-lab-cluster`.

| Sprint | Status | Notes |
|---|---|---|
| 0 — Foundations | ✅ **done** | facts/versions, 3 MinIO buckets exist, `lab-network` root inits+validates. Deviation: **local state** (MinIO S3 backend deferred — flaky from the workstation). |
| 1 — Lab network (router) | ✅ **done (LIVE)** | **lab-router VM 130 (FRR-on-Debian)** up; **BGP Established** pfSense(AS65000)↔router(AS65010); pfSense learned `192.168.30.0/24` in its FIB; `filter.bypassstaticroutes` (asymmetric fix) on; **zone firewall enforced** (Sprint 1.5). Router reconciled to a reproducible script; full bpg-Terraform gated on a Proxmox deploy-SSH-key decision. |
| 2 — Cluster base (Talos) | ⬜ not started | **Clear first:** `siderolabs/talos` provider download hangs from the workstation (GitHub releases unreachable) — pre-stage it or run from a LAN host. |
| 3 — Vault / secrets | ⬜ not started | — |
| 4 — Storage | ⬜ not started | — |
| 5 — Observability / DR | ⬜ not started | — |
| 6 — Acceptance | ⬜ not started | — |

**Resources created (all revertible):** Proxmox `vmbr30` + VM 130 + `LabIaC` role + `terraform@pve!labiac`
token; pfSense FRR pkg + BGP + sloppy-state (config backup `/tmp/pfsense-config-2026-06-16-pre-frr.xml`);
Vault `secret/homelab/proxmox/iac_token`; MinIO buckets `tfstate`/`velero-k8s-lab`/`thanos-k8s-lab`.

**Open follow-ups:** reconcile the authored bpg VyOS TF → FRR-on-Debian (or keep VM `qm`-managed +
`terraform import`); pre-stage `siderolabs/talos` for the `kubernetes` root; tighten the router zone firewall.

---

## How to use this plan

- **Source of truth for content:** the three specs. This plan sequences the work and defines acceptance;
  full resource detail lives in the specs (cited as `cluster §N` / `labnet §N` / `vault §N`).
- **Unbreakable step:** each `- [ ]` step is atomic, independently verifiable, and ends green or rolls back.
  Never leave a step half-applied.
- **Rhythm per step:** `terraform validate` → `terraform plan` (review) → `apply` → **live assert** → **commit**.
- **Commit discipline:** commit after every step. Conventional commits, **allowed scopes only**
  (`network, proxmox, deploy, monitoring, storage, security, docs, ci, inventory, backup, …`).
  Markdown must pass `markdownlint` (120-char prose; tables/code exempt).
- **No `null_resource`** anywhere; the only non-IaC actions are the flagged pfSense package/GUI bootstrap steps.
- **Run location:** locally, with Vault + Keychain + SSH (`proxmox`, `pfsense`) reachable. No remote agents.

### Prerequisites (one-time, before Sprint 0)

- [ ] `export VAULT_ADDR=http://vault.d.lcamaral.com` and `VAULT_TOKEN` from Keychain `vault-root-token`.
- [ ] SSH works: `ssh proxmox true` and `ssh pfsense true`.
- [ ] `mise install` (`terraform`, `kubectl`, `talosctl`, `helm`, `jq`, `yq` pinned in `.config/mise`).
- [ ] Confirm working branch: `git switch feat/k8s-talos-lab-cluster`.

---

## Sprint 0 — Foundations & pre-flight (zero production impact)

**Outcome:** every live unknown is resolved and pinned; state backend works; repo scaffolding compiles.

### Task 0.1 — Resolve live unknowns (gates everything downstream)

- [ ] **Step 1: Capture live facts into a pinned values file.**
  Run and record results in `terraform/lab-network/LIVE-FACTS.md`:

  ```bash
  ssh pfsense 'pkg info -x frr; echo ---; pfSsh.php playback svc list 2>/dev/null | grep -i frr'
  ssh proxmox 'free -h; pvesm status; qm list'
  # DHCP scopes + free IPs on SVR(28)/HOME(10)/LAB(100):
  # use the pfsense-manage skill to read dhcpd ranges; pick VyOS legs OUTSIDE pools and clear of .59.0/26
  vault status | grep Version            # ≥1.21 ⇒ audience mandatory (vault §2)
  ```

- [ ] **Step 2: Pin tool/provider/chart versions** (Context7 + registry) into `terraform/versions.md`:
  Talos (`siderolabs/talos ~>0.11`, Talos OS `v1.13.x`), `bpg/proxmox ~>0.109`, Cilium `≥1.19`,
  Argo CD, ESO, cert-manager, Velero, Kyverno, csi-driver-nfs, proxmox-csi-plugin.

- [ ] **Step 3: Confirm Proxmox-CSI Talos extension need** (cluster §3/§14.1): inspect the plugin's
  current install docs; record the exact Image Factory `systemExtensions` (likely just
  `siderolabs/qemu-guest-agent`).

- [ ] **Step 4: Commit.** `git add terraform/lab-network/LIVE-FACTS.md terraform/versions.md`
  → `git commit -m "docs(network): pin live facts and versions for lab cluster"`

**Acceptance:** FRR confirmed installable; all version pins recorded; VyOS leg + node IPs chosen and
verified free; Vault version known.

### Task 0.2 — MinIO state backend

- [ ] **Step 1:** In `terraform/minio/`, add buckets `tfstate`, `velero-k8s-lab`, `thanos-k8s-lab` with
  **versioning + SSE** and per-bucket access keys; write keys to Vault
  (`secret/homelab/minio/{tfstate,velero}`). Reference cluster §10/§13.
- [ ] **Step 2:** `cd terraform/minio && terraform plan` → review → `apply`.
- [ ] **Step 3 (assert):** `mc ls`/`aws --endpoint` lists the buckets; versioning on.
- [ ] **Step 4: Commit.** `terraform(storage): minio state + backup buckets for lab cluster`.

### Task 0.3 — Repo scaffolding (compiles, no resources yet)

- [ ] **Step 1:** Create `terraform/lab-network/` and `terraform/kubernetes/` with `providers.tf`
  (pinned versions, MinIO `s3` backend block incl. `use_lockfile=true` + MinIO `skip_*`/`use_path_style`
  flags per cluster §11) and empty `main.tf`. Create `gitops/{bootstrap,infra,apps}/.gitkeep`.
- [ ] **Step 2 (assert):** `terraform -chdir=terraform/lab-network init` and `…/kubernetes init` succeed
  against MinIO (backend creds via `AWS_*` env); `terraform validate` passes both.
- [ ] **Step 3: Commit.** `terraform(network): scaffold lab-network + kubernetes roots with minio backend`.

**Sprint 0 acceptance:** `terraform init/validate` green on both new roots; live facts + versions pinned;
no production change made.

---

## Sprint 1 — Lab network (VyOS) — `labnet` spec

**Outcome:** isolated CLUSTER segment routed by VyOS, BGP-peered to pfSense, reachable from HOME/SVR.
**Rollout is staged leg-by-leg (labnet §6); each step has an explicit rollback.**

### Task 1.1 — pfSense bootstrap (documented manual exceptions)

- [ ] **Step 1 (deploy):** Install `pfSense-pkg-frr` via Package Manager; add a firewall **pass TCP/179**
  from the chosen VyOS SVR leg on the SVR interface (use `pfsense-manage`). Do **not** configure peers yet.
- [ ] **Step 2 (assert):** FRR service present (`ssh pfsense 'pkg info -x frr'`); rule visible.
- [ ] **Step 3 (commit):** record the manual step in `terraform/lab-network/LIVE-FACTS.md`
  → `docs(network): record pfSense FRR bootstrap`.
  **Rollback:** uninstall package; delete rule.

### Task 1.2 — Bridge + VyOS VM (CLUSTER leg only)

- [ ] **Step 1 (implement):** `bridge.tf` = `proxmox_network_linux_bridge "vmbr30"` (no ports/address);
  `vyos.tf` = VM with the CLUSTER NIC, `vyos-config.tftpl` rendering interfaces + DHCP (reservations keyed
  to node MACs, labnet §4.3) + NTP relay. Provider needs the `ssh{}` block (cluster §3).
- [ ] **Step 2 (deploy):** `terraform -chdir=terraform/lab-network plan` → review → `apply`.
- [ ] **Step 3 (assert):** `ping 192.168.30.1`; a throwaway VM on `vmbr30` gets a reserved lease.
- [ ] **Step 4 (commit):** `terraform(network): vmbr30 + VyOS VM (cluster leg, DHCP, NTP)`.
  **Rollback:** `terraform destroy` of the root (no other segment touched yet).

### Task 1.3 — SVR leg + BGP peering

- [ ] **Step 1 (implement):** add the SVR NIC + leg IP; VyOS BGP (AS65010) neighbor pfSense `192.168.48.1`
  (AS65000); aggregate `10.244.0.0/16 summary-only` + originate `192.168.30.0/24`; prefix-lists (labnet §4.1).
  Configure pfSense FRR neighbor + inbound prefix-list + `redistribute bgp` (via `pfsense-manage`).
- [ ] **Step 2 (deploy + assert):** `apply`; then
  `ssh pfsense 'vtysh -c "show ip bgp summary"'` shows the neighbor **Established**;
  `192.168.30.0/24` appears in pfSense FIB (`ssh pfsense 'netstat -rn | grep 192.168.30'`).
- [ ] **Step 3 (commit):** `terraform(network): VyOS↔pfSense BGP peering + route aggregation`.
  **Rollback:** `shutdown` the BGP neighbor (both sides); remove SVR leg.

### Task 1.4 — Asymmetric-routing fix + remaining legs

- [ ] **Step 1 (deploy):** Enable pfSense **sloppy state** (“Bypass firewall rules for traffic on the
  same interface”) scoped to the cluster CIDRs (labnet §4.1, the agreed fix).
- [ ] **Step 2 (implement):** add HOME (MTU 9000) + LAB legs; **zone firewall** default-drop matrix
  (labnet §4.2); MSS clamp 1460 on HOME ingress; DNAT `:443/:80 → 192.168.30.128` (labnet §4.4).
- [ ] **Step 3 (deploy + assert):** `apply`; from a HOME host: `nc -vz 192.168.30.1 22` style reachability
  to a temp listener; verify **symmetric path** with `ssh pfsense 'pfctl -ss | grep 192.168.30'` (no stuck
  half-open); `mtr` across the HOME jumbo boundary (no PMTUD black hole).
- [ ] **Step 4 (commit):** `terraform(network): sloppy-state, HOME/LAB legs, zone firewall, DNAT, MSS`.
  **Rollback:** disable sloppy state; remove legs/zones.

**Sprint 1 acceptance:** BGP Established; cluster prefix in pfSense FIB; a HOME/SVR host completes a TCP
flow to a cluster-segment IP; zone matrix enforced; each step proven rollback-able.

---

## Sprint 2 — Talos cluster base — `cluster` §3–§5, §7

**Outcome:** 5-node Talos cluster Ready, Cilium BGP advertising LB IPs, Argo CD healthy.

### Task 2.1 — Image + VMs

- [ ] **Step 1 (implement):** `terraform/kubernetes/image.tf` = `talos_image_factory_schematic`
  (extensions from Task 0.3) + `data.talos_image_factory_urls` (nocloud); `vms.tf` = `for_each` node map
  (IPs/MACs from labnet contract, **MACs must equal the VyOS DHCP reservations**), all on `vmbr30`
  (via `terraform_remote_state` of `lab-network`). (cluster §3)
- [ ] **Step 2 (deploy + assert):** `plan` → `apply`; 5 VMs boot into Talos **maintenance mode** and pick
  up their reserved IPs (`talosctl -n 192.168.30.11 version --insecure` responds).
- [ ] **Step 3 (commit):** `terraform(proxmox): talos image factory + 5 cluster VMs`.

### Task 2.2 — Talos config + bootstrap

- [ ] **Step 1 (implement):** `talos.tf` = `machine_secrets`, `data.machine_configuration`
  (endpoint = VIP `https://192.168.30.5:6443`, `talos_version` pinned), `machine_configuration_apply` ×5
  with patches (VIP, `cni:none`, `proxy.disabled`, install disk + installer image, registry mirror, NTP,
  `kubernetesTalosAPIAccess` on CPs), `machine_bootstrap` targeting **cp-1 IP 192.168.30.11** (not VIP),
  `data.cluster_kubeconfig`. Write kubeconfig + talosconfig to Vault `secret/homelab/k8s/*`. (cluster §4)
- [ ] **Step 2 (deploy + assert):** `apply`; `talosctl -e 192.168.30.5 -n … health` OK;
  `kubectl get nodes` shows 5 nodes **NotReady** (expected: no CNI yet) and etcd quorum healthy.
- [ ] **Step 3 (commit):** `terraform(deploy): talos machineconfig + bootstrap + kubeconfig to vault`.
  **Rollback:** `terraform destroy` of VMs/config (segment + VyOS remain).

### Task 2.3 — Cilium (ordered) + Argo

- [ ] **Step 1 (implement):** Apply **Gateway API CRDs via Terraform** (`kubernetes_manifest`) **before**
  Cilium; then `helm_release` Cilium (`kubeProxyReplacement`, native routing, `nativeRoutingCIDR`,
  BGP control-plane, Gateway API, Hubble — cluster §5); BGP v2 CRDs (Cluster/Peer/Advertisement ×2 +
  `CiliumLoadBalancerIPPool`); then `helm_release` Argo CD with repo deploy-key (Vault).
- [ ] **Step 2 (deploy + assert):** `apply`; nodes go **Ready**; `cilium status` green;
  on VyOS/pfSense the **LB pool + pod routes** appear via BGP; `argocd app list` reachable.
- [ ] **Step 3 (commit):** `terraform(deploy): gateway-api crds, cilium (bgp), argo cd bootstrap`.

**Sprint 2 acceptance:** `kubectl get nodes` all Ready; etcd quorum; a `LoadBalancer` test svc gets a
`192.168.30.128/25` IP that is **pingable from a HOME host**; Argo healthy.

---

## Sprint 3 — Vault wiring, secrets & GitOps addons — `vault` spec + `cluster` §7–§8

**Outcome:** ESO pulls Vault secrets; cert-manager issues a real LE cert; Kyverno + Gateways live.

### Task 3.1 — Vault Kubernetes auth (acyclic ordering)

- [ ] **Step 1 (implement):** Argo `infra` app (wave 0) creates the `vault-auth` SA +
  `system:auth-delegator` binding (vault §3). In `terraform/vault/` add
  `vault_kubernetes_auth_backend_config` (host = VIP, CA from kubeconfig, audience if Vault ≥1.21),
  role for ESO, and the enumerated `eso-homelab-reader` policy; fix the dangling bindings (vault §2).
- [ ] **Step 2 (deploy + assert):** `terraform -chdir=terraform/vault apply`;
  `vault read auth/kubernetes/lab-cluster/config` returns the host/CA.
- [ ] **Step 3 (commit):** `security(deploy): vault kubernetes auth + eso least-priv role/policy`.

### Task 3.2 — ESO + ACME plumbing + cert-manager

- [ ] **Step 1 (implement):** `terraform/cloudflare/` adds the DreamHost CNAME
  `_acme-challenge.lab.lcamaral.com → _acme-challenge.lab.cf.lcamaral.com` (cluster §8). Argo `infra`
  (wave 1) deploys ESO (`ClusterSecretStore` → `kubernetes/lab-cluster`), cert-manager + `ClusterIssuer`
  (Cloudflare DNS-01, `cnameStrategy: Follow`), Kyverno, and the Cilium `Gateway`.
- [ ] **Step 2 (deploy + assert):** an `ExternalSecret` materializes a `secret/homelab/*` value
  (`kubectl get secret … -o yaml`); a test `Certificate` reaches **Ready/issued** for `test.lab.lcamaral.com`.
- [ ] **Step 3 (commit):** `deploy(network): eso, cert-manager dns-01 (cname-follow), kyverno, gateway`.

**Sprint 3 acceptance:** ExternalSecret = Synced; a real LE cert issues for a `*.lab.lcamaral.com` host;
Kyverno admission active.

---

## Sprint 4 — Storage — `cluster` §6

**Outcome:** RWO block (Proxmox-CSI) + RWX bulk (NFS) classes work; DB-on-NFS is blocked.

### Task 4.1 — Proxmox-CSI

- [ ] **Step 1 (implement):** create the least-priv Proxmox role + token (`VM.Audit`, `VM.Config.Disk`,
  `Datastore.AllocateSpace`, `Datastore.Audit`) → Vault `secret/homelab/proxmox/csi`; Argo deploys
  proxmox-csi-plugin + `proxmox-ssd` StorageClass (`WaitForFirstConsumer`, default). (cluster §6)
- [ ] **Step 2 (assert):** a RWO PVC binds; a pod writes; delete pod → reschedules and **reattaches**.
- [ ] **Step 3 (commit):** `storage(deploy): proxmox-csi block storageclass (least-priv token)`.

### Task 4.2 — NFS-CSI + DB guardrail

- [ ] **Step 1 (implement):** create a **new `/volume2` NFS export** (quota'd) on the NAS; Argo deploys
  csi-driver-nfs + `nfs-bulk` StorageClass + the **Kyverno** policy rejecting DB-labeled pods on `nfs-bulk`.
- [ ] **Step 2 (assert):** a RWX PVC binds and is shared by 2 pods; a DB-labeled pod mounting `nfs-bulk`
  is **rejected** by Kyverno.
- [ ] **Step 3 (commit):** `storage(deploy): nfs-csi bulk class + kyverno db-off-nfs guardrail`.

**Sprint 4 acceptance:** both StorageClasses provision; reschedule reattaches block PV; DB-on-NFS denied.

---

## Sprint 5 — Observability & DR — `cluster` §9–§10

**Outcome:** cluster metrics in existing Grafana/Thanos; etcd + PV backups proven restorable.

### Task 5.1 — Metrics into existing Thanos

- [ ] **Step 1 (implement):** Argo deploys in-cluster Prometheus (**full + Thanos sidecar** → MinIO
  `thanos-k8s-lab`, `external_labels{cluster:k8s-lab}`), kube-state-metrics, node/cAdvisor, Cilium/Hubble.
  Register the sidecar as a store on the existing Thanos Querier; allow Alertmanager reach in the VyOS
  zone matrix. (cluster §9)
- [ ] **Step 2 (assert):** a cluster metric (e.g. `kube_node_status_condition`) is queryable in the
  **existing Grafana**; Hubble UI reachable via Gateway.
- [ ] **Step 3 (commit):** `monitoring(deploy): cluster prometheus+thanos sidecar into existing querier`.

### Task 5.2 — Backups

- [ ] **Step 1 (implement):** Argo deploys `talos-backup` CronJob (age key in Vault → MinIO) and Velero
  (`--default-volumes-to-fs-backup=true`, kopia → `velero-k8s-lab`) with `BackupStorageLocation` + `Schedule`.
- [ ] **Step 2 (assert):** an etcd snapshot object lands in MinIO; `velero backup create test` then a
  **restore** of a test PV succeeds (cluster §10 restore order).
- [ ] **Step 3 (commit):** `backup(deploy): talos-backup cronjob + velero filesystem backups`.

**Sprint 5 acceptance:** metrics in Grafana/Thanos; one etcd snapshot + one PV backup restored end-to-end.

---

## Sprint 6 — End-to-end acceptance & handoff

### Task 6.1 — End-to-end app + HA drills

- [ ] **Step 1:** Deploy a sample app via Argo with an `HTTPRoute`; publish at `demo.lab.lcamaral.com`
  (Pi-hole split-horizon A → LB IP). **External request → VyOS DNAT → Gateway → pod with valid LE cert.**
- [ ] **Step 2 (HA drills):** reboot one control-plane (API stays up via VIP, quorum holds); perform a
  rolling Talos patch (no API downtime); reboot a worker (Proxmox-CSI reattaches; pods reschedule).
- [ ] **Step 3 (commit):** `deploy(network): sample app end-to-end + HA drill notes`.

### Task 6.2 — Documentation & inventory

- [ ] **Step 1:** Update `inventory/virtual-machines.md` (5 Talos VMs + VyOS), `inventory/servers.md`
  (`vmbr30`, cluster, VyOS), new `inventory/k8s-workloads.md`, `terraform/README.md` (new roots, MinIO
  backend, apply order), `CLAUDE.md` (kubeconfig/talosconfig paths, VyOS access, BGP topology). (cluster §15)
- [ ] **Step 2:** Save Memory MCP entities (cluster, ASNs, gotchas) and cross-link `iac-audit` I3 = closed.
- [ ] **Step 3 (assert):** `markdownlint` clean on changed docs.
- [ ] **Step 4 (commit):** `docs(inventory): record lab cluster + vyos; update terraform readme + claude.md`.

**Final acceptance checklist:**

- [ ] `kubectl get nodes` = 5 Ready; etcd quorum healthy; rolling upgrade proven.
- [ ] BGP Established; LB IP reachable from HOME/SVR (symmetric); zone matrix enforced.
- [ ] ESO Synced; LE cert valid; Kyverno denies DB-on-NFS.
- [ ] Both StorageClasses provision; block PV reattaches on reschedule.
- [ ] Cluster metrics in Grafana/Thanos; etcd + PV backup restored.
- [ ] Sample app reachable externally with a trusted cert.
- [ ] Inventory/CLAUDE.md/memory updated; every step committed.

---

## Open items carried from specs (resolve in-flight, do not block the wrong step)

- Proxmox-CSI exact Talos extensions (Task 0.1/0.3).
- Vault ≥1.21 ⇒ `audience` required (Task 3.1).
- pfSense FRR REST-API installability vs manual (Task 1.1).
- Proxmox LAB (`vmbr0`/`.100.1`) coexistence with the VyOS LAB leg (Task 1.4).
- NUMA pinning for cluster VMs (perf tuning; optional, post-acceptance).
