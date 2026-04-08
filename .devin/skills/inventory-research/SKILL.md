---
name: inventory-research
description: Research the inventory repo, Dockermaster documentation, compose stacks, and workflow patterns
argument-hint: "<topic or question>"
agent: inventory-workspace-researcher
triggers:
  - user
  - model
---

Research this repository topic:

$ARGUMENTS

Requirements:

1. Start with `CLAUDE.md`, `dockermaster/README.md`, `dockermaster/docker/compose/STATUS.md`, `docs/`,
   and `inventory/`.
2. Use `dockermaster/docker/compose/` as the local service catalog source of truth.
3. Trace how docs, automation, compose files, and inventory records connect.
4. Cite the most relevant files and line references.
5. If live remote evidence is required, say whether `/dockermaster-status` or `/compose-service-check`
   should run next.
