# Telegram Alerting Rollout — Investigation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to work this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking. This is an **investigation/ops plan**, not a
> greenfield feature build — several tasks end in "root cause TBD, pick a fix based on
> findings" rather than a pre-written implementation. Where the fix IS already known
> (Task 2), the exact diff is included.

**Goal:** Verify the newly-live Telegram alert pipeline is trustworthy, and clear every
alert currently firing/pending so the first real page a human sees over Telegram is a
real incident, not backlog noise.

**Approach:** Telegram push alerting (`terraform/portainer/locals.tf` + `vault.tf`) is
**already deployed to both Alertmanager replicas** as of 2026-07-01 (confirmed live via
`/api/v2/status` on both `192.168.59.27:9093` and `192.168.4.238:9093`, gossip-clustered,
2 peers, status `ready`) — this is not a "will it work" plan, it's a "what does it say
right now, and is that true" plan. 7 tasks: 1 hygiene (commit), 4 live incidents (P0),
1 IaC-adoption gap (P1), 1 product decision (P2). Tasks 1-5 touch disjoint subsystems
(git, blackbox config, Thanos storage, Pi-hole exporters, ESP32 firmware) — run them in
parallel. Task 6 has a mid-task approval gate (deleting a file on the production router).
Task 7 is a question, not an investigation — resolve it last.

**Tech stack:** Terraform (Portainer provider), Prometheus/Alertmanager/Thanos Ruler,
blackbox_exporter, pfSense (FreeBSD cron), Vault KV v2, Telegram Bot API.

## Global Constraints

