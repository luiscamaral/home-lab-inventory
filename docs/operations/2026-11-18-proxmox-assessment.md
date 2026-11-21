# Proxmox host assessment, 2026-11-18

## Summary

The host runs Proxmox VE 9.1.7 on Debian 13, not the VE 8.3.5 shown in older inventory records. [E1, E13]

Compute capacity has room for the current guests. Storage safety and backup reliability need work before a platform upgrade. [E1, E2, E5]

The RAID controller reports a failed cache capacitor while no-battery write cache remains enabled. Treat this as the first safety priority. [E5]

This assessment made no infrastructure changes. It used read-only commands, guest-agent queries, web research, and an APT simulation.

## Collection scope

Fresh host evidence spans 2026-11-18 16:59 to 17:04 UTC. Each evidence file records its own time, source, commands, and output.

Checked sources:

- Proxmox over SSH with sudo for read-only inspection.
- Six running VMs through their QEMU guest agents.
- The Pi-hole container OS through a read-only command.
- The NAS over SSH without sudo, for capacity and directory ownership.
- The primary Prometheus API and an attempted connection to its second replica.
- Repo inventory and host DNS source.
- Monitoring sources and official upstream documentation.

Not checked: switch-port settings, pfSense rules, WAN reachability, iLO access, UPS health, application package inventories, or backup restores.

The NAS denied access to `/etc/exports`. This assessment did not request its sudo password. [E11]

## Hardware and current load

| Item | Direct observation |
|---|---|
| Server | HP ProLiant DL360p Gen8 |
| CPU | Two Intel Xeon E5-2680 v2, 2.80 GHz base, 3.60 GHz maximum |
| CPU capacity | 20 physical cores, 40 threads, two NUMA nodes |
| Instruction set | AVX present, AVX2 absent from reported CPU flags |
| Installed RAM | 16 × 16 GiB DDR3 ECC, configured at 1866 MT/s |
| OS-visible RAM | 243.97 GiB |
| Memory snapshot | About 120 GiB used and 123 GiB available |
| Swap | No active swap, despite an 8 GiB swap logical volume |
| CPU sample | 74–81% idle in the two interval samples |
| Load average | About 11 across 40 logical CPUs |
| Uptime | About 45 days |
| BIOS | P71, dated 2019-05-24 |
| Boot mode | Legacy BIOS |
| Failed systemd units | None listed at collection |

Source: [E1, E2]. These short samples do not establish long-term performance or peak demand.

The kernel reports mitigations for several CPU vulnerabilities. L1TF and MDS entries still note SMT exposure. [E1]

Do not select an AVX2-dependent application build or an unsupported virtual CPU profile on this hardware.

## Installed host software and update candidates

Candidates below came from the host's existing APT indices. This assessment did not run `apt update`. [E4, E9]

| Component | Installed | Cached candidate |
|---|---|---|
| Proxmox manager | 9.1.7 | 9.2.28 |
| Proxmox VE metapackage | 9.1.0 | 9.2.0 |
| Running kernel | 6.17.13-2-pve | Simulated upgrade selects kernel 7.0.14-29 |
| QEMU | 10.1.2-7 | 11.1.3-2 |
| QEMU management | qemu-server 9.1.6 | 9.2.16 |
| LXC runtime | 6.0.5-4 | 7.0.0-2 |
| Container management | pve-container 6.1.2 | 6.1.20 |
| OpenSSH server | 1:10.0p1-7+deb13u2 | 1:10.0p1-7+deb13u4 |
| systemd | 257.9-1~deb13u1 | 257.13-1~deb13u1 |
| ifupdown2 | 3.3.0-1+pmx12 | 3.3.0-1+pmx14 |
| Backup client | 4.1.5-1 | 4.2.12-1 |
| smartmontools | 7.4-pve1 | 7.5-pve2 |
| ZFS tools | 2.4.1-pve1 | 2.4.4-pve1 |
| Intel microcode package | Not installed | No candidate in the current indices |

The APT simulation proposed 275 upgrades, seven new packages, and no removals or held-back packages. It did not install anything. [E9]

