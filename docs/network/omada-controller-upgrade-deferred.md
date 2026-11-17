# Omada controller upgrade (deferred)

Status: deferred by the user on 2026-11-16. No change was made to the controller.

## Current state

- Controller VM 100 (`omada-controller`) runs Omada 6.2.10.17, package `omadac`.
- The Omada UI offers 6.3.0.111, build 20261009150935.
- The guest runs Ubuntu 20.04.6, Java 17.0.15, and MongoDB 7.0.37. It has 19 GB free.
- Switch24a (SG3428X v1.30) runs firmware 1.30.24 Build 20260509. The controller
  reported no pending firmware for it.

## Why it waits

- TP-Link's public download page showed no Linux package for 6.3.0.111 on
  2026-11-16. It showed a Windows zip and a release note link only.
- The public Linux packages were 6.3.0.45 (2026-09-04) and 6.2.14.11 (2026-07-17).
- The 6.3.0 release note lists no Ubuntu requirement. Ubuntu 20.04 is past its
  standard support.
- The release note says several new features need Managed Switch firmware 6.4
  or newer. The switch runs the older 1.30 line.
- The controller manages the core switch. The June 2026 adoption caused a full
  LAN outage.

## Before the upgrade

1. Get the Linux package URL for the exact version. The Download button on the
   Omada UI update notice gives the link.
2. Read the release note for that version.
3. Take a Proxmox snapshot of VM 100. Name it with the date and the old version.
4. Export a controller backup from the Omada UI.
5. Plan the work for a quiet time, with the ADMIN path and the Keychain backup
   login ready. See `docs/network/keychain-credential-backup.md`.

## Upgrade steps

1. Copy the package to the guest. If TP-Link gives a checksum, check it.
2. Install it over the old package with `dpkg -i`.
3. Wait for `tpeap` to start. Log in and check that the switch shows as connected.
4. Check the switch port profiles and the VLAN list against the June 2026 notes
   in `docs/network/switch24a-omada-integration-plan.md`.

## Rollback

Roll VM 100 back to the snapshot. The switch keeps its configuration while the
controller is down.