- IaC only — every change lands in `terraform/portainer/` or `pfsense/*.yml` +
  `pfsense/scripts/`, applied via `terraform apply` or `scripts/sync-pfsense-*.py`. Never
  hand-edit `config.xml`, never hand-place cron/scripts on a host (see Task 6 — this is
  the exact violation being cleaned up, don't reintroduce it).
- Destructive / host-level actions (file deletion on a router, container restart,
  `terraform apply` against a production stack) get a stated rollback and explicit
  go-ahead before execution — flagged inline per task below.
- Vault secrets: fetch into shell variables inside one command, never `echo`/print raw
  token values. `VAULT_ADDR=http://192.168.59.25:8200` (direct; the `vault.d.lcamaral.com`
  hostname round-robins and can flap). Token: `security find-generic-password -s
  vault-root-token -a "$USER" -w`.
- Prometheus query API: `https://prometheus.d.lcamaral.com/api/v1/query` /
  `/api/v1/alerts` / `/api/v1/rules`.

---

## Priority order

| # | Task | Severity | Blocking? |
|---|------|----------|-----------|
| 1 | Commit deployed-but-uncommitted diff | hygiene | No — do anytime, ~2 min |
| 2 | Fix `RProxyEndpointDown` WS false-positive | warning, live, known fix | No |
| 3 | Root-cause `ThanosBucketUploadsStalled` | **critical**, live, unknown cause | No |
| 4 | Root-cause dual `PiholeExporterDown` | warning, live, unknown cause | No |
| 5 | Verify `WifiProbeHeapLow` self-heals | **critical**, live, likely self-resolving | No |
| 6 | Sync ix0-watchdog cron + retire hand-placed file | IaC drift, not urgent | Approval gate mid-task |
| 7 | Decide: Telegram DM vs. group/channel | decision | Do last |

Tasks 1–5 are independent — dispatch in parallel (5 subagents) if using
subagent-driven-development. Task 6 depends on nothing but is safer run after Task 1 (so
the sync script applies from a state that's also captured in git). Task 7 needs no
investigation, just an answer from the user.

---

### Task 1: Commit the deployed-but-uncommitted diff

**Why it's first:** the Telegram + ix0-watchdog work is already running in production
(verified in the prior turn) but absent from git — if the working tree were lost right
now, nobody could reconstruct the live config from history.

**Files:**

- Stage: `terraform/portainer/locals.tf`, `terraform/portainer/vault.tf`,
  `pfsense/cron-jobs.yml`, `pfsense/scripts/ix0-watchdog.sh`,
  `pfsense/scripts/ix0watchdog-rcd.sh`
- **Do NOT sweep in:** `docs/network/switch24a-omada-integration-plan.md` and the
  `monitoring/esp32-c5-wifi-probe` submodule bump — both show modified in `git status` but
  are unrelated to this body of work. Don't `git add -A`.

- [ ] **Step 1: Confirm the exact file set**

Run: `git status --short`
Expected: exactly the 5 files above as `M`/`??`, plus the 2 unrelated files noted above
(leave those alone).

- [ ] **Step 2: Stage and commit**

```bash
git add terraform/portainer/locals.tf terraform/portainer/vault.tf \
  pfsense/cron-jobs.yml pfsense/scripts/ix0-watchdog.sh \
  pfsense/scripts/ix0watchdog-rcd.sh
git commit -m "feat(monitoring): push alerts to Telegram + adopt ix0-watchdog cron into IaC

Route critical+warning alerts to Telegram (bot_token/chat_id from Vault
secret/homelab/telegram/alertmanager) alongside existing email, on all
three receivers (default/email-critical/email-warning). info stays
log-only.

Add pfsense-network rule group (Ix0LinkFlapping/Ix0FlapStorm/Ix0LinkDown)
watching the node_exporter textfile metrics from ix0_link_metrics.sh.

Bring the ix0-watchdog keepalive cron under pfsense/cron-jobs.yml,
replacing the hand-placed /etc/cron.d/ix0-watchdog (retired in Task 6
of docs/superpowers/plans/2026-07-01-alerting-rollout-investigation.md)."
```

- [ ] **Step 3: Verify branch is correct**

Run: `git branch --show-current`
Expected: `fix/keycloak-db0-off-nfs` — confirmed this branch already carries ~50 commits
of unrelated network/monitoring feature work ahead of `main` (checked via `git log
main..HEAD`), so it is the de facto integration branch for this area. Do not create a new
branch — that would strand this work from its prerequisites (ix0 metrics collector,
pfsense-network rule group scaffolding, etc. all live earlier on this same branch).

- [ ] **Step 4: Push per standing workflow**

```bash
git push
```

---

### Task 2: Fix `RProxyEndpointDown` WS false-positive (rustdesk × 2)

**Why:** firing right now for `rustdesk.home.lcamaral.com` and
`rustdesk-relay.home.lcamaral.com`. Known cause (WS-only upstreams reject a plain HTTP GET
probe; memory `feedback_blackbox_rproxy_websocket_fp.md`). Will re-notify Telegram every
6h (`repeat_interval` on the `email-warning`/Telegram-warning receiver) until fixed —
highest alert-fatigue cost of the four P0s even though it's only `warning`.

**Root cause confirmed in this plan's research:** `blackbox_rproxy_targets`
(`terraform/portainer/locals.tf:1111-1121`) auto-derives its target list from every
`*.conf` in `dockermaster/docker/compose/nginx-rproxy/vhost.d/`, filtered only to exclude
`*.cf.lcamaral.com`. There is no WS-aware exclusion yet. A `tcp_connect` blackbox module
already exists (`locals.tf:1032-1034`) — reuse it rather than inventing a new one.

**Files:**

- Modify: `terraform/portainer/locals.tf:1103-1121` (add exclusion + new target list)
- Modify: `terraform/portainer/locals.tf:324-337` and `:741-754` (both `blackbox-rproxy`
  job blocks — replica A and B — add a sibling `blackbox-rproxy-ws` job)
- Modify: `terraform/portainer/stacks.tf:470` and `:1352` area (pass the new
  `blackbox_rproxy_ws_targets` local into both Prometheus stack templatefile() calls,
  same pattern as `blackbox_rproxy_targets`)

- [ ] **Step 1: Add the WS exclusion list + second target set**

In `locals.tf`, right after the existing `rproxy_probe_hosts` block (~line 1115):

```hcl
  # WS-only upstreams: reject a plain HTTP GET (blackbox's http_rproxy_alive probe)
  # even when healthy, because they never complete an HTTP response — they expect
  # the Upgrade handshake. Probed via tcp_connect instead (confirms nginx is
  # listening + accepting the TCP connection, without asserting HTTP semantics).
  # 2026-07-01: found firing as RProxyEndpointDown false positives (memory
  # feedback_blackbox_rproxy_websocket_fp.md).
  websocket_only_vhosts = [
    "rustdesk.home.lcamaral.com",
    "rustdesk-relay.home.lcamaral.com",
  ]

  rproxy_probe_hosts = [
    for f in fileset("${path.module}/../../dockermaster/docker/compose/nginx-rproxy/vhost.d", "*.conf") :
    trimsuffix(f, ".conf")
    if !can(regex("\\.cf\\.lcamaral\\.com$", trimsuffix(f, ".conf")))
    && !contains(local.websocket_only_vhosts, trimsuffix(f, ".conf"))
  ]

  blackbox_rproxy_ws_targets = jsonencode([
    {
      targets = [for h in local.websocket_only_vhosts : "${h}:443"]
    }
  ])
```

- [ ] **Step 2: Add the second scrape job (replica A, ~line 324, and replica B, ~line 741 — both copies)**

```hcl
      # 2026-07-01: WS-only vhosts excluded from blackbox-rproxy (they fail a plain
      # HTTP GET even when healthy). tcp_connect just confirms the port is up.
      - job_name: blackbox-rproxy-ws
        scrape_interval: 30s
        metrics_path: /probe
        params:
          module: [tcp_connect]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/rproxy-ws-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115
```

- [ ] **Step 3: Wire the new target file into both Prometheus stack templatefile() calls**

`grep -n "blackbox_rproxy_targets" terraform/portainer/stacks.tf` — add
`blackbox_rproxy_ws_targets = local.blackbox_rproxy_ws_targets` next to each existing
`blackbox_rproxy_targets = local.blackbox_rproxy_targets` line, and confirm
`stacks/prometheus.yml.tftpl` / `prometheus-2.yml.tftpl` render it to
`/etc/prometheus/blackbox-targets/rproxy-ws-targets.json` the same way the existing one
renders (check the `configs:` block for the existing `rproxy-targets.json` entry and
mirror it).

- [ ] **Step 4: Existing `RProxyEndpointDown` rule must NOT also match the new job**

`RProxyEndpointDown` (`locals.tf:1281`) filters `probe_success{job="blackbox-rproxy"}` —
the new job is named `blackbox-rproxy-ws`, so it's already excluded. No rule change
needed. (Optional: add a matching `RProxyWSEndpointDown` on `job="blackbox-rproxy-ws"` in
a follow-up — out of scope here, don't add unrequested scope.)

- [ ] **Step 5: `terraform plan` and review**

```bash
cd terraform/portainer && terraform plan
```

Expected diff: both Prometheus stacks' `stack_file_content` change (new job + target
file), nothing else. If MORE than the 2 Prometheus stacks show a diff, stop and check
for an unrelated pending change getting swept in.

- [ ] **Step 6: Apply**

```bash
terraform apply
```

- [ ] **Step 7: Verify the false positive clears**

```bash
curl -s --max-time 5 "https://prometheus.d.lcamaral.com/api/v1/query" \
  --data-urlencode 'query=probe_success{job="blackbox-rproxy-ws"}' | jq -c '.data.result'
curl -s --max-time 5 "https://prometheus.d.lcamaral.com/api/v1/alerts" \
  | jq -c '.data.alerts[] | select(.labels.alertname=="RProxyEndpointDown")'
```

Expected: `probe_success` = 1 for both rustdesk targets on the new job; the second query
returns nothing (or only other, unrelated instances) once the alert's `for: 2m` window
clears on the old job's now-absent series.

---

### Task 3: Root-cause `ThanosBucketUploadsStalled` (thanos-sidecar-2, critical)

**Why it matters:** this is the exact regression class the rule's own comment warns
about — bucket empty for 13 days before being caught last time (PR #42/#44, root cause
was a UID 1001 vs `nobody:nobody` permission mismatch on the shared TSDB volume). If it's
the same class, long-term storage on the NAS replica is silently not receiving new
2-hour blocks right now.

**Files/hosts:** thanos-sidecar-2 runs on the Synology NAS (`ssh nas`), alongside
Prometheus-2 in the same Portainer stack.

- [ ] **Step 1: Recent logs**

```bash
ssh nas 'docker logs thanos-sidecar-2 --since 6h 2>&1 | tail -150'
```

Look for: upload errors, S3/MinIO connection refused/timeout, permission denied on
`/data` (or whatever the TSDB mount is), TLS errors against `s3.d.lcamaral.com`.

- [ ] **Step 2: Check for the known UID-mismatch regression**

```bash
ssh nas 'docker exec thanos-sidecar-2 ls -ln / | grep -i data'
ssh nas 'docker exec thanos-sidecar-2 id'
```

Compare the volume's owning UID against the container's runtime UID. Last time this broke
it was `1001` vs `nobody:nobody`.

- [ ] **Step 3: Confirm reachability to the object store independently of the sidecar**

```bash
ssh nas 'curl -sk -o /dev/null -w "%{http_code}\n" --max-time 5 https://s3.d.lcamaral.com/minio/health/live'
```

Expected: `200`. If not 200, the problem is network/TLS/Nginx-rproxy path from NAS →
Cloudflare-fronted or direct `s3.d.lcamaral.com`, not the sidecar itself — check
Nginx-rproxy vhost for `s3.d.lcamaral.com` and MinIO container health next.

- [ ] **Step 4: Confirm the metric itself, not just the alert label**

```bash
curl -s --max-time 5 "https://prometheus.d.lcamaral.com/api/v1/query" \
  --data-urlencode 'query=rate(thanos_objstore_bucket_operations_total{instance="thanos-sidecar-2",operation="upload"}[1h])' \
  | jq -c '.data.result'
curl -s --max-time 5 "https://prometheus.d.lcamaral.com/api/v1/query" \
  --data-urlencode 'query=time() - thanos_objstore_bucket_operations_total{instance="thanos-sidecar-2",operation="upload"} offset 5m' \
  | jq -c '.data.result'
```

This tells you exactly when the upload rate went to zero (cross-reference against Step
1's log timestamps and against Task 1/2's `terraform apply` — rule out "this stack
restarted for an unrelated reason and just hasn't shipped its first 2h block yet," which
is a false alarm, not an incident).

- [ ] **Step 5: Decide remediation based on findings**

No pre-written fix — branches on Step 1-4 results:

- UID mismatch → `chown` the volume to match container UID (check how PR #42/#44 fixed it
  originally: `git show <that PR's commit> -- terraform/portainer/stacks/*.tftpl` for the
  precedent) and/or fix the volume's `configs:`/mount definition in Terraform so it's not
  a one-off host fix.
- Network/TLS path broken → fix Nginx-rproxy vhost or MinIO container health, not Thanos.
- False alarm (stack just restarted, no real gap) → note in this doc, no code change,
  consider tuning `for: 30m` if restarts are routine enough to cause repeat false alarms.

---

### Task 4: Root-cause dual `PiholeExporterDown` (pihole-1 + pihole-2)

**Why:** both replicas down at the same time is a different shape than the known
single-instance FD-leak history (memory: exporter-1 spun for ~10d alone). Simultaneous
failure across two independent hosts smells like a shared cause (network path, DNS, or a
common dependency) rather than two coincidental leaks — worth ruling out before treating
it as "the same old bug."

**Files/hosts:** `pihole-exporter-1` likely on dockermaster, `pihole-exporter-2` — check
actual host (memory only confirms exporter-3 is on the NAS; verify 1 and 2's hosts before
SSHing to the wrong box).

- [ ] **Step 1: Locate both exporters and their current container state**

```bash
ssh dockermaster 'docker ps -a --filter "name=pihole-exporter" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
ssh nas 'docker ps -a --filter "name=pihole-exporter" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
```

- [ ] **Step 2: Logs for both**

```bash
ssh dockermaster 'docker logs pihole-exporter-1 --since 2h 2>&1 | tail -80'
# repeat for exporter-2 on whichever host Step 1 shows it on
```

Look for: the known FD-leak signature (repeated connection/scrape errors, `too many open
files`), vs. a clean "can't reach pihole-N:80" connection-refused (different failure
mode → points at the Pi-hole itself or the network path, not the exporter).

- [ ] **Step 3: FD count check (only if Step 2 shows leak-shaped errors)**

```bash
ssh dockermaster 'docker exec pihole-exporter-1 sh -c "ls /proc/1/fd | wc -l"'
```

Cap was raised to 65536 in commit `c496e31` — full exhaustion is less likely now, but a
climbing trend still indicates the same unfixed upstream leak in
`amonacoos/pihole6_exporter`, just with more runway before it wedges again.

- [ ] **Step 4: Rule out "Pi-hole itself is down" as the shared cause**

```bash
curl -sk -o /dev/null -w "%{http_code}\n" --max-time 5 https://pihole-1.d.lcamaral.com/admin/  # adjust to actual vhost/IP
curl -sk -o /dev/null -w "%{http_code}\n" --max-time 5 https://pihole-2.d.lcamaral.com/admin/
```

If both Pi-holes themselves respond fine but both exporters are wedged, that's strong
evidence for the exporter-side leak recurring on both independently (coincidence, not a
shared network cause) — the nightly Rundeck restart job (from `c496e31`) should already
be covering exporter-1; check whether it's also scheduled against exporter-2, since the
original fix commit may have only applied to one replica.

- [ ] **Step 5: cAdvisor CPU cross-check**

```bash
curl -s --max-time 5 "https://prometheus.d.lcamaral.com/api/v1/query" \
  --data-urlencode 'query=rate(container_cpu_usage_seconds_total{name=~"pihole-exporter-.*"}[15m])' | jq -c '.data.result'
```

Confirms/denies `PiholeExporterCpuRunaway` territory (>0.4 cores) alongside the `Down`
alert — if CPU is flat/low, this is a hang, not a spin, which points away from the known
leak signature and toward something else (e.g., DNS resolution failure inside the
container, or the scrape target being genuinely unreachable).

- [ ] **Step 6: Remediate**

If leak-confirmed and the nightly Rundeck reset isn't covering both replicas:

```bash
ssh dockermaster 'docker restart pihole-exporter-1'
```

(and the equivalent for exporter-2 on its actual host). This restart is the same action
the nightly Rundeck job already performs automatically — treat as pre-approved routine
remediation, not a novel destructive action. If root cause is something else (Step 4
showed the Pi-hole itself unreachable, or Step 2 showed a config/network error), fix that
specific cause instead and note findings here rather than blind-restarting.

---

### Task 5: Verify `WifiProbeHeapLow` (GARAGE-WIFI-PROBE) self-heals

**Why lower hands-on urgency despite `critical`:** memory confirms P23 self-healing OTA
(reboot_first + heap watchdog + rollback, fw 0.11.1) is live on all 3 probes including
garage. This task is "confirm the safety net worked," not "manually fix a fragmenting
device."

- [ ] **Step 1: Current heap state + firmware version**

```bash
curl -s --max-time 5 http://<garage-probe-ip>/status | jq '{fw_version, heap_largest_free_block: .heap.largest_free_block, heap_free: .heap.free}'
```

(Resolve `<garage-probe-ip>` — memory notes garage was "USB-flashed 2026-06-16" at fw
0.11.1; check the wifi-probe scrape target list in `locals.tf` for its current IP, it's
in the reserved `.42-.47` range per memory.)

- [ ] **Step 2: Trend check — is it recovering or flatlined?**

```bash
curl -s --max-time 5 "https://prometheus.d.lcamaral.com/api/v1/query_range" \
  --data-urlencode 'query=wifi_probe_heap_largest_free_block_bytes{room="garage"}' \
  --data-urlencode 'start='"$(date -u -v-2H +%FT%TZ 2>/dev/null || date -u -d '2 hours ago' +%FT%TZ)" \
  --data-urlencode 'end='"$(date -u +%FT%TZ)" \
  --data-urlencode 'step=5m' | jq -c '.data.result[0].values'
```

Expected one of: (a) climbing back above 32768 bytes → watchdog's reboot already fired,
self-heal working, alert will auto-clear, no action; (b) flat near/at the floor for the
full `for: 15m` window with no reboot → watchdog didn't trip, worth a manual `/reboot`
call and a look at whether the P23 threshold logic itself has a gap.

- [ ] **Step 3: If not self-healing, manual recovery**

```bash
curl -s --max-time 5 -X POST http://<garage-probe-ip>/reboot -H "Authorization: Bearer <token>"
```

(Token per the probe's session-cookie/token auth from memory — check
`docs/network/esp32-c5-wifi-probe.md` for the current auth mechanism before running.)

---

### Task 6: Sync ix0-watchdog cron via IaC + retire the hand-placed file

**Why P1, not P0:** the watchdog process is confirmed running right now (PID alive since
last Saturday per `ps aux`) via a **hand-placed** `/etc/cron.d/ix0-watchdog` file — this
works today but violates the repo's IaC-only rule, and nothing will restart the watchdog
if it dies before the next pfSense reboot. Not an active incident; it's debt with a
specific, already-understood cleanup path.

**⚠️ Approval gate:** Step 3 (`rm` on the production router) is a host-level destructive
action per `.claude/operating-rules.md` §2. State rollback and get explicit go-ahead
before running it, even though the risk is low (both cron entries are idempotent
"start-if-not-running").

- [ ] **Step 1: Confirm current state (read-only)**

```bash
ssh pfsense 'grep -i ix0 /etc/crontab; echo "---"; cat /etc/cron.d/ix0-watchdog; echo "---"; ps aux | grep "[i]x0-watchdog"'
```

Expected (as of this plan's research): `/etc/crontab` has no ix0-watchdog line yet;
`/etc/cron.d/ix0-watchdog` has the hand-placed `* * * * * root
/usr/local/sbin/ix0-watchdog.sh start`; a watchdog process is running. If any of this has
changed since 2026-07-01, re-derive the plan from what's actually there instead of
assuming this doc is still accurate.

- [ ] **Step 2: Sync the IaC cron entry (from Task 1's already-committed `cron-jobs.yml`)**

```bash
./scripts/sync-pfsense-cron-jobs.py --diff   # check the script's actual flag name first: --help
./scripts/sync-pfsense-cron-jobs.py
```

Verify:

```bash
ssh pfsense 'grep -i ix0-watchdog /etc/crontab'
```

Expected: the new `* * * * * root /usr/local/sbin/ix0-watchdog.sh start >/dev/null 2>&1`
line now present in `/etc/crontab`.

- [ ] **Step 3: STOP — get explicit go-ahead, then retire the legacy file**

Present to user: "About to `rm /etc/cron.d/ix0-watchdog` on pfSense (production router).
Rollback: the file's full content is captured in this plan's Step 1 output above — can be
recreated by hand in under a minute if something regresses. The replacement entry in
`/etc/crontab` (Step 2) is already live and doing the same job, so this is cleanup, not a
functional change. OK to proceed?"

After go-ahead:

```bash
ssh pfsense 'rm /etc/cron.d/ix0-watchdog'
```

- [ ] **Step 4: Confirm no gap in watchdog coverage**

```bash
sleep 90  # let /etc/crontab's minutely entry fire at least once
ssh pfsense 'ps aux | grep "[i]x0-watchdog"'
```

Expected: still exactly one watchdog process running (the existing one, untouched — the
cron entry is "start if not running," so it's a no-op while the process is already
healthy). If the process is gone and doesn't come back within 2 minutes, manually run
`ssh pfsense '/usr/local/sbin/ix0-watchdog.sh start'` and investigate why the cron entry
didn't pick it up (check `/etc/crontab` syntax from Step 2 was written correctly).

---

### Task 7: Decide — Telegram private DM vs. group/channel

**Not an investigation — a question.** Current state: `chat_id` in
`secret/homelab/telegram/alertmanager` resolves to a private 1:1 chat with
`@OLHomeLabAlertsBot` (confirmed via live `getChat`), not a group or channel, despite
being described as "the alerts channel." message_id reached 28 on the verification ping,
implying ~27 prior messages already in that thread.

**Option A — keep as-is.** Zero work. Fine if you're the only intended recipient and a
DM is where you'll actually see it (e.g., pinned chat on your phone).

**Option B — migrate to a group/channel** (lets other household members, or a
phone-widget/pinned-channel view, see alerts too):

1. In Telegram: create a group (or channel), add `@OLHomeLabAlertsBot` as a member (channels
   require adding it as admin for it to post).
2. Send any message in the new group so the bot receives an update, then:

   ```bash
   curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" | jq -c '.result[].message.chat'
   ```

   to read the new `chat_id` (negative for a group, `-100…` for a channel/supergroup).
3. `vault kv put -mount=secret homelab/telegram/alertmanager bot_token=<unchanged> chat_id=<new id>`
4. `terraform apply` (re-renders both alertmanager stacks' `configs:` with the new
   `chat_id`) — but per memory `feedback_portainer_stack_redeploy.md`, the Portainer
   provider does **not** recreate a running container on a `configs:`-only diff. Follow
   with `./scripts/portainer-redeploy.py alertmanager` (or manual stack stop+start via the
   Portainer API for both `alertmanager` and `alertmanager-2` stacks) or the new `chat_id`
   silently won't take effect despite `terraform apply` reporting success.
5. Re-run this plan's Telegram verification (Vault field check → `getMe` → `getChat` →
   one `sendMessage` test) against the new `chat_id` to confirm before trusting it.

---

## Self-review

- **Coverage:** all 7 items from the prior verification pass have a task here — 5 live
  investigations (2-5 include Task 2 which is fix-not-just-investigate), 1 hygiene
  (commit), 1 decision (chat_id). Nothing dropped.
- **Placeholders:** Task 2 has a fully-specified diff (no "add appropriate exclusion"
  hand-waving) because the fix was fully derivable from code already read during
  research. Tasks 3-5 intentionally end in "decide based on findings" branches rather
  than a fabricated fix, because the root cause is genuinely unknown — inventing a fix
  for an uninvestigated bug would violate systematic-debugging (fix after diagnosis, not
  before).
- **Consistency:** `blackbox_rproxy_ws_targets` (Task 2) is named to parallel the existing
  `blackbox_rproxy_targets`; `tcp_connect` module reused verbatim from
  `locals.tf:1032-1034` rather than inventing a new module name.
