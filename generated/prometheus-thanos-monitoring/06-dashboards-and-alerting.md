# 06 — Grafana Connection and Alerting

> **Scope note (this phase):** this document covers Grafana **deployment
> and wiring only** — no dashboards are authored or imported. A
> dashboards project is deferred to a later, dedicated phase and will
> get its own plan document. Everything in this file that relates to
> dashboards is either stubbed as "deferred" or retained as background
> for whoever tackles that phase later.

## Grafana

### Deployment

- Portainer stack `grafana` on **ds-1**.
- Storage: Grafana's built-in SQLite for initial install; migrate to
  Postgres (new stack `grafana-db` or reuse `keycloak-db` with a
  separate database) only if we want multi-user history.
- Version pin: `grafana/grafana:12.0.0` (LTS branch at planning date).

### External access

- nginx vhost `grafana.cf.lcamaral.com.conf` in the nginx-rproxy
  volume.
- Cloudflare tunnel route via the existing
  `terraform/cloudflare/` config; use the `modules/cf-service` module
  with `service_name = "grafana"`.

### SSO

- Keycloak realm `homelab`; new OIDC client `grafana`.
- Grafana `[auth.generic_oauth]`:
  ```ini
  enabled = true
  name = Keycloak
  auth_url = https://auth.cf.lcamaral.com/realms/homelab/protocol/openid-connect/auth
  token_url = https://auth.cf.lcamaral.com/realms/homelab/protocol/openid-connect/token
  api_url = https://auth.cf.lcamaral.com/realms/homelab/protocol/openid-connect/userinfo
  scopes = openid email profile offline_access roles
  role_attribute_path = contains(roles[*], 'grafana-admin') && 'Admin' || 'Viewer'
  ```
- Client secret in Vault at `secret/homelab/grafana/oidc`.

### Datasources (provisioned)

```yaml
apiVersion: 1
datasources:
  - name: Thanos
    type: prometheus
    url: http://thanos-query:10902
    isDefault: true
    jsonData:
      httpMethod: POST
      timeInterval: 15s
  - name: Prometheus-1 (direct)
    type: prometheus
    url: http://prometheus-1:9090
    isDefault: false
    editable: false
```

Having both means you can compare "what the replica saw" vs "what
Thanos returned" when debugging dedupe.

### Dashboards — **DEFERRED to a later phase**

No dashboards are authored, imported, or provisioned in this phase.
Grafana ships with its default empty home. Users build ad-hoc panels
via Explore as needed until the dashboards project runs.

Guidance for the future dashboards phase (**non-binding**, kept here as
a seed list):

- A single "Home Overview" fleet-wide panel should come first.
- Per-node and per-container detail dashboards next.
- Service-health grid (Vault, Keycloak, MinIO) — straightforward.
- pfSense and DNS dashboards require decisions about which metrics are
  actually interesting day-to-day — best tackled after real alerts
  have been tuned.
- Prefer **import** (grafana.com community dashboards) over authoring;
  customize panel queries to use `cluster="homelab"` label.

When that phase begins, this section will be split into its own
document.

## Alertmanager

### Deployment

- HA gossip pair: `alertmanager-1` on ds-1, `alertmanager-2` on ds-2.
- Same config file on both; both start with
  `--cluster.peer=<other>:9094`.
- State (silences, notifications) is replicated via gossip.
- Both receive alerts from prometheus-1, prometheus-2, AND thanos-ruler
  (on ds-2). The AM cluster dedupes across all three senders.

### Routing tree (Q5=Email, locked)

```yaml
global:
  smtp_smarthost: postfix-relay.d.lcamaral.com:25
  smtp_from: 'alertmanager@lcamaral.com'
  smtp_require_tls: false   # internal relay; postfix handles external TLS

route:
  receiver: default
  group_by: [alertname, cluster]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers: [ 'severity="critical"' ]
      receiver: email-critical
      group_wait: 10s          # fire fast on critical
      repeat_interval: 1h
      continue: false
    - matchers: [ 'severity="warning"' ]
      receiver: email-warning
      group_interval: 15m       # bundle warnings
      repeat_interval: 6h
    - matchers: [ 'severity="info"' ]
      receiver: log-only

receivers:
  - name: default
    email_configs:
      - to: 'luiscamaral+homelab@gmail.com'
        send_resolved: true
        headers:
          Subject: '[ALERT] {{ .CommonLabels.alertname }} on {{ .CommonLabels.instance }}'

  - name: email-critical
    email_configs:
      - to: 'luiscamaral+homelab@gmail.com'
        send_resolved: true
        headers:
          Subject: '[CRIT] {{ .CommonLabels.alertname }}'

  - name: email-warning
    email_configs:
      - to: 'luiscamaral+homelab@gmail.com'
        send_resolved: true
        headers:
          Subject: '[WARN] {{ .CommonLabels.alertname }}'

  - name: log-only
```

