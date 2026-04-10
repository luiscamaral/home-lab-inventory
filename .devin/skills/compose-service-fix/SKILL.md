---
name: compose-service-fix
description: Work on a specific Dockermaster compose service, make local repo changes, and prepare safe rollout steps
argument-hint: "<service> <change request>"
agent: compose-service-operator
triggers:
  - user
---

Work on the compose service named `$1`.

Requested change:

$ARGUMENTS

Requirements:

1. Read the local service files first and follow conventions from `CLAUDE.md`, `CONTRIBUTING.md`, and
   `docs/`.
2. Make local repo edits only when they are clearly required by the request.
3. If a remote rollout, restart, pull, or compose apply is needed, stop and ask for explicit confirmation
   first.
4. Protect secrets in `.env`, `.env.local`, `.env.production`, and similar files.
5. End with the local changes made, remote changes still pending, and verification steps.
