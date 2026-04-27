# 09 — Open Questions (Decisions Required)

> **ANSWERED (2026-04-24).** See [DECISIONS.md](./DECISIONS.md) for the
> locked-in choices. The questions below are retained for historical
> context and to explain the *why* behind each decision when you come
> back to this plan months from now.
>
> **Headline answers:**
> - **Q1** Retention = B (frugal) — 7d local, 90d/1y/2y tiers, ~200 GB
> - **Q2** Scrape cadence = B — 15s infra / 60s IoT + blackbox
> - **Q3** HA topology = B — `prometheus-2` on NAS (Proxmox-independent)
> - **Q4** Object store = A — reuse existing MinIO
> - **Q5** Alert channels = Email via postfix-relay
> - **Q6** SSO = A — Keycloak OIDC
> - **Q7** Thanos Ruler = B — deploy, single instance on ds-2
> - **Q8** HA scrape token = A — dedicated `prometheus-scrape` token
> - **Q9** pfSense 15-min reload = B — proceed; investigate later

---

These were the decisions only you could make. Each shaped the plan in a
concrete, often irreversible way. Retained below for context and for
the next person (or future you) trying to understand *why*.

---

## Q1 — Retention policy

Pick how far back each resolution keeps data. Trade-off is MinIO
storage cost vs. ability to answer "why did this spike 9 months ago?".

| Tier | Option A (defaults) | Option B (frugal) | Option C (lavish) |
|---|---|---|---|
| Local Prometheus raw | 15 d | 7 d | 30 d |
| Thanos raw | **180 d** | 90 d | 365 d |
| Thanos 5m downsample | **730 d** | 365 d | 1095 d (3 y) |
| Thanos 1h downsample | **1825 d** (5 y) | 730 d | 3650 d (10 y) |
| Estimated MinIO footprint | ~400 GB yr 1 | ~200 GB | ~900 GB |

**Shape-changer:** this drives MinIO capacity and Compactor tuning. No
right answer — depends on what you care about.

## Q2 — Scrape cadence

Default is 15s across the board. Options:

- **A.** 15s everywhere (standard, highest resolution).
- **B.** 15s for infra (T0/T1/T2) + 60s for IoT/blackbox (lower
  cardinality storage cost).
- **C.** 30s everywhere (cuts storage ~2×, loses micro-blip visibility).

**Impact:** series rate at Prometheus, MinIO growth rate, alert
timing. A bursty 10s problem disappears at 30s.

## Q3 — HA topology for both Prometheus replicas

Both Prometheus currently would live on `ds-1` + `ds-2`, which **share
the same Proxmox hypervisor**. If proxmox dies, both go.

- **A. Accept the risk.** They fail-together in most homelab failure
  modes anyway (power, network). Simplest.
- **B. Move one replica to the NAS.** Runs `prometheus-3` on the
  Synology as a Docker container. Adds geographic redundancy.
- **C. Dedicate a new VM** on a future second-hypervisor (no second
  hypervisor exists today — this is a "not now" option).

**Recommendation:** A for now, with a note to revisit when you
actually get a second hypervisor.

## Q4 — Object-store placement

- **A. Reuse existing MinIO.** Bucket `thanos` inside existing
  `minio` (ds-1) + replicated to `minio-2` (ds-2). Lowest effort.
- **B. Dedicated MinIO instance.** New stack `minio-thanos` purely
  for blocks. Isolates capacity & blast radius. More ops overhead.
- **C. Thanos S3-compatible only, point at NAS-native S3** (Synology's
  object-store package if you have it). Different failure domain.

**Recommendation:** A. Revisit at 75% MinIO utilization.

## Q5 — Alert routing channels

Where should alerts go? Answer can be multi-channel by severity.

- [ ] Email (via your existing `postfix-relay`)
- [ ] Telegram (bot + chat_id — you'd create a bot via @BotFather)
- [ ] Discord (webhook URL — you'd create a server)
- [ ] Slack (webhook URL — requires a workspace)
- [ ] None / Grafana-only (just the UI shows alerts; no push)

Also: **critical** vs **warning** — same channel or split?

**Shape-changer:** some channels require creating accounts / bots.

## Q6 — SSO for Grafana

- **A. Keycloak OIDC** (recommended — fits the existing pattern).
- **B. Grafana's built-in username/password only.**
- **C. Delegate to Cloudflare Access** on top of the tunnel — pure
  email whitelist, no Keycloak dep for this one service.

**Recommendation:** A. Homelab already uses Keycloak for other
services.

## Q7 — Should we deploy Thanos Ruler?

- **A. No.** Use Prometheus-native alert rules only.
- **B. Yes.** Needed for alerts over long time windows.

**Chosen: B — deploy Ruler, single-instance on ds-2.**

- Prometheus-native rules stay for short-window critical alerts
  (fire from both replicas, dedupe at AM cluster).
- Ruler handles long-window trend rules (cert expiry, capacity growth).
- Accepted trade-off: if ds-2 is down, Ruler-sourced alerts do not
  evaluate. Documented in runbook.

## Q8 — Home Assistant scrape token

- **A. Create dedicated metrics token** with a limited-scope HA user
  (e.g., admin-read-only). Rotated independently from the
  `HA-TOKEN` currently in your Keychain.
- **B. Reuse existing `HA-TOKEN`** (broader scope; simpler; less
  secure if leaked because it can write too).

**Recommendation:** A. Small effort, big blast-radius reduction.

## Q9 — Bonus: quarter-hourly filter reload

Pre-existing (not monitoring-project scope, but found during
investigation): pfSense reloads firewall every 15 minutes via cron.
Source unidentified — pfBlockerNG update, dyndns cron, or custom.

- **A. Find and fix before starting.** Avoids muddying baselines.
- **B. Proceed; investigate later.** Document current metric noise as
  expected.

**Recommendation:** A, because dashboards built during B will show
flaps that then "go away" after the fix, creating distracting
dashboard ghosts.

---

## Template to copy into `DECISIONS.md`

```markdown
# DECISIONS — prometheus-thanos-monitoring

## Q1 Retention
Chosen: <A/B/C> — <optional notes>

## Q2 Scrape cadence
Chosen: <A/B/C>

## Q3 HA topology
Chosen: <A/B/C>

## Q4 Object store
Chosen: <A/B/C>

## Q5 Alert channels
Critical: <channel>
Warning: <channel>
Info: log-only / <channel>
(Any channels requiring new account / bot creation: <list>)

## Q6 SSO
Chosen: <A/B/C>

## Q7 Thanos Ruler
Chosen: <A/B>

## Q8 HA scrape token
Chosen: <A/B>

## Q9 pfSense 15-min reload
Chosen: <A/B>
```