The simulation includes kernel 7.0, not only a patch to kernel 6.17. A maintenance plan must test the new kernel and retain a known-working boot entry. [E9]

Core Proxmox services, SSH, chrony, and smartmontools were active. Docker and containerd were inactive on the host. [E1, E6]

ZFS tools are installed, but `zpool status` found no pools. Storage definitions use LVM, LVM-thin, directories, and NFS. [E2]

Ceph packages and a partial configuration exist. No local monitor, OSD, or manager directories contain instances. `ceph -s` did not identify monitors. [E12]

This is not evidence of a working Ceph cluster. Do not remove Ceph packages without a separate dependency review.

### Repositories and firmware

The active Debian sources use `trixie`, `trixie-updates`, and `trixie-security`. Proxmox uses the free `pve-no-subscription` repository. [E4]

Debian sources include `main contrib`, but omit `non-free-firmware`. The Intel microcode package has no installed version or cached candidate. [E4]

The CPU reports loaded microcode revision `0x42e`. Missing the package does not mean that the CPU has no microcode. [E5]

Proxmox documents `non-free-firmware` and `intel-microcode` for early OS microcode updates. Any benefit for this CPU needs a revision check. [E8/U4]

The HPE MCP source points to `bookworm/current` while the host runs Debian 13. No corresponding InRelease appeared in the collected cache listing. [E4]

Review HPE repository compatibility and refresh results before an upgrade. The evidence does not establish why its cached index is absent.

## Guest setup

Current configuration and guest-agent responses show nine VMs, with six running. Three LXC entries include one running container, one stopped container, and one template. [E3, E6, E12]

| ID | Guest | State | vCPUs | Configured RAM | Main disk | Reported OS |
|---|---|---|---:|---:|---:|---|
| 100 | omada-controller | Running | 2 | 4 GiB | 30 GiB | Ubuntu 24.04.5 LTS |
| 120 | dockermaster | Running | 8 | 15.88 GiB | 120 GiB | Ubuntu 24.04.4 LTS |
| 121 | ha | Running | 4 | 16 GiB | 64 GiB | Home Assistant OS 18.4 |
| 122 | unifi-controller | Running | 2 | 8 GiB | 128 GiB | Ubuntu 20.04.6 LTS |
| 123 | dockerserver-1 | Running | 10 | 24 GiB | 120 GiB | Ubuntu 24.04.4 LTS |
| 124 | dockerserver-2 | Running | 10 | 48 GiB | 120 GiB | Ubuntu 24.04.4 LTS |
| 101 | tiny | Stopped | 4 | 4 GiB | 120 GiB | Not queried |
| 111 | rootmaster | Stopped | 4 | 7.91 GiB | 80 GiB | Not queried |
| 130 | lab-router | Stopped | 2 | 2 GiB | 8 GiB | Not queried |
| 10000 | pihole, LXC | Running | 4 | 1 GiB | 8 GiB | Debian 12 |
| 10020 | hermes, LXC | Stopped | 6 | 7.94 GiB | 236 GiB | Not queried |
| 9000 | tmpl-debian-devops | Template | 6 | 7.94 GiB | 236 GiB | Not queried |

The running VMs have 36 configured vCPUs and about 116 GiB of maximum RAM. Ballooning can change actual use. [E3]

The Docker VMs use socket-based CPU affinity. Their configs set `numa: 0`, so affinity alone does not establish guest memory locality. [E3]

All six running VMs answered guest-agent OS queries. No application-level version or compatibility audit took place. [E6]

UniFi's Ubuntu 20.04 passed standard support on 2025-05-31. Its extended support status was not checked. [E6, E8/U6]

Plan a UniFi migration to a supported LTS after checking UniFi and database requirements. Ubuntu 24.04 offers standard maintenance through May 2029. [E8/U7]

This host has no Corosync cluster configuration and no HA-managed resources. All active guests share one physical host. [E1]

Multiple application VMs do not protect services against failure of this physical host.

## Storage and data-safety findings

### Urgent: RAID cache protection reports failure

The P420i reports these values: [E5]

- Controller status: OK.
- Logical-drive and physical-drive status: OK.
- Battery/capacitor status: Failed.
- No-battery write cache: Enabled.
- Drive write cache: Enabled.
- Controller firmware: 8.32.

