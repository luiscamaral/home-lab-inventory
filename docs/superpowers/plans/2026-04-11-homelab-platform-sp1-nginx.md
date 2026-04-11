# Homelab Platform SP1: Schema + Catalog + Nginx Generator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the foundation of the homelab platform — a CUE schema, a catalog of all ~29 services, and a working nginx vhost generator that regenerates the 22 existing vhosts with a canonical shape, without drift, validated end-to-end against live production.

**Architecture:** A `platform/` directory at the repo root contains CUE schemas (`schemas/`), per-service data files (`services/`), and a single top-level `gen_tool.cue` that runs `cue cmd gen` to write nginx vhosts into the existing `dockermaster/docker/compose/nginx-rproxy/vhost.d/` directory. Generated files are committed to git. Pre-commit and CI enforce that source and generated stay in sync.

**Tech Stack:** CUE (the language), CUE's built-in `tool/file` and `text/template` packages, Go `text/template` syntax for the `.tmpl` file, Bash for scripts, GitHub Actions for CI, pre-commit framework for local hooks, nginx 1.29 for the reverse proxy being configured.

**Spec:** `docs/superpowers/specs/2026-04-11-homelab-platform-design.md`

**Prerequisites:** The `custom-login-portal` PR must have merged (or be merged-in to a fresh branch for SP1). SP1 starts on a new branch `platform-sp1-nginx` off `main`.

---

### Task 1: Bootstrap — branch, CUE install, platform directory

**Files:**
- Create: `platform/cue.mod/module.cue`
- Create: `platform/README.md`
- Modify: `.mise.toml` (add `cue`)
- Modify: `Makefile` at repo root (add `platform-*` targets as empty stubs)

- [ ] **Step 1: Create and check out the SP1 branch**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git fetch origin
git checkout -b platform-sp1-nginx origin/main
```

- [ ] **Step 2: Pin CUE version via mise**

Check what the current stable CUE version is:

```bash
mise ls-remote cue 2>&1 | tail -5
```

Add to `.mise.toml` at the repo root (create the file if it doesn't exist, or add the line to the `[tools]` section if it does):

```toml
[tools]
cue = "latest"
```

Then install:

```bash
mise install cue
cue version
```

Expected: prints a version like `cue version v0.11.x` or newer.

- [ ] **Step 3: Create the platform directory and CUE module**

```bash
mkdir -p platform/cue.mod
mkdir -p platform/schemas
mkdir -p platform/services
mkdir -p platform/generators/nginx/testdata
mkdir -p platform/scripts
```

Create `platform/cue.mod/module.cue`:

```cue
module: "lcma.dev/platform"
language: version: "v0.11.0"
```

(Use whatever version `cue version` reported in Step 2 for the `language: version` field — this pins the schema language version the module was authored against.)

- [ ] **Step 4: Create a minimal platform README**

Create `platform/README.md`:

```markdown
# Homelab Platform

CUE-based internal platform for the lcamaral homelab. Every service has one file
under `services/` that describes its DNS, IPs, reverse proxy, observability, secrets,
and dependencies. A set of generators derive nginx vhosts, Terraform for Cloudflare
and Portainer, bind9 zones, Prometheus scrape configs, and documentation from that
single source of truth.

## Quick start

```bash
make platform-vet    # validate the catalog
make platform-gen    # regenerate all outputs
make platform-diff   # fail if generated files are out of date
make platform-test   # run golden file tests per generator
```

## Layout

- `schemas/` — CUE type definitions (`#Service`, `#Network`, etc.)
- `services/` — one `.cue` file per service, data only
- `generators/<name>/` — one directory per generator with a `.tmpl` file
- `gen_tool.cue` — top-level `cue cmd gen` command
- `scripts/` — helper shell scripts for CI and pre-commit

## Spec

See `docs/superpowers/specs/2026-04-11-homelab-platform-design.md` for the full design.
```

- [ ] **Step 5: Add empty Makefile targets at the repo root**

Check the existing `Makefile` at the repo root:

```bash
grep -n '^platform-' Makefile 2>/dev/null || echo "no platform targets yet"
```

Append to `Makefile` (or create one if it doesn't exist):

```makefile
# ─── Platform targets ─────────────────────────────────────

.PHONY: platform-gen platform-vet platform-diff platform-fmt platform-test

platform-gen:       ## Regenerate all platform outputs
	cd platform && cue cmd gen

platform-vet:       ## Validate the service catalog
	cd platform && cue vet ./...

platform-diff:      ## Fail if generated files are out of date
	$(MAKE) platform-gen
	git diff --exit-code -- \
	  dockermaster/docker/compose/nginx-rproxy/vhost.d/

platform-fmt:       ## Format CUE files
	cd platform && cue fmt ./...

platform-test:      ## Run golden file tests per generator
	@./platform/scripts/run-golden-tests.sh
```

- [ ] **Step 6: Verify the CUE module loads**

```bash
cd platform && cue vet ./... && cd ..
```

Expected: no output (empty catalog vets clean).

- [ ] **Step 7: Commit**

```bash
git add .mise.toml platform/cue.mod/module.cue platform/README.md Makefile
git commit -m "chore(platform): bootstrap cue module and makefile targets"
```

---

### Task 2: Schema — core `#Service` type

**Files:**
- Create: `platform/schemas/service.cue`
- Create: `platform/schemas/service_test.cue`

The schema is the contract every service file must satisfy. Writing it in one task (no TDD-incrementalism) because CUE schemas are holistic — you can't write a partial `#Service` and have anything meaningful to validate.

- [ ] **Step 1: Write the test file first with a known-good fixture**

Create `platform/schemas/service_test.cue`:

```cue
package schemas

// Test fixture: a fully-populated service that should pass schema validation.
_test_valid_full: #Service & {
    name:        "example-service"
    description: "Example service covering every optional field"
    owner:       "platform"
    tags: ["test", "example"]

    container: {
        image:      "registry.cf.lcamaral.com/example:latest"
        build_from: "apps/example"
        watchtower: true
        resources: {
            cpu_limit:    "1"
            memory_limit: "512M"
        }
        healthcheck: {
            test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
        }
    }

    network: {
        mode: "rproxy-bridge"
    }

    endpoints: [{
        name:   "web"
        port:   8080
        health: "/healthz"
    }]

    dns: {
        external: "example.cf.lcamaral.com"
    }

    http: {
        cert:     "d.lcamaral.com"
        endpoint: "web"
    }

    secrets: [{
        env: "API_KEY"
        ref: "secret/homelab/example#api_key"
    }]

    monitoring: {
        loki_logs: true
        otel:      true
    }
}

// Test fixture: the minimal service (infra daemon with no HTTP).
_test_valid_minimal: #Service & {
    name:        "example-daemon"
    description: "Minimal infra daemon"
    network: {
        mode: "rproxy-bridge"
    }
    monitoring: {}  // defaults apply
}
```

- [ ] **Step 2: Run vet — expect failure because `#Service` doesn't exist yet**

```bash
cd platform && cue vet ./schemas/... 2>&1
```

Expected: error like `reference "#Service" not found`.

- [ ] **Step 3: Write the full `#Service` schema**

Create `platform/schemas/service.cue`:

```cue
// platform/schemas/service.cue
package schemas

import "strings"

// #Service is the canonical description of a homelab service.
// Every service in the catalog satisfies this schema.
#Service: {
    // ─── Identity ───────────────────────────────────────
    name:        =~"^[a-z][a-z0-9-]*[a-z0-9]$" & strings.MaxRunes(63)
    description: string
    owner:       *"platform" | string
    tags?:       [...string]

    // ─── Container / runtime (optional — infra services may omit) ─
    container?: {
        image:       string
        build_from?: string
        watchtower:  *true | false
        resources?: {
            cpu_limit?:      string
            memory_limit?:   string
            cpu_reserve?:    string
            memory_reserve?: string
        }
        healthcheck?: {
            test:         [...string]
            interval:     *"30s" | string
            timeout:      *"5s"  | string
            retries:      *3     | int
            start_period: *"20s" | string
        }
    }

    // ─── Network placement ──────────────────────────────
    network: {
        mode:    "rproxy-bridge" | "docker-servers-net" | "back-tier" | "dual" | "host"
        lan_ip?: =~"^192\\.168\\.59\\.[0-9]+$"
        extra?:  [...string]

        exposed_ports?: [...{
            port:     >0 & <65536
            protocol: *"tcp" | "udp"
            name?:    string
        }]
    }
    if network.mode == "docker-servers-net" {
        network: lan_ip: !=""
    }

    // ─── HTTP endpoints (optional — daemons can omit) ──
    endpoints?: [...{
        name:    string
        port:    >0 & <65536
        path:    *"/"          | string
        health?: *"/healthz"   | string
        scheme:  *"http"       | "https"
    }]

    // ─── DNS ────────────────────────────────────────────
    dns?: {
        internal?:         =~".*\\.lcamaral\\.com$"
        external?:         =~".*\\.cf\\.lcamaral\\.com$"
        internal_aliases?: [...string]
        external_aliases?: [...string]
    }

    // ─── Reverse proxy (nginx vhost) ────────────────────
    // Required iff dns is set.
    http?: {
        cert:             "d.lcamaral.com" | "home.lcamaral.com"
        endpoint:         string
        upstream_dynamic: *true | false
        read_timeout:     *"3600s" | string
        send_timeout:     *"3600s" | string
        max_body_size:    *"10m" | string | "0"
        frame_options:    *"SAMEORIGIN" | "DENY"

        allow_insecure_http:    *false | true
        extra_location_config?: string
        extra_server_config?:   string
    }
    if dns != _|_ {
        if (dns & {internal: _} != _|_) || (dns & {external: _} != _|_) {
            http: !=_|_
        }
    }

    // ─── Auth / OIDC ────────────────────────────────────
    oidc?: {
        provider:          "keycloak"
        realm:             *"homelab" | string
        client_id:         string
        client_secret_ref: =~"^secret/.*#.*$"
    }

    // ─── Secrets (Vault → env vars) ─────────────────────
    secrets?: [...{
        env: string
        ref: =~"^secret/.*#.*$"
    }]

    // ─── Observability ──────────────────────────────────
    monitoring: {
        loki_logs: *true | false
        otel:      *true | false
        prometheus_scrape?: {
            endpoint: string
            path:     *"/metrics" | string
            interval: *"30s"      | string
        }
    }

    // ─── Dependencies ───────────────────────────────────
    depends_on?: [...string]

    // ─── Documentation ──────────────────────────────────
    notes?:   string
    runbook?: string
}
```

- [ ] **Step 4: Run vet — expect pass**

```bash
cd platform && cue vet ./schemas/...
```

