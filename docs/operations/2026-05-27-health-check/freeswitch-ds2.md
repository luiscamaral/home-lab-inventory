# freeswitch (ds-2) health investigation — 2026-05-27

## Symptom

`docker ps` reports container `freeswitch` on ds-2 (192.168.48.46) as
`Up 2 weeks (unhealthy)`. Image: `ghcr.io/patrickbaus/freeswitch-docker`.

## Confirmation

- **Healthcheck definition**: `CMD-SHELL fs_cli -x status | grep -q ^UP || exit 1`
  (interval 15s, timeout 5s).
- **Failing streak**: **91,031** consecutive failures. Every probe returns:
  `[ERROR] fs_cli.c:1699 main() Error Connecting []` — fs_cli can't connect to
  mod_event_socket on 127.0.0.1:8021.
- Manual `docker exec freeswitch fs_cli -x status` reproduces the same error.
- The probe is **fully container-local** (loopback, not 5060), so the firewall
  carve-out from commit c6b5561 is unrelated.

## Is FreeSWITCH actually working?

Partially. The core is alive but the event socket is dead:

- PID 1 (`/usr/bin/freeswitch`) up 16 days, ~6% CPU, no respawn.
- Sofia stack is still processing outbound: most recent log shows periodic
  `Registering callcentric.com` (last attempt 2026-05-25 15:55, with rolling
  60s timeouts + 30s retries — i.e. the SIP trunk to callcentric is itself
  flapping, but mod_sofia is operating).
- However, the entire recent log (~3000 lines) is dominated by
  `[WARNING] switch_core_db.c:92 SQLite is BUSY` loops on the `sip_registrations`
  table — `sane=265..299` countdowns, meaning the SQL thread is hitting the
  retry ceiling repeatedly. This usually means a long-running writer (or a
  stale lock from the bind-mounted DB on NFS) is starving readers.
- `sofia status` / `status` cannot be queried because mod_event_socket is the
  thing that's wedged — likely starved by the same SQLite contention or a
  thread deadlock in the SQL core.
