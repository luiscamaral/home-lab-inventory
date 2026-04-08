---
name: cloudflare-api
description: Interact with Cloudflare API and manage tunnels, DNS, and account resources for the homelab
argument-hint: "<action or question>"
allowed-tools:
  - read
  - grep
  - glob
  - exec
permissions:
  allow:
    - Exec(curl *)
    - Exec(security find-generic-password *)
    - Exec(ssh dockermaster *)
    - Exec(python3 *)
    - Read(**)
triggers:
  - user
  - model
---

# Cloudflare API & CLI Skill

Perform the requested Cloudflare action:

$ARGUMENTS

---

## Authentication

The API token is stored in Vault. Retrieve it with:

```bash
export VAULT_ADDR="http://vault.d.lcamaral.com"
export VAULT_TOKEN=$(security find-generic-password -w -a lamaral -s vault-root-token)
TOKEN=$(vault kv get -field=api_token secret/homelab/cloudflare)
```

Legacy Keychain access (still works):

```bash
TOKEN=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
```

Use it in every API call as a Bearer token:

```bash
curl -s "https://api.cloudflare.com/client/v4/<endpoint>" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json"
```

**Token details:**

| Field | Value |
|-------|-------|
| Token ID | `b40dbcd0bd08566a212e2c5f9659b446` |
| Type | Account-scoped API Token (not a Global API Key) |
| Status | Active |

**Token permissions** (verified by probing):

| Scope | Access |
|-------|--------|
| Accounts list | Read |
| Tunnels | Read / Write / Config |
| Zone | Read / Edit |
| DNS | Read / Edit |
| Zone Settings | Read / Edit |
| Access Service Tokens | Read / Write |
| Account details | No access |
| User endpoint | No access (not a user-level key) |
| Token verify | Yes |

---

## Account

| Field | Value |
|-------|-------|
| Account ID | `13538d3dbd6b9cd04da9359142bb8d10` |
| Account name | Luis.c.amaral@gmail.com's Account |
| Type | Standard |
| Created | 2021-10-22 |

---

## Zone (lcamaral.com)

| Field | Value |
|-------|-------|
| Zone ID | `d91929b42a245625bebb527e5fd2e020` |
| Domain | `lcamaral.com` |
| Status | Active |
| Type | Partial (CNAME setup via DreamHost) |
| Plan | Free |
| DNSSEC | Disabled |
| Activated | 2021-11-26 |

**DNS Records:**

| Type | Name | Content | Proxied |
|------|------|---------|---------|
| CNAME | `bologna.lcamaral.com` | `<tunnel-id>.cfargotunnel.com` | Yes |
| CNAME | `lcamaral.com` | `resolve-to.www.lcamaral.com` | Yes |
| CNAME | `www.lcamaral.com` | `resolve-to.www.lcamaral.com` | Yes |

---

## Cloudflare Tunnel ("bologna")

| Field | Value |
|-------|-------|
| Tunnel name | `bologna` |
| Tunnel ID | `eb4461ec-689f-4f8a-98f1-321cb246bb65` |
| Tunnel type | `cfd_tunnel` |
| Status | Healthy |
| Config source | Cloudflare (remote-managed) |
| Origin IP | `136.36.139.5` |
| Cloudflared version | `2026.3.0` |
| Edge colos | lax07, slc01, lax10 |

**Ingress rules** (remote config):

| Hostname | Service |
|----------|---------|
| `bologna.lcamaral.com` | `https://nginx-rproxy:443` |
| Catch-all | `http_status:404` |

**Docker container on dockermaster:**

| Field | Value |
|-------|-------|
| Container | `cloudflare-tunnel-cloudflare-1` |
| Image | `cloudflare/cloudflared:latest` |
| Compose file | `/nfs/dockermaster/docker/cloudflare/docker-compose.yml` |
| Network | `rproxy` (external) |
| Restart policy | `on-failure:5` |
| Resource limits | 2 CPU / 1 GB RAM |
| Watchtower | Disabled (manual updates only) |
| Portainer autodeploy | Disabled |

---

## Common API Patterns

### Verify token

```bash
TOKEN=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### List accounts

```bash
TOKEN=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
curl -s "https://api.cloudflare.com/client/v4/accounts?page=1&per_page=20" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### List tunnels

```bash
TOKEN=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
ACCOUNT_ID="13538d3dbd6b9cd04da9359142bb8d10"
curl -s "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tunnels" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### Get tunnel config (ingress rules)

```bash
TOKEN=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
ACCOUNT_ID="13538d3dbd6b9cd04da9359142bb8d10"
TUNNEL_ID="eb4461ec-689f-4f8a-98f1-321cb246bb65"
curl -s "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### Update tunnel ingress (PUT)

```bash
TOKEN=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
ACCOUNT_ID="13538d3dbd6b9cd04da9359142bb8d10"
TUNNEL_ID="eb4461ec-689f-4f8a-98f1-321cb246bb65"
curl -s -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "config": {
      "ingress": [
        {"hostname": "bologna.lcamaral.com", "service": "https://nginx-rproxy:443"},
        {"service": "http_status:404"}
      ],
      "warp-routing": {"enabled": false}
    }
  }' | python3 -m json.tool
```

### Check tunnel connections

```bash
TOKEN=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
ACCOUNT_ID="13538d3dbd6b9cd04da9359142bb8d10"
TUNNEL_ID="eb4461ec-689f-4f8a-98f1-321cb246bb65"
curl -s "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tunnels/${TUNNEL_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
t = data['result']
print(f\"Tunnel: {t['name']} ({t['status']})\")
for c in t.get('connections', []):
    print(f\"  {c['colo_name']} - {c['opened_at']}\")
"
```

---

## Dockermaster Operations

### Check tunnel container health

```bash
ssh dockermaster "docker inspect cloudflare-tunnel-cloudflare-1 --format '{{.State.Health.Status}}'"
```

### View tunnel container logs

```bash
ssh dockermaster "docker logs --tail 50 cloudflare-tunnel-cloudflare-1"
```

### Restart tunnel container

```bash
ssh dockermaster "cd /nfs/dockermaster/docker/cloudflare && docker compose restart"
```

### Recreate tunnel container (pull latest)

```bash
ssh dockermaster "cd /nfs/dockermaster/docker/cloudflare && docker compose pull && docker compose up -d"
```

---

## Important Notes

- The tunnel token in the compose file is a **JWT containing the account ID, tunnel ID, and secret**. It is NOT the same as the API token in Keychain.
- The tunnel is **remote-managed** (`config_src: cloudflare`), meaning ingress rules are configured via the API, not a local `config.yml`.
- No CLI tools (`flarectl`, `wrangler`, `cloudflared`) are installed locally. All management is done via the API or SSH to dockermaster.
- Always use `python3 -m json.tool` to format JSON responses for readability.
- When modifying tunnel ingress, the **entire ingress array** must be sent (PUT replaces, does not patch). Always read current config first.
- The catch-all rule `{"service": "http_status:404"}` must always be the **last** ingress entry.