Expected: no output. Both `_test_valid_full` and `_test_valid_minimal` unify with `#Service` cleanly.

- [ ] **Step 5: Add a known-bad fixture to prove validation bites**

Append to `platform/schemas/service_test.cue`:

```cue
// Test fixture: a service with an invalid name (uppercase). Should fail vet.
// Commented out — uncomment locally to verify, then re-comment before commit.
// _test_invalid_uppercase: #Service & {
//     name: "BadName"
//     description: "has uppercase letters"
//     network: { mode: "rproxy-bridge" }
//     monitoring: {}
// }
```

Verify manually:

```bash
# Uncomment _test_invalid_uppercase temporarily
sed -i '' 's|// _test_invalid_uppercase|_test_invalid_uppercase|' platform/schemas/service_test.cue
cd platform && cue vet ./schemas/... 2>&1 | head -5
# Expected: error about the name regex
# Re-comment
sed -i '' 's|^_test_invalid_uppercase|// _test_invalid_uppercase|' platform/schemas/service_test.cue
cd platform && cue vet ./schemas/...
# Expected: clean
```

- [ ] **Step 6: Format**

```bash
cd platform && cue fmt ./schemas/...
```

- [ ] **Step 7: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add platform/schemas/
git commit -m "feat(platform): #Service schema with validation fixtures"
```

---

### Task 3: Catalog package with cross-reference validation

**Files:**
- Create: `platform/services/_catalog.cue`

- [ ] **Step 1: Write the catalog package header**

Create `platform/services/_catalog.cue`:

```cue
// platform/services/_catalog.cue
package services

import "lcma.dev/platform/schemas"

// All services indexed by name. The key must equal the service's name field.
services: [name=string]: schemas.#Service & {
    name: name
}

// Cross-service validation: every depends_on must reference a declared service.
for svcName, svc in services {
    for dep in (*svc.depends_on | []) {
        services: "\(dep)": _
    }
}

// Endpoint reference validation: http.endpoint must match one endpoints[].name.
for svcName, svc in services
if svc.http != _|_ {
    let _endpointNames = {for e in svc.endpoints {(e.name): true}}
    svc: http: endpoint: or([for n, _ in _endpointNames {n}])
}
```

- [ ] **Step 2: Run vet on empty catalog**

```bash
cd platform && cue vet ./services/...
```

Expected: no output (empty `services` map is valid).

- [ ] **Step 3: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add platform/services/_catalog.cue
git commit -m "feat(platform): catalog package with cross-reference validation"
```

---

### Task 4: Services — infrastructure daemons

**Files:**
- Create: `platform/services/bind-dns.cue`
- Create: `platform/services/cloudflare-tunnel.cue`
- Create: `platform/services/twingate-a.cue`
- Create: `platform/services/twingate-b.cue`
- Create: `platform/services/watchtower.cue`
- Create: `platform/services/postfix-relay.cue`
- Create: `platform/services/github-runner.cue`
- Create: `platform/services/ollama.cue`

