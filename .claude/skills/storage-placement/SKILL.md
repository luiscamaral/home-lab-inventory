---
name: storage-placement
description: Use for ANY change that adds, moves or re-points persistent data in this homelab: new service or stack, new volume or bind mount, database/log/upload path change, Portainer or compose edit that touches volumes, storage migration, or when a "local disk" or "named volume" is proposed. Enforces NAS-by-default placement and the register of exceptions.
---

# Storage placement (NAS by default)

## The rule
- Persistent data lives on the NAS under `/nfs/` (for dockermaster-group services,
  `/nfs/dockermaster/docker/<service>/`).
- A NAS export used by several hosts is mounted at the **same path on every host**.
- **Undocumented local storage is a violation by default.** Only the exception classes in
  `docs/architecture/storage-policy.md` are allowed, and each needs a reason, a source
  document and a recovery plan.
- Do not treat "it's on local disk" as a fix. Local storage needs a documented class.

## Checklist (do all of it, in order)
1. List every path the service writes (database, state, uploads, keys, logs, caches).
2. Default each path to a NAS location under `/nfs/`.
3. Only if the default cannot work, pick an exception class from the policy:
   `postgres`, `raft`, `tsdb`, `sqlite`, `cache`, `scratch`. `other` needs explicit
   approval. For each, write the reason and the recovery plan.
4. Record it in `docs/architecture/storage-register.yml`:
   - exception: `class: exception`, `exception_class`, reason (40+ characters)
   - undocumented or undecided: `class: violation`, `status: open|planned`
   - writable-layer data (not a mount): `manual: true`
5. Run `scripts/check-storage-placement.py --report` (repo scan). It must report
   0 unregistered.
6. After any deploy, run `scripts/check-storage-placement.py --live` (read-only SSH) and
   confirm the running container matches the register.
7. Moving data between local and NAS needs a backup, a maintenance window and approval
   (`operating-rules.md` section 2).

## Facts that have caused incidents here
- SQLite on NFS (calibre-web, 2026-08-24): disk I/O errors and corruption. This is why
  `sqlite` is an exception class, not a default.
- Two Postgres instances on local disks (Keycloak, 2026-10-30): a split-brain loss. NAS
  would not fix this. Fencing or a witness is the fix.
- Freeswitch's SQLite DB lives in the container writable layer. It is invisible to mount
  scans and lost on recreate. It needs a manual register entry.
- The repo can say NAS while the running container uses local disk (minio-2). Always run
  `--live` after a deploy.

## Do not
- Do not add a bind mount outside `/nfs/` to "make it work" without a register entry.
- Do not mark something as an exception because it is convenient. The reason must cite a
  source.
- Do not silence the guard by editing the register to hide a violation. Violations stay
  visible until they are moved or decided.
- Do not put secrets in volumes or files on any host. Use Vault (`operating-rules.md`
  section 5).