- No inbound registrations visible in logs (the ESP32 SIP phone activity is
  not in the tail window — cannot confirm endpoint registrations from logs
  alone without a state query, which is the very thing that's broken).

## Root cause

**Real failure, not a false alarm.** Two coupled issues:

1. `mod_event_socket` is unresponsive on 127.0.0.1:8021 — root cause of the
   healthcheck red.
2. Persistent `SQLite is BUSY` storm on `core.db` (the SIP registrations table).
   The DB lives on the bind-mount under `/nfs/dockermaster/docker/freeswitch/`
   — NFS-backed SQLite is a known foot-gun (advisory locks behave oddly), and
   this is the most likely upstream cause of (1).

The container itself is in a degraded but-not-dead state: SIP signalling
threads still fire, but management plane is gone.

## Recommended fix

Short term: restart the container (`docker restart freeswitch`) — will clear
the SQLite lock and resurrect mod_event_socket. Expect outbound registration
to recover within ~30s.

Medium term (IaC follow-ups, NOT done in this read-only run):

- Move `core.db` / `core.db-journal` / `sofia*.db` off the NFS bind-mount onto
  a local-disk Docker volume (NFS + SQLite is the smoking gun). Keep only
  `conf/` and `logs/` on NFS.
- Once the event socket is reliable again, the existing healthcheck is fine —
  no change needed. It correctly catches this exact failure mode.
- Add a `mod_event_socket` keepalive watchdog or convert to a Compose
  `restart: unless-stopped` + `on-failure` health policy so 91k consecutive
  fails would have auto-recovered.

## Severity

**Medium**. Core SIP plane is up and outbound trunk still attempts to register,
but: (a) no manageability via fs_cli/ESL, (b) inbound registration state is
suspect, (c) ESP32 SIP phone behaviour cannot be verified from current logs,
(d) SQLite BUSY storm wastes CPU and will eventually wedge the SQL thread.

## How urgent

**Today / this session.** A `docker restart freeswitch` is a 30-second fix that
restores observability. Defer the NFS-off-SQLite refactor to a follow-up PR.

## Real root cause (2026-05-27 investigation)

The previous "Root cause" section above is **wrong** and is left in place for
the record. SQLite-on-NFS is not the cause. After the user pushed back
("freeswitch was working just fine before, and the sqlite on nfs was not an
issue") a deeper investigation found the actual cause.

### Findings

1. **The container has been functionally healthy the entire time.** ESL
   (mod_event_socket) is up and answering on `127.0.0.1:8021`. A raw `nc`
   to that port returns `Content-Type: auth/request` immediately. Sofia
   profiles `internal` and `external` are both `RUNNING (0)`. The
   callcentric trunk is `REGED` (registered) — not flapping. CPU is 88-90%
   idle. `fs_cli -x status` with the correct ESL password returns `UP`.
2. **The healthcheck never worked after ESL password rotation.** The
   upstream image (`ghcr.io/patrickbaus/freeswitch-docker`) bakes a
   `HEALTHCHECK CMD-SHELL fs_cli -x status | grep -q ^UP || exit 1` into
   the image (no `-p` flag). `fs_cli` with no password flag defaults to
   `ClueCon`, but this homelab uses a rotated ESL password. So the probe
   has always returned `Error Connecting []` (auth rejected → ESL
   disconnects → fs_cli exits non-zero). This is just an auth failure
   that _looks_ like a connection failure in the fs_cli error message.
3. **The 91k consecutive failures = 16 days** at the image's 15 s
   interval matches a container restart on **2026-05-12 00:42** (visible
   in the logs). The "broken since 2026-05-17" math in the original task
   prompt was wrong; the failure has continued from at least the 2026-05-12
   restart, but is structurally older — every restart since the password
   was rotated has the same failing probe.
4. **The IaC stack file (`terraform/portainer/stacks/freeswitch.yml`)
   intentionally commented out a `healthcheck:` block at IaC migration
   time** with the note "Healthcheck disabled: fs_cli ESL connection failing
   (pre-existing issue)". Commenting out a `healthcheck:` block in Compose
   does **not** disable the image's baked-in HEALTHCHECK — that requires
   either `test: ["NONE"]` or `disable: true` or an actual override.
   So the image's broken probe stayed in effect.
5. **The "SQLite is BUSY" warnings in the old log tail are a separate,
   benign noise pattern** — FreeSWITCH retries internally and recovers.
   After the fresh restart in this session, there are zero SQLite BUSY
   lines in the new log. They never wedged the SQL thread; they were
   transient and the previous agent over-interpreted them as causal.
6. **Vault / on-disk config drift.** Vault `secret/homelab/freeswitch`
   stores `esl_password=ClueCon_FS2026`. The actual rendered
   `/etc/freeswitch/autoload_configs/event_socket.conf.xml` on the NFS
   bind-mount had a different, older auto-generated value
   (`gi2HEvbJxv0LV2h41mQrHIK4`). The image's entrypoint templates the
   password into this file on first run only; subsequent password
   rotations in Vault never get applied because the file is
   bind-mount-persistent.

### Why the previous hypothesis was wrong

- The previous agent saw old `SQLite BUSY` log lines and over-fit a story
  around them. They are real but cosmetic — FreeSWITCH's SQL core retries
  and recovers, and the warnings have been in this exact container's logs
  for months without affecting service.
- The agent didn't probe the ESL port at the TCP level (`nc 127.0.0.1
  8021`) which would have immediately shown the server is healthy and
  the issue is auth, not lock contention. Their next test
  (`docker exec ... fs_cli -x status`) reproduced the same fs_cli error
  as the healthcheck — which is consistent with both "ESL is dead" and
  "ESL is healthy but auth is wrong"; they picked the wrong hypothesis.
- The "Sofia is flapping with rolling 60 s timeouts" claim was based on
  log lines older than the most recent registration event. `sofia status`
  was unavailable (the very command they needed) because fs_cli was being
  rejected; from outside the ESL plane, there was no actual flap.

### Fix applied

1. Updated `/nfs/dockermaster/docker/freeswitch/config/autoload_configs/event_socket.conf.xml`
   to set `password="ClueCon_FS2026"` so it matches Vault. Backup at
   `event_socket.conf.xml.bak-2026-05-27`. `reload mod_event_socket`
   inside fs_cli to pick up the new password without restarting the core.
2. Updated `terraform/portainer/stacks/freeswitch.yml` to **explicitly
   override** the image's baked-in healthcheck with one that uses
   `$$ESL_PASSWORD`:

   ```yaml
   healthcheck:
     test: ["CMD-SHELL", "fs_cli -p $$ESL_PASSWORD -x status | grep -q ^UP"]
     interval: 30s
     timeout: 10s
     retries: 3
     start_period: 30s
   ```

   This way the probe will keep working through future password rotations
   as long as Vault → env var → container env stays consistent.
3. `terraform apply -target=portainer_stack.freeswitch` failed with
   "Proxy failure" on the ds-2 Portainer endpoint (a known transient
   issue today, see the minio-2 migration notes). Fell back to the
   minio-2 workaround: copied the updated stack file to the NFS
   bind-mount and ran `Docker Compose up -d` directly on ds-2, with a
   tmp env file rendered from Vault on the ds-2 box so secrets never
   transit the local terminal.

### Verification

```text
$ docker ps --filter name=freeswitch --format "{{.Status}}"
Up 51 seconds (healthy)

$ docker exec freeswitch fs_cli -p ClueCon_FS2026 -x status
UP 0 years, 0 days, 0 hours, 0 minutes, 50 seconds
FreeSWITCH (Version 1.10.12-release  64bit) is ready

$ docker exec freeswitch fs_cli -p ClueCon_FS2026 -x "sofia status"
internal                   profile   RUNNING (0)
external                   profile   RUNNING (0)
external::callcentric.com  gateway   REGED
```

### Follow-up

- The Terraform plan still shows a diff for `portainer_stack.freeswitch`
  (the Portainer-side stack content is stale because we deployed via
  Docker Compose). Re-run `terraform apply -target=portainer_stack.freeswitch`
  once the ds-2 Portainer "Proxy failure" clears. It will succeed because
  the running container already matches the desired state, and `portainer_stack`
  will just push the new YAML to Portainer's stored copy. This is the same
  drift pattern documented for `portainer_stack_redeploy` in user memory.
- Long-term: consider pinning the image to a known digest and pre-baking
  the healthcheck in our own derived image so we control the probe
  command directly instead of fighting upstream's default.