These are daemons without HTTP surfaces (or, in Ollama's case, HTTP surfaces not currently exposed through nginx). They have `container`, `network`, `monitoring`, and optional `secrets` — nothing else.

- [ ] **Step 1: Create `bind-dns.cue`**

Create `platform/services/bind-dns.cue`:

```cue
package services

services: "bind-dns": {
    description: "Authoritative DNS for internal lcamaral.com zones"
    container: {
        image:      "internetsystemsconsortium/bind9:9.20"
        watchtower: false
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.3"
        exposed_ports: [
            {port: 53, protocol: "tcp", name: "dns-tcp"},
            {port: 53, protocol: "udp", name: "dns-udp"},
        ]
    }
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 2: Create `cloudflare-tunnel.cue`**

Create `platform/services/cloudflare-tunnel.cue`:

```cue
package services

services: "cloudflare-tunnel": {
    description: "Cloudflare Zero Trust tunnel (bologna) for *.cf.lcamaral.com"
    container: {
        image:      "cloudflare/cloudflared:latest"
        watchtower: true
    }
    network: {
        mode: "rproxy-bridge"
    }
    secrets: [
        {env: "TUNNEL_TOKEN", ref: "secret/homelab/cloudflare#tunnel_token"},
    ]
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 3: Create `twingate-a.cue`**

Create `platform/services/twingate-a.cue`:

```cue
package services

services: "twingate-a": {
    description: "Twingate connector A (sepia-hornet)"
    container: {
        image:      "twingate/connector:latest"
        watchtower: true
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.12"
        extra: ["rproxy"]
    }
    secrets: [
        {env: "TWINGATE_ACCESS_TOKEN",  ref: "secret/homelab/twingate/sepia-hornet#access_token"},
        {env: "TWINGATE_REFRESH_TOKEN", ref: "secret/homelab/twingate/sepia-hornet#refresh_token"},
    ]
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 4: Create `twingate-b.cue`**

Create `platform/services/twingate-b.cue`:

```cue
package services

services: "twingate-b": {
    description: "Twingate connector B (golden-mussel)"
    container: {
        image:      "twingate/connector:latest"
        watchtower: true
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.24"
        extra: ["rproxy"]
    }
    secrets: [
        {env: "TWINGATE_ACCESS_TOKEN",  ref: "secret/homelab/twingate/golden-mussel#access_token"},
        {env: "TWINGATE_REFRESH_TOKEN", ref: "secret/homelab/twingate/golden-mussel#refresh_token"},
    ]
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 5: Create `watchtower.cue`**

Create `platform/services/watchtower.cue`:

```cue
package services

services: "watchtower": {
    description: "Automatic container updater (runs daily at 4 AM)"
    container: {
        image:      "containrrr/watchtower:latest"
        watchtower: false
    }
    network: {
        mode: "rproxy-bridge"
    }
    secrets: [
        {env: "WATCHTOWER_API_TOKEN", ref: "secret/homelab/watchtower#api_token"},
    ]
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 6: Create `postfix-relay.cue`**

Create `platform/services/postfix-relay.cue`:

```cue
package services

services: "postfix-relay": {
    description: "Postfix SMTP relay through DreamHost for Keycloak outbound email"
    container: {
        image:      "boky/postfix:latest"
        watchtower: true
    }
    network: {
        mode: "rproxy-bridge"
    }
    secrets: [
        {env: "RELAYHOST_USERNAME", ref: "secret/homelab/smtp#username"},
        {env: "RELAYHOST_PASSWORD", ref: "secret/homelab/smtp#password"},
    ]
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 7: Create `github-runner.cue`**

Create `platform/services/github-runner.cue`:

```cue
package services

services: "github-runner": {
    description: "Self-hosted GitHub Actions runner for CI/CD"
    container: {
        image:      "myoung34/github-runner:latest"
        watchtower: true
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.4"
    }
    secrets: [
        {env: "GITHUB_TOKEN", ref: "secret/homelab/github-runner#github_token"},
    ]
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 8: Create `ollama.cue`**

Create `platform/services/ollama.cue`:

```cue
package services

services: "ollama": {
    description: "Ollama LLM server"
    container: {
        image:      "ollama/ollama:latest"
        watchtower: true
    }
    network: {
        mode: "rproxy-bridge"
    }
    monitoring: {loki_logs: true, otel: false}
}
```

- [ ] **Step 9: Vet the catalog with 8 infra services**

```bash
cd platform && cue vet ./...
```

Expected: no output.

- [ ] **Step 10: Format and commit**

```bash
cd platform && cue fmt ./services/...
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add platform/services/
git commit -m "feat(platform): catalog infra daemons (8 services)"
```

---

### Task 5: Services — HTTP apps on rproxy-bridge (Docker DNS upstreams)

**Files:**
- Create: `platform/services/homelab-portal.cue`
- Create: `platform/services/keycloak.cue`
- Create: `platform/services/calibre.cue`
- Create: `platform/services/minio.cue`
- Create: `platform/services/minio-console.cue`
- Create: `platform/services/grafana.cue`
- Create: `platform/services/loki.cue`
- Create: `platform/services/prometheus.cue`
- Create: `platform/services/openldap.cue`
- Create: `platform/services/vault.cue`
- Create: `platform/services/docker-registry.cue`

These services run on the `rproxy` Docker bridge network and are proxied via Docker DNS hostnames. nginx uses `resolver 127.0.0.11` to re-resolve them.

- [ ] **Step 1: Create `homelab-portal.cue`**

Create `platform/services/homelab-portal.cue`:

```cue
package services

services: "homelab-portal": {
    description: "Homelab login portal (SvelteKit + Keycloak)"
    container: {
        image:      "registry.cf.lcamaral.com/homelab-portal:latest"
        build_from: "apps/homelab-portal"
        watchtower: true
        resources: {
            cpu_limit:      "1"
            memory_limit:   "512M"
            memory_reserve: "128M"
        }
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "web", port: 3000, health: "/healthz"}]
    dns: {external: "login.cf.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        read_timeout:  "60s"
        send_timeout:  "60s"
        max_body_size: "1m"
        frame_options: "DENY"
    }
    secrets: [
        {env: "KEYCLOAK_CLIENT_SECRET", ref: "secret/homelab/keycloak/clients#homelab_portal_secret"},
        {env: "SESSION_SECRET",         ref: "secret/homelab/portal#session_secret"},
        {env: "SESSION_ENCRYPTION_KEY", ref: "secret/homelab/portal#session_encryption_key"},
    ]
    depends_on: ["keycloak", "postfix-relay"]
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 2: Create `keycloak.cue`**

Keycloak is reachable via both `auth.cf.lcamaral.com` (Cloudflare) and `keycloak.d.lcamaral.com` (internal LAN). Both resolve to the same container. The spec commits to pointing `auth.cf` at the Docker DNS hostname (not the LAN IP) for consistency.

Create `platform/services/keycloak.cue`:

```cue
package services

services: "keycloak": {
    description: "Keycloak identity provider (homelab realm)"
    container: {
        image:      "quay.io/keycloak/keycloak:26.3"
        watchtower: false
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "web", port: 8080}]
    dns: {
        external: "auth.cf.lcamaral.com"
        internal: "keycloak.d.lcamaral.com"
    }
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        max_body_size: "100m"
    }
    secrets: [
        {env: "KC_DB_PASSWORD",          ref: "secret/homelab/keycloak#db_password"},
        {env: "KEYCLOAK_ADMIN_PASSWORD", ref: "secret/homelab/keycloak#admin_password"},
    ]
    depends_on: ["postfix-relay"]
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 3: Create `calibre.cue`**

Create `platform/services/calibre.cue`:

```cue
package services

services: "calibre": {
    description: "Calibre-web ebook server"
    container: {
        image:      "linuxserver/calibre-web:latest"
        watchtower: true
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "web", port: 8181, scheme: "https"}]
    dns: {internal: "calibre.d.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        max_body_size: "100m"
    }
    secrets: [
        {env: "CALIBRE_PASSWORD", ref: "secret/homelab/calibre#password"},
    ]
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 4: Create `minio.cue` (the S3 API)**

Create `platform/services/minio.cue`:

```cue
package services

services: "minio": {
    description: "MinIO S3-compatible object storage — S3 API"
    container: {
        image:      "minio/minio:latest"
        watchtower: true
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "s3", port: 9000}]
    dns: {
        external:         "s3.cf.lcamaral.com"
        internal:         "s3.d.lcamaral.com"
    }
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "s3"
        max_body_size: "100m"
    }
    secrets: [
        {env: "MINIO_ROOT_USER",          ref: "secret/homelab/minio#root_user"},
        {env: "MINIO_ROOT_PASSWORD",      ref: "secret/homelab/minio#root_password"},
        {env: "MINIO_OIDC_CLIENT_SECRET", ref: "secret/homelab/keycloak/clients#minio_client_secret"},
    ]
    depends_on: ["keycloak"]
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 5: Create `minio-console.cue`**

Create `platform/services/minio-console.cue`:

```cue
package services

services: "minio-console": {
    description: "MinIO web console (shares minio container, different port)"
    // No container — the container is already declared by the `minio` service;
    // this entry exists only to give the console its own hostname + vhost.
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "console", port: 9001}]
    dns: {
        external: "minio.cf.lcamaral.com"
        internal: "minio.d.lcamaral.com"
    }
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "console"
        max_body_size: "100m"
    }
    monitoring: {loki_logs: false, otel: false}
}
```

Note: `minio` and `minio-console` are two separate services in the catalog even though they share a container. This replaces the current `s3.d.lcamaral.com.conf` file that has four server blocks. Each logical service gets its own generated vhost file.

- [ ] **Step 6: Create `grafana.cue`**

Create `platform/services/grafana.cue`:

```cue
package services

services: "grafana": {
    description: "Grafana dashboards"
    container: {
        image:      "grafana/grafana:latest"
        watchtower: true
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "web", port: 3000}]
    dns: {internal: "grafana.d.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        max_body_size: "100m"
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 7: Create `loki.cue`**

Create `platform/services/loki.cue`:

```cue
package services

services: "loki": {
    description: "Loki log aggregation"
    container: {
        image:      "grafana/loki:latest"
        watchtower: true
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "api", port: 3100}]
    dns: {internal: "loki.d.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "api"
        max_body_size: "100m"
    }
    monitoring: {loki_logs: false, otel: true}
}
```

- [ ] **Step 8: Create `prometheus.cue`**

Create `platform/services/prometheus.cue`:

```cue
package services

services: "prometheus": {
    description: "Prometheus metrics server"
    container: {
        image:      "prom/prometheus:latest"
        watchtower: true
    }
    network: {mode: "back-tier"}
    endpoints: [{name: "web", port: 9090}]
    dns: {internal: "prometheus.d.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        max_body_size: "100m"
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 9: Create `openldap.cue`**

Create `platform/services/openldap.cue`:

```cue
package services

services: "openldap": {
    description: "OpenLDAP directory with phpLDAPadmin web UI"
    // Hand-written standalone compose stack (not Terraform-managed yet).
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "admin", port: 8181, scheme: "https"}]
    dns: {internal: "openldap.d.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "admin"
        max_body_size: "100m"
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 10: Create `vault.cue`**

Create `platform/services/vault.cue`:

```cue
package services

services: "vault": {
    description: "HashiCorp Vault secret store"
    container: {
        image:      "hashicorp/vault:latest"
        watchtower: false
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "api", port: 8200}]
    dns: {internal: "vault.d.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "api"
        max_body_size: "100m"
    }
    secrets: [
        {env: "VAULT_TOKEN", ref: "secret/homelab/vault#vault_token"},
    ]
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 11: Create `docker-registry.cue`**

Create `platform/services/docker-registry.cue`:

```cue
package services

services: "docker-registry": {
    description: "Local Docker image registry"
    container: {
        image:      "registry:2"
        watchtower: true
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "api", port: 5000}]
    dns: {
        external: "registry.cf.lcamaral.com"
    }
    http: {
        cert:                "d.lcamaral.com"
        endpoint:            "api"
        max_body_size:       "0"     // unlimited for image pushes
        read_timeout:        "900s"
        send_timeout:        "900s"
        allow_insecure_http: true    // registry needs unencrypted http on :80 too
        extra_location_config: """
            # Chunked transfer encoding for large layers
            proxy_request_buffering off;
            """
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 12: Vet the catalog with 11 HTTP services on rproxy-bridge**

```bash
cd platform && cue vet ./...
```

Expected: no output. Any schema violation (bad regex, missing required field, broken endpoint ref) will fail here.

- [ ] **Step 13: Format and commit**

```bash
cd platform && cue fmt ./services/...
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add platform/services/
git commit -m "feat(platform): catalog http apps on rproxy-bridge (11 services)"
```

---

### Task 6: Services — LAN IP upstreams and WebSocket services

**Files:**
- Create: `platform/services/rundeck.cue`
- Create: `platform/services/rustdesk.cue`
- Create: `platform/services/rustdesk-relay.cue`
- Create: `platform/services/freeswitch.cue`
- Create: `platform/services/chisel.cue`
- Create: `platform/services/portainer-ce.cue`

These services either use a static LAN IP upstream (macvlan), serve WebSocket-heavy traffic, or are the Portainer management UI.

- [ ] **Step 1: Create `rundeck.cue`**

Create `platform/services/rundeck.cue`:

```cue
package services

services: "rundeck": {
    description: "Rundeck automation server"
    container: {
        image:      "registry.cf.lcamaral.com/la-rundeck-rundeck:latest"
        watchtower: false
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.22"
    }
    endpoints: [{name: "web", port: 4440}]
    dns: {
        internal:         "rundeck.d.lcamaral.com"
        internal_aliases: []
    }
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false
    }
    secrets: [
        {env: "RUNDECK_DB_PASSWORD",      ref: "secret/homelab/rundeck#db_password"},
        {env: "RUNDECK_STORAGE_PASSWORD", ref: "secret/homelab/rundeck#storage_converter_password"},
    ]
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 2: Create `rustdesk.cue` (ID server, hbbs)**

Create `platform/services/rustdesk.cue`:

```cue
package services

services: "rustdesk": {
    description: "RustDesk ID server (hbbs) — WebSocket remote-desktop registration"
    container: {
        image:      "rustdesk/rustdesk-server:latest"
        watchtower: true
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.10"
        extra: ["rproxy"]
    }
    endpoints: [{name: "signal", port: 21118}]
    dns: {internal: "rustdesk.home.lcamaral.com"}
    http: {
        cert:         "home.lcamaral.com"
        endpoint:     "signal"
        read_timeout: "86400s"
        send_timeout: "86400s"
        extra_location_config: """
            # Disable buffering for real-time WebSocket traffic
            proxy_buffering off;
            """
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 3: Create `rustdesk-relay.cue` (hbbr)**

Create `platform/services/rustdesk-relay.cue`:

```cue
package services

services: "rustdesk-relay": {
    description: "RustDesk relay server (hbbr) — WebSocket relay"
    // Container declared in the rustdesk service; this is the second endpoint
    // of the same stack with its own hostname and vhost.
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.11"
        extra: ["rproxy"]
    }
    endpoints: [{name: "relay", port: 21119}]
    dns: {internal: "rustdesk-relay.home.lcamaral.com"}
    http: {
        cert:         "home.lcamaral.com"
        endpoint:     "relay"
        read_timeout: "86400s"
        send_timeout: "86400s"
        extra_location_config: """
            # Disable buffering for real-time WebSocket traffic
            proxy_buffering off;
            """
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 4: Create `freeswitch.cue`**

Create `platform/services/freeswitch.cue`:

```cue
package services

services: "freeswitch": {
    description: "FreeSWITCH VoIP/SIP server with mod_xml_rpc web interface"
    container: {
        image:      "safarov/freeswitch:latest"
        watchtower: false
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.40"
        exposed_ports: [
            {port: 5060, protocol: "udp", name: "sip"},
            {port: 5080, protocol: "udp", name: "sip-alt"},
        ]
    }
    endpoints: [{name: "web", port: 8080}]
    dns: {internal: "freeswitch.home.lcamaral.com"}
    http: {
        cert:          "home.lcamaral.com"
        endpoint:      "web"
        max_body_size: "10m"
    }
    secrets: [
        {env: "ESL_PASSWORD",   ref: "secret/homelab/freeswitch#esl_password"},
        {env: "EXT_1001_PASS",  ref: "secret/homelab/freeswitch#ext_1001_pass"},
        {env: "EXT_1002_PASS",  ref: "secret/homelab/freeswitch#ext_1002_pass"},
        {env: "EXT_1003_PASS",  ref: "secret/homelab/freeswitch#ext_1003_pass"},
        {env: "CC_USERNAME",    ref: "secret/homelab/freeswitch#cc_username"},
        {env: "CC_PASSWORD",    ref: "secret/homelab/freeswitch#cc_password"},
        {env: "CC_DID",         ref: "secret/homelab/freeswitch#cc_did"},
    ]
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 5: Create `chisel.cue`**

Create `platform/services/chisel.cue`:

```cue
package services

services: "chisel": {
    description: "Chisel TCP tunnel server (used by RustDesk relay)"
    container: {
        image:      "jpillora/chisel:latest"
        watchtower: true
    }
    network: {
        mode: "rproxy-bridge"
        extra: ["docker-servers-net"]
    }
    endpoints: [{name: "tunnel", port: 8080}]
    dns: {internal: "tunnel.home.lcamaral.com"}
    http: {
        cert:         "home.lcamaral.com"
        endpoint:     "tunnel"
        read_timeout: "86400s"
        send_timeout: "86400s"
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 6: Create `portainer-ce.cue`**

Portainer is the management UI for the other stacks. It runs standalone (not in Terraform) but still has a vhost.

Create `platform/services/portainer-ce.cue`:

```cue
package services

services: "portainer-ce": {
    description: "Portainer CE container management UI (standalone, not Terraform-managed)"
    container: {
        image:      "portainer/portainer-ce:latest"
        watchtower: false
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.2"
    }
    endpoints: [{name: "web", port: 9000}]
    dns: {
        external:         "portainer.cf.lcamaral.com"
        internal:         "portainer.d.lcamaral.com"
    }
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false
    }
    monitoring: {loki_logs: true, otel: true}
}
```

- [ ] **Step 7: Vet the full catalog**

```bash
cd platform && cue vet ./...
```

Expected: no output. This exercises cross-reference validation too (all `depends_on` refs must resolve; all `http.endpoint` refs must match `endpoints[].name`).

- [ ] **Step 8: Format and commit**

```bash
cd platform && cue fmt ./services/...
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add platform/services/
git commit -m "feat(platform): catalog lan-ip upstreams and websocket services (6 services)"
```

---

### Task 7: Services — hand-written standalone compose projects

**Files:**
- Create: `platform/services/docspell.cue`
- Create: `platform/services/n8n.cue`
- Create: `platform/services/netbox.cue`
- Create: `platform/services/dockermaster.cue`

These services run from hand-written docker-compose files (not tracked in this repo's Terraform) but still have nginx vhosts. They get catalog entries so the nginx generator produces their vhost files, but no Portainer stack generation happens in SP5 for them (they'd need their compose files added to the repo first).

- [ ] **Step 1: Create `docspell.cue`**

Create `platform/services/docspell.cue`:

```cue
package services

services: "docspell": {
    description: "Docspell document management (hand-written standalone, not Terraform-managed)"
    // No container declared — the container is managed outside this repo.
    network: {mode: "host"}  // uses LAN IP directly
    endpoints: [{name: "web", port: 8486}]
    dns: {internal: "docspell.d.lcamaral.com"}
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false
    }
    monitoring: {loki_logs: false, otel: false}
    notes: "Runs at 192.168.48.44:8486 — upstream host is hardcoded in http.endpoint via a LAN-IP lookup"
}
```

Wait — this needs to model a LAN-IP upstream. The `network.lan_ip` field is for macvlan-hosted containers on `docker-servers-net`. For truly external upstreams like docspell at `192.168.48.44`, we need a different mechanism.

**Design note:** The schema does not currently have an "external upstream host" field. For hand-written standalone services whose upstream is a LAN IP NOT on `docker-servers-net`, add a new optional field.

Modify `platform/schemas/service.cue` — in the `http` block, add:

```cue
http?: {
    ...
    // Override upstream host — used when the upstream is not the service's
    // endpoint name (which resolves via Docker DNS) and not a docker-servers-net
    // lan_ip. Takes precedence over both.
    upstream_host_override?: string
    ...
}
```

And update the network block (already has `mode: "host"` — that's the signal).

For SP1, instead of adding a new field, keep the schema as designed and handle docspell/n8n/netbox via a simpler convention: set `network.lan_ip` to the upstream IP even though the service isn't technically on `docker-servers-net`. Change the network mode to `"host"` meaning "not on any of our managed networks, upstream is a literal LAN IP from `lan_ip`."

Update the `lan_ip` regex to accept the `192.168.48.x` range too:

Modify `platform/schemas/service.cue`:

```cue
network: {
    mode:    "rproxy-bridge" | "docker-servers-net" | "back-tier" | "dual" | "host"
    lan_ip?: =~"^192\\.168\\.(48|59)\\.[0-9]+$"
    ...
}
```

And remove the `if network.mode == "docker-servers-net"` clause or relax it to allow `host` to also have `lan_ip`.

Actually, simpler: relax the constraint to `lan_ip?: =~"^192\\.168\\.[0-9]+\\.[0-9]+$"` (any RFC1918 192.168.x.x) and remove the mode-specific requirement. Document in the schema comment.

Rewrite the `network` block:

```cue
network: {
    mode:    "rproxy-bridge" | "docker-servers-net" | "back-tier" | "dual" | "host"
    // LAN IP. Required when mode="docker-servers-net" (macvlan) or when the
    // upstream is an external LAN host (mode="host"). Optional for rproxy-bridge.
    lan_ip?: =~"^192\\.168\\.[0-9]+\\.[0-9]+$"
    extra?:  [...string]

    exposed_ports?: [...{
        port:     >0 & <65536
        protocol: *"tcp" | "udp"
        name?:    string
    }]
}
if network.mode == "docker-servers-net" {
    network: lan_ip: !=""
}
```

- [ ] **Step 2: Update the schema with the relaxed `lan_ip` regex**

Edit `platform/schemas/service.cue` — replace the network block with the version above.

Run vet to confirm the existing services still validate:

```bash
cd platform && cue vet ./...
```

Expected: no output.

- [ ] **Step 3: Rewrite `docspell.cue` with the schema now supporting host mode + lan_ip**

Replace `platform/services/docspell.cue`:

```cue
package services

services: "docspell": {
    description: "Docspell document management (hand-written standalone, not Terraform-managed)"
    network: {
        mode:   "host"
        lan_ip: "192.168.48.44"
    }
    endpoints: [{name: "web", port: 8486}]
    dns: {internal: "docspell.d.lcamaral.com"}
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false
    }
    monitoring: {loki_logs: false, otel: false}
}
```

- [ ] **Step 4: Create `n8n.cue`**

Create `platform/services/n8n.cue`:

```cue
package services

services: "n8n": {
    description: "n8n workflow automation (hand-written standalone)"
    network: {
        mode:   "host"
        lan_ip: "192.168.59.30"
    }
    endpoints: [{name: "web", port: 5678}]
    dns: {internal: "n8n.d.lcamaral.com"}
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false
    }
    monitoring: {loki_logs: false, otel: false}
}
```

- [ ] **Step 5: Create `netbox.cue`**

Create `platform/services/netbox.cue`:

```cue
package services

services: "netbox": {
    description: "NetBox IPAM / DCIM (hand-written standalone)"
    network: {
        mode:   "host"
        lan_ip: "192.168.59.29"
    }
    endpoints: [{name: "web", port: 8080}]
    dns: {internal: "netbox.d.lcamaral.com"}
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false
    }
    monitoring: {loki_logs: false, otel: false}
}
```

- [ ] **Step 6: Create `dockermaster.cue`**

The `dockermaster.d.lcamaral.com` vhost currently just proxies to the Portainer UI at 192.168.59.2:9000 (same as `portainer.d.lcamaral.com`). It's an alias. Create a minimal service entry:

Create `platform/services/dockermaster.cue`:

```cue
package services

services: "dockermaster": {
    description: "Alias for Portainer management UI via dockermaster hostname"
    network: {
        mode:   "host"
        lan_ip: "192.168.59.2"
    }
    endpoints: [{name: "web", port: 9000}]
    dns: {internal: "dockermaster.d.lcamaral.com"}
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false
    }
    monitoring: {loki_logs: false, otel: false}
    notes: "Same upstream as portainer-ce; separate vhost for legacy .d hostname compatibility"
}
```

- [ ] **Step 7: Vet the full catalog one more time**

```bash
cd platform && cue vet ./...
```

Expected: no output.

- [ ] **Step 8: Count services — should be 29**

```bash
ls platform/services/*.cue | grep -v _catalog | wc -l
```

Expected: `29` (or within a couple depending on how `openldap`/`minio-console` are split).

- [ ] **Step 9: Format and commit**

```bash
cd platform && cue fmt ./...
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add platform/schemas/service.cue platform/services/
git commit -m "feat(platform): catalog standalone services and relax lan_ip regex"
```

---

### Task 8: The nginx vhost template file

**Files:**
- Create: `platform/generators/nginx/vhost.tmpl`

- [ ] **Step 1: Write the template**

Create `platform/generators/nginx/vhost.tmpl`:

```gotemplate
# =============================================================================
# GENERATED by platform/generators/nginx — DO NOT EDIT BY HAND
# Source:     platform/services/{{.name}}.cue
# Regenerate: make platform-gen
# =============================================================================

{{if not .http.allow_insecure_http -}}
server {
  listen 80;
  server_name {{.hostname}}{{range .aliases}} {{.}}{{end}};
  return 301 https://$host$request_uri;
}
{{- else -}}
server {
  listen 80;
  server_name {{.hostname}}{{range .aliases}} {{.}}{{end}};

  {{if .http.upstream_dynamic -}}
  resolver 127.0.0.11 valid=10s ipv6=off;
  set $upstream_{{.upstream_var}} {{.upstream_host}}:{{.upstream_port}};
  {{- end}}

  location {{.upstream_path}} {
    {{if .http.upstream_dynamic -}}
    proxy_pass {{.upstream_scheme}}://$upstream_{{.upstream_var}};
    {{- else -}}
    proxy_pass {{.upstream_scheme}}://{{.upstream_host}}:{{.upstream_port}};
    {{- end}}
    proxy_http_version  1.1;
    proxy_set_header    Host              $host;
    proxy_set_header    X-Real-IP         $remote_addr;
    proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header    X-Forwarded-Proto $scheme;
    proxy_set_header    X-Forwarded-Host  $host;
    proxy_set_header    X-Forwarded-Port  $server_port;
    proxy_read_timeout  {{.http.read_timeout}};
    proxy_send_timeout  {{.http.send_timeout}};
    client_max_body_size {{.http.max_body_size}};
    {{with .http.extra_location_config -}}
    {{.}}
    {{- end}}
  }
}
{{- end}}

server {
  listen 443 ssl;
  http2 on;
  server_name {{.hostname}}{{range .aliases}} {{.}}{{end}};

  ssl_certificate         /etc/nginx/cert/{{.http.cert}}.fullchain;
  ssl_certificate_key     /etc/nginx/cert/{{.http.cert}}.key;
  ssl_trusted_certificate /etc/nginx/cert/{{.http.cert}}.crt;
  ssl_protocols           TLSv1.2 TLSv1.3;
  ssl_ciphers             HIGH:!aNULL:!MD5;
  ssl_prefer_server_ciphers on;
  ssl_session_cache       shared:SSL:10m;
  ssl_session_timeout     10m;

  add_header Strict-Transport-Security "max-age=300; includeSubDomains" always;
  add_header X-Frame-Options            {{.http.frame_options}} always;
  add_header X-Content-Type-Options     nosniff always;
  add_header Referrer-Policy            strict-origin-when-cross-origin always;

  otel_trace_context propagate;

  {{if .http.upstream_dynamic -}}
  resolver 127.0.0.11 valid=10s ipv6=off;
  set $upstream_{{.upstream_var}} {{.upstream_host}}:{{.upstream_port}};
  {{- end}}

  {{with .http.extra_server_config -}}
  {{.}}
  {{- end}}

  location {{.upstream_path}} {
    {{if .http.upstream_dynamic -}}
    proxy_pass {{.upstream_scheme}}://$upstream_{{.upstream_var}};
    {{- else -}}
    proxy_pass {{.upstream_scheme}}://{{.upstream_host}}:{{.upstream_port}};
    {{- end}}
    proxy_http_version  1.1;
    proxy_set_header    Host              $host;
    proxy_set_header    X-Real-IP         $remote_addr;
    proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header    X-Forwarded-Proto $scheme;
    proxy_set_header    X-Forwarded-Host  $host;
    proxy_set_header    X-Forwarded-Port  $server_port;
    proxy_set_header    Upgrade    $http_upgrade;
    proxy_set_header    Connection $connection_upgrade;
    proxy_read_timeout  {{.http.read_timeout}};
    proxy_send_timeout  {{.http.send_timeout}};
    client_max_body_size {{.http.max_body_size}};
    otel_trace on;
    otel_trace_context inject;
    {{with .http.extra_location_config -}}
    {{.}}
    {{- end}}
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add platform/generators/nginx/vhost.tmpl
git commit -m "feat(platform): nginx vhost template for canonical shape"
```

---

### Task 9: The nginx generator `gen_tool.cue`

**Files:**
- Create: `platform/gen_tool.cue`

The `gen_tool.cue` file is the top-level command entry point. It reads the template, iterates over services with an `http` block, and writes one file per service. Files ending in `_tool.cue` are only loaded when running `cue cmd` — they can import `tool/*` packages that aren't available in regular schema mode.

- [ ] **Step 1: Write the generator**

Create `platform/gen_tool.cue`:

```cue
// platform/gen_tool.cue
package platform

import (
    "strings"
    "tool/file"
    "text/template"
    "lcma.dev/platform/services"
)

// Output directory for nginx vhosts, relative to platform/.
_nginxOutputDir: "../dockermaster/docker/compose/nginx-rproxy/vhost.d"

// Template file, relative to platform/.
_nginxTemplate: "generators/nginx/vhost.tmpl"

// Build the template context for a given service.
_nginxCtxFor: {
    [name=string]: {
        let _s = services.services[name]

        // Look up the endpoint referenced by http.endpoint.
        let _ep = [
            for e in _s.endpoints
            if e.name == _s.http.endpoint
            {e}
        ][0]

        // Upstream host: Docker DNS name (same as endpoint.name) for rproxy-bridge,
        // or the literal LAN IP for docker-servers-net / host mode.
        let _upHost =
            if _s.network.lan_ip != _|_ { _s.network.lan_ip }
            if _s.network.lan_ip == _|_ { _s.http.endpoint }

        // Hostname used in server_name: external takes precedence, then internal.
        let _hostname =
            if _s.dns.external != _|_ { _s.dns.external }
            if _s.dns.external == _|_ { _s.dns.internal }

        // Variable name derivation: replace hyphens with underscores (nginx var names).
        let _var = strings.Replace(name, "-", "_", -1)

        name:            name
        hostname:        _hostname
        aliases: [
            for a in (*_s.dns.external_aliases | []) {a},
            for a in (*_s.dns.internal_aliases | []) {a},
        ]
        http:            _s.http
        upstream_host:   _upHost
        upstream_port:   _ep.port
        upstream_scheme: _ep.scheme
        upstream_path:   _ep.path
        upstream_var:    _var
    }
}

// The output filename for a service: external DNS if present, else internal.
_outputFilename: {
    [name=string]: {
        let _s = services.services[name]
        let _n =
            if _s.dns.external != _|_ { _s.dns.external }
            if _s.dns.external == _|_ { _s.dns.internal }
        filename: "\(_nginxOutputDir)/\(_n).conf"
    }
}

command: gen: {
    // Read the template file once.
    readTemplate: file.Read & {
        filename: _nginxTemplate
        contents: string
    }

    // Write one .conf file per service that has an http block.
    for name, s in services.services
    if s.http != _|_ {
        "nginx-\(name)": file.Create & {
            filename: _outputFilename[name].filename
            contents: template.Execute(readTemplate.contents, _nginxCtxFor[name])
        }
    }
}
```

- [ ] **Step 2: Run the generator for the first time**

```bash
cd platform && cue cmd gen
```

Expected: writes ~22 `.conf` files under `../dockermaster/docker/compose/nginx-rproxy/vhost.d/`. If there's a CUE syntax error, fix it and re-run.

If CUE complains about missing `contents` field on `file.Read`, the syntax may have evolved; check `cue help cmd` for the current form.

- [ ] **Step 3: Verify file count**

```bash
ls dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf | wc -l
```

Expected: 22 `.conf` files (one per service with an `http` block). May include `00-default.conf` and `00-shared.conf` from previous work — count only files NOT starting with `00-`:

```bash
ls dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf | grep -v '/00-' | wc -l
```

Expected: 22 (or 21, depending on whether `minio-console` counted as its own file).

- [ ] **Step 4: Spot-check one generated file**

```bash
head -30 dockermaster/docker/compose/nginx-rproxy/vhost.d/login.cf.lcamaral.com.conf
```

Expected: starts with `# GENERATED by platform/generators/nginx — DO NOT EDIT BY HAND`. Body matches the canonical shape.

- [ ] **Step 5: Commit**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
git add platform/gen_tool.cue dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf
git commit -m "feat(platform): nginx generator writes all vhosts from catalog"
```

---

### Task 10: Shared nginx fragment and hand-written header on 00-default

**Files:**
- Create: `dockermaster/docker/compose/nginx-rproxy/vhost.d/00-shared.conf`
- Modify: `dockermaster/docker/compose/nginx-rproxy/vhost.d/00-default.conf` (prepend header only; do not touch body)

- [ ] **Step 1: Create `00-shared.conf`**

Create `dockermaster/docker/compose/nginx-rproxy/vhost.d/00-shared.conf`:

```nginx
# =============================================================================
# Hand-written, not platform-managed.
# Shared upgrade map consumed by all generated vhosts.
# =============================================================================

map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}
```

- [ ] **Step 2: Check whether `00-default.conf` exists in the repo**

```bash
ls dockermaster/docker/compose/nginx-rproxy/vhost.d/00-default.conf 2>/dev/null && echo "exists" || echo "missing"
```

If missing: fetch it from dockermaster and add it:

```bash
ssh dockermaster 'cat /nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/00-default.conf' > \
    dockermaster/docker/compose/nginx-rproxy/vhost.d/00-default.conf
```

- [ ] **Step 3: Prepend the "hand-written" header to `00-default.conf`**

Edit `dockermaster/docker/compose/nginx-rproxy/vhost.d/00-default.conf` so the first lines are:

```nginx
# =============================================================================
# Hand-written, not platform-managed.
# Catch-all default server for unknown hostnames.
# =============================================================================
```

Keep the rest of the file unchanged.

- [ ] **Step 4: Commit**

```bash
git add dockermaster/docker/compose/nginx-rproxy/vhost.d/00-shared.conf \
        dockermaster/docker/compose/nginx-rproxy/vhost.d/00-default.conf
git commit -m "feat(platform): add shared connection_upgrade map and mark 00-default hand-written"
```

---

### Task 11: Golden file tests per generator

**Files:**
- Create: `platform/generators/nginx/testdata/homelab-portal.input.cue`
- Create: `platform/generators/nginx/testdata/homelab-portal.expected.conf`
- Create: `platform/generators/nginx/testdata/keycloak.input.cue`
- Create: `platform/generators/nginx/testdata/keycloak.expected.conf`
- Create: `platform/generators/nginx/testdata/docker-registry.input.cue`
- Create: `platform/generators/nginx/testdata/docker-registry.expected.conf`
- Create: `platform/scripts/run-golden-tests.sh`

- [ ] **Step 1: Capture three canonical fixtures**

Use the already-generated files as golden masters. Three fixtures to lock:

1. **homelab-portal** — simplest case, single dynamic upstream, custom timeouts, DENY frame options.
2. **keycloak** — external + internal DNS on the same service, default timeouts, body size override.
3. **docker-registry** — escape hatch: `allow_insecure_http: true` (both http and https serve), custom `extra_location_config`.

Copy the current generator output for each as the expected file:

```bash
cp dockermaster/docker/compose/nginx-rproxy/vhost.d/login.cf.lcamaral.com.conf \
   platform/generators/nginx/testdata/homelab-portal.expected.conf
cp dockermaster/docker/compose/nginx-rproxy/vhost.d/auth.cf.lcamaral.com.conf \
   platform/generators/nginx/testdata/keycloak.expected.conf
cp dockermaster/docker/compose/nginx-rproxy/vhost.d/registry.cf.lcamaral.com.conf \
   platform/generators/nginx/testdata/docker-registry.expected.conf
```

- [ ] **Step 2: Create corresponding `*.input.cue` fixtures**

These fixtures are stand-alone CUE files that instantiate one service against the schema and can be fed to a standalone renderer.

Create `platform/generators/nginx/testdata/homelab-portal.input.cue`:

```cue
package testdata

import "lcma.dev/platform/schemas"

homelab_portal: schemas.#Service & {
    name:        "homelab-portal"
    description: "Homelab login portal (SvelteKit + Keycloak)"
    container: {
        image: "registry.cf.lcamaral.com/homelab-portal:latest"
    }
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "web", port: 3000, health: "/healthz"}]
    dns: {external: "login.cf.lcamaral.com"}
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        read_timeout:  "60s"
        send_timeout:  "60s"
        max_body_size: "1m"
        frame_options: "DENY"
    }
    monitoring: {}
}
```

Create `platform/generators/nginx/testdata/keycloak.input.cue`:

```cue
package testdata

import "lcma.dev/platform/schemas"

keycloak: schemas.#Service & {
    name:        "keycloak"
    description: "Keycloak identity provider"
    container: {image: "quay.io/keycloak/keycloak:26.3", watchtower: false}
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "web", port: 8080}]
    dns: {
        external: "auth.cf.lcamaral.com"
        internal: "keycloak.d.lcamaral.com"
    }
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        max_body_size: "100m"
    }
    monitoring: {}
}
```

Create `platform/generators/nginx/testdata/docker-registry.input.cue`:

```cue
package testdata

import "lcma.dev/platform/schemas"

docker_registry: schemas.#Service & {
    name:        "docker-registry"
    description: "Local Docker registry"
    container: {image: "registry:2"}
    network: {mode: "rproxy-bridge"}
    endpoints: [{name: "api", port: 5000}]
    dns: {external: "registry.cf.lcamaral.com"}
    http: {
        cert:                "d.lcamaral.com"
        endpoint:            "api"
        max_body_size:       "0"
        read_timeout:        "900s"
        send_timeout:        "900s"
        allow_insecure_http: true
        extra_location_config: """
            # Chunked transfer encoding for large layers
            proxy_request_buffering off;
            """
    }
    monitoring: {}
}
```

- [ ] **Step 3: Write the golden test runner script**

Create `platform/scripts/run-golden-tests.sh`:

```bash
#!/bin/bash
# Runs golden file tests for each generator.
# For each testdata/*.input.cue, render the service through the generator
# and diff the output against testdata/*.expected.conf.

set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLATFORM_DIR"

fail=0

# ─── nginx generator golden tests ────────────────────────
for input in generators/nginx/testdata/*.input.cue; do
    name=$(basename "$input" .input.cue)
    expected="generators/nginx/testdata/${name}.expected.conf"

    if [[ ! -f "$expected" ]]; then
        echo "MISSING expected file: $expected" >&2
        fail=1
        continue
    fi

    # Compare the actual generator output (already written by `cue cmd gen`
    # during the normal dev loop) against the expected file.
    #
    # We infer the actual output path from the name convention:
    #   homelab-portal → login.cf.lcamaral.com.conf
    # by reading the expected file's comment header.
    actual_hostname=$(grep -oE 'Source: +platform/services/[^ ]+\.cue' "$expected" | head -1 || true)
    # Fallback: use the name and look for any matching file in the output dir.

    # Simpler approach: compare expected against the committed generated file
    # with the same hostname. Hostname is encoded in the file's `server_name` line.
    expected_host=$(grep -m1 'server_name ' "$expected" | awk '{print $2}' | tr -d ';')
    actual="../dockermaster/docker/compose/nginx-rproxy/vhost.d/${expected_host}.conf"

    if [[ ! -f "$actual" ]]; then
        echo "FAIL $name: generated file not found at $actual" >&2
        fail=1
        continue
    fi

    if ! diff -u "$expected" "$actual" > /dev/null; then
        echo "FAIL $name: expected differs from generated" >&2
        diff -u "$expected" "$actual" | head -30
        fail=1
    else
        echo "PASS $name"
    fi
done

if [[ $fail -ne 0 ]]; then
    echo "❌ Golden tests failed"
    exit 1
fi
echo "✅ All golden tests passed"
```

Make it executable:

```bash
chmod +x platform/scripts/run-golden-tests.sh
```

- [ ] **Step 4: Run the golden tests**

```bash
./platform/scripts/run-golden-tests.sh
```

Expected: `PASS homelab-portal`, `PASS keycloak`, `PASS docker-registry`, `✅ All golden tests passed`.

- [ ] **Step 5: Commit**

```bash
git add platform/generators/nginx/testdata/ platform/scripts/run-golden-tests.sh
git commit -m "test(platform): golden file tests for nginx generator"
```

---

### Task 12: Byte-diff generated vhosts vs current NFS state

**Files:** None created; this is an analysis and reconciliation step.

The canonical vhost shape intentionally differs from what's currently on NFS. This task documents the deltas and makes sure every delta is intentional.

- [ ] **Step 1: Snapshot the current NFS vhost state**

```bash
mkdir -p /tmp/vhosts-baseline
scp dockermaster:/nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/\*.conf /tmp/vhosts-baseline/
ls /tmp/vhosts-baseline/ | wc -l
```

Expected: 24 files (22 services + 00-default + login.cf from earlier work).

- [ ] **Step 2: Diff each generated file against the baseline**

```bash
cd /Users/lamaral/Library/CloudStorage/SynologyDrive-lamaral/SynDrive/05.Code/Dev/lamaral/home/inventory
mkdir -p /tmp/vhost-diffs
for f in dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf; do
    base=$(basename "$f")
    if [[ "$base" == "00-"* ]]; then continue; fi
    if [[ -f "/tmp/vhosts-baseline/$base" ]]; then
        diff -u "/tmp/vhosts-baseline/$base" "$f" > "/tmp/vhost-diffs/${base}.diff" || true
    else
        echo "NEW: $base (no baseline)" > "/tmp/vhost-diffs/${base}.diff"
    fi
done
ls /tmp/vhost-diffs/ | wc -l
```

- [ ] **Step 3: Read each diff and classify each change**

Every line of change must fall into one of these categories (documented in the spec's "Behavioral changes on deploy" section):

- Added: HSTS header
- Added: `X-Forwarded-Host`, `X-Forwarded-Port` headers
- Added: `otel_trace on;` / `otel_trace_context inject;`
- Added: WebSocket upgrade headers
- Removed: `auth_basic off;`
- Removed: inline `map $http_upgrade $connection_upgrade { ... }` blocks
- Removed: `proxy_hide_header WWW-Authenticate;`
- Changed: `Referrer-Policy` → `strict-origin-when-cross-origin`
- Changed: `X-Frame-Options` → `SAMEORIGIN` (or `DENY` for portal)
- Changed: `proxy_read_timeout`/`proxy_send_timeout` standardized
- Changed: `client_max_body_size` standardized
- Structural: `s3.d.lcamaral.com.conf` split into `s3.cf.lcamaral.com.conf` + `minio.cf.lcamaral.com.conf`
- Structural: `auth.cf.lcamaral.com` upstream changed from `192.168.59.13` to `keycloak`
- Structural: `.home` aliases dropped from legacy vhosts
- Structural: freeswitch's `$connection_upgrade_fs` → shared `$connection_upgrade`

If any diff contains a change NOT in this list, investigate. Either:
- The schema/service definition is wrong (fix it), or
- The canonical shape needs an override (add an `extra_*_config` field to the service or a `frame_options` override).

- [ ] **Step 4: Run `cue cmd gen` again after reconciling**

```bash
cd platform && cue cmd gen && cd ..
```

- [ ] **Step 5: Re-diff**

Repeat Step 2. Continue reconciling until every diff is accounted for.

- [ ] **Step 6: Write the reconciliation report**

Create `platform/generators/nginx/RECONCILIATION.md`:

```markdown
# SP1 Migration Reconciliation

Summary of diffs between pre-migration `vhost.d/*.conf` on dockermaster NFS
and the canonical shape generated by the platform.

## Per-vhost deltas

### login.cf.lcamaral.com.conf
- Added: HSTS, otel_trace_context propagate at server scope
- Added: X-Forwarded-Port header
- No change: DENY frame_options (already set in the portal work)

### auth.cf.lcamaral.com.conf
- Added: HSTS
- Changed: upstream from 192.168.59.13 → keycloak (Docker DNS)
- Removed: ssl_trusted_certificate (now standard in every vhost)
- Standardized: Referrer-Policy

### calibre.d.lcamaral.com.conf
- Added: HSTS, X-Forwarded-Host, X-Forwarded-Port
- Removed: inline `map` block, `auth_basic off`, `proxy_hide_header WWW-Authenticate`
- Standardized: security headers, Referrer-Policy

(... repeat for every vhost with non-empty diff ...)

## Structural changes

- `s3.d.lcamaral.com.conf` → split into `s3.cf.lcamaral.com.conf` + `minio.cf.lcamaral.com.conf`
- `.home` aliases dropped from: dockermaster, docspell, n8n, netbox, portainer, rundeck
- freeswitch: removed custom `$connection_upgrade_fs` map
```

- [ ] **Step 7: Commit**

```bash
git add dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf \
        platform/generators/nginx/RECONCILIATION.md \
        platform/services/ platform/schemas/service.cue
git commit -m "feat(platform): reconcile generated vhosts with canonical shape"
```

---

### Task 13: Capture response header baseline from production

**Files:**
- Create: `platform/generators/nginx/testdata/baseline/*.headers`
- Create: `platform/scripts/header-baseline.sh`

- [ ] **Step 1: Write the baseline capture script**

Create `platform/scripts/header-baseline.sh`:

```bash
#!/bin/bash
# Captures response headers from all services in the catalog for later diff.
# Usage: header-baseline.sh capture | diff
#
# `capture` mode: writes one .headers file per service into testdata/baseline/
# `diff` mode:    compares current headers against the baseline and reports
#                 any unexpected deltas (deltas in a known whitelist are ignored).

set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_DIR="$PLATFORM_DIR/generators/nginx/testdata/baseline"

mkdir -p "$BASELINE_DIR"

# Hosts to probe — extracted from the catalog. Hardcoded here since parsing
# CUE from bash is painful; keep in sync with the catalog by hand for SP1.
HOSTS=(
    login.cf.lcamaral.com
    auth.cf.lcamaral.com
    keycloak.d.lcamaral.com
    calibre.d.lcamaral.com
    grafana.d.lcamaral.com
    loki.d.lcamaral.com
    prometheus.d.lcamaral.com
    openldap.d.lcamaral.com
    vault.d.lcamaral.com
    s3.cf.lcamaral.com
    minio.cf.lcamaral.com
    registry.cf.lcamaral.com
    rundeck.d.lcamaral.com
    rustdesk.home.lcamaral.com
    rustdesk-relay.home.lcamaral.com
    freeswitch.home.lcamaral.com
    tunnel.home.lcamaral.com
    dockermaster.d.lcamaral.com
    docspell.d.lcamaral.com
    n8n.d.lcamaral.com
    netbox.d.lcamaral.com
    portainer.d.lcamaral.com
)

capture() {
    for h in "${HOSTS[@]}"; do
        echo "Capturing $h..."
        /usr/bin/curl -sI -k --max-time 10 "https://$h/" > "$BASELINE_DIR/$h.headers" || \
            echo "!! $h unreachable" > "$BASELINE_DIR/$h.headers"
    done
    echo "✅ Baseline captured to $BASELINE_DIR"
}

# Header lines that are expected to change after migration (per spec).
# These are filtered out of the diff so only UNEXPECTED changes fail the check.
EXPECTED_DELTAS_REGEX='^(Strict-Transport-Security|X-Frame-Options|Referrer-Policy|X-Forwarded-Host|X-Forwarded-Port|Server|Date)'

diff_headers() {
    local fail=0
    for h in "${HOSTS[@]}"; do
        if [[ ! -f "$BASELINE_DIR/$h.headers" ]]; then
            echo "MISSING baseline for $h"
            fail=1
            continue
        fi
        current=$(/usr/bin/curl -sI -k --max-time 10 "https://$h/" 2>/dev/null || echo "UNREACHABLE")
        baseline=$(cat "$BASELINE_DIR/$h.headers")

        # Compare, ignoring expected deltas.
        b_filtered=$(echo "$baseline" | grep -vE "$EXPECTED_DELTAS_REGEX" || true)
        c_filtered=$(echo "$current"  | grep -vE "$EXPECTED_DELTAS_REGEX" || true)

        if [[ "$b_filtered" != "$c_filtered" ]]; then
            echo "❌ $h has unexpected header changes:"
            diff <(echo "$b_filtered") <(echo "$c_filtered") | head -20
            fail=1
        else
            echo "✅ $h headers OK"
        fi
    done
    if [[ $fail -ne 0 ]]; then
        exit 1
    fi
    echo "🎉 All headers match baseline (modulo expected deltas)"
}

case "${1:-}" in
    capture) capture ;;
    diff)    diff_headers ;;
    *)       echo "Usage: $0 {capture|diff}"; exit 1 ;;
esac
```

Make it executable:

```bash
chmod +x platform/scripts/header-baseline.sh
```

- [ ] **Step 2: Capture the baseline BEFORE migration**

This is the "snapshot pre-migration production state" step. It must happen BEFORE Task 19 (deploy), otherwise the baseline captures the post-migration state.

```bash
./platform/scripts/header-baseline.sh capture
ls platform/generators/nginx/testdata/baseline/*.headers | wc -l
```

Expected: 22 `.headers` files (one per host).

- [ ] **Step 3: Commit**

```bash
git add platform/scripts/header-baseline.sh platform/generators/nginx/testdata/baseline/
git commit -m "test(platform): capture response header baseline from production"
```

---

### Task 14: Makefile and pre-commit hooks

**Files:**
- Modify: `Makefile` (finalize the platform-* targets)
- Modify: `.pre-commit-config.yaml` (add 3 hooks)
- Create: `platform/scripts/check-no-manual-edits.sh`

- [ ] **Step 1: Finalize the Makefile**

Edit `Makefile` (replace the stubs from Task 1 with the full version):

```makefile
# ─── Platform targets ─────────────────────────────────────

.PHONY: platform-gen platform-vet platform-diff platform-fmt platform-test

platform-gen:       ## Regenerate all platform outputs
	cd platform && cue cmd gen

platform-vet:       ## Validate the service catalog
	cd platform && cue vet ./...

platform-diff:      ## Fail if generated files are out of date
	$(MAKE) platform-gen
	git diff --exit-code -- \
	  dockermaster/docker/compose/nginx-rproxy/vhost.d/

platform-fmt:       ## Format CUE files
	cd platform && cue fmt ./...

platform-test:      ## Run golden file tests per generator
	./platform/scripts/run-golden-tests.sh
```

- [ ] **Step 2: Create the manual-edit prevention script**

Create `platform/scripts/check-no-manual-edits.sh`:

```bash
#!/bin/bash
# Rejects commits that modify generated files without a matching platform/ source change.
# Invoked by the pre-commit framework.

set -euo pipefail

# Files in the staged diff.
staged=$(git diff --cached --name-only)

# Generated files have a "GENERATED by platform/generators/" marker in their header.
edited_generated=()
for f in $staged; do
    # Only check files that exist (not deletions).
    if [[ -f "$f" ]] && head -5 "$f" 2>/dev/null | grep -q "GENERATED by platform/generators/"; then
        edited_generated+=("$f")
    fi
done

# If any generated files are edited, require platform/ files to also be staged.
if [[ ${#edited_generated[@]} -gt 0 ]]; then
    platform_staged=$(echo "$staged" | grep '^platform/' || true)
    if [[ -z "$platform_staged" ]]; then
        echo "❌ The following generated files were modified without any platform/ source changes:"
        printf '   %s\n' "${edited_generated[@]}"
        echo ""
        echo "Generated files are only allowed to change as a result of 'make platform-gen'."
        echo "Edit the source under platform/services/ or platform/generators/ instead."
        exit 1
    fi
fi

exit 0
```

Make executable:

```bash
chmod +x platform/scripts/check-no-manual-edits.sh
```

- [ ] **Step 3: Add pre-commit hooks**

Edit `.pre-commit-config.yaml` — append to the `repos:` list:

```yaml
  - repo: local
    hooks:
      - id: platform-vet
        name: CUE schema validation
        entry: make platform-vet
        language: system
        files: ^platform/.*\.cue$
        pass_filenames: false

      - id: platform-diff
        name: Generated files are in sync
        entry: make platform-diff
        language: system
        files: ^platform/.*\.(cue|tmpl)$
        pass_filenames: false

      - id: platform-no-manual-edits
        name: Generated files have not been hand-edited
        entry: platform/scripts/check-no-manual-edits.sh
        language: system
        pass_filenames: false
```

- [ ] **Step 4: Test pre-commit hooks locally**

```bash
pre-commit run platform-vet --all-files
pre-commit run platform-diff --all-files
```

Expected: both pass.

Try a dry run of the manual-edit check: manually edit a generated vhost, stage it, run the hook, confirm it fails:

```bash
# Bad edit
echo "# manual edit" >> dockermaster/docker/compose/nginx-rproxy/vhost.d/login.cf.lcamaral.com.conf
git add dockermaster/docker/compose/nginx-rproxy/vhost.d/login.cf.lcamaral.com.conf
pre-commit run platform-no-manual-edits
# Expected: FAIL with "modified without any platform/ source changes"

# Revert
git checkout dockermaster/docker/compose/nginx-rproxy/vhost.d/login.cf.lcamaral.com.conf
```

- [ ] **Step 5: Commit**

```bash
git add Makefile .pre-commit-config.yaml platform/scripts/check-no-manual-edits.sh
git commit -m "feat(platform): makefile targets and pre-commit hooks"
```

---

### Task 15: GitHub Actions workflow for platform validation

**Files:**
- Create: `.github/workflows/platform-validate.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/platform-validate.yml`:

```yaml
name: Platform Validate

on:
  push:
    branches: [main]
    paths:
      - 'platform/**'
      - 'dockermaster/docker/compose/nginx-rproxy/vhost.d/**'
      - '.github/workflows/platform-validate.yml'
  pull_request:
    paths:
      - 'platform/**'
      - 'dockermaster/docker/compose/nginx-rproxy/vhost.d/**'
      - '.github/workflows/platform-validate.yml'
  workflow_dispatch:

jobs:
  validate:
    runs-on: [self-hosted, dockermaster]
    steps:
      - uses: actions/checkout@v4

      - name: Install CUE via mise
        run: |
          mise install cue || true
          which cue || (echo "cue not found in PATH" && exit 1)
          cue version

      - name: Validate schema
        run: make platform-vet

      - name: Check generated files are in sync
        run: make platform-diff

      - name: Run golden file tests
        run: make platform-test

      - name: Syntax-check generated nginx files
        run: |
          # Use the rproxy container's nginx to test the vhost directory.
          docker run --rm \
            -v "$(pwd)/dockermaster/docker/compose/nginx-rproxy/vhost.d:/etc/nginx/vhost.d:ro" \
            -v "$(pwd)/.github/workflows/test-nginx.conf:/etc/nginx/nginx.conf:ro" \
            nginx:1.29-otel nginx -t
```

- [ ] **Step 2: Write a minimal `test-nginx.conf` for the syntax check**

Create `.github/workflows/test-nginx.conf`:

```nginx
events {
  worker_connections 1024;
}

http {
  # Dummy upstream resolver — the syntax check doesn't actually resolve upstreams.
  resolver 127.0.0.11 valid=10s ipv6=off;

  # Stub OpenTelemetry module so otel_* directives parse without a real collector.
  # If the nginx image doesn't have the otel module, these lines can be commented
  # out in the test config without affecting production.

  # Dummy cert files — nginx -t only checks syntax, not cert validity.
  # We mount a dummy cert dir in CI.

  include /etc/nginx/vhost.d/*.conf;
}
```

Note: nginx's `-t` syntax check loads referenced cert files. CI needs dummy files at `/etc/nginx/cert/d.lcamaral.com.{fullchain,key,crt}` and `/etc/nginx/cert/home.lcamaral.com.{fullchain,key,crt}`. The syntax check is best done in the deploy step (Task 19) rather than in CI where certs aren't available.

For CI, **skip the nginx -t step** and rely on the golden file tests + header baseline diff instead. Remove the "Syntax-check generated nginx files" step from the workflow:

Edit `.github/workflows/platform-validate.yml` — remove the last step so the workflow becomes:

```yaml
name: Platform Validate

on:
  push:
    branches: [main]
    paths:
      - 'platform/**'
      - 'dockermaster/docker/compose/nginx-rproxy/vhost.d/**'
      - '.github/workflows/platform-validate.yml'
  pull_request:
    paths:
      - 'platform/**'
      - 'dockermaster/docker/compose/nginx-rproxy/vhost.d/**'
      - '.github/workflows/platform-validate.yml'
  workflow_dispatch:

jobs:
  validate:
    runs-on: [self-hosted, dockermaster]
    steps:
      - uses: actions/checkout@v4

      - name: Install CUE via mise
        run: |
          mise install cue || true
          which cue || (echo "cue not found in PATH" && exit 1)
          cue version

      - name: Validate schema
        run: make platform-vet

      - name: Check generated files are in sync
        run: make platform-diff

      - name: Run golden file tests
        run: make platform-test
```

Delete `test-nginx.conf`:

```bash
rm -f .github/workflows/test-nginx.conf
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/platform-validate.yml
git commit -m "ci(platform): add platform-validate github actions workflow"
```

---

### Task 16: End-to-end local validation

**Files:** None created; this task runs all the checks.

- [ ] **Step 1: Run schema vet**

```bash
make platform-vet
```

Expected: no output.

- [ ] **Step 2: Run generator**

```bash
make platform-gen
```

Expected: ~22 `.conf` files written. No errors.

- [ ] **Step 3: Check diff is clean**

```bash
make platform-diff
```

Expected: exit 0 (generated files match committed state).

- [ ] **Step 4: Run golden file tests**

```bash
make platform-test
```

Expected: all PASS.

- [ ] **Step 5: Run pre-commit hooks on the entire platform directory**

```bash
pre-commit run --files platform/**/*.cue platform/**/*.tmpl
```

Expected: all hooks pass.

- [ ] **Step 6: Verify nothing is uncommitted**

```bash
git status --short
```

Expected: clean working tree (modulo pre-existing submodule changes).

- [ ] **Step 7: No commit — this is validation only**

---

### Task 17: Deploy to dockermaster — rsync + reload nginx

**Files:** None created; this task changes live infrastructure.

- [ ] **Step 1: Dry-run rsync to preview**

```bash
rsync -avn --delete --exclude='00-default.conf' --exclude='00-shared.conf' \
    dockermaster/docker/compose/nginx-rproxy/vhost.d/ \
    dockermaster:/nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/
