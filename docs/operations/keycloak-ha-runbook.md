# Keycloak HA and host-restart runbook

Status: active (2026-11-05). Covers the Keycloak Postgres pair (repmgr), the two Keycloak
nodes, and the restart procedure for any Docker host.
Policy references: `docs/architecture/storage-policy.md` (postgres exception),
`docs/ha-architecture.md`.

## 1. Known risk (open design task)

The repmgr pair (`keycloak-db-0` on dockermaster, `keycloak-db-1` on dockerserver-1) runs on
local disks. If both nodes restart within the same window, or a restart leaves a node
without a primary, the two can each promote themselves. On 2026-10-30 this caused a split
brain. Writes landed on the wrong node and were later lost when the other node re-cloned.

NAS storage does **not** fix this. A fencing or witness design does. Track it as a separate
task. Until it exists, follow the rules below.

## 2. Rules

1. **Never restart both DB nodes in the same window.** Restart one node, wait until it is
   healthy and repmgr shows one primary, then do the other.
2. **Before any DB restart, check primary and standby:**

   ```bash
   # on the host that runs the node, via the DB container
   docker exec keycloak-db-1 bash -c 'PGPASSWORD=$POSTGRESQL_PASSWORD psql -h 127.0.0.1 \
     -U $POSTGRESQL_USERNAME -d $POSTGRESQL_DATABASE -Atc "select pg_is_in_recovery()"'
   ```

   `f` = primary, `t` = standby. Exactly one node must answer `f`.
3. **Keycloak nodes**: restart one, confirm `ISPN000094` shows 2 members in its log, then the
   other. Keycloak keeps serving from the other node while one is down.
4. **Never edit `JGROUPS_ADDRESS_SEQUENCE` or `JGROUPS_PING` by hand** except under an
   approved incident. (The 2026-10-30 fix set the sequence to 36 in `server_config`. Rollback
   value was 35.)

## 3. Host restart (any Docker host): required steps, in order

Learned the hard way during the 2026-11-05 NFS wave.

1. **Sync disks** before any reset (`sync` twice). Get approval first.
2. **After any `dockerd` restart, restart `portainer-agent`.** The agent keeps the old
   `/var/run/docker.sock` inode, so the Portainer endpoint reports down and the proxy
   returns 500. Confirm with `curl -sk -H "Authorization: Bearer $JWT"
   https://192.168.59.2:9443/api/endpoints/<id>/docker/containers/json` (expect 200).
   Affected: ds-1 (endpoint 9), ds-2 (13), NAS (14).
3. **Vault restarts seal the node.** Unseal with the designed script, not by hand:
   `sudo /usr/local/bin/vault-auto-unseal.sh`. Do **not** use `systemctl start
   vault-auto-unseal`: the unit has `RemainAfterExit=yes`, so the start is a no-op.
   Then confirm with `vault operator raft list-peers` (3 voters).
4. **Containers that hold a bind mount do not see a remounted NFS.** Restarting the host
   mount is not enough. Each container with an NFS bind must be stopped and started again,
   and its mount checked in `/proc/<pid>/mountinfo` (expect `,hard,`).
5. **Use literal loops in shell snippets** that run over SSH. The remote shell is zsh, which
   does not split unquoted variables. `docker stop $LIST` silently does nothing.
6. **Check the endpoint and the container health** after every step. A healthy container can
   still hold a stale mount or socket.

## 4. Mount policy

- NFS mounts from `tnas` must be `hard` (fstab `defaults,hard,...`). `soft` returns I/O
  errors to applications, and MinIO treats those as a drive going offline.
- Check with: `grep " nfs" /proc/mounts | grep -o -E "soft|hard"`.
- The live remount of `hard` is rejected by this `mount.nfs` (nfs-utils 2.6.4). The
  procedure that worked: stop the users, `umount`, `mount` from fstab, start the users.

## 5. Verification checklist after any change to these components

- [ ] `pg_is_in_recovery()` returns exactly one `f` across the pair
- [ ] Keycloak logs show 2 cluster members, `ISPN000094`
- [ ] Vault: all nodes unsealed, 3 voters
- [ ] Portainer: all endpoints `Status == 1`
- [ ] `https://keycloak.d.lcamaral.com/realms/master/.well-known/openid-configuration` returns 200
- [ ] MinIO: `mc admin info` shows `Drives: 1/1 OK` on minio-1 and minio-2
