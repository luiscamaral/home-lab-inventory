# Homelab login portal (parked)

Parked on 2026-11-18 by the owner. PR [#6](https://github.com/luiscamaral/home-lab-inventory/pull/6) was
closed without merging. This record replaces it.

## Warning: the live portal has no source on `main`

The portal is deployed, but its source code lives only on the branch `custom-login-portal`.
`.gitignore` ignores `apps/` on `main`, and `main` has no `apps/` files.

- Never delete `custom-login-portal`, locally or on `origin`. It is the only copy of the source.
- The image is served from zot as `zot.d.lcamaral.com/homelab/homelab-portal:latest`. Without the branch,
  the project cannot rebuild it.
- A first restart task is to give the source a permanent home. See "Open decisions".

## What it is

A SvelteKit 5 web app at `https://login.cf.lcamaral.com`. It offers login, registration, password reset,
and profile edits. Keycloak is the back end. Its `realm` is `homelab` and its client is `homelab-portal`.

From the PR description:

- Login uses the OAuth2 password grant. Registration uses the Keycloak admin API.
  Profile edits use the account REST API.
- Sessions use HTTP-only cookies with AES-256-GCM and a signature check (`jose`).
- The container is a multi-stage build on `node:24-alpine`.
- Routes: `/`, `/login`, `/register`, `/forgot-password`, `/profile`, `/auth/logout`, `/healthz`.

## State

| Item | State | Source |
| --- | --- | --- |
| PR #6 | Closed 2026-11-18. It was a draft with conflicts: 32 commits, 86 files, +10,424 and -9 lines. | GitHub |
| Branch head | `a1ca9c8`, last commit 2026-04-11 | Git |
| App source | `apps/homelab-portal/`, last changed 2026-04-10, on the branch only | Git |
| Stacks | `homelab-portal` (dockermaster) and `homelab-portal-2` (ds-1), in `terraform/portainer/stacks.tf` | `main` |
| Inventory | Records both replicas as stateless, with session state in cookies | `inventory/docker-containers.md` |
| PR test plan | None of the boxes were ticked | PR #6 |

The stack and inventory rows come from files on `main`. Nobody checked the running services when this
record was written.

## Why it was closed

The PR mixed several unrelated changes with the portal. It conflicts with `main`, which gained
hundreds of commits after the PR was opened. A mixed PR of this size cannot be reviewed or merged safely.

## Other work on the branch

The branch also holds design documents that are not on `main`:

- `docs/superpowers/specs/2026-04-11-homelab-platform-design.md`: a CUE-based platform. One schema and one
  file per service. Each file produces DNS, Nginx, stack, and monitoring configuration. Status in the file: Approved.
- `docs/superpowers/plans/2026-04-11-homelab-platform-sp1-nginx.md`: the plan for the first of five
  sub-projects. No `platform/` directory exists on the branch or on `main`, so none of it was built.
- Specs and plans for the portal and for Watchtower, dated 2026-04-09 to 2026-04-10.

The platform design may overlap with later work on `main`, such as the Nginx vhosts in git. Review it
against current `main` before you reuse any of it.

## Open decisions

1. Where does the portal source live? Options: its own repository, or a tracked directory on `main` with
   the `apps/` ignore rule changed. The owner decides.
2. Does the platform design still apply? Review it against the current Nginx and Terraform layout.
3. Is the OAuth2 password grant still the right login method? Review it against the current Keycloak
   hardening in `docs/keycloak-security.md`.

## How to restart

1. Make a worktree from fresh `origin/main`.
2. Move the source out of the branch into its chosen home. Do not carry over unrelated files.
3. Open small PRs, one per concern. Follow rule #1 in `.claude/operating-rules.md`.
4. Before you change a live stack, check the running state first.
