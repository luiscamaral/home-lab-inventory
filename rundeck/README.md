# Rundeck Job Definitions

Source-of-truth for scheduled maintenance jobs running in Rundeck.
Every YAML here is a Rundeck job definition imported via the API
(see [Importing](#importing) below). Edit-then-reimport is the IaC
flow; don't hand-edit jobs in the Rundeck UI.

## Layout

```text
rundeck/
└── jobs/
    ├── calibre-replication.yaml    # nightly calibre -> calibre-web rsync
    ├── calibre-restart.yaml        # restart calibre & calibre-web containers
    ├── pihole-auth-check.yaml      # one-time follow-up (2026-05-12)
    ├── ps.yaml                     # process snapshot every 30 min
    ├── rundeck-token-check.yaml    # monthly token-expiry warning
    ├── sync-ssl-certificates.yaml  # daily SSL cert sync pfSense -> nginx
    ├── Ubuntu-auto-update.yaml     # Ubuntu apt dist-upgrade (Sun/Wed/Fri)
    └── vms-backup.yaml             # XenServer VM export backups
```

## Jobs

| File | Job Name | UUID | Schedule | Target Nodes |
| ------ | -------- | ------ | -------- | ------------ |
| `calibre-replication.yaml` | Calibre replication to Calibre-Web | `682e675a-4ec3-435d-80e5-288c8cd1a316` | Daily 22:10 (America/Denver) | Dockermaster.local |
| `calibre-restart.yaml` | Calibre Restart | `20007299-edab-4383-b416-12359ca5f294` | On-demand (called by replication job) | Dockermaster.local |
| `pihole-auth-check.yaml` | pihole-auth-check | `pihole-auth-check-2026-05-12` | One-time: 2026-05-12 15:00 UTC | Local |
| `ps.yaml` | PS | `12b5296b-846d-43aa-85b1-559d794b6326` | Every 30 min | All servers (excl. XenServer) |
| `rundeck-token-check.yaml` | rundeck-token-check | `rundeck-token-check-monthly` | 1st of month 15:00 UTC | Local |
| `sync-ssl-certificates.yaml` | Sync SSL Certificates | `cert-sync-pfsense-nginx` | Daily 00:00 UTC | rundeck-local |
| `Ubuntu-auto-update.yaml` | Ubuntu Auto-Update | `9e5ebe53-ce3a-41d6-a8a0-cf3d0a6c3fb8` | Sun/Wed/Fri 01:36 (America/Denver) | Ubuntu servers |
| `vms-backup.yaml` | VMs-Backup | `1be173e2-c945-4ab7-9bc7-24dbf79dec35` | On-demand (no schedule) | Xenserver.* |

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
- **Format**: All job files are exported directly from the Rundeck API
  (`/api/45/project/HomeNet/jobs/export?format=yaml`) and stored as
  single-job YAML documents (one job per file).
- **Groups**: `maintenance` for monitoring/check jobs, `Infrastructure`
  for infrastructure automation. Ungrouped jobs are general operations.
- **Schedule**: One-time jobs use `month`/`year`/`dayofmonth` fixed
  values; recurring jobs use `*` wildcards. Time zones are explicit
  where set (America/Denver), otherwise UTC.
- **Notification**: Some jobs (e.g. sync-ssl-certificates) have email
  notification on failure. Ubuntu Auto-Update uses Discord webhooks
  via Rundeck Key Storage (`keys/project/HomeNet/discord_webhook_key`).
- **Secrets**: Read at runtime, not embedded. The token-check job
  reads the rundeck DB password via `docker exec rundeck printenv`;
  any job needing Vault should pull a token from the Rundeck Key
  Storage and source it just before the API call.
- **Job References**: calibre-replication calls calibre-restart as a
  sub-job via `jobref` (UUID `20007299-edab-4383-b416-12359ca5f294`).

## Initial seed

The pihole-auth-check and rundeck-token-check jobs were created during
the Phase 3 monitoring wrap-up (2026-04-28). The remaining 6 jobs
(`calibre-replication`, `calibre-restart`, `ps`, `sync-ssl-certificates`,
`ubuntu-auto-update`, `vms-backup`) were exported from the live Rundeck
instance and added to the repository during the job audit.