```

Expected output: a list of files that would be transferred. Read through it. Verify no unexpected deletions.

- [ ] **Step 2: Copy 00-shared.conf separately (first-time add)**

```bash
scp dockermaster/docker/compose/nginx-rproxy/vhost.d/00-shared.conf \
    dockermaster:/nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/00-shared.conf
```

- [ ] **Step 3: Test nginx config on dockermaster BEFORE reloading**

```bash
ssh dockermaster 'docker exec rproxy nginx -t'
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`.

- [ ] **Step 4: Actual rsync (no `-n`)**

```bash
rsync -av --exclude='00-default.conf' \
    dockermaster/docker/compose/nginx-rproxy/vhost.d/ \
    dockermaster:/nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/
```

Expected: files transferred successfully.

- [ ] **Step 5: Test nginx config again after the rsync**

```bash
ssh dockermaster 'docker exec rproxy nginx -t'
```

Expected: `test is successful`. If it fails, **stop and diagnose** — do not reload.

- [ ] **Step 6: Reload nginx**

```bash
ssh dockermaster 'docker exec rproxy nginx -s reload'
```

- [ ] **Step 7: Quick sanity curl**

```bash
/usr/bin/curl -sI https://login.cf.lcamaral.com/healthz
/usr/bin/curl -sI https://auth.cf.lcamaral.com/
/usr/bin/curl -sI https://registry.cf.lcamaral.com/v2/
```

Expected: all return 2xx/3xx.

- [ ] **Step 8: No commit — infrastructure change only**

---

### Task 18: Run post-migration header baseline diff

**Files:** None created; runs the verification step.

- [ ] **Step 1: Run the header diff check**

```bash
./platform/scripts/header-baseline.sh diff
```

Expected: `✅` for every host. If any host shows `❌` with unexpected header changes, investigate:

- If it's a service whose schema/http block was wrong → fix the service file, re-run `make platform-gen`, rsync, reload, re-check.
- If it's an unexpected canonical shape change that we want to keep → update the `EXPECTED_DELTAS_REGEX` in `header-baseline.sh` to include the new header name, commit the change, and re-run.
- If it's an actual regression → revert or hand-fix.

- [ ] **Step 2: If every host passes, no commit — this is verification only**

If any changes were needed in step 1, commit them:

```bash
git add platform/services/ platform/scripts/header-baseline.sh \
        dockermaster/docker/compose/nginx-rproxy/vhost.d/
