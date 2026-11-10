# Homelab Infrastructure as Code

Terraform configurations for managing the homelab infrastructure.

## Architecture

```text
                   DreamHost (registrar + authoritative NS)
                       |
                       | *.cf.lcamaral.com CNAME wildcard
                       v
                   Cloudflare (partial zone, free plan)
                       |
                       | Tunnel "bologna"
                       v
                   dockermaster
                  /     |      \
           nginx-rproxy |    Portainer (stack management)
                        |
              +-------------------+
              | Docker services   |
              | registry, vault,  |
              | calibre, runner,  |
              | bind-dns, ...     |
              +-------------------+
                        |
                   Vault (secrets)
```

## Directory Structure

```text
terraform/
  cloudflare/              # Cloudflare zone, DNS, tunnels + DreamHost delegation
  portainer/               # Portainer stacks, settings, registries
    stacks/                # Compose files referenced by Portainer stack resources
  vault/                   # Vault secret engines, policies, auth methods
  modules/
    cf-service/            # Reusable module: DNS record for *.cf.lcamaral.com
  lab-network/             # ⚠️ script-managed FRR-on-Debian lab router — NOT a Terraform root
```

Each **Terraform root** directory is independent, with its own state, providers,
and `terraform apply`. This isolation prevents failures in one domain from blocking
changes in another.

> **Exception — `lab-network/` is not a Terraform root.** It provisions the FRR-on-Debian
> inter-segment router via `bootstrap-lab-router.sh` + cloud-init (no `.tf`, no state, no
> `terraform apply`) because `bpg/proxmox` needs root-level SSH the host disallows. Do not run
> `terraform init/apply` there. See `lab-network/README.md`.

## Quick Reference

| Directory | Providers | What it manages |
|-----------|-----------|-----------------|
| `cloudflare/` | Cloudflare, DreamHost | Zone, DNS, tunnel, ingress, wildcard CNAME |
| `portainer/` | Portainer, Vault | Docker stacks, settings, users |
| `vault/` | HashiCorp Vault | Secret engines, policies |
| `lab-network/` | _none — script-managed_ | FRR-on-Debian lab router (NOT a Terraform root) |

## Prerequisites

- Terraform >= 1.5.0 (installed via mise)
- Access to macOS Keychain and Vault for secrets

## Authentication

All secrets come from Vault, bootstrapped by a single Keychain token.

```bash
# Bootstrap: set Vault access (only token stored in Keychain)
export VAULT_ADDR="http://vault.d.lcamaral.com"
export VAULT_TOKEN=$(security find-generic-password -w -a lamaral -s vault-root-token)
```

### Cloudflare

```bash
cd terraform/cloudflare
export TF_VAR_cloudflare_api_token=$(vault kv get -field=api_token secret/homelab/cloudflare)
export TF_VAR_dreamhost_api_key=$(vault kv get -field=api_token secret/homelab/dreamhost)
```

### Portainer

```bash
cd terraform/portainer
export TF_VAR_portainer_password=$(vault kv get -field=admin_password secret/homelab/portainer)
```

### Vault

```bash
cd terraform/vault
export TF_VAR_vault_token=$(security find-generic-password -w -a ${USER} -s vault-root-token)
```

## Workflows

### Init / Plan / Apply

```bash
cd terraform/<directory>
terraform init
terraform plan
terraform apply
```

### Provider lock files

Every root commits its `.terraform.lock.hcl` (hashes for `darwin_arm64` and
`linux_amd64`). All checkouts and worktrees share the same local state files, so they
must all use the same provider versions. An older provider can't decode attributes a
newer one wrote (for example portainer `source_id`, or the keycloak client schema v1).

- After pulling or creating a worktree, run `terraform init`. It installs exactly the
  locked versions. Never run `init -upgrade` outside a PR.
- To upgrade a provider, do it in a PR: bump the constraint if needed, then run
  `terraform init -upgrade` and
  `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64`. Commit the
  lock file, and re-init every checkout after the PR merges.

