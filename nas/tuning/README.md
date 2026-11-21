# NAS kernel tuning (IaC)

Declarative kernel tunables for the Synology NAS (DS1522+, DSM 7.4.1, 8 GB RAM).

| | |
| --- | --- |
| Source of truth | [`sysctl.yml`](sysctl.yml) |
| Apply | `scripts/sync-nas-tuning.py --apply` |
| Drift check | `scripts/sync-nas-tuning.py --check` (exit 1 on drift) |
| Rollback | `scripts/sync-nas-tuning.py --rollback` |
| On the NAS | `/usr/local/etc/rc.d/zz-iac-nas-tuning.sh` (rendered — never edit there) |
| Logs | `journalctl -t iac-nas-tuning` |
| Tests | `uv run --no-project --with pytest --with pyyaml python -m pytest tests/test_sync_nas_tuning.py` |

## What is managed

| Key | Value | DSM default |
| --- | --- | --- |
| `vm.dirty_background_bytes` | 64 MiB | `dirty_background_ratio=10` (~465 MiB) |
| `vm.dirty_bytes` | 256 MiB | `dirty_ratio=20` (~930 MiB) |

**Why:** `/volume2` sits on a flashcache-syno NVMe cache in `WRITE_BACK` mode with
`skip sequential thresh(1024K)` — sequential writes >= 1 MiB bypass the SSDs and land on the
RAID5 HDDs, which also serve uncached media reads over SMB. With DSM defaults up to ~930 MiB of
dirty pages accumulate and flush in large bursts that stall those reads (observed 624 MiB dirty
with 21% iowait while an SMB client was streaming 4K remuxes, 2026-11-03).

### Measured effect (2026-11-03, 4K remux cold reads, 3 GB sequential write, n=1 each)

| | DSM defaults | IaC values |
| --- | --- | --- |
| Peak `Dirty` during write | 706 MiB | **167 MiB** |
| Cold read during write | 88.2 MB/s | **107 MB/s** |
| Sequential write | 208 MB/s | 204 MB/s |

## Deliberately NOT managed

- **`vm.swappiness`** — swap is zram (lzo, in RAM); disk swap (`md1`) is unused. Lowering
  swappiness would evict the page cache that serves media instead of compressing idle anon pages.
- **Read-ahead** — btrfs reads through its own BDI (`/sys/class/bdi/btrfs-1/read_ahead_kb` = 4096)
  and `cachedev_0` is already 2048 KB; md-level read-ahead has no effect on file reads.
- **SMB settings** (`smb.conf`) — DSM regenerates them; change via DSM UI → File Services → SMB.
- **`/etc/sysctl.conf`** — DSM regenerates it. Do not edit.

## How persistence works

DSM's `pkg-rclocal.service` (`WantedBy=syno-bootup-done.target`, `After=multi-user.target`) runs
`/usr/syno/lib/systemd/scripts/pkg-rclocal.sh`, which executes every
`/usr/local/etc/rc.d/*.sh start`. That runs after `volume.sh`, the only DSM script that writes
`vm.dirty_*` (and only when Synology cache-protection replay is enabled —
`/sys/fs/syno-cache-protection/pool_enable` does not exist on this box).

Boot path verified without a reboot: reset values to DSM defaults, ran `pkg-rclocal.sh`, values
re-applied.

## Access

Root is required. The sync script reads the sudo password from the macOS Keychain
(`nas-sudo-password`, fallback Vault `secret/homelab/nas-sudo-password`) only for
`--apply`/`--rollback` and passes it to `sudo -S` on stdin — never on a command line.

## Adding a tunable

Add the key to `sysctl:` (and its DSM default to `restore:`), run the tests, dry-run, then
`--apply`. Keys must match `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$` and values must be non-negative
integers — the loader rejects anything else before it can reach a root shell.
