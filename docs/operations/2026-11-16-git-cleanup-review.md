# Git closure and cleanup review

## Scope and time

Review date: 2026-11-16 in America/Denver. Evidence uses UTC on 2026-11-17.

The main survey ran at 00:23–00:30 UTC. It checked GitHub and local Git records, not live infrastructure.
The reference was `origin/main` at `18786b56395a9c43003022965ee224a748bee6dd` after a fresh fetch.

The survey covered 150 local branches, 146 remote branches, 69 worktrees, three stashes, and all 143 pull requests.
GitHub reported seven open PRs, 124 merged PRs, 12 closed PRs, and zero open issues. [E1–E5]

Other agents were working during this review. A later snapshot found 152 local branches and 71 worktrees.
The two new worktrees hold Omada static-IP and switch SNMP work. Treat both as active, not cleanup targets. [E13]

A final GitHub check at 00:33:52 UTC found nine open PRs.
The two new PRs, #148 and #149, belong to that active work. [E13]

This agent did not merge, commit, check out, delete, change stashes, or change infrastructure.
This agent refreshed remote refs and wrote these review files. It did not prune refs.

## What can close now

### Historical branch tasks

Of the original 150 local branches, 130 have evidence that their work reached `main`.
This uses merged PR head hashes, ancestry within those PRs, or patch matches from `git cherry`.
Their historical merge tasks can close without opening another PR. [E6]

This does not authorize deleting branches. Project rules require keeping them unless the user requests deletion.
It also does not prove that their changes remain deployed today.

Plain `git branch --merged` is not enough here. Only five local tips are Git ancestors of `origin/main`.
Squash merges explain much of the difference. [E3, E6]

The full branch list and the reason for each decision are in `local-closure-register.json`.

### Open pull requests

No reviewed PR is ready for an unconditional merge now.
All six dependency PRs are mergeable, but GitHub reports them as `behind`.
Main requires branches to be current and seven required checks to pass.
Their green check results date from May or July, not this review. [E1, E2, E5]