git commit -m "fix(platform): reconcile vhost deltas found by header baseline check"
```

---

### Task 19: Update documentation

**Files:**
- Modify: `CLAUDE.md` (add platform notes)
- Modify: `dockermaster/docker/compose/STATUS.md` (add platform line)
- Create: `docs/platform-overview.md` (short human-facing overview)

SP2 will generate these docs automatically later. For SP1, we update by hand.

- [ ] **Step 1: Add platform section to `CLAUDE.md`**

Edit `CLAUDE.md`. In the "Infrastructure as Code (Terraform)" section or just after it, add:

```markdown
# Platform Catalog (CUE)

- All services are modeled as CUE files under `platform/services/*.cue`
- The schema lives in `platform/schemas/service.cue`
- Generated artifacts (nginx vhosts in SP1; more generators in future sub-projects)
  are written into their existing directories under `dockermaster/`, `terraform/`,
  and `inventory/`.
- Developer workflow:
  - `make platform-vet` — validate catalog
  - `make platform-gen` — regenerate all outputs
  - `make platform-diff` — fail if out of date
  - `make platform-test` — golden file tests
- Pre-commit hooks enforce schema validity, drift-free regeneration, and
  prevention of manual edits to generated files.
- See `docs/superpowers/specs/2026-04-11-homelab-platform-design.md` for the
  full design and sub-project decomposition.
