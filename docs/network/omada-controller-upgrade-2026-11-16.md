# Omada controller upgrade to 6.3.0.111 (2026-11-16)

Status: done on 2026-11-16 at 18:16 MST. Verified.
This was a break-glass change. The controller version has no declarative source in the
repo, and the user approved the action in the session. This file is the post-hoc record.

## Result

- Controller VM 100 (`omada-controller`, `192.168.32.40`) moved from Omada 6.2.10.17 to 6.3.0.111.
- The package name did not change. It is still `omadac`.
- The install took about two minutes. The controller was unreachable for about that long.
- The switch (SG3428X v1.30, firmware 1.30.24 Build 20260509) reconnected by itself.
  It reported status 14 (connected) about 20 seconds after the controller came up.
- The controller reported no pending firmware for the switch before the upgrade.
- `ix0` and the other VLANs did not change. The switch kept forwarding.

## Why this version

The 6.3.0.111 release note lists fixes only. One is a security fix for gRPC communication.
It lists no new features. TP-Link's download page showed only a Windows zip for this version.
The Linux package sits in the same directory, with the build stamp from the update notice in its name.

- Package: `https://static.tp-link.com/upload/software/2026/202610/20261016/Omada_Network_Application_v6.3.0.111_linux_x64_20261009150935.deb`
- Release note: `Release Note for Omada Software Controller v6.3.0.111.pdf` in the same directory.
- Size: 322,210,172 bytes.
- SHA-256: `172963ea7f5b673405d46003f3c31aea98884d2e3d1de5ba572c1c3ba26d6013`.
  Two independent downloads, one on the guest and one on the Mac, gave the same hash.
  TP-Link publishes no checksum.

## Procedure

1. Capture the controller configuration through its API: devices, 28 switch ports with their
   profiles, networks, port profiles, and sites. Save it as a baseline.
2. Take a Proxmox snapshot of VM 100: `pre-omada-6-3-0-111-20261116`.
   Make a MongoDB dump with `mongodump --port 27217 --db omada`. Archive the data directory.
   Both are in `/root/omada-pre-6.3.0.111/` on the guest.
3. Download the package on the guest. Check the size and read its control data with `dpkg -I`.
   Run `apt-get install --simulate`. It must upgrade `omadac` only, with no new dependencies.
4. Install it detached, so no connection has to survive:
   `systemd-run --unit=omada-upgrade /bin/sh -c 'dpkg -i omada-6.3.0.111.deb > upgrade.log 2>&1'`.
   Read `upgrade.log` until it ends with `EXIT=0`.
5. Check `/api/info` for the version. Capture the configuration again and compare it with the baseline.
   Watch the switch status until it returns to 14.

## Verification

- `/api/info` reported 6.3.0.111. The guest reported package version 6.3.0.111 with `tpeap`
  and `mongod` active.
- After the switch reconnected, the only differences from the baseline were the version
  and the LAG runtime counters. Sites (1), networks (6), port profiles (15), and ports (28) matched.
  All 28 port profiles, native networks, and tagged VLANs were identical.
- A retest from HOME reached all gateways, Vault, Portainer, Proxmox, and the switch UI.
  It also reached Google, Grafana, Home Assistant, Keycloak, and the controller by name.

## Rollback

Roll VM 100 back to the snapshot `pre-omada-6-3-0-111-20261116` with `qm rollback 100
pre-omada-6-3-0-111-20261116`. The switch keeps its configuration while the controller is down.
Delete the snapshot and the folder `/root/omada-pre-6.3.0.111/` after a week without problems.

## Notes

- Several 6.3 features need Managed Switch firmware 6.4 or newer. This switch runs the 1.30 line.
  The controller still manages it. Those features are not available.
- The release note says devices marked with `!` in the device list will lose support in
  controller 6.4. The switch had no such marker in the API data. Check the UI before any 6.4 upgrade.
- The guest runs Ubuntu 20.04, which is past standard support. This was not a blocker.
  The dependencies (Java 17 and MongoDB 7.0.37) were already met.

## Same-day follow-up: OS packages and Ubuntu 24.04

Status: done on 2026-11-16 at 19:49 MST. Verified. This was also a break-glass change, approved
by the user in the session.

### Timeline

