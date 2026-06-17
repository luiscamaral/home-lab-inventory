# Design: Talos Kubernetes Cluster on Proxmox — IaC

**Date:** 2026-06-15
**Status:** Draft (revised after 5-agent review; pending sign-off)
**Owner:** Luis Amaral
**Companion specs:**

- `2026-06-15-lab-network-vyos-design.md` — **prerequisite** (VyOS router, BGP, CLUSTER segment, DHCP, edge DNAT). Owns
  the **shared network contract** (segments, IPs, ASNs, MACs).
- `2026-06-15-vault-k8s-wiring-design.md` — Vault `kubernetes` auth + ESO role/policy (addendum to
  `iac-audit-2026-04-30.md`).

> **Note (2026-06-16):** the inter-segment router was implemented as **FRR-on-Debian**, not VyOS (VyOS
> rolling images are now paywalled). Wherever this spec says "VyOS," read "the lab-router" — same role,
> same BGP/DHCP/NAT/zone-firewall design. It's **live**: see `terraform/lab-network/`.

---

## 1. Goal & non-goals

**Goal:** a production-shaped **Talos** Kubernetes cluster on the single Proxmox host, provisioned end-to-end from IaC —
VM → OS → etcd → CNI → workloads — with **no `null_resource`/shell**. Terraform bootstraps the minimum (Cilium + Argo);
**Argo CD** (GitOps) owns everything else.

**Success:** `terraform apply` (+ git) is the only path; one control-plane VM can fail without API loss; rolling
Talos/K8s upgrades with no downtime; integrates with existing Vault, MinIO, Thanos/Grafana, registry, Pi-hole.

**Non-goals:** migrating existing Docker workloads; VyOS HA; second Proxmox host; demoting pfSense.

---

## 2. Decisions (locked)

| Area | Decision |
|---|---|
| Distro / provisioning | **Talos** · `siderolabs/talos ~>0.11` + `bpg/proxmox ~>0.109` (with `ssh{}` block) |
| Topology | 3 control-plane (2c/4G, tainted) + 2 workers (8c/32G) + API VIP — **32 GB workers confirmed** (live: 165 GiB free) |
| CNI / LB | **Cilium ≥1.19** — kube-proxy replacement, native routing, **BGP v2 API**, LB-IPAM, Gateway API, Hubble |
| Storage | **Proxmox-CSI** (RWO block, default, DBs) + **NFS-CSI** (RWX, new `/volume2` export) |
| GitOps | **Argo CD** app-of-apps; TF bootstraps Cilium + Gateway-API CRDs + Argo only |
| Secrets | **ESO** ⇄ Vault `kubernetes/lab-cluster` auth (see vault-wiring spec) |
| Edge / TLS | VyOS DNAT → Cilium Gateway API · cert-manager **LE DNS-01 (Cloudflare solver + `cnameStrategy: Follow`)** for `*.lab.lcamaral.com` |
| State / Obs | **MinIO S3** backend (locking + SSE) · **3rd Prometheus + Thanos sidecar → MinIO** (sidecar model, not remote-write) |

Versions pinned at plan time (current stable: Talos v1.13.x, Cilium ≥1.19) verified via TF registry + Context7.

---

## 3. Compute (`bpg/proxmox`)

