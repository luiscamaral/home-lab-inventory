# nas (Synology) Drive versioning — desired state (applied) + apply (manual, DSM UI)

Synology Drive keeps old file versions under `/volume2/@synologydrive/@sync`. On 2026-11-03 that folder held at
least 2.6 TiB that no share accounts for (btrfs data used 21.93 TiB, minus the referenced size of every other
subvolume). There is no IaC path for Drive settings, so this file is the record.

## Previous state (read 2026-11-04, before the change)

Only 2 of 27 folders have Drive enabled:

| Folder | Policy | Max versions | Age limit |
|---|---|---|---|
| `homes/mydrive_home` (each user's My Drive) | Intelliversioning | 8 | none |
| `sharedCloudStation` | Intelliversioning | 12 | none |

## Desired state (= live, applied by hand in DSM; verified 2026-11-12)

| Folder | `view_id` | Policy | Max versions | Age limit |
|---|---|---|---|---|
| `homes/mydrive_home` | 0 | Intelliversioning | 2 | 120 days |
| `sharedCloudStation` | 3 | Intelliversioning | 2 | 30 days |

`sharedCloudStation` was set to 30 days (not the 120 first planned); this file records what is live.
Effect: btrfs data used on `/volume2` went from 21.93 TiB (2026-11-03) to 18.91 TiB (2026-11-12), about 3 TiB freed.

Lowering the count deletes the extra versions as soon as it is applied. That cannot be undone, and homes have no
Hyper Backup, so these versions may be the only restore points.

## Apply (manual — DSM UI)

Synology Drive Admin Console → **Team Folder** → select both folders → **Versioning Settings**:

- Maximum versions: `2`
- Rotation policy: Intelliversioning
- Tick **Rotate versions regularly**, then pick the age limit from the table above (choices: 7, 30, 60, 120). The
  age limit is a separate checkbox that works with either policy. Unticked, it stores `rotate_days=0`.

Status 2026-11-04 00:32: max versions set to 2 on both folders (admin log ids 12846956 and 12846960). The age limit
was still off (`rotate_days=0`).

Status 2026-11-12: age limits applied by hand in DSM (homes 120 days, `sharedCloudStation` 30 days); verified with
the query below.

## Verify (no root needed)

```bash
ssh nas 'sqlite3 -readonly /volume2/@synologydrive/@sync/user-db.sqlite \
  "select view_id,rotate_cnt,rotate_policy,rotate_days from view_setting_table;"'
# expected: 0|2|smart|120   and   3|2|smart|30
# view_id → folder:
ssh nas 'sqlite3 -readonly /volume2/@synologydrive/@sync/user-db.sqlite \
  "select view_id,name,watch_path from user_table where user_type=1;"'   # 3 | @sharedCloudStation
ssh nas 'btrfs filesystem df /volume2 | head -1'   # 21.93TiB before; 18.91TiB on 2026-11-12
```

## CLI attempt that does not work

`synowebapi --exec api=SYNO.SynologyDrive.Share method=set` (version 1 and 2, run as root on 2026-11-04) returned
`success: true` but left `view_setting_table` unchanged and wrote no admin log entry. Use the UI. Reading works:
`synowebapi --exec api=SYNO.SynologyDrive.Share method=list version=2`.
