# Agent instructions — homelab inventory

All AI agents (Claude Code, pi, Codex, Devin, sub-agents) must follow
[`.claude/operating-rules.md`](.claude/operating-rules.md) before doing anything else.
[`CLAUDE.md`](CLAUDE.md) has the project context.

## RULE #1 — PR → merge → apply from `main`

1. Branch (worktree) from an up-to-date `origin/main`.
2. Change the declarative source, run local checks and a plan or dry run, then commit.
3. Push and open a PR to `main` that lists the targets, the expected diff and the rollback.
4. Wait until all required CI checks pass, then squash-merge.
5. Apply **only** from a clean checkout of merged `main`, and only the diff this PR
   introduced. Use `-target` and report any other drift.
6. Verify the live result. Commit the evidence locally and post a summary on the PR.

Never apply from a feature branch, and never change live infrastructure before the merge.
The local clone is the repo. A local commit saves work and evidence, with no PR. Open a PR only
to change `main`: for anything you will apply, and for sources, scripts, rules or docs that must
be on `main`. Never open a PR that holds only evidence. Add it to the next PR for the same work.

The only exception to the order above is break-glass with explicit user approval, followed by a
`post-hoc` PR in the same session.

## Parked projects

Read [`docs/projects/README.md`](docs/projects/README.md) at the start of every session and before
work on any area it lists. Never delete the branch of a parked project.