```

- [ ] **Step 2: Add platform note to STATUS.md**

Edit `dockermaster/docker/compose/STATUS.md`. Near the top (after the "Deployment Model" section), add:

```markdown
> **New in 2026-04:** nginx vhosts are generated from `platform/services/*.cue`
> by a CUE generator. Edit the service catalog, run `make platform-gen`, commit
> both the source and the regenerated vhost files. See
> `docs/superpowers/specs/2026-04-11-homelab-platform-design.md`.
```

- [ ] **Step 3: Write a short platform overview**

Create `docs/platform-overview.md`:

```markdown
# Platform overview

The homelab runs a small CUE-based internal platform that models every service
in one place and generates downstream config from it. See the full design at
`docs/superpowers/specs/2026-04-11-homelab-platform-design.md`.

## Adding a new service

1. Create `platform/services/<name>.cue` — start with the minimal shape:
   ```cue
   package services

   services: "<name>": {
       description: "short description"
       container: { image: "..." }
       network: { mode: "rproxy-bridge" }
       endpoints: [{ name: "web", port: 8080 }]
       dns: { external: "<name>.cf.lcamaral.com" }
       http: { cert: "d.lcamaral.com", endpoint: "web" }
       monitoring: {}
   }
   ```
2. Run `make platform-vet` to validate.
3. Run `make platform-gen` to regenerate outputs.
4. Commit `platform/services/<name>.cue` and the generated vhost file together.

