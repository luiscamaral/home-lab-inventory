# Storage Placement Policy

Status: **active** (adopted 2026-11-05). Enforced by `scripts/check-storage-placement.py`
(pre-commit) and audited live with `scripts/check-storage-placement.py --live`.
Register of every exception and violation: `docs/architecture/storage-register.yml`.

## 1. Principle

All application data lives on the NAS, so any container can run on any host and a host
loss does not lose state.

- **Default:** persistent data is bind-mounted from a NAS export under `/nfs/`
  (`/nfs/dockermaster/docker/<service>/` for dockermaster-group services).
- **Same path everywhere:** an export that more than one host uses is mounted at the
  **same path on every host**. Hosts must not see different paths for the same data.
  The live audit checks container mounts, not host mounts yet (see section 8).
- `/volume2/...` on the NAS host is NAS storage by definition.

## 2. What counts as persistent data

Anything that must survive a container recreate or a host loss:

- databases, consensus stores, search or time-series indexes
- application state and uploads, runtime-written config (for example an app's own settings
  database), keys and certificates generated at runtime
- audit or retention logs

Not persistent data, so not covered (the scanner ignores these):

- host runtime plumbing: `/var/run/docker.sock`, `/proc`, `/sys`, `/dev`, `/etc/localtime`,
  `/etc/hosts`, cAdvisor's `/var/lib/docker`, node-exporter textfile collector
- repo-relative config files bind-mounted read-only (`./file` in the compose file; config
  as code)
- rebuildable caches and scratch, **only** when declared in the register (section 4)

## 3. Violations (default)

**Any local persistent data without a register entry is a violation.** This includes data
that is undocumented, or that a reviewer has not explicitly accepted. The guard fails a
commit that adds one. A register entry with `class: violation` (status `open` or `planned`)
is recorded debt: allowed to exist, but tracked until it is moved or decided.

## 4. Exception classes (documented reasoning)

An exception needs one of these classes, a reason of at least 40 characters, and a source
document. "Undocumented" never qualifies.

| Class | Use for | Why local (reasoning) | Source |
|---|---|---|---|
| `postgres` | PostgreSQL data directories, especially repmgr HA pairs | NFS fsync and locking behaviour is a known footgun, and a shared PGDATA across two instances is worse than split-brain | `docs/ha-architecture.md`, `docs/architecture/storage-pattern-audit-2026-05-27.md` |
| `raft` | Vault Raft and other consensus stores | NFS latency breaks heartbeats; durability comes from replication across nodes | storage audit |
| `tsdb` | Prometheus and other time-series write paths | Constant small writes are latency-sensitive over NFS; durability via remote-write or object storage | storage audit |
| `sqlite` | SQLite or BoltDB files (app DBs) | NFS soft mounts and missing locks caused corruption and I/O errors (calibre-web, 2026-08-24) | `terraform/portainer/stacks/calibre.yml` |
| `cache` | Rebuildable caches | Loss costs only warm-up time | register reason |
| `scratch` | Rebuildable working dirs (compactor, rule WAL) | Rebuilt from object storage on restart | storage audit |
| `other` | Anything else | Discouraged. Needs explicit approval and a specific reason | — |

Every exception must also state the **recovery plan**: HA replication, a backup, or a
rebuild path. "Local" is not a backup.

## 5. Consistency rules

- Multi-site MinIO: each site keeps independent storage, so one NAS failure cannot take out
  both sites. **Open decision** (section 9): this conflicts with "all on NAS" for minio-2.
- Migrating data between local and NAS is a change: it needs a backup, a maintenance window,
  and approval (`operating-rules.md` section 2).

## 6. Decision checklist (run it for every change, new feature or new service)

1. Where does this service's state live? List every path it writes.
2. Default: a NAS path under `/nfs/`. Use it unless section 4 applies.
3. If local: which class, what is the reason, what is the recovery plan. Get approval if
   the class is `other`.
4. Add or update the register entry (`docs/architecture/storage-register.yml`).
5. Run `scripts/check-storage-placement.py --report`. It must show 0 unregistered.
6. After a deploy, run `scripts/check-storage-placement.py --live` and confirm the live
   container matches the register.

## 7. Enforcement

- **Commit time:** `check-storage-placement` pre-commit hook. Fails on unregistered local
  storage, invalid register entries, and stale entries (file, service or mount gone).
- **Live:** `--live` inspects every host over read-only SSH (`docker ps`, `docker inspect`,
  `docker volume inspect`). Run it before infrastructure changes and after deploys.
- **Agents:** `.claude/skills/storage-placement/SKILL.md` and `.claude/operating-rules.md`
  section 6 require the checklist for any change that adds or moves data.

## 8. Known gaps (be explicit about them)

- Writable-layer data is not a mount, so the scanner cannot see it. Record it as a manual
  register entry (`manual: true`). Example: FreeSWITCH's SQLite DB.
- Repo-scan covers compose files in `terraform/portainer/stacks`, `dockermaster/docker`,
  `dockerserver-1`, `dockerserver-2` and `nas/docker`. Live containers that have no repo
  file are covered by `--live` only.
- `--live` does not yet check that a shared export is mounted at the same path on every
  host. Add this check before claiming full coverage.
- The repo can say NAS while a live container runs local (minio-2 today). Only `--live`
  catches this, so run it, not just the repo scan.

## 9. Open decisions (each is a register entry until decided)

1. **MinIO sites:** keep minio-2 local for site independence, or move it to NAS (and accept
   a shared NAS failure domain)?
2. **Portainer BoltDB:** NAS, or a `sqlite` exception?
3. **FreeSWITCH SQLite core DB:** `sqlite` exception, or a NAS volume?
4. **Rundeck Postgres:** `postgres` exception with a reason, or move to NAS?
5. **Logs** (Vault, Rundeck, Puppet): does a `scratch` class for logs exist, or do logs
   default to NAS?
6. **Legacy files:** DECIDED and removed 2026-11-05 (not deployed on any host).
   Orphaned NAS volume `vault_vault-data` kept, pending owner decision.
7. **Postfix DKIM keys:** move to Vault, which the secrets rule already requires.
8. **Keycloak HA:** local PGDATA stays (`postgres`), but split-brain fencing or a witness is
   a separate design task. NAS does not fix it.

## 10. Change log

- 2026-11-05: policy created. Register seeded from `--report` and `--live`
  (16 exceptions, 22 violations). Default-undocumented rule adopted.
