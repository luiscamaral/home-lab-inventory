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