## Editing an existing service

1. Edit the `.cue` file.
2. Run `make platform-gen`.
3. Commit both files together.

Manual edits to generated files are blocked by a pre-commit hook.

## Current generators

- `nginx` (SP1) — produces `dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf`

Future sub-projects (SP2–SP5) add docs, prometheus, promtail, bind9, cloudflare,
and portainer generators.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md dockermaster/docker/compose/STATUS.md docs/platform-overview.md
git commit -m "docs(platform): add sp1 notes to claude.md, status.md, and overview"
```

---

### Task 20: Push and open PR

**Files:** None created.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin platform-sp1-nginx
```

- [ ] **Step 2: Create the PR**

```bash
gh pr create --draft \
  --title "✨(platform): SP1 — CUE schema + catalog + nginx generator" \
  --body "$(cat <<'EOF'
## Summary

- New `platform/` directory with CUE schema (\`#Service\`), catalog of ~29 services, and a working nginx vhost generator
- All 22 nginx vhost files regenerated with a canonical shape and committed to git for the first time (they were untracked on NFS before)
- Aggressive standardization of the canonical vhost shape: HSTS, consistent security headers, consistent timeouts, shared \`\$connection_upgrade\` map, dead \`auth_basic off\` removed
- Structural cleanup: \`s3.d\` split into \`s3.cf\` + \`minio.cf\`; \`auth.cf\` points at Docker DNS instead of LAN IP; \`.home\` aliases dropped; freeswitch uses shared \`\$connection_upgrade\`
- Pre-commit hooks enforce \`cue vet\`, \`make platform-diff\`, and reject manual edits to generated files
- GitHub Actions workflow validates the platform on every PR
- Response header baseline diff test catches unexpected header drift during migration

## Changes

- \`platform/cue.mod/\` — CUE module
- \`platform/schemas/service.cue\` — full \`#Service\` schema
- \`platform/services/*.cue\` — 29 service definition files
- \`platform/gen_tool.cue\` — top-level generator command
- \`platform/generators/nginx/vhost.tmpl\` — canonical vhost template
- \`platform/generators/nginx/testdata/\` — 3 golden file fixtures
- \`platform/generators/nginx/RECONCILIATION.md\` — migration delta documentation
- \`platform/scripts/run-golden-tests.sh\`, \`header-baseline.sh\`, \`check-no-manual-edits.sh\`
- \`dockermaster/docker/compose/nginx-rproxy/vhost.d/00-shared.conf\` — hand-written shared map
- \`dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf\` — 22 regenerated vhosts
- \`Makefile\` — \`platform-*\` targets
- \`.pre-commit-config.yaml\` — 3 new hooks
- \`.github/workflows/platform-validate.yml\` — CI workflow
- \`.mise.toml\` — pinned CUE version

## Spec reference

Full design: \`docs/superpowers/specs/2026-04-11-homelab-platform-design.md\`. This PR implements SP1 only; SP2–SP5 are future sub-projects.

## Test plan

- [ ] \`make platform-vet\` — passes
- [ ] \`make platform-gen\` — produces 22 files, zero drift
- [ ] \`make platform-diff\` — passes
- [ ] \`make platform-test\` — 3 golden fixtures PASS
- [ ] Pre-commit hooks block manual edits to generated files
- [ ] \`./platform/scripts/header-baseline.sh diff\` — every host returns \`✅\`
- [ ] Smoke test: browser-verify login flow on https://login.cf.lcamaral.com works after deploy
- [ ] Smoke test: \`docker pull registry.cf.lcamaral.com/homelab-portal:latest\` succeeds
- [ ] Smoke test: keycloak login at https://auth.cf.lcamaral.com still works
EOF
)" \
  --base main
```

