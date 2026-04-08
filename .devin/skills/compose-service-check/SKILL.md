---
name: compose-service-check
description: Check one Dockermaster compose service locally and remotely without changing state
argument-hint: "<service> [goal or symptom]"
agent: compose-service-operator
triggers:
  - user
---

Inspect the compose service named `$1`.

Additional context:

$ARGUMENTS

Requirements:

1. Start with local files under `dockermaster/docker/compose/$1/`.
2. Identify the compose entrypoints, env files, validation docs, and related inventory or doc references.
3. Verify the matching remote directory and deployed state on Dockermaster without changing it.
4. Ask before any action that would change containers, images, networks, or remote files.
5. Summarize local config, remote state, gaps, and the recommended next steps.
