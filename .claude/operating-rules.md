# ⛔ Operating non-negotiables — homelab inventory

Read this before ANY infrastructure change. It overrides speed/convenience.
Auto-loaded at session start. The IaC-guard `PreToolUse` hook that re-surfaced these on risky Bash
commands was **removed 2026-08-18**, so there is no tool-time gate any more — these rules are
self-enforced, which matters most in long sessions where context decays.
This file is the single source of truth — CLAUDE.md and AGENTS.md point here.
**Applies to every AI agent and every session** (Claude Code, pi, Codex, Devin, sub-agents, …),
including sessions already running when this rule was adopted (2026-11-08).

## 1. RULE #1 — PR → merge → apply from `main`. No exceptions without explicit approval.
Every change to this repo **and** every change to live infrastructure follows this order.
No step may be skipped or reordered.

1. **Branch.** Create a worktree and branch from an up-to-date `origin/main`
   (`git fetch && git worktree add -b <type>/<topic> .worktrees/<topic> origin/main`).
   Never base work on another unmerged branch.
2. **Change + check locally.** Edit the declarative source. Run pre-commit,
   `terraform fmt`/`validate`, and a **plan or dry run** of the apply tool. Commit.
3. **PR.** Push, then `gh pr create --base main`. The PR body lists the apply targets, the
   expected diff, and the rollback.
4. **Merge.** Wait until **all required CI checks pass**, then squash-merge
   (`gh pr merge --squash --admin`; the admin flag only bypasses the solo-maintainer review
   requirement, **never failing checks**).
5. **Apply from merged `main` only.** Use a clean, detached checkout of the merge commit
   (`git fetch && git worktree add --detach .worktrees/apply-main origin/main`, or
   `git -C .worktrees/apply-main checkout --detach origin/main`). Never apply from a
   feature branch, an unmerged worktree, or a dirty tree.
   - Plan first. Apply **only the diff this PR introduced**. If the plan shows any other
     change (drift from unmerged or hand-made live changes), do **not** apply it: use
     `-target` for this PR's resources and report the drift to the user.
   - Portainer Terraform state is local: pass
     `-state=<main worktree>/terraform/portainer/terraform.tfstate` and back it up first.
   - Run `terraform init` in the apply checkout so it uses the **committed**
     `.terraform.lock.hcl`. Never symlink or borrow another checkout's `.terraform`, which
     may hold different provider versions than the ones that wrote the shared state.
6. **Verify + record.** Check the live result, then post the evidence as a PR comment
   (the plan shows "No changes", health checks, and so on).

**Prohibited:** applying anything (`terraform apply`, `scripts/sync-*.py --apply`,
`scripts/portainer-redeploy.py`, API or SSH changes) before its PR is merged. Also
prohibited: leaving applied changes unmerged, and merging with red checks.
"Apply" covers every tool in the table in section 2, not only Terraform.

**Docs-only or rule-only changes** still go through steps 1–4 (no apply step).

**Emergency exception (break-glass):** only when the user explicitly approves *that specific*
out-of-order action in the current session (e.g. an outage fix). Afterwards, open the PR in
the same session, label it `post-hoc` in the title/body, merge it, and confirm that a plan
from `main` shows no changes.

## 2. IaC only — never touch a host/router config directly
Every change goes through a declarative source in the repo, then a tool applies it.
**IaC is NOT only Terraform.** Map of surface → source → apply:

| Surface | Declarative source | Apply with |
|---|---|---|
| Portainer stacks, Cloudflare, Vault config | `terraform/<domain>/` | `terraform apply` |
| pfSense (cron, scripts, ACME, host-overrides) | `pfsense/*.yml`, `pfsense/scripts/` | `scripts/sync-pfsense-*.py`, `scripts/sync-host-*.py` |
| Rundeck jobs | `rundeck/jobs/*.yaml` | API import (see `rundeck/README.md`) |
| DNS zones | pihole `dnsmasq.d/*.conf` via Compose `configs:` | `terraform/portainer` |
| Grafana dashboards | `terraform/portainer/stacks/grafana-dashboards/*.json` | terraform + `scripts/portainer-redeploy.py` |
| NAS kernel tuning (sysctl) | `nas/tuning/sysctl.yml` | `scripts/sync-nas-tuning.py` |
| Docker daemon config | `hosts/<host>/etc/docker/daemon.json` | `scripts/sync-docker-daemon.py` |

**Never** SSH in and edit `config.xml`, run `write_config`, hand-place a cron/script,
or scp config to a host. If a surface has no IaC path yet, **add one** (declarative
source + sync) — do not make the change manually.

## 3. Destructive / host / network changes need approval FIRST
Link bounces (`ifconfig down/up`), `pfctl -F/-d`, `docker rm -f`, VM/LXC stop, reboots,
disk ops: present options + rollback, get explicit user approval **before** acting.

## 4. Before any mutating action, state five things
which merged PR (rule #1) · which IaC mechanism · is it destructive/host-level? · rollback · approved?

## 5. Re-ground when context gets polluted
When scope grows past the original ask, or several changes pile up, **STOP and re-read
this file** before continuing. Long sessions dilute these rules — re-anchor deliberately.

## 6. Secrets: Vault only
`vault.d.lcamaral.com` round-robins across rproxy IPs and flaps if one is dead — use the
direct address `http://192.168.59.25:8200` when it times out. Never hardcode secrets.
