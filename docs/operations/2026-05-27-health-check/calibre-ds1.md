# calibre (ds-1) — exited container investigation — 2026-05-27

## Symptom

Container `calibre` on ds-1 (192.168.48.45) is `Exited (127)` for ~2 weeks. Its sibling
`calibre-web` (the user-facing UI) is `Up 2 weeks (healthy)` on the same host.

## Confirmation

- ExitCode: **127** (runc init failure, not application exit)
- FinishedAt: **2026-05-12T00:47:40Z**
- StartedAt: 2026-04-20T18:42:02Z (so it ran ~3 weeks before dying)
- OOMKilled: false
- RestartPolicy: `always` (Docker gave up after repeated init failures)
- Error from `docker inspect`:

  > failed to create shim task ... error mounting
  > `/nfs/dockermaster/docker/calibre-server/10-keyboard.conf` to
  > rootfs at `/etc/X11/xorg.conf.d/10-keyboard.conf` ...
  > **not a directory: Are you trying to mount a directory onto a file (or vice-versa)?**

- On the NFS host: `/nfs/dockermaster/docker/calibre-server/10-keyboard.conf` is itself a
  **directory** (empty, mode 0755, mtime 2026-05-11 18:47) — created ~6 hours before the failed
  restart. The compose file (`terraform/portainer/stacks/calibre.yml`) expects it to be a
  _file_ bind-mounted to `/etc/X11/xorg.conf.d/10-keyboard.conf`.
- No application-level log lines from `calibre` are reachable (`docker logs --tail 100 calibre`
  returns logs from a different container — the actual `calibre` init never produced stdout
  because runc rejected the mount before entrypoint).

## Root cause

**Crash, not intentional.** Container is configured to auto-restart (`restart: always`) and
exited with a runc init error 127, not a clean stop. Triggering event: the bind-mount source
`10-keyboard.conf` on the dockermaster NFS share was replaced by an empty directory of the
same name on 2026-05-11 18:47 (root-owned). Likely cause: an `mkdir -p` somewhere that walked
the path and materialised the missing leaf as a directory, or an NFS/Synology touch from a
manual cleanup. From then on Docker could not bind a file→file mount and bailed every restart
attempt until it gave up. No commits to `calibre.yml` in that window — the IaC didn't change.

## User impact

**Low / none for normal reading.** `calibre-web` (the web reader UI users actually open) is
still healthy and continues to serve `/nfs/calibre/calibre-web/Library`. What's lost:

- The Calibre **desktop GUI over the linuxserver KasmVNC port** (used for library management,
  bulk edits, metadata grabbing, adding books via the rich client).
- Anything that talked to the `calibre` container's content-server / OPDS port specifically.

Users who only read books via calibre-web are unaffected. The book library files themselves
are untouched on the Synology share at `192.168.2.50:/volume2/shared/02.Books/...`.

## Recommended fix

1. On dockermaster: `rmdir /nfs/dockermaster/docker/calibre-server/10-keyboard.conf` (it's
   empty) and either restore the original `10-keyboard.conf` file or remove that bind-mount
   line from `terraform/portainer/stacks/calibre.yml` if the keyboard customisation isn't
   needed. The linuxserver/calibre image ships a sane default.
2. Re-deploy the `calibre` stack via Portainer/Terraform. **Do not** just `docker start` —
   that would only paper over the IaC drift.
3. Optionally: convert that single-file bind into a Compose `configs:` entry so it can't be
   silently turned into a directory again (matches the project's IaC-first principle).

## Severity

Low (P3). Book reading via calibre-web is intact; only the admin/desktop side is offline.

## How urgent

Not urgent. Schedule a normal maintenance window. Note that the container has been broken for
~2 weeks without any user complaint surfacing, which is itself a signal that the `calibre`
desktop side may be a candidate for decommission if it stays unused.

## Resolution — 2026-05-27

User confirmed `calibre` is not a decommission candidate and asked it restored.

### Findings

- The bind source `/nfs/dockermaster/docker/calibre-server/10-keyboard.conf` lives on the
  shared NFS export `tnas:/volume2/servers/dockermaster`, visible to both dockermaster and
  ds-1. The corruption (file replaced by empty directory) was therefore visible to ds-1 too,
  so this is a single-source problem, not a missing NFS export on ds-1.
- The original `10-keyboard.conf` content was preserved at
  `/nfs/dockermaster/docker/_archive/calibre-server/10-keyboard.conf` (34 bytes, X11 layout
  config):

  ```text
  XKBLayout="us"
  XKBVARIANT="intl"
  ```

- The migration commits `9f8a509` (Apr 8) and `79c4569` (Apr 11) did not drop any bind
  mounts — they only changed the network from `rproxy` to `docker-servers-net` and the IPs.
  The dockermaster compose and the ds-1 stack both list the same six volumes.
- Upstream `linuxserver/calibre` does not ship or require `10-keyboard.conf`; it is a local
  customization for the VNC desktop's keyboard layout.

### Fix applied (IaC-first)

1. Inlined the keyboard config into `terraform/portainer/stacks/calibre.yml` via Compose
   `configs:` (matches the `blackbox-exporter`, `vault`, `pihole-2` pattern). The fragile
   host bind line is gone; the file is now reproducible from the stack definition alone.
2. Removed the phantom empty directory at
   `/nfs/dockermaster/docker/calibre-server/10-keyboard.conf` on the NFS share so no future
   bind mount can resurrect the bug.
3. `terraform apply -target=portainer_stack.calibre` succeeded with no drift after the
   state-only refresh; the new `stack_file_content` was already in state from the planned
   diff. Forced a stop/start via `scripts/portainer-redeploy.py calibre` (Portainer TF
   provider doesn't redeploy on `configs:`-only changes — see
   `feedback_portainer_stack_redeploy.md`).

### Verification

- `docker ps` on ds-1 immediately after redeploy shows `calibre` as
  `Up (healthy)` and `calibre-web` as `Up (health: starting)` (180s start_period).
- `docker exec calibre cat /etc/X11/xorg.conf.d/10-keyboard.conf` returns the expected
  `XKBLayout="us"` / `XKBVARIANT="intl"` content, confirming the `configs:` injection
  works.
- `calibre-web` was recreated as part of the stack stop/start but its NFS-backed volumes
  (`/nfs/calibre/calibre-web/{config,Library}`) are unchanged, so no data risk.

### Notes for the next incident

- Single-file bind mounts onto an X11/xorg path are a known foot-gun: if the source
  vanishes, Docker silently auto-creates a directory at that path, which then mismatches
  the file→file mount on every subsequent restart. Prefer `configs:` for any static config
  small enough to inline.
- Both calibre and calibre-web share the same Portainer stack, so any redeploy bounces
  both. That's fine here (calibre-web came back healthy within the start_period) but worth
  remembering.