The `log-only` receiver deliberately has no email config — silence is
the point. Adding a second channel later (Telegram, Discord) means
appending a new `receiver:` block and matching route without touching
the rules.

**Pre-requisite:** `postfix-relay` must be configured to accept SMTP
from both `alertmanager-1` (docker-servers-net) and `alertmanager-2`
(NAS home-net). Add both source subnets to the postfix `mynetworks`
list.

### Where each rule lives — Prometheus-native vs Thanos Ruler

| Rule family | Evaluator | Why |
|---|---|---|
| Node / host health | Prometheus-native (both replicas) | Short-window, critical — must fire even if ds-2 is down |
| Docker container health | Prometheus-native | Same reason |
| Network / gateway flap | Prometheus-native | Critical, sub-minute |
| Service up-checks | Prometheus-native | Critical, sub-minute |
| Thanos self-health | Prometheus-native (scrape the Thanos components themselves) | Meta-health; must not depend on Thanos |
| TLS cert expiry (<14d, <3d) | **Thanos Ruler** | 30-day+ lookbacks |
| MinIO bucket growth trend | **Thanos Ruler** | Month-over-month windows |
| SLO burn-rate alerts | **Thanos Ruler** | Multi-window, requires Thanos-level dedupe |

Short-window alerts that must not depend on a single host stay on
Prometheus-native. Trend alerts that need long history live on Ruler
(single-instance; acceptable because they're not emergency alerts).

### Rule families (Prometheus-native, in `prometheus/rules/*.yml`)

1. **Node health** (`node.rules.yml`):
   - Disk >85% full
   - Disk will fill within 24h (linear regression)
   - Load > 2× num_cpu for 15m
   - Memory available < 200 MB for 10m
2. **Docker** (`container.rules.yml`):
   - Container restart > 3 in 15m
   - Container not up (`count(container_last_seen) < expected`)
3. **Network** (`network.rules.yml`):
   - pfSense gateway loss > 10% for 5m (sev: warn at 10%, critical at 50%)
   - WAN down via blackbox probe
   - DNS resolution failing (any pihole returns SERVFAIL for known name)
4. **Services** (`services.rules.yml`):
   - Vault sealed
   - Keycloak up check fails
   - MinIO cluster health degraded
   - nginx upstream down
5. **Certificates** (`cert.rules.yml`):
   - SSL expiry < 14d (warn) or < 3d (critical)
6. **Thanos self** (`thanos.rules.yml`):
   - `thanos_sidecar_prometheus_up{} == 0`
   - Compactor hasn't run in 6h
   - Store gateway error rate > 5%

### Alert annotations convention

Every rule MUST set:

```yaml
annotations:
  summary: "Short title — <{{ $labels.instance }}>"
  description: "Expanded one-line description of what's broken"
  runbook_url: "https://<repo>/runbooks/<slug>.md"
```

Runbook files go alongside the rule files, in the repo under
`monitoring/runbooks/` (to be created in phase 5).

### Silence workflow

- For planned maintenance: set a silence via Alertmanager API (or
  Grafana UI if we wire it up).
- For known-broken (e.g., UnifiAP-1): add a silence with an explicit
  `ends_at` far in the future, comment with a Jira-like tag.

## Fitness tests

- Inject failure: `docker stop keycloak`. Expect alert routed within 2
  minutes; silence it; restart; alert resolves within 2 minutes.
- Induce cert-expiry near-miss by editing a test rule's threshold to
  3650d temporarily; verify every public endpoint gets flagged by the
  **Ruler** (not Prometheus-native), then revert.
- Kill `prometheus-1` for 5 minutes. Grafana Explore queries stay
  green; Prometheus-native alerts still fire via `prometheus-2`; no
  duplicate alerts (AM cluster dedupes).
- Kill ds-2 (power off). Prometheus-native alerts keep firing from
  prometheus-1 via alertmanager-1. Ruler rules stop evaluating —
  **document this in the runbook; it is the accepted trade-off of the
  single-Ruler decision.**
