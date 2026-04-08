---
name: dockermaster-war-room
description: Coordinate repo research, Dockermaster checks, compose service checks, and doc updates
argument-hint: "<incident, service, or operational goal>"
triggers:
  - user
---

Run a focused Dockermaster investigation or execution plan for:

$ARGUMENTS

Use the minimum set of specialized skills needed:

1. Start with `/inventory-research` to map the relevant docs, service files, and automation.
2. Use `/dockermaster-status` for host-level state, service-root discovery, or Docker runtime issues.
3. Use `/compose-service-check` for a specific compose project.
4. Use `/inventory-doc-sync` when the evidence should be written back into `inventory/` or `docs/`.
5. Use `/compose-service-fix` only when the user wants local repo changes or rollout preparation.

Finish with:

- the most likely fault or change surface
- the evidence that supports it
- the next one or two actions with the best value