- **Talos image** — `talos_image_factory_schematic` (extensions: `siderolabs/qemu-guest-agent`; CSI extensions added
  only after verifying Proxmox-CSI's exact needs — likely none for virtio-blk) → `data.talos_image_factory_urls`
  (platform `nocloud`) → installer image fed into machineconfig. Declarative + reproducible (no hardcoded URL).
- **VMs** — 5 via `for_each` node map `{role, cpu, ram, disk, ip, mac}` (IPs/MACs from the shared contract), all on
  **`vmbr30`** (referenced via `terraform_remote_state` from `lab-network`). Stable MACs **match the VyOS DHCP
  reservations** → deterministic maintenance-mode IPs. System disks on `thin-pool-ssd`. PVs are carved on-demand by
  Proxmox-CSI (no pre-provisioned data disks).
- Provider creds (Proxmox API token + SSH key) from Vault; `vault` provider + `data.vault_kv_secret_v2` per existing
  `terraform/portainer` pattern; `TF_VAR_vault_token` from Keychain at apply.

---

## 4. Talos cluster (`siderolabs/talos`) — declarative, no shell

```text
resource talos_machine_secrets                      # cluster PKI
data     talos_machine_configuration (cp / worker)  # base config, talos_version pinned, endpoint = https://192.168.30.5:6443 (VIP)
resource talos_machine_configuration_apply (×5)     # node = static IP (== DHCP reservation); config_patches via yamlencode
resource talos_machine_bootstrap                    # node/endpoint = cp-1 DIRECT IP 192.168.30.11 (NOT the VIP)
data     talos_cluster_kubeconfig                   # after bootstrap; feeds helm/kubernetes providers
```

**machineconfig patches:** static IP + gateway `.30.1`; **VIP `.30.5`**; `cluster.network.cni.name = none`;
`cluster.proxy.disabled = true`; install disk + installer image; **registry mirror → `registry.cf.lcamaral.com`**
(node-level auth, avoids per-pod imagePullSecrets); `machine.time.servers = [192.168.30.1]` (NTP via VyOS);
`kubernetesTalosAPIAccess` enabled on control planes (for `talos-backup`). All control-plane nodes share `vmbr30` (VIP
L2 requirement satisfied).

kubeconfig **and** talosconfig are written to **Vault** (`secret/homelab/k8s/{kubeconfig,talosconfig}`); operators pull
to `~/.kube/config-lab` / `~/.talos/config-lab`. The MinIO state (which also contains these as outputs) is
**SSE-encrypted** with restricted bucket access.

---

## 5. Cilium (Helm, TF-bootstrapped) — order matters

1. **Gateway API CRDs first** — applied by **Terraform** (`kubernetes_manifest`/`kubectl_manifest`) before Cilium, NOT
   by Argo (Argo isn't up yet).
2. `helm_release` Cilium: `kubeProxyReplacement=true`, `routingMode=native`, `nativeRoutingCIDR=192.168.30.0/24`,
   `ipam=kubernetes`, `bgpControlPlane.enabled=true`, `gatewayAPI.enabled=true`, `hubble.{relay,ui}.enabled=true`. **No
   `l2announcements`** (BGP only).
3. **BGP v2 API** CRDs (Argo or TF): `CiliumBGPClusterConfig` (peer VyOS `192.168.30.1` AS65010), `CiliumBGPPeerConfig`,
   `CiliumBGPAdvertisement` (two: `PodCIDR` **and** `Service` for LB IPs), `CiliumLoadBalancerIPPool 192.168.30.128/25`.

> Cilium install failure with kube-proxy disabled + `cni:none` leaves nodes NotReady with no fallback → validate the
> Helm install on first apply before scaling; pin Cilium ≥1.19 (v2 BGP API; Gateway-API LB advertisement fix).

---

## 6. Storage

| Class | Driver | Mode | Use |
|---|---|---|---|
| `proxmox-ssd` (default) | Proxmox-CSI · `volumeBindingMode: WaitForFirstConsumer` | RWO | stateful, **DBs** |
| `nfs-bulk` | csi-driver-nfs → **new `/volume2` export** (quota'd) | RWX | bulk/media — **no DBs** |

- Proxmox-CSI uses a **dedicated least-priv Proxmox token** (`VM.Audit`, `VM.Config.Disk`, `Datastore.AllocateSpace`,
  `Datastore.Audit`) — separate from the TF token; Vault path `secret/homelab/proxmox/csi`. Single-host = one CSI zone →
  clean attach/detach on reschedule. **No CSI snapshots** (those need `root@pam`).
- **DB-off-NFS enforced** by a **Kyverno** policy (reject DB-labeled pods mounting `nfs-bulk`), citing the NFS lock-loss
  history. Existing `pve-*` NFS pools (95% full) are **not** used.

---

## 7. GitOps (Argo CD)

- TF installs Argo via `helm_release`; Argo **repo auth** = read-only **deploy key** (Vault
  `secret/homelab/k8s/argo-deploy-key`, materialized into an Argo `Repository` secret).
- **app-of-apps** with **sync waves**: wave 0 = Kyverno + Gateways; wave 1 = cert-manager + ESO (gated until Vault
  wired); wave 2 = CSI drivers, Velero, monitoring; wave 3 = workloads.

```text
gitops/{bootstrap, infra, apps}
```

- **PodSecurity:** `baseline` enforce cluster-wide, `privileged` exemption for `kube-system`/`cilium`/`csi-*`.
  **NetworkPolicy:** allow-all initially (documented), per-namespace deny-all as workloads mature. **LimitRange**
  default requests per namespace.

---

## 8. Secrets, edge & TLS

- **ESO** `ClusterSecretStore` → Vault `kubernetes/lab-cluster` auth (see vault-wiring spec); SA
  `external-secrets/external-secrets`; policy enumerates only the `secret/homelab/*` leaves needed. ESO/cert-manager
  sync **gated to wave 1** so it never races ahead of Vault config.
- **cert-manager** `ClusterIssuer` ACME LE **DNS-01 Cloudflare solver** + `cnameStrategy: Follow`. The static delegation
  record `_acme-challenge.lab.lcamaral.com → _acme-challenge.lab.cf.lcamaral.com` is added in
  **`terraform/cloudflare/`** via the `adamantal/dreamhost` provider (one record). Hostnames `*.lab.lcamaral.com`.
- **Edge:** Cilium **Gateway API** terminates TLS; **VyOS DNAT** (lab-network spec) `:443`→`192.168.30.128`; **Pi-hole
  split-horizon** A records map hostnames → LB IP.

---

## 9. Observability (integrate with existing Thanos)

Existing stack is **sidecar + block-upload to MinIO (no Thanos Receive)**. So: deploy an **in-cluster Prometheus (full,
not agent) + Thanos sidecar** uploading 2h blocks to a MinIO bucket; `external_labels = {cluster: k8s-lab, replica: A}`
(distinct `cluster` label so it does **not** dedupe against homelab replicas A/B). The existing Thanos **Querier adds
the new sidecar as a store endpoint**. Scrape: kube-state-metrics, node/cAdvisor, Cilium/Hubble, Talos. Alerts →
existing Alertmanager (`192.168.59.27:9093`/`192.168.4.238:9093`) — cross-segment reachability allowed by the VyOS zone
matrix. Hubble UI via Gateway.

---

## 10. Backup / DR

- **etcd:** `talos-backup` **CronJob** (Argo-managed; `kubernetesTalosAPIAccess` + `age` key in Vault) → MinIO bucket,
  e.g. `0 */6 * * *`, retained N. _(No machineconfig snapshot scheduler exists.)_
- **Apps/PVs:** **Velero** with **filesystem backup (kopia)** — `--default-volumes-to-fs-backup=true` (CSI snapshots
  unavailable without `root@pam`) → MinIO `velero` bucket with `BackupStorageLocation` + `Schedule` CRs; **separate
  MinIO creds** from state.
- **Restore order:** etcd snapshot → cluster bootstrap → Velero restore. Documented runbook.
- **MinIO concentration risk** (state + Thanos + Velero) noted; distinct buckets + creds + SSE; covered by the NAS
  backup of MinIO volumes.

---

## 11. IaC structure, upgrades, rollback

**Roots:** `terraform/kubernetes/` (new), consuming `lab-network` outputs via `terraform_remote_state` (MinIO);
`terraform/vault/` edited per the vault-wiring spec; `terraform/cloudflare/` adds the ACME CNAME. All new roots: MinIO
S3 backend (`use_lockfile` + MinIO `skip_*`/`use_path_style`; creds via `AWS_*` env at init).

**Upgrades:** Talos = bump `talos_version` + installer in machineconfig (`talos_machine_configuration_apply` rolls
nodes); K8s = `talosctl upgrade-k8s` runbook; Cilium chart tracked to the K8s version matrix.

**Rollback (per bring-up phase):** cluster not yet serving → `terraform destroy` of `kubernetes` root; Cilium/Argo
failure → re-apply pinned chart; Vault wiring → `terraform` revert (auth backend additive). Network rollback lives in
the lab-network spec.

---

## 12. Bring-up order

1. **lab-network spec** complete (VyOS, BGP, sloppy-state, DHCP reservations) — cluster segment live.
2. `terraform/kubernetes` apply → Image Factory schematic → 5 Talos VMs (maintenance IPs from VyOS reservations) →
   config apply → bootstrap (cp-1 IP) → kubeconfig → **Gateway-API CRDs → Cilium (BGP) → Argo**.
3. BGP establishes; LB pool advertised; verify routes in pfSense FIB.
4. **vault-wiring spec** apply → `kubernetes/lab-cluster` auth + ESO role.
5. Argo waves sync: Kyverno/Gateways → cert-manager/ESO → CSI/Velero/monitoring → apps.
6. ACME issues `*.lab.lcamaral.com`; first service published via Gateway + VyOS DNAT.

---

## 13. Risks & validation

| Risk | Mitigation |
|---|---|
| Single host SPOF | accepted (lab) |
| Cilium install fails → nodes NotReady | validate Helm install before scale; pinned chart |
| ESO races Vault | sync-wave gating (wave 1) |
| Compromised pod → prod | VyOS zone default-drop (lab-network) |
| MinIO is state+backup+Thanos | separate buckets/creds + SSE + NAS backup |
| thin-pool overcommit | autoextend threshold + Prometheus alert + per-ns ResourceQuota |

**Validation:** `talosctl health`, nodes Ready, etcd quorum; HA drill (reboot a CP → VIP holds; rolling upgrade no
downtime; reboot worker → CSI reattaches); BGP routes in pfSense + LB IP reachable from HOME/SVR (symmetric via
sloppy-state); ESO `ExternalSecret` materializes; Argo app syncs; external hit → DNAT → Gateway → pod with valid LE
cert; cluster metrics in existing Grafana/Thanos; Velero backup+restore of a test PV.

---

## 14. Open items (verify at plan time)

1. Proxmox-CSI exact Talos extensions (likely none for virtio-blk) + least-priv role.
2. Version pins (Talos/K8s/Cilium/Argo/ESO/cert-manager/Velero/Kyverno).
3. New `/volume2` NFS export path + Synology quota.
4. Thanos sidecar MinIO bucket + Querier store registration; Alertmanager auth.
5. NUMA CPU pinning for cluster VMs (perf tuning — to plan, not blocking).

---

## 15. Documentation updates (on implementation)

`inventory/virtual-machines.md` (5 Talos VMs + VyOS) · `inventory/servers.md` (vmbr30, cluster, VyOS) · new
`inventory/k8s-workloads.md` · `terraform/README.md` (new roots, MinIO backend, apply order) · `CLAUDE.md` (kubeconfig
`~/.kube/config-lab`, talosconfig, VyOS `ssh vyos@192.168.30.1`, BGP topology) · Memory MCP (cluster entities, ASNs,
gotchas).
