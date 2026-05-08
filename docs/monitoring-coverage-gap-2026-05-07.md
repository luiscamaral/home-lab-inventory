# 📊 Monitoring Coverage Gap Audit — 2026-05-07

Audit of Prometheus scrape coverage against
`generated/prometheus-thanos-monitoring/05-exporters.md` and current inventory.
Phase A items below are landed in this PR; the remainder are tracked for follow-up.

## ✅ Currently covered (62/63 targets UP)

| Layer         | Job                                   | Targets                                       |
| ------------- | ------------------------------------- | --------------------------------------------- |
| Host OS       | `node`                                | dockermaster, ds-1, ds-2, nas                 |
| Containers    | `cadvisor`                            | dockermaster, ds-1, ds-2, nas                 |
| Hypervisor    | `pve`                                 | proxmox                                       |
| Network       | `snmp-pfsense`                        | pfSense                                       |
| Synthetic     | `blackbox-{dns,http,icmp,ssl,tcp}`    | 31 endpoints                                  |
| Self / Thanos | `prometheus`, `thanos`                | prom-1/2, query, sidecar-1, store-gw          |
| Apps          | `vault`, `keycloak`, `minio`, others  | 14 instances                                  |
| Ops           | `watchtower`                          | 2 (1 DOWN — see Phase B)                      |

`Apps` row covers `vault`, `keycloak`, `minio`, `cloudflared`, `home-assistant`,
`pihole`, `registry`.

## 🟢 Phase A — landed in this PR

| #   | Job                 | Target additions                                     |
| --- | ------------------- | ---------------------------------------------------- |
| A.1 | `alertmanager`      | alertmanager-1, alertmanager-2                       |
| A.2 | `thanos` (extended) | thanos-sidecar-2 (192.168.4.239:10902, replica B)    |

A.1 IPs: 192.168.59.27:9093, 192.168.4.238:9093. Both endpoints expose
`alertmanager_*` metrics on `/metrics` with no auth. AMs are alert
receivers in the existing `alerting:` block but were never scraped — no
visibility into notification failures, gossip cluster health, or
active-silence count.

A.2: Sidecar-2 was already known to thanos-query as a store endpoint;
its `/metrics` was missing from the `thanos` self-scrape job.

Both endpoints verified responsive on 2026-05-07.

## 🟡 Phase B — diagnosed in this audit, deferred

### B.1 — `watchtower-dm` DOWN (root cause: macvlan IP collision)

_Symptom:_ scrape returns `307 → /containers/` with HTML content-type.

_Root cause:_ ds-1 has IP `192.168.59.33` bound to its own
`server-net-shim@ens19` (MAC `02:00:00:00:00:21`). When Prometheus on
ds-1's `docker-servers-net` resolves `192.168.59.33`, it gets the local
shim — which forwards to ds-1's host networking stack, where the
_Portainer Agent_ is listening on `:8080`. Portainer Agent's
`/containers/` endpoint is what's actually answering the scrape, not
the watchtower-dm container on dockermaster.

```text
# from prometheus-1 container on ds-1:
192.168.59.33 dev eth0 lladdr 02:00:00:00:00:21    # ds-1's own shim!
# vs. dockermaster (where watchtower lives):
192.168.59.33 dev docker-servers-net lladdr 32:31:bb:2a:92:66
```

_Fix paths_ (host-level, requires user discussion per memory
`feedback_destructive_host_changes.md`):

1. Reassign ds-1's `server-net-shim` to a free IP (e.g. `192.168.59.7`).
   Then Prometheus on ds-1 will resolve `192.168.59.33` to the actual
   watchtower-dm MAC via macvlan L2.
2. Or move watchtower-dm to a different macvlan IP and update the scrape
   config + any cross-references.

_Recommended:_ option 1 — the shim was assigned an in-use IP and
should be moved. Option 2 leaves the conflict for the next deploy.

### B.2 — Rundeck `/api/40/metrics/metrics` blocked on auth model

Token at `/etc/prometheus/tokens/rundeck_api` exists and is valid, but
the endpoint returns `404 Not Found` on the standard Rundeck token
header. Per memory `reference_rundeck_oss_auth.md`:

> Rundeck OSS metrics endpoint moved to _session-only_
> `/metrics/metrics`; bearer token won't scrape.

_Fix paths:_

1. Switch to session-cookie auth (sidecar that logs in, harvests
   `JSESSIONID`, exposes a metrics-cookie file). Heaviest plumbing but
   matches OSS reality.
2. Drop Rundeck from Prometheus coverage — rely on `blackbox-http`
   liveness only.
3. Migrate to Rundeck Enterprise (paywall — out of scope per project
   conventions: "no frameworks under a paywall").

_Recommended:_ option 1, but only if we adopt the Vault-agent sidecar
pattern (already noted as deferred). Until then, option 2 is the
honest choice.

## 🟠 Phase C — design-named exporters not yet deployed

Tracked for separate PRs.

| #   | Item                         | Inventory hit                            |
| --- | ---------------------------- | ---------------------------------------- |
| C.1 | `unpoller` (UniFi)           | VM 122 — UniFi Controller                |
| C.2 | `omada-exporter`             | VM 100 — Omada Controller                |
| C.3 | `thanos-compactor` (ds-2)    | Required for retention plan to execute   |
| C.4 | `thanos-ruler` (ds-2)        | Long-window alerts (capacity, SLO burn)  |
| C.5 | `ilo_exporter` (HPE iLO)     | proxmox = HP ProLiant Gen8               |
| C.6 | `nginx-prometheus-exporter`  | Nginx-rproxy on dockermaster + ds-2      |
| C.7 | `twingate-exporter`          | sepia-hornet (ds-1), golden-mussel (ds-2)|

C.5 motivation: would have caught the 2026-04-26 amsd runaway via
temperature/load metrics from BMC.

## 🔵 Phase D — not in design but justified by inventory

| #   | Item                          | Targets                                       |
| --- | ----------------------------- | --------------------------------------------- |
| D.1 | `postgres_exporter` × 3       | keycloak-db-0/1, postgres-rundeck             |
| D.2 | `node_exporter` proxmox host  | 192.168.7.11:9100 (host-level CPU/IRQ/load)   |

## ⚫ Phase E — likely drop from design

| #   | Item                       | Note                                          |
| --- | -------------------------- | --------------------------------------------- |
| E.1 | FreeSWITCH ESL exporter    | Already covered by `blackbox-tcp` on :5060    |
| E.2 | Postfix exporter           | Not currently routing real alerts             |
| E.3 | Managed-switch SNMP        | No managed switch in inventory                |

---

_Audit context: triggered after Thanos shipping investigation revealed
the bucket has been empty for 13 days due to a sidecar permission issue
(separate fix). Coverage check confirmed 62/63 targets UP at audit time._
