# Proxmox P1 item 1: VM 120 and 123 mapping warnings

## Result

The warning source is confirmed. Both thin devices retain mappings beyond their current 120 GiB exposed size. [E1]

Their highest mapped sector reaches the old 196 GiB boundary. The kernel can retain these mappings after a thin target becomes smaller. [E1, E6]

This explains the LVM warnings. It does not establish thin-pool corruption or a current guest filesystem that exceeds its disk.

This task diagnosed the warnings. It made no infrastructure changes.

## Scope and method

Fresh checks ran on 2026-11-21 at about 06:31–06:33 UTC. Each evidence file records its collection time.

Checked sources:

- Proxmox LVM reports, device-mapper tables/status, disk sizes, partition tables, VM configuration, and snapshot lists.
- Read-only commands inside VM 120 and VM 123 through the QEMU guest agent.
- Retained LVM text archives, prior repo records, and official kernel documentation.
- Current thin-pool status, RAID cache status, backup archive presence, and selected kernel logs.

No guest shutdown, reboot, snapshot, TRIM, discard, resize, filesystem repair, or thin-metadata change took place.

Repo checks normalized trailing spaces and final newlines in saved command output. They did not change the reported values.

No active metadata dump or offline filesystem check took place. The investigation did not validate application data or restore a backup.

## Current sizes agree across the disk layers

Both guests were running at collection. [E1]

| Measurement | VM 120, dockermaster | VM 123, dockerserver-1 |
|---|---:|---:|
| Proxmox disk config | 120 GiB | 120 GiB |
| Host logical-volume size | 128849018880 bytes | 128849018880 bytes |
| Device-mapper target length | 251658240 sectors | 251658240 sectors |
| Guest disk size | 128849018880 bytes | 128849018880 bytes |
| Main partition size | 128845873152 bytes | 128845873152 bytes |
| ext4 block count × 4096 bytes | 128845873152 bytes | 123480309760 bytes |
| Root filesystem use from `df` | 38% | 69% |

Sources: [E1, E2]. Device-mapper and partition sectors use 512 bytes here.

Each filesystem fits its partition. Each partition fits the current guest and host disk size.

Both ext4 superblocks report `clean`. That marker is not a substitute for an offline consistency check. [E2]

The selected seven-day host and guest kernel-log searches found no matching I/O or ext4 error messages. [E1, E2]

A separate control query returned host kernel entries. Empty error searches do not prove that no storage fault exists. [E4]

## Why LVM warns

Device-mapper reports these thin-target values: [E1]

| Measurement | VM 120 | VM 123 |
|---|---:|---:|
| Current target length, sectors | 251658240 | 251658240 |
| Mapped sectors | 406610944 | 411041792 |
| Highest mapped sector, inclusive | 411041791 | 411041791 |
| Highest mapped endpoint | 196 GiB | 196 GiB |
| Total mapped bytes | 208184803328 | 210453397504 |
| Current target size | 120 GiB | 120 GiB |

The highest mapped endpoint is `(411041791 + 1) × 512`, or 196 GiB.

LVM compares the mapped allocation with the smaller declared volume size. The mapped allocation exceeds that size for both volumes.

The kernel stores thin mappings separately from the current device length. Loading a shorter target does not itself remove mappings beyond its end. [E6]

Those mappings are inaccessible through the current 120 GiB target. Their presence explains these warnings without requiring a corruption hypothesis.

Per-device mapped totals do not establish how much unique pool space a cleanup can reclaim. Shared references need separate accounting.

Neither guest has a registered Proxmox snapshot. Their LVM rows show no snapshot origin. This is not a case for blind snapshot deletion. [E1]

## Historical evidence and limits

The server inventory records a VM 120 reduction from 196 to 120 GiB on 2026-04-12. [E5]

The architecture document records file damage from that shrink and package repair work on 2026-04-17. These are historical claims, not fresh file checks. [E5]

The present out-of-range mappings match that former size. This supports a retained-mappings explanation for VM 120.

The retained LVM text files cover 43 records, with the earliest dated October 22. They already show both volumes at 120 GiB. [E3]

They do not preserve the April resize transition. The exact command, order, and date that reduced VM 123 remain unconfirmed.

The current filesystem boundary checks do not prove that every file survived earlier operations.

## Pool state and separate safety blocker

At collection, the SSD thin pool used 42.94% of data and 14.62% of metadata. Its volume group had no free extents. [E1]

Kernel pool status reported read/write mode without a `Fail` or `needs_check` marker. That status is not a full metadata integrity test. [E1]

The configured automatic-extension threshold defaults to 100, which disables automatic extension. No free SSD volume-group extents exist for growth. [E1, E4]

The P420i still reports a failed cache capacitor. No-battery write cache and drive write cache remain enabled. [E4]

That cache-protection failure remains a separate safety blocker for planned write-heavy maintenance.

November 19 backup archives exist for both VMs. Their presence does not prove successful recovery. [E4]

## Next step options

This diagnosis does not authorize cleanup or repair.

| Option | Benefit | Limit or risk |
|---|---|---|
| Leave current sizes unchanged and monitor | Avoids new disk writes and downtime now | Retains warnings and inaccessible mappings |
| Restore or copy into fresh 120 GiB volumes | Rebuilds mappings without carrying the inaccessible tail | Needs verified recovery, space, downtime, and a cutover plan |
| Design a targeted mapping cleanup | May reclaim obsolete allocations without rebuilding guests | Needs a separate safety review and controlled write operations |

Do not extend the disks back to 196 GiB only to hide the warnings. Do not run blind `blkdiscard`, `lvreduce`, or metadata repair.

Guest filesystem TRIM alone cannot address mappings beyond the exposed disk end. The guest cannot reach those addresses. [E1, E6]

Before a write-based follow-up:

1. Restore working RAID cache protection, or approve a specific interim safety plan.
2. Test recovery of both guests and preserve host configuration plus relevant metadata backups.
3. Select a cleanup or rebuild design with explicit downtime, space, and rollback requirements.
4. Add the required declarative source and apply tool. Merge its PR before live changes.
5. Obtain explicit approval for the disk operations and guest interruption.

NFS remains the fixed service-data backend. These options concern the affected VM boot volumes, not relocation of service data off NFS.

## Evidence

| Ref | Record |
|---|---|
| E1 | [Live mappings, pool status, disk tables, and snapshots](evidence/2026-11-21-proxmox-lvm/01-live-mapping.txt) |
| E2 | [Guest disk, partition, and filesystem sizes](evidence/2026-11-21-proxmox-lvm/02-guest-sizes.txt) |
| E3 | [Retained LVM history](evidence/2026-11-21-proxmox-lvm/03-lvm-history.txt) |
| E4 | [RAID cache, growth defaults, recovery candidates, and log control](evidence/2026-11-21-proxmox-lvm/04-safety-and-recovery.txt) |
| E5 | [Historical repo records](evidence/2026-11-21-proxmox-lvm/05-repo-history.txt) |
| E6 | [Official kernel thin-target semantics](evidence/2026-11-21-proxmox-lvm/06-kernel-reference.txt) |