The failed capacitor and enabled no-battery write cache create a power-loss data-safety concern. No corruption was demonstrated.

Review cache safety and arrange capacitor replacement before optional platform work. Cache-policy changes need approval and a performance-impact plan.

Do not treat an unverified UPS as a substitute for working cache protection.

### RAID layout and capacity

| Storage | Observed setup or use |
|---|---|
| SSD array | Three 1 TB SATA SSDs, RAID5, logical drive about 1.86 TiB |
| HDD array | Three 600 GB SAS HDDs, RAID5, logical drive about 1.09 TiB |
| HDD spare | One 600 GB SAS spare, plus one unassigned 600 GB SAS disk |
| Host root | About 34 GiB total, 15 GiB available, `df` reports 56% use |
| local-lvm | 42 GiB thin pool, data allocation 0% |
| thin-pool-ssd | 1806.67 GiB pool, data allocation 42.87%, metadata use 14.60% |
| SSD volume-group reserve | No unallocated extents |
| hdd-pool | 1117.75 GiB free, no logical volumes |
| NFS backup/shared exports | Each reports 6 TiB total, 97.62% used, about 146 GiB available |

Sources: [E2, E5]. Pool allocation is not the same as guest filesystem use.

The HDD pool's three physical-volume entries are partitions of one RAID logical disk. They are not three independent storage systems. [E2, E5]

### High: thin-volume mapping warnings

LVM reports that VM 120 maps 193.89 GiB and VM 123 maps 196 GiB, but both logical volumes declare 120 GiB. [E2]

Proxmox guest configs also declare 120 GiB disks. Guest-agent data reports root filesystems of about 111.1 GiB and 106.4 GiB. [E3, E6]

Those filesystems report about 37.6% and 68.2% use. A thin-volume allocation of 100% does not mean either filesystem is full. [E6]

The mapping warnings need a focused review of thin metadata, device sizes, and resize history. They do not prove a prior unsafe shrink.

Do not run `lvreduce`, thin repair, or speculative resize commands on these live volumes.

Backup logs also warn about thin-pool overcommit and missing automatic extension protection. The SSD volume group has no reserve for automatic growth. [E2, E5]

### Capacity discrepancy: NFS view versus NAS volume

Proxmox sees about 146 GiB free on a 6 TiB NFS capacity view. The NAS reports a 25 TiB physical volume with 5.3 TiB free. [E2, E7]

Quota or export accounting is a hypothesis. No quota configuration was collected, so the cause remains unknown.

Do not describe the whole NAS as 98% full. Resolve the client-visible limit and maintain backup headroom without deleting recovery copies blindly.

## Backups

The enabled job runs Monday and Thursday at midnight in host local time. It selects all six running VMs and Pi-hole. [E3]

It uses snapshot mode, zstd compression, and `keep-daily=1,keep-weekly=1`. That policy does not mean backups run daily. [E3]

The newest 25 job records, from August 24 through November 16, all report `job errors`. This is historical task data collected today. [E5]

The November 16 logs show successful completion for VMs 100, 120, 121, 122, 123, and 124. Their November 12 and 16 archives are listed. [E5]

Pi-hole failed because tar did not open the temporary backup directory: `Cannot open: Permission denied`. [E5]

Both hosts show the backup export directory owned by UID 1027 with mode 0700. The container backup uses mapped UID 100000. [E5, E9, E11]

These permissions support a traversal-access explanation. NAS export squashing and ACL settings remain unchecked because `/etc/exports` was not readable. [E11]

No completed Pi-hole archive appeared in the queried `pve-backups` list. Other backup locations were not exhaustively searched. [E5]

Recommended next steps:

1. Define a repo-managed LXC backup fix, such as suitable local temporary storage, after checking permissions and available space.
2. Run an approved backup and confirm the Pi-hole archive exists.
3. Restore Pi-hole into an isolated network and test DNS recovery.
4. Restore-test a critical Docker VM and validate its applications.
5. Review retention and backup age alerts against the desired recovery window.

