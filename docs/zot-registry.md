# Zot registry (successor to registry:2)

Status: **live** since 2026-11-06. The old `registry:2` stack (`registry.cf.lcamaral.com`)
keeps running for a cool-off period. See [Cool-off and decommission](#cool-off-and-decommission).

## What it is

| Item | Value |
|---|---|
| Software | [zot](https://zotregistry.dev) `ghcr.io/project-zot/zot:v2.1.22` (full build: sync, search, UI, metrics, scrub) |
| Host | dockermaster, Portainer stack `zot` (Terraform: `portainer_stack.zot`) |
| Address | `https://zot.d.lcamaral.com` (LAN only, via the 3 rproxy replicas) |
| Container IP | `192.168.59.5:5000` on `docker-servers-net` (+ `rproxy` bridge) |
| Storage | `/nfs/dockermaster/docker/zot/data` (NAS, hard NFS mount) |
| Config | `terraform/portainer/stacks/zot-config.json`, rendered via Compose `configs:` |
| Credentials | Vault `secret/homelab/zot` (`admin_user`, `admin_password`, `htpasswd`, plus the SSO fields `oidc_client_secret`, `session_hash_key`, `session_encrypt_key`) |
| SSO | Keycloak realm `homelab`, client `zot`; admins = group `zot-admins` (see [Single sign-on](#single-sign-on-keycloak)) |
| Portainer registry | "Zot Registry" (`portainer_registry.zot_registry`) so stacks can pull `homelab/*` |
| Metrics | Prometheus job `zot` (`192.168.59.5:5000/metrics`, both replicas); blackbox-rproxy probe on `https://zot.d.lcamaral.com` |
| UI | `https://zot.d.lcamaral.com/` (Keycloak login, or `admin` with the Vault password as break-glass) |

It is **not** published on Cloudflare (`*.cf`). Anonymous reads are allowed for the cache
namespaces, so exposing it to the internet would make an open proxy. The LAN path also avoids
Cloudflare's 100 MB request-body limit, which is why `la-rundeck` (1.28 GB) never landed in
the old registry.

## Namespaces

| Path | Contents | Anonymous | Authenticated (`admin`) |
|---|---|---|---|
| `homelab/*` | Homelab images (pushed) | no access | read, push, delete |
| `docker.io/*` | On-demand cache of Docker Hub | read | read, push, delete |
| `ghcr.io/*` | On-demand cache of GHCR | read | read, push, delete |
| `quay.io/*` | On-demand cache of Quay | read | read, push, delete |
| `registry.k8s.io/*` | On-demand cache of registry.k8s.io | read | read, push, delete |
| `gcr.io/*` | On-demand cache of GCR | read | read, push, delete |

Upstreams each get their own prefix, so there is no namespace collision between cached
Docker Hub images and `homelab/*` (Docker Hub's root namespace is never served at `/`).

Docker Hub is pulled **anonymously** (no Docker Hub account in Vault). Its anonymous rate
limit now applies to zot's single IP instead of each host. If that limit becomes a problem,
add a Docker Hub token to Vault and a `credentialsFile` entry for `index.docker.io`.

## Using it

```bash
# Pull through the cache (any host on the LAN, no login needed)
docker pull zot.d.lcamaral.com/docker.io/library/alpine:3.20
docker pull zot.d.lcamaral.com/ghcr.io/project-zot/zot-minimal:v2.1.22
docker pull zot.d.lcamaral.com/quay.io/prometheus/busybox:latest

# Push a homelab image (credentials from Vault)
vault kv get -field=admin_password secret/homelab/zot | \
  docker login zot.d.lcamaral.com -u admin --password-stdin
docker tag myimage:1.0 zot.d.lcamaral.com/homelab/myimage:1.0
docker push zot.d.lcamaral.com/homelab/myimage:1.0
```

In Compose stacks, reference `zot.d.lcamaral.com/homelab/<name>:<tag>`. Portainer pulls it
with the "Zot Registry" credentials. `scripts/check-image-pins.sh` allows `:latest` only for
`zot.d.lcamaral.com/homelab/*`, the same contract as the old registry.

## Retention and garbage collection

- Cache namespaces: tags not pulled for 90 days (`2160h`) are removed after a 24h delay, then
  GC frees the blobs (`gcInterval` 24h). A removed image is simply fetched again on the next pull.
- `homelab/*`: no retention policy, so nothing is deleted automatically.
- `scrub` checks blob integrity every 24h.
- `dedupe` is off. Deduplication keeps a BoltDB cache and hard links, and the data sits on NFS.
  The volume is small, so dedupe isn't worth that risk.

## How the htpasswd gets in

The zot image is distroless (no shell), so the `registry:2` entrypoint trick doesn't work.
A one-shot `busybox:1.37.0` service (`zot-auth-init`) writes the Vault htpasswd, passed in
through `environment:`, into the `zot-auth` named volume. zot then starts
(`depends_on: service_completed_successfully`) and mounts that volume read-only. The file is
rewritten on every deploy, so the volume holds no persistent data. This avoids the Compose
`configs.content` `$` interpolation problem with bcrypt hashes.

To rotate the password, update all three fields in `secret/homelab/zot` (regenerate the
`htpasswd` line with `htpasswd -nbB -C 10 admin <password>`), then run
`terraform apply -target=portainer_stack.zot -target=portainer_registry.zot_registry`.

## Single sign-on (Keycloak)

zot signs users in through the Keycloak `homelab` realm (OIDC, authorization-code flow). The htpasswd
`admin` user keeps working (break-glass, and what Portainer uses to pull `homelab/*`).

| Item | Value |
|---|---|
| Keycloak client | `zot` (confidential, standard flow only), `keycloak_openid_client.zot` in `terraform/portainer/keycloak.tf` |
| Redirect URI | `https://zot.d.lcamaral.com/zot/auth/callback/oidc` (zot uses `/zot/auth/callback/<provider key>`; the key is `oidc`) |
| Issuer | `https://auth.cf.lcamaral.com/realms/homelab` |
| Groups claim | `groups` (plain names, no leading `/`) from the client's group-membership mapper, in the ID token and userinfo |
| Admin group | `zot-admins` (Terraform: `keycloak_group.zot_admins`, members in `keycloak_group_memberships.zot_admins`) |
| Authorization | `accessControl.adminPolicy` = user `admin` or group `zot-admins`. Other signed-in users keep `read` (the `defaultPolicy`). Anonymous access is unchanged: read on the cache namespaces, none on `homelab/**`. |
| Secrets | Vault `secret/homelab/zot`: `oidc_client_secret`, `session_hash_key`, `session_encrypt_key` (hex, so no `$`). Vault is the source; Terraform pushes the client secret to Keycloak, so it also sits in the local Terraform state, like the other stack secrets. |
| zot settings | `http.externalUrl`, `auth.openid.providers.oidc`, `auth.sessionKeysFile`, `auth.apikey`, `auth.secureSession` (the proxy terminates TLS) |

**Why that issuer.** The realm has a fixed frontend URL, so the discovery document and every token carry
`https://auth.cf.lcamaral.com/realms/homelab`, even when the request came in on `keycloak.d.lcamaral.com`
(checked: both return the same `issuer`). zot discovers the provider from `issuer` and rejects a token whose `iss`
differs, so the configured value must be that one. Browsers reach it through Cloudflare (the `bologna` tunnel), like
`homelab-portal` (`KEYCLOAK_PUBLIC_URL`). zot itself does **not**: see [Startup dependencies](#startup-dependencies).

`zot-auth-init` writes `oidc-credentials.json` (`clientid`, `clientsecret`) and `session-keys.json` (`hashKey`,
`encryptKey`) next to the htpasswd, from the same Vault read, on every deploy. Fixed session keys keep logins valid
across restarts. Sessions are stored under the zot data directory.

### Startup dependencies

zot fetches the OIDC discovery document from the issuer at startup and **panics if that fails** (zot 2.1.22,
`pkg/api/authn.go`: `failed to initialize new relying party oidc`), so a restart needs Keycloak reachable. To keep
that off the internet and Cloudflare, the stack maps `auth.cf.lcamaral.com` to the three rproxy replicas with
`extra_hosts` (`192.168.59.28`, `.48`, `.49`), which write three `auth.cf.lcamaral.com` lines into the container's
`/etc/hosts`. The rproxies present a publicly trusted Let's Encrypt certificate for the `*.cf` names (a SAN
certificate whose first name is `auth.cf.lcamaral.com`, managed by the pfSense ACME job), so TLS verification still
works and nothing is skipped.

- Startup now depends only on the LAN: the rproxies (any of 3) and Keycloak (2 replicas behind them). No DNS, internet
  or Cloudflare is needed.
- Resolver: the zot binary is static (`CGO_ENABLED=0`), so Go's own resolver is used. It reads `/etc/hosts` before DNS
  (the image's `nsswitch.conf` says `hosts: files dns`) and returns the three addresses in file order. The dialer tries
  them in that order and moves on when a connection fails or times out, so one dead rproxy is tolerated. It always
  starts with `.28` (no round-robin), and it does not retry a reachable proxy that answers with an HTTP error.
- If that `cf` certificate expires or the rproxy vhost for `auth.cf.lcamaral.com` goes away, zot fails to start.
  Renewal is the ACME job on pfSense (`pfsense/acme-actions.yml`); check the certificate before a planned zot restart.
- Fallback: remove `extra_hosts` and apply `portainer_stack.zot`. zot then resolves `auth.cf.lcamaral.com` through DNS and
  Cloudflare again (needs internet).

### Logging in

- **Browser:** open `https://zot.d.lcamaral.com/`, choose **Keycloak**, sign in. Sign-in goes through
  `https://zot.d.lcamaral.com/zot/auth/login?provider=oidc`.
- **`docker login` / CLI:** OIDC does not work for command-line clients, so create an **API key** while signed in
  (it carries the same permissions as you; the key is shown once). Use the API keys page of the UI user menu, or the
  REST call below with the browser session cookie:

  ```bash
  curl -s -X POST https://zot.d.lcamaral.com/zot/auth/apikey -H 'Cookie: session=<cookie>' \
    -d '{"label":"laptop","expirationDate":"2027-11-08T00:00:00Z"}'
  docker login zot.d.lcamaral.com -u '<keycloak username>' --password-stdin <<< 'zak_...'
  ```

  The Docker username is the Keycloak `preferred_username` (the account's email address). Revoke with
  `DELETE /zot/auth/apikey?id=<uuid>`. Store keys in Vault or a password manager, not in dotfiles.
- **Break-glass:** `admin` with `vault kv get -field=admin_password secret/homelab/zot` still works if Keycloak is
  down. Keycloak runs on ds-1/ds-2 and is itself reached through the same rproxies.

### End-to-end test

`scripts/zot-e2e.py` tests SSO, API keys and access control without a browser, against the live registry:

```bash
export VAULT_ADDR=http://192.168.59.25:8200 VAULT_TOKEN=$(security find-generic-password -w -a lamaral -s vault-root-token)
uv run --no-project --quiet --with requests python scripts/zot-e2e.py probe   # read-only checks
uv run --no-project --quiet --with requests python scripts/zot-e2e.py all     # creates and deletes test users
```

`all` creates two disposable users in realm `homelab` through the Keycloak admin API (`zot-e2e-test`, a member of
`zot-admins`, and `zot-e2e-user`, a plain user), runs the scripted login (zot, Keycloak form, callback, session cookie),
creates API keys, pushes, pulls and deletes `homelab/e2e-test` with `docker` on `dockerserver-2` (throw-away
`DOCKER_CONFIG`), checks that the plain user can read but not push or delete, prints the rproxy lines that show zot's
token and jwks requests arriving from `192.168.59.5`, then deletes the users and the temporary files. The Keycloak
and zot writes are real, so run it deliberately.

`keycloak_group_memberships.zot_admins` is authoritative: while the test admin is in `zot-admins`, a plan that includes
that resource shows drift and an apply of it would remove the test user. The test uses the admin API only (never
Terraform), is over in a few minutes, and `cleanup` fails if the group members differ from the snapshot taken before.
Do not apply that resource while it runs. The deleted image leaves its tiny blobs under `homelab/e2e-test` until the
next garbage collection (`gcDelay` 1 h, `gcInterval` 24 h).

### Admin access

Add or remove a user in `keycloak_group_memberships.zot_admins` (the Keycloak username, not a display name) and apply
`-target=keycloak_group_memberships.zot_admins`. The change takes effect at the user's next sign-in, because zot stores
the groups it saw at the last login. Existing API keys use the groups from that last sign-in.

### Rotation

- Client secret: patch `oidc_client_secret` in Vault (`vault kv patch`, never `put`), then apply
  `-target=keycloak_openid_client.zot -target=portainer_stack.zot` and run `scripts/portainer-redeploy.py zot`.
- Session keys: patch both fields, apply `-target=portainer_stack.zot` and redeploy. This signs everyone out and
  invalidates existing sessions (API keys keep working).

## Migration record (2026-11-06)

| Image | Source | Result in zot |
|---|---|---|
| `homelab-portal:latest` | registry:2 (`192.168.59.16:5000`) | `homelab/homelab-portal:latest`, manifest digest preserved (`sha256:4a625ecb…`) |
| `la-rundeck:latest` | **local image on ds-1 only.** registry:2 has partial layers and no manifest (the push never completed; probably the CF body limit) | `homelab/la-rundeck:latest`, config `sha256:5c0c9da1…` = running image |

Copied with `quay.io/skopeo/stable:v1.22.3` (`skopeo copy --all --preserve-digests` and
`docker-daemon:` for the ds-1 image). Credentials came from Vault over SSH stdin, not argv.

Consumers switched:

- [x] `homelab-portal` (dm) → `zot.d.lcamaral.com/homelab/homelab-portal:latest`
- [x] `homelab-portal-2` (ds-1) → same
- [x] `la-rundeck` (ds-1): switched to `zot.d.lcamaral.com/homelab/la-rundeck:latest` on 2026-11-08
  (same image: config `sha256:5c0c9da1…`). In the same recreate `postgres:17` became
  `postgres:17.9@sha256:7ad98329…`, the exact running build. The `17.9` tag alone was rebuilt on
  Docker Hub after the container was pulled, so only the digest guarantees no change to PGDATA.

### Rundeck PGDATA exception (local disk, not NAS)

`postgres-rundeck` keeps PGDATA on **local ds-1 disk** (`/opt/rundeck/dbdata`), not on the NAS.
The soft NFS mount returned EIO during the 2026-06-14 ix0/NFS stall and Postgres PANIC'd, so the
data was salvaged to local disk on 2026-06-30 (`terraform/portainer/stacks/rundeck.yml.tftpl`
carries the same comment). This is a deliberate `postgres` exception to the NAS-by-default
storage placement (register: `feat/storage-policy`, `docs/architecture/storage-register.yml`, which still lists
it as an open violation). Do not move it back to `/nfs/dockermaster/docker/rundeck/dbdata`; that
directory is a stale pre-salvage copy. The host path is not IaC-managed, so back up with
`pg_dump` before any recreate. Rundeck's own `data` and `container-plugins` stay on NFS.

## Docker Hub mirror endpoint (`hub.d.lcamaral.com`)

dockerd's `registry-mirrors` expects a Docker Hub mirror at the registry **root**, and zot serves
Docker Hub under `/docker.io`. The rproxy vhost `hub.d.lcamaral.com.conf` bridges them:

| Request to `hub.d.lcamaral.com` | Sent to zot (`192.168.59.5:5000`) |
|---|---|
| `GET /v2/` | answered by Nginx itself (`200 {}`, see below), not sent to zot |
| `GET\|HEAD /v2/library/alpine/manifests/3.20` | `/v2/docker.io/library/alpine/manifests/3.20` |
| `GET\|HEAD /v2/grafana/grafana/blobs/sha256:…` | `/v2/docker.io/grafana/grafana/blobs/sha256:…` |
| `GET /v2/docker.io/…` | unchanged (so zot's `Link` pagination headers stay valid) |
| any other method (push, delete, upload) | **405**, never reaches zot |
| `GET /v2/_catalog`, anything outside `/v2/` | 404 |

It is LAN-only (3 rproxy replicas, DNS `.28/.48/.49`, `*.d.lcamaral.com` cert) and anonymous: the
`Authorization` header is stripped, so the name can never act with the zot admin credentials and can
only ever read the `docker.io/` namespace. On a cache miss zot fetches from Docker Hub on demand, so
the first pull of an image can take a while (timeouts are 900 s).

`GET /v2/` is answered by Nginx, not zot: zot answers Docker clients on `/v2/` with `401` and
`Www-Authenticate: Basic realm="zot"`, and classic (overlay2) dockerd then rejects the mirror with
`no basic auth credentials` and silently pulls from Docker Hub instead (the containerd image store
ignores the challenge). Found with a throwaway dind test, 2026-11-08.

## Sparse on-demand caching (what to expect in the cache namespaces)

zot v2.1.22 syncs on demand **sparsely**: pulling a multi-arch tag stores the index and only the platform
child that the client then requests by digest (zot fetches that child, with its config and layers, before it
answers). The sync `platforms` allowlist applies to periodic sync only, which is not enabled here. A cached
`docker.io/library/alpine:3.21` therefore holds an index that lists about 16 platforms but contains one.
This is by design, and it has three visible effects:

- **Scrub noise.** The daily scrub logs `blobs/manifest affected … blob not found` for the missing platform
  children of every cached index in `docker.io/*`, `ghcr.io/*`, `quay.io/*` and the other cache namespaces.
  These warnings are expected and are not corruption. Real damage in those repos is hard to see among
  them, so treat scrub output on the cache namespaces as noise. `homelab/*` is not sparse: a warning
  there is real.
- **GC prunes index-only entries.** GC keeps a sparse index while at least one of its children exists, and
  drops the tag entry only when **none** does (for example a tag that was only looked up, never pulled).
  The next request syncs it again, so the prune is harmless. The 24h GC log lines
  `skipping missing image manifest blob, continuing GC` belong to the same behaviour.
- **First-pull latency.** The first pull of an uncached image blocks while zot copies the platform child from
  Docker Hub. A large image can take longer than the client waits (containerd gave up after about 30 s on
  `grafana/promtail:3.4.2`, which needed about 78 s). dockerd then falls back to Docker Hub for that pull and
  the pull still succeeds, while zot finishes the sync in the background. Later pulls are served from the cache.
  To warm a large image ahead of time, pull it once through `hub.d` (or with skopeo against
  `zot.d.lcamaral.com/docker.io/…`).

No zot setting changes this for on-demand sync, so none is configured.

## Docker hosts use the mirror

`dockermaster`, `dockerserver-1` and `dockerserver-2` have `"registry-mirrors": ["https://hub.d.lcamaral.com"]`
in `/etc/docker/daemon.json` (source: `hosts/<host>/etc/docker/daemon.json`, applied with
`scripts/sync-docker-daemon.py`; see `hosts/README.md`). A plain `docker pull alpine:3.21` or
`image: grafana/grafana:…` (Docker Hub images only) now goes
**host → hub.d (rproxy) → zot → Docker Hub on a cache miss**, so Docker Hub sees zot's single IP and
every later pull is served from the NAS-backed cache. Images from `ghcr.io`, `quay.io` and other
registries are not affected (mirrors only apply to Docker Hub); reference those through
`zot.d.lcamaral.com/<registry>/…` explicitly if you want them cached.

- **Fallback:** dockerd tries each mirror first and then Docker Hub itself, so if `hub.d` or zot is down
  or returns an error for a pull, the pull falls back to Docker Hub directly. Pulls only fail if both are
  unreachable. (`docker info` lists the mirror under "Registry Mirrors".)
- **Bootstrap:** zot runs on dockermaster and `hub.d` resolves via the pihole instances, so a cold start
  of the whole fleet still works: the mirror is simply skipped until it answers.
- **dockermaster** uses the containerd image store, the other two use classic overlay2. Both work, but
  only because `hub.d` answers `GET /v2/` itself (see above). Each host was verified with a pull that
  appeared in the zot log.
- **Also changed on dockermaster:** `live-restore: true` and `json-file` log caps (50m × 3) now match
  ds-1 and ds-2. The first restart that enabled live-restore stopped dockermaster's containers once
  (it had no live-restore); later dockerd restarts keep containers running.
- **NAS excluded:** it is a Synology DSM host, not one of the three Ubuntu Docker VMs under `hosts/`,
  and it also holds zot's storage (NFS), so it should not depend on zot for its own pulls.
- Rollback: remove the `registry-mirrors` key from the host's file, re-run
  `scripts/sync-docker-daemon.py --host <h> --apply --restart`.

## Not done yet (needs approval: host-level)

- **Talos/K8s:** the cluster design (`docs/superpowers/specs/2026-06-15-k8s-talos-proxmox-iac-design.md`)
  should use zot. Talos `machine.registries.mirrors` supports `overridePath: true`, e.g.
  `docker.io` → `https://zot.d.lcamaral.com/v2/docker.io`.
- **CVE scanning** (`search.cve`, Trivy DB): off for now to keep memory under the 1 GB limit.

## Cool-off and decommission

The old registry stays up, unchanged, at `registry.cf.lcamaral.com` (stack `docker-registry`,
`192.168.59.16`). Nothing writes to it any more. Remove it once all of these hold:

1. ~~`la-rundeck` has moved to the zot reference.~~ Done 2026-11-08.
2. No container on any host references `registry.cf.lcamaral.com`:
   `docker ps --format '{{.Image}}' | grep registry.cf` on dm, ds-1 and ds-2.
3. The Nginx access log shows no `registry.cf.lcamaral.com` traffic for 30 days.

**Cool-off started 2026-11-08** (the day `la-rundeck` moved to zot, the last consumer). Earliest
decommission: **2026-12-08**, once the three conditions above hold.

Then, in one change: delete `portainer_stack.docker_registry`, `portainer_registry.homelab_registry`,
the `registry.cf.lcamaral.com.conf` vhost, the Cloudflare DNS record and tunnel ingress
(`terraform/cloudflare/main.tf`), the `registry` Prometheus job, and the
`registry\.cf\.lcamaral\.com` allowlist line. Keep `/nfs/dockermaster/docker/registry/data`
(203 MB) for another 30 days, then delete it.

## Rollback

zot is purely additive. To roll back the consumer switch, revert the image lines in
`stacks/homelab-portal*.yml` and apply those two stacks; the old registry still serves
`homelab-portal:latest`. To remove zot entirely, `terraform destroy -target=portainer_stack.zot
-target=portainer_registry.zot_registry`, remove the vhost and the DNS lines, and apply
`reverse_proxy*`/`pihole_*` (then `scripts/portainer-redeploy.py pihole-2 pihole-3` and
`scripts/sync-host-overrides.py --apply`).