| Time (MST) | Step |
| --- | --- |
| 18:25 | The user ran `apt update && apt upgrade` on the guest by hand. It upgraded 17 packages. One of them was MongoDB, from 7.0.37 to 7.0.48. |
| 18:36 | Check: the controller kept running. Both MongoDB processes still ran the old 7.0.37 binary. |
| 18:39 | Reboot of VM 100. Both MongoDB processes came up on 7.0.48. The static IP survived. |
| 18:43 | Snapshot `pre-ubuntu-22-04-20261116`, database dump, upgrade settings. |
| 18:45 to 19:11 | Ubuntu 20.04 to 22.04.5 with `do-release-upgrade`. |
| 19:12 | Reboot into 22.04. Controller and switch verified. |
| 19:18 | Snapshot `pre-ubuntu-24-04-20261116`, database dump. |
| 19:18 to 19:39 | Ubuntu 22.04 to 24.04.5. |
| 19:45 | Reboot into 24.04, kernel 6.8.0-149. |
| 19:49 | Verified. |

### Result

- Ubuntu 24.04.5 LTS, kernel 6.8.0-149, no failed systemd units.
- Static `192.168.32.40/27` on `ens18`, unchanged. `sync-guest-netplan.py` reports the file in sync.
- Omada 6.3.0.111. Sites (1), networks (6), port profiles (15), and ports (28) matched the baseline.
- The switch reconnected on its own after every reboot, about 20 seconds after the controller came up.
- MongoDB 7.0.48 on both ports (27017 and 27217). Java 17.0.21. jsvc 1.0.15.

### How the upgrade ran

Ubuntu cannot jump from 20.04 to 24.04. Each hop ran detached on the guest:

```sh
systemd-run --unit=release-upgrade --property=KillMode=process /bin/sh -c \
  'DEBIAN_FRONTEND=noninteractive do-release-upgrade -f DistUpgradeViewNonInteractive \
   > /var/log/omada-release-upgrade.log 2>&1; echo EXIT=$? >> /var/log/omada-release-upgrade.log'
```

Settings that mattered:

- `/etc/update-manager/release-upgrades` has `Prompt=lts`. It stays that way.
- A temporary `/etc/apt/apt.conf.d/99-upgrade-confold` kept existing config files during the upgrade.
  It was removed afterwards.
- `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` holds `network: {config: disabled}`.
  It stops cloud-init from writing a DHCP netplan file. A DHCP file can override the static one.
  Someone set this file by hand. It is not in the repo yet.
- The upgrader refuses to start while any update is pending. A held `mongodb-mongosh` blocked it.
  The hold was lifted and the package upgraded.
- The upgrader disables the MongoDB repo and renames the file to `.list.distUpgrade`.

### MongoDB caveat

MongoDB publishes no 7.0 repo for Ubuntu 24.04 (`noble` has no Release file). The guest runs the
MongoDB 7.0 packages from the `jammy` repo: `jammy/mongodb-org/7.0` in
`/etc/apt/sources.list.d/mongodb-org-7.0.list`. The `mongod` binary links only to OpenSSL 3
and runs on 24.04. MongoDB does not support this combination.

- On 22.04 the focal build still needed `libssl1.1`, so the packages were reinstalled from `jammy`
  before the first reboot. Do the same check after any release upgrade.
- Moving to MongoDB 8.0 is the supported path for 24.04. It needs a staged database compatibility
  upgrade (feature compatibility version 7.0 to 8.0). Plan it as its own change.

### Notes for later

- `/etc/netplan/01-netcfg.yaml` is mode 600, as netplan 1.1 prefers. The sync script now writes mode 600.
- The old backup `/etc/netplan/01-netcfg.yaml.bak-20261116-173518` is still on the guest.
  Netplan ignores it.
- `motd-news.service` failed before the upgrades. It did not fail after.
- Ubuntu 24.04 has standard support to 2029. The project rules exclude Ubuntu Pro.

### Rollback and cleanup

Snapshots on VM 100, newest first: `pre-ubuntu-24-04-20261116`, `pre-ubuntu-22-04-20261116`,
`pre-omada-6-3-0-111-20261116`. Roll back with `qm rollback 100 <name>`. Rolling back to an older
snapshot discards the newer ones.

After a week without problems, delete the three snapshots and the folders under `/root/`:
`omada-pre-6.3.0.111`, `omada-pre-ubuntu-22.04`, and `omada-pre-ubuntu-24.04`.