A completed archive is not proof of a successful restore. The latest VM backups still need restore tests.

## Networking and access

| Area | Direct observation |
|---|---|
| Management | 192.168.32.61/27 on vmbr01 and 192.168.32.62/27 on vmbr1 |
| HOME/storage | 192.168.7.10/20 on vmbr10 and 192.168.7.11/20 on vmbr010 |
| Lab | 192.168.100.1/24 on internal bridge vmbr0 |
| Other bridges | vmbr28, vmbr205, and internal vmbr30 |
| Primary 10 GbE | ens1f0, 10,000 Mb/s, full duplex, link up |
| Second 10 GbE | ens1f1, no link |
| Management links | eno1 and eno2, each 1,000 Mb/s, link up |
| MTU | ens1f0 and vmbr10 use 1500, not the old inventory's 9000 |
| NAS route | 192.168.2.50 through vmbr10, source 192.168.7.10 |
| Default route | Through 192.168.4.1 on vmbr10 |
| DNS | 192.168.4.1, 192.168.100.254, 192.168.4.236 |
| Time | Chrony synchronized, leap status normal |

Sources: [E4, E6, E13]. DNS matches `hosts/proxmox/dns.yml`.

Two bridges serve each of the HOME and management subnets. They are separate interfaces, not a configured bond. [E4]

Review whether these duplicate subnet paths are intentional before changing them. The idle 10 GbE link does not prove a cable or switch fault.

Only the Proxmox end of these links was checked. No end-to-end MTU, switch-port, or failover test took place.

### Security posture

Effective SSH defaults allow root login and password authentication. Public-key authentication is also enabled. [E4, E6]

The Proxmox firewall reports `disabled/running`. Host and cluster firewall files are absent, nftables has no listed tables, and iptables policies accept traffic. [E4, E9]

SSH, the Proxmox API/UI, SPICE proxy, and rpcbind listen beyond loopback. This does not establish Internet exposure. [E4]

Review upstream rules, user access, and recovery access before adding a host allowlist or changing SSH authentication.

The local Proxmox node certificate expires on 2027-03-09. Public trust and the certificate served through any reverse proxy were not tested. [E12]

## Monitoring

Primary Prometheus reports `up{job="pve"}=1` and version 9.1.7 at 17:03 UTC. Proxmox API monitoring already works. [E10]

The host has no installed Prometheus node exporter or listener on port 9100. API metrics do not replace detailed host and RAID metrics. [E4, E5]

Add node exporter and a repo-managed textfile collector for P420i cache status, physical-drive state, thin-pool data, and thin-pool metadata.

Add backup-age and backup-failure alerts. Check alert delivery, not only dashboard panels.

The narrow host-label alert query returned no firing series. It does not prove the required alert rules exist or work. [E10]

The second Prometheus address was unreachable from this workstation. That is a collection limit, not proof that the replica is down. [E10]

Kernel logs also contain repeated `hpilo` dequeue warnings. Investigate iLO communication separately. The warnings do not prove a controller failure. [E4]

## Proposed work, in order

These are proposals, not approved changes. All software choices below can use free, open-source editions.

| Priority | Work | Reason and acceptance test |
|---|---|---|
| Immediate | Repair RAID cache protection and review unsafe cache policy | Controller reports failed capacitor. Confirm healthy protection afterward. |
| Immediate | Fix Pi-hole backup and test restores | Confirm a new archive and a working isolated restore. |
| Before upgrade | Investigate VM 120/123 mapping warnings | Establish disk-size consistency and safe recovery options. |
| Before upgrade | Resolve NFS capacity accounting | Check quota/export limits and preserve backup headroom. |
| Soon | Extend host IaC beyond DNS | Add declarative sources, dry-run sync tools, and validation for each changed host surface. |
| Soon | Add host/RAID metrics and tested alerts | Keep existing PVE exporter. Add missing host and cache-protection visibility. |
| Soon | Review repositories and microcode delivery | Validate HPE compatibility and the Intel firmware path. |
| Next maintenance window | Upgrade PVE 9.1 to current 9.2 packages | Apply current fixes after recovery and storage checks. Validate kernel, networking, storage, and guests. |
| Soon | Move UniFi from Ubuntu 20.04 | Choose a supported LTS after application/database compatibility checks. |
| Soon | Harden SSH and host access | Confirm keys and console access, then apply a tested allowlist. |
| Following month | Evaluate Proxmox Backup Server | Add deduplication, scheduled verification, retention, and a separate recovery copy. |