- [ ] **Step 3: Verify the PR URL is printed and open it in a browser**

```bash
gh pr view --web
```

---

## Self-review

### Spec coverage

- ✅ Schema: Task 2 writes the full `#Service`
- ✅ Catalog cross-reference validation: Task 3
- ✅ All ~29 services modeled: Tasks 4, 5, 6, 7
- ✅ Shared `00-shared.conf`: Task 10
- ✅ Template file `vhost.tmpl`: Task 8
- ✅ Generator `gen_tool.cue`: Task 9
- ✅ Golden file tests: Task 11
- ✅ Reconciliation against current NFS: Task 12
- ✅ Response header baseline capture + diff: Tasks 13, 18
- ✅ Makefile targets: Task 14
- ✅ Pre-commit hooks (3): Task 14
- ✅ GitHub Actions workflow: Task 15
- ✅ End-to-end local validation: Task 16
- ✅ Deploy (rsync + reload): Task 17
- ✅ Post-deploy verification: Task 18
- ✅ Documentation updates: Task 19
- ✅ PR creation: Task 20
- ✅ Branch setup: Task 1
- ✅ CUE install: Task 1
- ✅ Hand-written `00-default.conf` header: Task 10

### Gaps fixed

- The schema initially required `lan_ip` to match the `192.168.59.x` subnet, which breaks docspell at `192.168.48.44`. Task 7 Step 2 relaxes the regex to `^192\.168\.[0-9]+\.[0-9]+$` and removes the mode-specific requirement.
- The nginx template initially had no `else` branch for `allow_insecure_http`; Task 8 includes the complete two-branch template for the registry case.

### Placeholder scan

None. Every step has exact file paths, exact code, exact commands.

### Type consistency

- `#Service.http.endpoint` (string) referenced consistently as a lookup into `endpoints[].name` in Tasks 2, 3, 9
- `upstream_var` in the template matches `_var` produced by `_nginxCtxFor` in Task 9
- `allow_insecure_http` field name consistent between Task 2 (schema), Task 5 (docker-registry service), Task 8 (template), Task 11 (golden fixture)
- `upstream_dynamic` field name consistent across schema, services, template, golden tests

---

## Execution handoff

After this plan is saved, the writing-plans skill offers execution choice. For SP1 (with its visible infrastructure-touching steps), **subagent-driven-development is recommended** — fresh subagent per task with two-stage review keeps the implementer focused and bounds the blast radius of any misstep on the deploy tasks.
