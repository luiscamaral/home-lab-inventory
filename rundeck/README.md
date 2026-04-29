# Rundeck Job Definitions

Source-of-truth for scheduled maintenance jobs running in Rundeck.
Every YAML here is a Rundeck job definition imported via the API
(see [Importing](#importing) below). Edit-then-reimport is the IaC
flow; don't hand-edit jobs in the Rundeck UI.

## Layout

```text
rundeck/
└── jobs/
    ├── pihole-auth-check.yaml      # one-time follow-up (2026-05-12)
    └── rundeck-token-check.yaml    # monthly token-expiry warning
```

## Importing

```bash
# Token comes from Vault. Use the laptop or any host with vault CLI.
TOKEN="$(vault kv get -field=api_token secret/homelab/rundeck)"
RD=https://rundeck.d.lcamaral.com

for f in jobs/*.yaml; do
  echo "--- importing $f ---"
  curl -sk -X POST -H "X-Rundeck-Auth-Token: $TOKEN" \
       -H "Content-Type: application/yaml" \
       --data-binary "@$f" \
       "$RD/api/45/project/HomeNet/jobs/import?dupeOption=update&format=yaml" \
       | python3 -m json.tool
done
```

`dupeOption=update` causes Rundeck to overwrite an existing job whose
UUID matches (the YAML pins each job's UUID). The project is `HomeNet`
(see <https://rundeck.d.lcamaral.com>).

## Conventions

- **UUID**: Pinned per job in the YAML (`uuid:` field) so re-imports
  update in place rather than creating duplicates.
- **Group**: `maintenance` for jobs in this dir. Other directories may
  emerge as the catalog grows (`backup/`, `ops/`, etc.).
- **Schedule**: One-time jobs use `month`/`year`/`dayofmonth` fixed
  values; recurring jobs use `*` wildcards. All times are UTC.
- **Notification**: Jobs fail on actionable conditions so the run
  surfaces red in the Rundeck UI. Email push is wired up later via
  `RUNDECK_MAIL_*` env vars on the rundeck stack — see
  `terraform/portainer/stacks/rundeck.yml.tftpl`.
- **Secrets**: Read at runtime, not embedded. The token-check job
  reads the rundeck DB password via `docker exec rundeck printenv`;
  any job needing Vault should pull a token from the Rundeck Key
  Storage and source it just before the API call.

## Initial seed

The two jobs in this dir were created during the Phase 3 monitoring
wrap-up (2026-04-28) as deferred follow-ups to the manual checklist.
Future maintenance jobs (Vault snapshot rotation, MinIO bucket
capacity warning, Keycloak DB reindex, etc.) belong here too.