| PR | Change | Next action |
|---|---|---|
| [#54](https://github.com/luiscamaral/home-lab-inventory/pull/54) | upload-artifact v7 | Update from main and rerun checks with #55. |
| [#55](https://github.com/luiscamaral/home-lab-inventory/pull/55) | download-artifact v8 | Review and test the upload/download pair. |
| [#56](https://github.com/luiscamaral/home-lab-inventory/pull/56) | checkout v6 | Update from main and rerun checks. |
| [#57](https://github.com/luiscamaral/home-lab-inventory/pull/57) | github-script v9 | Review script API changes, then update and test. |
| [#58](https://github.com/luiscamaral/home-lab-inventory/pull/58) | codeql-action v4 | Update from main and rerun checks. |
| [#63](https://github.com/luiscamaral/home-lab-inventory/pull/63) | commitlint CLI 21.2.1 | Fix Node requirements before merging. |
| [#6](https://github.com/luiscamaral/home-lab-inventory/pull/6) | Login portal | Owner decision: close as abandoned or restart from current main. |
| [#148](https://github.com/luiscamaral/home-lab-inventory/pull/148) | Omada VM static IP | New during review. Keep with its owner for review and CI. |
| [#149](https://github.com/luiscamaral/home-lab-inventory/pull/149) | Switch SNMP metrics | New during review. Keep with its owner for review and CI. |

PR #6 is a draft with conflicts. It contains 32 commits across 86 files.
Do not merge it as cleanup. Age alone does not prove abandonment. [E2]

PRs #148 and #149 were mergeable but blocked at the final snapshot.
This review did not assess their full code or approve their deployment. [E13]

The registered runner reports version `2.338.2`. That exceeds the documented checkout v6 runner requirement of `2.329.0`.
This checks the GitHub registration, not the container image or host runtime. [E5, E8]

PR #63 changes only `package.json`. Commitlint 21.2.1 requires Node `>=22.12.0`.
The workflow sets Node 20, while `package.json` claims Node `>=18.0.0`.
Other commitlint 21 packages already have the higher requirement. Align these together.

The workflow installs global, unpinned commitlint packages, so it does not test the exact declared dependency set. [E8, E9]

## Cleanup priorities

### 1. Fix runner labels before releasing queued health jobs

Workflow jobs request `[self-hosted, dockermaster]`.
The only registered runner is online and idle, with the custom label `dockerserver-1`, not `dockermaster`.
The runner stack declares that same label set. [E5, E9]

Eight Service Health Monitor runs were queued at 00:28 UTC.
A sampled queued job requests the unmatched labels. One queued run dates from May. [E10]

Update workflow selectors through a PR, or change the managed label definition after reviewing its meaning.
Review queued runs before enabling a match. Some workflow jobs can restart services or perform deployments.
Cancel obsolete runs only after approval. Do not relabel the runner merely to drain the queue.

### 2. Make the security gate fail when a required scan fails

Run `43835539553` shows failed Secret Detection and successful Security Gate. [E10]
The gate uses `if: always()`. It checks available reports but does not reject failed scan jobs.
Missing secret reports skip the secret check. JSON parse errors fall back to a count of zero. [E9]

Require successful scans and valid expected reports. Keep any allowed skip rules explicit.
No secret leak is confirmed here. This review did not read failure logs or SARIF findings.

The latest sampled main security run succeeded. That does not remove the gate defect. [E4, E10]

### 3. Stop new work from starting on the stale shared checkout

The shared checkout is still at `6104e15` on `fix/ds2-portainer-agent-ip-collision`.
It is 54 commits behind its tracking branch and differs from current main across many files.
Its local operating rules lack the newer PR-first and NFS requirements. [E3, E7, E12]

Use a new worktree from refreshed `origin/main` for each cleanup PR.
Do not reset or switch the shared checkout while other agents use it.

### 4. Finish active work as separate commits and PRs

Network incident reports and raw evidence remain untracked in the shared checkout.
A later snapshot found the SNMP Terraform changes in `.worktrees/switch24a-snmp`.
That worktree includes the stack-template rename, Vault wiring, generated SNMP files, and network evidence. [E3, E13]

Confirm ownership before moving files. Split incident records from deployable SNMP changes where possible.
Review secrets and generated files before committing. Do not use `git add .` on the shared checkout.

### 5. Do not recommit stale local files

The untracked `hosts/nas/drive-versioning.md` is older than the version already merged into main.
It still proposes 120 days for both folders. Main records 120 days for homes and 30 for sharedCloudStation.
Preserve any unique notes, then remove the duplicate only with approval. Do not overwrite main with it. [E7]

Main already ignores `.pi/`. Its untracked appearance comes from the stale checkout.
Do not commit Herdr runtime mappings or open a duplicate ignore-rule PR. [E7, E12]

### 6. Retire unused worktrees, not branch history

The first worktree survey found 68 clean worktrees and one dirty shared checkout.
Of these, 62 clean worktrees match completed work or detached commits already in main. [E3, E11]

They are review candidates, not approved removals. Confirm that no agent uses each path.
Inspect ignored files before removal. The worktree tree used about 3.2 GiB, not all of which is disposable. [E7]

Protect Terraform state in the main checkout and `.worktrees/prometheus-thanos-plan`.
That second worktree looks clean to Git but contains local state and backups.
31 surveyed worktrees contain Terraform caches, state, plans, or actual environment files.
Tracked `.env.example` templates are excluded from that count. [E11]

The dry-run worktree prune proposed no removals. All registered paths existed in the survey.
This is mostly worktree retirement, not stale registration pruning. [E12]

### 7. Review the three stashes

| Stash | Contents | Decision |
|---|---|---|
| `stash@{0}` | Switch/Omada plan edits | Compare with current network work before closing. |
| `stash@{1}` | Image-pin pre-commit hook | Main already has this hook. Candidate for closure after a final comparison. |
| `stash@{2}` | Broad April work | Preserve and review separately. It includes an untracked-file parent. |

The third stash includes 94 changed tracked paths and 14 saved untracked paths.
Do not pop it into the active checkout or discard it because it is old. [E7, E12]

### 8. Fix the confirmed stale project instruction

`CLAUDE.md:14` says Rundeck jobs are not implemented and no `rundeck/` directory exists.
Main contains `rundeck/README.md` and nine job files.
Correct that statement through a docs-only PR. File presence does not prove live jobs match them. [E7]

## Further maintenance work from the parallel review

The parent agent rechecked these suggestions against the same audited main commit after the parallel review finished.
These are source findings, not runtime failures. No setup, test, lint, or deployment command ran during that recheck. [E15]

| Area | Confirmed source finding | Next cleanup |
|---|---|---|
| Root documentation | Main has no root `README.md`. Python metadata and PR documentation checks expect it. | Add a short project entry point, or align the checks and metadata with another document. |
| Local lint scope | `Makefile:169,192,223,310` searches do not exclude `.worktrees/`. Markdown uses an unquoted `**/*.md` pattern. | Use explicit tracked-file lists or safe exclusions. Match the intended CI scope. |
| Test coverage | Main contains six Python test files and the watchdog shell test. The pre-commit hook runs only the two NOMAD test files. | Add explicit checks for the other four Python files and the watchdog test after reviewing their setup. |
| Hook setup | `package.json:51` and `setup-commitlint.sh:61–65` use `husky install` and `husky add`. Hooks retain the legacy bootstrap line. | Align setup with the declared Husky 9 version. Test it in an isolated checkout. |
| Historical inventory links | The superseded `docs/service-matrix.md` points readers to a missing Compose `STATUS.md`. | Fix the redirect to current inventory and Terraform sources. Keep the historical record. |
| Stale TODO comments | Prometheus templates render MinIO and Watchtower token files, while `locals.tf` still calls that wiring a TODO. | Update the comments to describe the implemented wiring. Do not change tokens or scrape settings as documentation cleanup. |
| Duplicate host sources | Two network shim files match exactly. Two Vault unseal script copies differ by three added lines. | Identify each deploy consumer, choose a source, and test it before removing duplicates. |
| Old validation output | Calibre validation output carries a 2025 timestamp and an old deployment procedure. | Mark it as historical. Verify external build consumers before retiring the old Calibre Dockerfile or scripts. |
| Generated records | Main tracks monitoring design snapshots under `generated/`. | Review references and move retained records into a clear archive. Do not delete evidence by age alone. |

The peer suggested broad archival and deletion. This review does not approve either.
The peer also described test coverage too broadly. The existing NOMAD regression hook must stay in place. [E15]

## Branches that still need a decision

19 original local branches need manual review. The portal branch is a separate open-PR decision. [E6]

| Branches | Review path |
|---|---|
| `fix/ops-github-runner` | Small runner-image pin absent from main. Review with runner-label cleanup. |
| `feat/storage-policy` | Three unmatched commits add a storage register, guard, and HA runbook. Recheck proposed exceptions against the current NFS rule. |
| `fix/freeswitch-pin-dhcp-write-path` | Image pin/log cap and DHCP writer work need separate current-main reviews. |
| `fix/calibre-version-bump`, `fix/calibre-gui-supervision` | Extract useful GUI supervision changes. The old branch has an older image and reverses newer settings. |
| `fix/ops-ds1-log-rotation` | Main has the log settings at the newer `hosts/` path, plus registry mirrors. Likely superseded, not a fresh apply. |
| `fix/ops-ds2-agent-ip` | Main already uses `.59`. The remaining source difference is an explanatory comment. Likely superseded. |
| `feat/circunflexo-dns-root` | Terraform paths match main. Review the two remaining documentation differences before closure. |
| `fix/iac-followups` | Branch differs from its merged PR head. Review the two later commits. |
| `docs/network-resilience-redesign`, `fix/ix0-optic-flap-handoff`, `fix/ix0-watchdog-safety` | Compare remaining patches with the active network investigation and current watchdog. |
| `feat/minio-tfstate-access`, `feat/pfsense-dhcp-static-mappings`, `feat/pfsense-p2p-scavenger-shaper` | Separate unique patches from older combined work before deciding. |
| `fix/github-runner-image-pin`, `fix/grafana-oauth-disable-keycloak-down`, `fix/rundeck-db-off-nfs` | Review as historical incident branches. Do not restore old workarounds automatically. |
| `backup/zot-registry-pre-rebase` | Retain as a recovery branch. Four non-merge patches do not match main individually. |

Patch mismatches do not prove missing features. Squashes, renamed paths, and later replacements need human review.
Do not merge these branches wholesale or restore old storage migrations. NFS remains the required storage architecture. [E6, E7, E12]

## Suggested order

1. Confirm active owners and isolate the network/SNMP work.
2. Repair the security gate and review the runner-label mismatch.
3. Align Node and commitlint, then refresh the six dependency PRs.
4. Close covered historical tasks and decide the portal draft.
5. Review the small unmatched branches and stashes.
6. Remove approved inactive worktrees after protecting ignored state. Keep branches.
7. Fix stale instructions and document remaining decisions.

Each code or rule change needs a branch, local checks, a PR, and green required CI.
Infrastructure changes also need an approved plan, rollback, and apply from merged main.

## Limits

No SSH, Terraform plan, service probe, or host API check ran here.
This review does not establish deployment status, infrastructure health, or current host configuration.
It did not run project tests or inspect every historical TODO.
The local Gitleaks scan did not run because its Mise shim lacked a configured version.
No tool installation or global tool change followed. [E14]
Active work can change branch, worktree, and PR counts after these snapshots.

## Evidence index

All files below are under `docs/operations/evidence/2026-11-16-git-cleanup/`.
Each record includes its collection time, source, command or method, and relevant output.
State and environment file contents were not collected.

| Ref | Files |
|---|---|
| E1 | `open-prs.json`, `all-prs.json`, `open-issues.json` |
| E2 | `pr-details.json` |
| E3 | `initial-local.json`, `remote-heads.json`, `branch-analysis.json`, `worktree-analysis.json` |
| E4 | `recent-runs.json` |
| E5 | `github-controls.json` |
| E6 | `branch-disposition.json`, `unresolved-branches.json`, `local-closure-register.json` |
| E7 | `cleanup-checks.json`, `source-comparisons.json`, `next-work-source.json`, `stash-and-archive.json`, `stale-checkout-source.json` |
| E8 | `dependency-requirements.json` |
| E9 | `workflow-source-excerpts.json` |
| E10 | `actions-backlog.json` |
| E11 | `protected-local-artifacts-filtered.json`, `worktree-review-candidates.json` |
| E12 | `final-safety-checks.json` |
| E13 | `concurrent-changes.json`, `final-open-prs.json` |
| E14 | `validation-limits.json` |
| E15 | `peer-tooling-verified.json` |
