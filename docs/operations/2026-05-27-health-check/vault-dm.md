# vault (dm) health investigation — 2026-05-27

## Symptom

`docker ps` reports `vault` on dockermaster as `Up 2 weeks (unhealthy)`.
`docker inspect` shows `FailingStreak: 136611` — healthcheck has been
failing continuously for weeks while the container itself runs fine.

## Confirmation

Healthcheck output (last 5 probes, all identical):

```text
Connecting to 127.0.0.1:8200 (127.0.0.1:8200)
wget: server returned error: HTTP/1.1 429 Too Many Requests
```

Vault itself is healthy:

- `vault status` → `Initialized: true, Sealed: false, HA Mode: standby,
  Active Node Address: http://192.168.59.15:8200` (vault-3 / ds-2 is leader)
- `vault operator raft list-peers`:

  ```text
  vault-1    192.168.59.25:8201    follower    true
  vault-2    192.168.59.9:8201     follower    true
  vault-3    192.168.59.15:8201    leader      true
  ```

  All 3 voters present, leader elected, raft committed/applied indexes match
  (`97952` / `97952`) — quorum intact.

## Root cause

**Healthcheck mis-design, not a Vault problem.** The container's healthcheck
calls `wget http://127.0.0.1:8200/v1/sys/health` with no query params. Per
Vault's documented behavior, `/sys/health` returns:

- `200` only on the **active** (leader) node
- `429` on unsealed **standby** nodes (this is by design — "I'm alive but
  performance-standby/standby")
- `503` if sealed

Since dm's `vault` container is a standby follower (leader is vault-3 on
ds-2), every probe gets a legitimate `429`, and `wget` exits non-zero, so
Docker marks it unhealthy. The same misclassification will affect whichever
two of the three nodes are not the current leader at any moment.

To pass healthcheck on followers, the probe needs
`?standbyok=true&perfstandbyok=true` (or `&standbycode=200`).

## Cluster impact

- **None.** Consensus intact (3/3 voters, leader = vault-3 @ 192.168.59.15).
- Reads/writes succeeding from Terraform's PoV — matches session evidence:
  earlier `terraform apply` against `secret/homelab/portainer`,
  `grafana/admin`, `minio`, `keycloak/clients` all succeeded.
- `vault.d.lcamaral.com` round-robins to 3 nodes via Pi-hole multi-A →
  `nginx-rproxy`. Followers proxy writes to the leader transparently, so DNS
  hitting any of the 3 IPs still works.

## Recommended fix

Update the Vault stack's healthcheck (Portainer stack source) to use a
standby-tolerant probe. Two viable forms:

```yaml
healthcheck:
  test: ["CMD", "wget", "--spider", "-q",
         "http://127.0.0.1:8200/v1/sys/health?standbyok=true&perfstandbyok=true"]
  interval: 10s
  timeout: 5s
  retries: 3
```

Or use the built-in `vault status` exit code:

```yaml
test: ["CMD-SHELL", "VAULT_ADDR=http://127.0.0.1:8200 vault status >/dev/null 2>&1 || exit 1"]
```

Apply to all 3 nodes (vault, vault-2, vault-3) — the same misconfiguration
will be intermittently lighting up whichever node is not the current leader.

## Severity

**Low / cosmetic.** No data-plane or control-plane impact. Risk is that a
real Vault outage gets ignored because everyone has learned to dismiss
"vault unhealthy" alerts. Worth fixing for signal quality, not urgency.

## How urgent

**Not urgent.** Batch this with the next Vault stack edit. No immediate
action required; cluster is fully operational.
