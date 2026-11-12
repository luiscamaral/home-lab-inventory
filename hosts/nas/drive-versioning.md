# nas (Synology) Drive versioning — desired state + apply (manual, DSM UI)

Synology Drive keeps old file versions under `/volume2/@synologydrive/@sync`. On 2026-11-03 that folder held at
least 2.6 TiB that no share accounts for (btrfs data used 21.93 TiB, minus the referenced size of every other
subvolume). There is no IaC path for Drive settings, so this file is the record.

## Current state (read 2026-11-04)

Only 2 of 27 folders have Drive enabled:

| Folder | Policy | Max versions | Age limit |
|---|---|---|---|
| `homes/mydrive_home` (each user's My Drive) | Intelliversioning | 8 | none |
| `sharedCloudStation` | Intelliversioning | 12 | none |

## Desired state

| Folder | Policy | Max versions | Age limit |
|---|---|---|---|
| `homes/mydrive_home` | Intelliversioning | 2 | 120 days |
| `sharedCloudStation` | Intelliversioning | 2 | 120 days |

Lowering the count deletes the extra versions as soon as it is applied. That cannot be undone, and homes have no
Hyper Backup, so these versions may be the only restore points.

## Apply (manual — DSM UI)

Synology Drive Admin Console → **Team Folder** → select both folders → **Versioning Settings**:

- Maximum versions: `2`
- Rotation policy: Intelliversioning
- Tick **Rotate versions regularly**, then pick `120 days` (choices: 7, 30, 60, 120). The age limit is a separate
  checkbox that works with either policy. Unticked, it stores `rotate_days=0`.

Status 2026-11-04 00:32: max versions set to 2 on both folders (admin log ids 12846956 and 12846960). The age limit
was still off (`rotate_days=0`).

## Verify (no root needed)

```bash
ssh nas 'sqlite3 -readonly /volume2/@synologydrive/@sync/user-db.sqlite \
  "select view_id,rotate_cnt,rotate_policy,rotate_days from view_setting_table;"'
ssh nas 'btrfs filesystem df /volume2 | head -1'   # baseline: Data used=21.93TiB
```

## CLI attempt that does not work

`synowebapi --exec api=SYNO.SynologyDrive.Share method=set` (version 1 and 2, run as root on 2026-11-04) returned
`success: true` but left `view_setting_table` unchanged and wrote no admin log entry. Use the UI. Reading works:
`synowebapi --exec api=SYNO.SynologyDrive.Share method=list version=2`.
