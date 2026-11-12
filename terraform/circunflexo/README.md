# circunflexo.com — Terraform root (`terraform/circunflexo`)

DNS for **circunflexo.com** — an independent domain, separate from
`lcamaral.com`. Authoritative DNS is DreamHost (`ns1/ns2/ns3.dreamhost.com`);
mail is Google Workspace.

This root uses **only the DreamHost provider**. It must never depend on
Cloudflare: `terraform/cloudflare/` owns `lcamaral.com`'s Cloudflare zone and
the `*.cf.lcamaral.com` delegation, nothing else.

## Managed records

| Record | Type | Purpose |
|---|---|---|
| `circunflexo.com` | TXT | SPF — `v=spf1 include:_spf.google.com ~all` |
| `cfxo._domainkey.circunflexo.com` | TXT | DKIM (Google, selector `cfxo`, 2048-bit) |

## Not managed here (intentionally)

- **MX** (`ASPMX.L.GOOGLE.COM` + `ALT1-4`) — DreamHost-managed, not editable via
  API (`editable=0`). Change them in the DreamHost panel.
- A / CNAME records (`www`, `ftp`, `ssh`, `mail`, `sites`, `drive`, `calendar`) —
  pre-existing, unmanaged.

## Ownership rule

The DreamHost API key is account-wide (it can edit every DreamHost zone). Each
record must be declared in **exactly one** Terraform root: circunflexo.com
records live here; `*.cf.lcamaral.com` lives in `terraform/cloudflare/`.

## Usage

```bash
export VAULT_ADDR=http://vault.d.lcamaral.com   # or http://192.168.59.25:8200
export VAULT_TOKEN=$(security find-generic-password -w -s vault-root-token)
export TF_VAR_dreamhost_api_key=$(vault kv get -field=api_token secret/homelab/dreamhost)

terraform init
terraform plan
terraform apply
```

## Provider notes

- `adamantal/dreamhost` v0.3.x: records are immutable — any change is a
  destroy + create.
- Import id format is `TYPE|RECORD|VALUE`, e.g.
  `terraform import dreamhost_dns_record.spf 'TXT|circunflexo.com|v=spf1 include:_spf.google.com ~all'`.
- DreamHost publishes changes to its nameservers on a delay (observed ~10 min).

## Google Workspace

After DKIM is published, Google Admin → Apps → Google Workspace → Gmail →
Authenticate email → `circunflexo.com` → **Start authentication**.