### Adding a New Service Behind Cloudflare Tunnel

1. **Cloudflare DNS** -- add a `cf-service` module call in `cloudflare/main.tf`:

   ```hcl
   module "myservice" {
     source    = "../modules/cf-service"
     name      = "myservice"
     zone_id   = cloudflare_zone.lcamaral_com.id
     tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.bologna.id
   }
   ```

2. **Tunnel ingress** -- add an entry in the tunnel config in `cloudflare/main.tf`:

   ```hcl
   {
     hostname = "myservice.cf.lcamaral.com"
     service  = "https://nginx-rproxy:443"
     origin_request = {
       no_tls_verify = true
     }
   },
   ```

3. **Nginx vhost** -- add `myservice.cf.lcamaral.com.conf` to the repo at
   `dockermaster/docker/compose/nginx-rproxy/vhost.d/`, or add the `.cf` name to an
   existing vhost's `server_name`. Terraform renders that directory into the three
   rproxy stacks as Compose `configs:`. Never copy vhosts to the host. After
   `terraform apply`, run `scripts/portainer-redeploy.py` on `reverse-proxy-3`, then
   `reverse-proxy-2`, then `reverse-proxy`, one at a time. The provider doesn't
   recreate containers on `configs:`-only changes.

4. **Portainer stack** -- add a `portainer_stack` resource in `portainer/stacks.tf`
   with the compose file in `portainer/stacks/`

5. **Vault secrets** -- if the stack needs secrets, add a `vault_kv_secret_v2` data
   source in `portainer/vault.tf` and reference it as an environment variable in the
   stack resource:

   ```hcl
   data "vault_kv_secret_v2" "myservice" {
     mount = "secret"
     name  = "homelab/myservice"
   }
   ```

6. Apply both directories, Cloudflare first. Use `-target` for the resources you
   changed (see `cloudflare/README.md` for known drift and the token IP-filter
   gotcha):

   ```bash
   cd terraform/cloudflare && terraform apply
   cd terraform/portainer && terraform apply
   ```

### Importing Existing Resources

Each directory has an `imports.tf` with HCL import blocks for existing resources.
After initial import, these blocks are harmless to keep.

For Portainer stacks that were created outside Terraform:

```bash
cd terraform/portainer
terraform import portainer_stack.<name> <stack-id>
```

## State Management

- State is **local** and gitignored in each directory
- Each directory's `.gitignore` excludes `*.tfstate*`, `.terraform/`, `*.tfvars`
- For team use, consider migrating to a remote backend (S3, Consul, or Terraform Cloud)

## Future Directories

| Directory | Provider | When to add |
|-----------|----------|-------------|
| `proxmox/` | `bpg/proxmox` | When managing VMs/LXC via Terraform |
| `synology/` | `synology-community/synology` | When managing NAS config via Terraform |

## Credentials Reference

| Secret | Location | Used by |
|--------|----------|---------|
| Vault root token | Keychain: `vault-root-token` | Bootstrap (all dirs) |
| Cloudflare API token | Vault: `secret/homelab/cloudflare` | `cloudflare/` |
| DreamHost API key | Vault: `secret/homelab/dreamhost` | `cloudflare/` |
| Portainer password | Vault: `secret/homelab/portainer` | `portainer/` |
| Vault operational token | Vault: `secret/homelab/vault` | `portainer/` |
| Twingate A connector tokens | Vault: `secret/homelab/twingate/sepia-hornet` | `portainer/` |
| Twingate B connector tokens | Vault: `secret/homelab/twingate/golden-mussel` | `portainer/` |
| Calibre admin password | Vault: `secret/homelab/calibre` | `portainer/` |
| GitHub PAT | Vault: `secret/homelab/github-runner` | `portainer/` |
| DNSSEC keys backup | Vault: `secret/homelab/bind9/dnssec` | `portainer/` |
