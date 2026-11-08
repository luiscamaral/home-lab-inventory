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
| Credentials | Vault `secret/homelab/zot` (`admin_user`, `admin_password`, `htpasswd`) |
| Portainer registry | "Zot Registry" (`portainer_registry.zot_registry`) so stacks can pull `homelab/*` |
| Metrics | Prometheus job `zot` (`192.168.59.5:5000/metrics`, both replicas); blackbox-rproxy probe on `https://zot.d.lcamaral.com` |
| UI | `https://zot.d.lcamaral.com/` (log in with the Vault credentials) |

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
- [ ] `la-rundeck` (ds-1): **pending.** The image is in zot, but switching the reference
  recreates Rundeck, and pinning `postgres:17` to the running `17.9` recreates the DB container.
  Do both together in a planned window.

### Rundeck PGDATA exception (local disk, not NAS)

`postgres-rundeck` keeps PGDATA on **local ds-1 disk** (`/opt/rundeck/dbdata`), not on the NAS.
The soft NFS mount returned EIO during the 2026-06-14 ix0/NFS stall and Postgres PANIC'd, so the
data was salvaged to local disk on 2026-06-30 (`terraform/portainer/stacks/rundeck.yml.tftpl`
carries the same comment). This is a deliberate `postgres` exception to the NAS-by-default
storage placement (register: `feat/storage-policy`, `docs/architecture/storage-register.yml`, which still lists
it as an open violation). Do not move it back to `/nfs/dockermaster/docker/rundeck/dbdata`; that
directory is a stale pre-salvage copy. The host path is not IaC-managed, so back up with
`pg_dump` before any recreate. Rundeck's own `data` and `container-plugins` stay on NFS.

## Not done yet (needs approval: host-level)

- **Transparent mirroring for Docker Engine** (`registry-mirrors` in `/etc/docker/daemon.json`)
  needs a dockerd restart on each host. Remember to restart `portainer-agent` afterwards (see
  the Keycloak/host-restart runbook). Also, dockerd expects a Docker Hub mirror at the
  registry root, and zot serves Docker Hub under `/docker.io`. Options:
  1. An Nginx rewrite vhost (for example `hub.d.lcamaral.com`: `/v2/(.*)` → `/v2/docker.io/$1`).
  2. Reference cached images explicitly (`zot.d.lcamaral.com/docker.io/...`) in stacks.
  3. With the containerd image store, a `hosts.toml` mirror with a path override.
- **Talos/K8s:** the cluster design (`docs/superpowers/specs/2026-06-15-k8s-talos-proxmox-iac-design.md`)
  should use zot. Talos `machine.registries.mirrors` supports `overridePath: true`, e.g.
  `docker.io` → `https://zot.d.lcamaral.com/v2/docker.io`.
- **CVE scanning** (`search.cve`, Trivy DB): off for now to keep memory under the 1 GB limit.

## Cool-off and decommission

The old registry stays up, unchanged, at `registry.cf.lcamaral.com` (stack `docker-registry`,
`192.168.59.16`). Nothing writes to it any more. Remove it once all of these hold:

1. `la-rundeck` has moved to the zot reference.
2. No container on any host references `registry.cf.lcamaral.com`:
   `docker ps --format '{{.Image}}' | grep registry.cf` on dm, ds-1 and ds-2.
3. The Nginx access log shows no `registry.cf.lcamaral.com` traffic for 30 days.

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
