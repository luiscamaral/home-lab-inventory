# NAS Cron Jobs

Scheduled tasks running on the Synology NAS via `/etc/crontab`.

## Custom Cron Entries

### liviaamaral.com Backup

- **Schedule**: Daily at 02:00 (local time)
- **User**: root
- **Script**: `/volume1/lvamaral/liviaamaral.com.backup/copy-from-dickenson.sh`
- **Log**: `/volume1/lvamaral/liviaamaral.com.backup/copy-from-dickenson.out`
- **Owner**: `lvamaral` user home directory (not accessible via `lamaral` SSH user)

```cron
0   2   *   *   *   root    /volume1/lvamaral/liviaamaral.com.backup/copy-from-dickenson.sh >> /volume1/lvamaral/liviaamaral.com.backup/copy-from-dickenson.out 2>&1
```

> The script content is owned by root under `/volume1/lvamaral/` and cannot
> be read by the `lamaral` SSH user. To version-control it, copy with root
> access: `sudo cat /volume1/lvamaral/liviaamaral.com.backup/copy-from-dickenson.sh`

## Synology Scheduled Tasks

The remaining crontab entries are Synology system tasks managed via DSM Task Scheduler UI:

| ID | Purpose (inferred from schedule) |
| --- | --- |
| 1 | Daily at 03:00 |
| 2 | Annual (May 10) |
| 3 | Daily at midnight |
| 4 | Daily at midnight |
| 5 | Weekly (Tuesday 01:36) |
| 6 | Daily at 03:17 |
| 8 | 3x/week (Sun, Wed, Fri 22:30) |
| 9 | Hourly |
| 10 | Every 30 min |
| 11 | Quarterly (Feb, May, Aug, Nov) |
| 12 | Daily at 03:00 |
| 13 | Weekly (Sunday 05:00) |
| 14 | Weekly (Saturday midnight) |

These are managed via DSM UI (Services > Task Scheduler) and stored in
`/usr/syno/etc/synocron/`. Not currently IaC-managed.

## Security Note

A GitHub backup script exists at `~/scripts/github_backup.py` on the NAS with
a hardcoded GitHub API token (`ghp_...`). This token was created in 2023 and is
likely expired/revoked, but should be rotated to a Vault-managed token if the
script is still in use.