For Backup Server, prefer a separate machine with storage independent of this hypervisor. A VM here shares its failure domain.

A NAS-backed destination still shares NAS failure risk. Design datastore storage, capacity, verification, pruning, garbage collection, and a second copy together. [E8/U5]

Defer Ceph, Kubernetes expansion, new SDN fabrics, and dynamic cluster balancing. They do not fix the current backup or cache-protection risks.

VE 9.2's cluster balancing and HA arm/disarm offer little benefit on this standalone node. Custom CPU profiles may help future standardization. [E1, E8/U1]

Do not rebuild these hardware-RAID arrays as ZFS as part of a routine software upgrade. That needs a separate migration design.

## Upgrade gates and rollback

Before any upgrade, agree on downtime, recovery objectives, and who can reach the physical console or iLO.

Require these checks:

1. Working RAID cache protection, or an explicitly approved interim safety plan.
2. Successful Pi-hole backup and tested recovery for critical guests.
3. A documented conclusion for the LVM mapping warnings.
4. Adequate backup capacity and a protected host configuration backup.
5. Current repository checks and a fresh reviewed package simulation.
6. A known-working kernel entry and confirmed console access.
7. An approved repo-managed apply path and maintenance window.

A prior kernel can help recover from a kernel regression. It does not roll back QEMU, Proxmox userspace, or package configuration.

Full rollback may require host reinstall and restore. Guest snapshots alone do not provide host rollback.

Apply one change class at a time. Do not combine a host upgrade, network redesign, cache-policy change, and guest OS migration.

## Evidence index

All paths below are relative to `docs/operations/evidence/2026-11-18-proxmox/`.

| Ref | File | Scope |
|---|---|---|
| E1 | [01-system.txt](evidence/2026-11-18-proxmox/01-system.txt) | Hardware, versions, load, services, standalone status |
| E2 | [02-storage.txt](evidence/2026-11-18-proxmox/02-storage.txt) | Disks, mounts, pools, LVM warnings |
| E3 | [03-guests-backups.txt](evidence/2026-11-18-proxmox/03-guests-backups.txt) | Guest configs, backup job, task history |
| E4 | [04-network-security-updates.txt](evidence/2026-11-18-proxmox/04-network-security-updates.txt) | Network, SSH, firewall, APT, time, kernel warnings |
| E5 | [05-backup-storage-followup.txt](evidence/2026-11-18-proxmox/05-backup-storage-followup.txt) | Backup logs, archives, P420i state, microcode, update count |
| E6 | [06-guests-network-followup.txt](evidence/2026-11-18-proxmox/06-guests-network-followup.txt) | Guest OS/filesystems, NIC links, update-service history |
| E7 | [07-nas-storage-peer.txt](evidence/2026-11-18-proxmox/07-nas-storage-peer.txt) | NAS-side physical capacity |
| E8 | [08-upstream-sources.txt](evidence/2026-11-18-proxmox/08-upstream-sources.txt) | Official release and support guidance, U1–U7 |
| E9 | [09-upgrade-preflight.txt](evidence/2026-11-18-proxmox/09-upgrade-preflight.txt) | Read-only package simulation, path permissions, filter rules |
| E10 | [10-monitoring.json](evidence/2026-11-18-proxmox/10-monitoring.json) | Live Prometheus queries and access limits |
| E11 | [11-nas-export-permissions.txt](evidence/2026-11-18-proxmox/11-nas-export-permissions.txt) | NAS path ownership and denied export-config access |
| E12 | [12-runtime-details.txt](evidence/2026-11-18-proxmox/12-runtime-details.txt) | Ceph limits, public certificates, container OS |
| E13 | [13-repo-records.txt](evidence/2026-11-18-proxmox/13-repo-records.txt) | Pre-edit inventory and existing IaC excerpts |
