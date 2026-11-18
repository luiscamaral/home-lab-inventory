# Parked projects

A parked project is work that is not merged into `main` and is not being built now.
It is not abandoned. This register keeps it from being forgotten.

## Rule for agents

Read this register:

- at the start of every session, after the operating rules
- each time you re-anchor on a long session
- before any task that touches an area named below

If a task touches a listed area, say so to the user before you start. Do not delete the branch of a parked
project. The branch can be the only copy of the work.

## Register

| Project | Status | Branch | Areas it touches | Record |
| --- | --- | --- | --- | --- |
| Homelab login portal | **Live**, source unmerged | `custom-login-portal` | Keycloak, `login.cf`, Portainer stacks `homelab-portal` and `homelab-portal-2` | [homelab-login-portal.md](homelab-login-portal.md) |
| Homelab platform (CUE catalog) | Designed, not started | `custom-login-portal` | Nginx vhosts, service catalog, generated config | [homelab-login-portal.md](homelab-login-portal.md#other-work-on-the-branch) |

## How to park a project

1. Close the PR with a comment that links the record.
2. Write a record in this folder: what it is, its state, where the work lives, and how to restart.
3. Add a row to the table above.
4. Keep the branch.

## How to restart a project

Open a new worktree from fresh `origin/main`. Bring the work over in small PRs. Do not reopen an old
mixed PR. Follow rule #1 in `.claude/operating-rules.md` for every change.
