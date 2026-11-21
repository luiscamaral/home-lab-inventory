# vault-2 (ds-1) health investigation — 2026-05-27

## Symptom

`docker ps` reports `vault-2` as `Up 2 weeks (unhealthy)` on ds-1
(192.168.48.45). Container image `hashicorp/vault:1.21`,
`api_addr` `http://192.168.59.9:8200`.

## Confirmation

Healthcheck failing continuously. `FailingStreak: 136541` (≈15.8 days
at 10s interval, matches the 2026-05-12 container start). All 5 most
recent probe records show identical output:

```text
wget: server returned error: HTTP/1.1 429 Too Many Requests
```

Healthcheck definition:
`wget --no-verbose --tries=1 --spider http://127.0.0.1:8200/v1/sys/health || exit 1`
— unauthenticated, no query args, every 10s.

## Sealed/unsealed state

**Unsealed and active in the Raft cluster.** Last log line at startup
(2026-05-12T00:47:55Z):

```text
storage.raft: initial configuration: servers="[
  {Voter vault-1 192.168.59.25:8201}
  {Voter vault-2 192.168.59.9:8201}
  {Voter vault-3 192.168.59.15:8201}]"
storage.raft: entering follower state
core: vault is unsealed
core: entering standby mode
```

(`vault status` exec was blocked by sandbox; not retried — log
evidence is conclusive.)

No log output since startup 15 days ago — node is quietly following.

## Root cause

Vault's default `/v1/sys/health` semantics return HTTP 429 for an
**unsealed standby node** ([Vault docs][1]). The healthcheck baked
into the container treats any non-2xx as failure. The node is
healthy; the probe is wrong. Active node (likely vault on dm or
vault-3 on ds-2) returns 200; the two standbys both return 429.

Not sealed, not network-partitioned, not disk/raft-stuck. Just a
cosmetic Docker healthcheck mismatch with HA semantics.

[1]: https://developer.hashicorp.com/vault/api-docs/system/health

## Cluster impact

None. vault-2 is a Raft voter in follower/standby mode and has been
participating since 2026-05-12. Cluster has quorum (3/3 voters in the
config). Other services that talk to the active leader are unaffected.

## Recommended fix

Adjust the healthcheck to accept standby (429) and DR-standby (472) as
healthy. Two options:

1. **Compose override** (preferred, IaC):
   `wget --spider 'http://127.0.0.1:8200/v1/sys/health?standbyok=true&perfstandbyok=true'`
   The query flags make Vault return 200 for any unsealed node.

2. Or use `vault status -format=json` exit codes (0=unsealed&active,
   2=unsealed&standby — both acceptable).

Same fix applies to all 3 vault containers. Roll via Terraform/Portainer
stack update; no Vault restart required beyond container recreate.

## Severity

**Low (cosmetic).** Vault HA is functioning. Only impact is noisy
`unhealthy` status confusing monitoring/dashboards and potentially
masking a real failure later.

## How urgent

**Not urgent.** Schedule with the parallel vault-on-dm investigation
and fix all three at once via the compose/Terraform path. No data or
availability risk in leaving it as-is for days/weeks.
