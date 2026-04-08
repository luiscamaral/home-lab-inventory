---
name: dockermaster-status
description: Inspect Dockermaster host health, Docker state, networks, and service-root layout over SSH
argument-hint: "[goal or symptom]"
agent: dockermaster-host-operator
triggers:
  - user
---

Inspect Dockermaster for:

$ARGUMENTS

Requirements:

1. Read local repo docs first so the remote checks use the project’s terminology and paths.
2. Confirm whether the live service root is `/nfs/dockermaster/Docker`, `/nfs/dockermaster/docker`, or
   both.
3. Prefer read-only checks for host health, Docker health, network presence, and compose-service discovery.
4. Ask before any state-changing command.
5. Return the current state, the supporting evidence, and the next useful follow-up.
