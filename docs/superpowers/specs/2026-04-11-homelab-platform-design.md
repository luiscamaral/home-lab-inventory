# Homelab Platform Design

Date: 2026-04-11
Status: Approved

## Overview

A CUE-based internal developer platform for the homelab. One `#Service` schema + one `.cue` file per service describes DNS, IPs, reverse proxy, Cloudflare exposure, observability, secrets, and dependencies. A suite of code generators emits every downstream artifact — nginx vhosts, Terraform for Cloudflare and Portainer, bind9 zones, Prometheus scrape configs, promtail targets, and documentation — from that single source of truth.

Adding a new service becomes one file. Drift between concerns disappears because every concern derives from the same catalog.

## Goals

- **Single source of truth.** Every concern for a service (DNS, nginx routing, stack, monitoring, docs) derives from one file.
- **Eliminate drift.** Today's 24 nginx vhosts are not in git. STATUS.md lags reality. Vault paths are inconsistently documented. The catalog makes drift impossible because every artifact is regenerated from one source.
- **Typed, validated configuration.** CUE catches typos, missing fields, constraint violations, and broken cross-references at `cue vet` time — before any generator runs, before any deploy happens.
- **Reviewable diffs.** Generated files are committed to git. PRs show exactly what changes on disk for every source edit. Reviewers don't mentally execute generators.
- **Incremental rollout.** Ship the platform as 5 sub-projects over 5 PRs. Each is independently shippable with standalone value.
- **Standardize while migrating.** Aggressively canonicalize the 22 existing vhosts during SP1 rather than preserving drift.

## Non-goals

- Replacing nginx with Traefik (evaluated, deferred — schema survives a future switch)
- OIDC forward-auth gating for arbitrary services (future sub-project)
- Automatic Let's Encrypt cert issuance (pfSense manages certs today)
- Secret rotation automation (Vault refs are static strings)
- Multi-realm Keycloak or multi-tunnel Cloudflare support (only one of each exists)
- CI-triggered auto-deploy (deploys stay manual rsync+ssh for the first cycle)
- Service dependency visualization / DOT / Mermaid graphs (nice-to-have future)

## Motivation

Today, adding a new service to the homelab is a 7–10 file touch across 4 directories:

1. A Portainer stack resource in `terraform/portainer/stacks.tf`
2. A Vault data source in `terraform/portainer/vault.tf`
3. A compose file in `terraform/portainer/stacks/*.yml`
4. A Cloudflare DNS record + tunnel ingress rule in `terraform/cloudflare/main.tf`
5. An nginx vhost file on dockermaster NFS (not tracked in git at all)
6. A bind9 zone entry (hand-edited, not tracked)
7. A Prometheus scrape config entry (if metrics)
8. A `STATUS.md` row in `dockermaster/docker/compose/STATUS.md`
9. A `CLAUDE.md` update (Vault paths, etc.)
10. An entry in `inventory/docker-containers.md`

Each touch is a separate place where drift can happen. Several of them are not tracked in git (vhosts, zones) or are lagged by days/weeks after the source of truth moves (STATUS.md, inventory docs). A new contributor has to remember all the files. A rename requires updates in 7 places.

The platform collapses this to one file. The CUE catalog becomes the source; everything else is regenerated on demand.

## Architecture

### Core idea

A `platform/` directory at the repo root contains:

- `schemas/` — CUE type definitions (`#Service`, `#Network`, `#DNS`, etc.)
- `services/` — one `.cue` file per service, data only
- `generators/` — one subdirectory per generator, each containing a `gen.cue` + one or more `.tmpl` files

Everything else in the repo (existing `terraform/`, `dockermaster/`, `apps/`, `inventory/`) is **unchanged in purpose**. The platform writes generated files into those existing locations so the existing consumers (Terraform, nginx, Prometheus, docs) continue to work without modification. The platform is a code generator, not a replacement for the runtime infrastructure.

### Repository layout

```
platform/
├── cue.mod/                               # CUE module root
│   └── module.cue                         # module: "lcma.dev/platform"
├── schemas/
│   ├── service.cue                        # #Service + validators
│   ├── network.cue                        # #Network, endpoint types
│   ├── monitoring.cue                     # #Monitoring, Prometheus scrape
│   └── dns.cue                            # #DNS, hostname patterns
├── services/
│   ├── _catalog.cue                       # catalog package header + cross-ref validation
│   ├── _shared.cue                        # shared constants, defaults
│   ├── homelab-portal.cue
│   ├── keycloak.cue
│   ├── calibre.cue
│   ├── bind-dns.cue
│   ├── ... (one per service, ~25 total)
├── generators/
│   ├── nginx/
│   │   ├── gen.cue
│   │   ├── vhost.tmpl
│   │   └── testdata/
│   │       ├── homelab-portal.input.cue
│   │       └── homelab-portal.expected.conf
│   ├── docs/
│   │   ├── gen.cue
│   │   ├── status-table.tmpl
│   │   └── testdata/
│   ├── prometheus/
│   │   ├── gen.cue
│   │   ├── scrape-config.tmpl
│   │   └── testdata/
│   ├── promtail/
│   ├── bind9/
│   ├── cloudflare/
│   └── portainer/
├── Makefile                               # targets: gen, vet, diff, fmt, test
└── README.md                              # platform overview, dev workflow
```

`platform/` sits alongside `terraform/`, `apps/`, `dockermaster/` at the repo root. Generated outputs are written into those existing directories — not into `platform/` itself.

### Dataflow

```
platform/services/*.cue  ──┐
platform/schemas/*.cue   ──┤
platform/services/_catalog.cue ──┤
                           │
                           ▼
                      cue vet (validate schema + cross-refs)
                           │
                           ▼
                   cue cmd gen (execute all generators)
                           │
  ┌────────────────────────┼────────────────────────┐
  ▼                        ▼                        ▼
dockermaster/              terraform/               inventory/
  docker/compose/            cloudflare/              docker-containers_generated.md
    nginx-rproxy/              services_generated      (doc fragments)
      vhost.d/                   .tf.json
        *.conf                 portainer/
    bind-dns/                    stacks_generated
      zones/                       .tf.json
        d.lcamaral.com             vault_generated
          .generated.db              .tf.json
    prometheus/                    stacks/
      scrape_configs_               *.yml
        generated.yml                (compose files,
    reverse-proxy/                    regenerated in SP5)
      promtail_scrape_
        generated.yml
```

Terraform natively reads both `.tf` and `.tf.json` files in a module directory, so generated `.tf.json` files sit alongside hand-written `.tf` files with no special wiring.

### Key architectural decisions

1. **Generated files are committed to git.** Reviewers see the source change and the output diff in the same PR. Deploy does not need CUE. Migration verification is a visual diff.

2. **Pure CUE generators.** No external Go binary, no Python wrapper. Each generator is a `cue cmd` using `tool/file.Create` + the `text/template` built-in package. Single binary dependency (`cue`), no compile step.

3. **Templates live in `.tmpl` files, not embedded CUE strings.** IDE syntax highlighting for nginx/markdown/HCL in the template files.

4. **All services in one CUE package.** Cross-service validation (`depends_on` references, endpoint ref consistency) requires the full catalog loaded at once.

5. **Outputs written directly into target directories.** Not into `platform/generated/`. The nginx vhosts go into the same `vhost.d/` directory that rsyncs to NFS. The Terraform JSON sits next to hand-written `.tf` files in the same module. This avoids a "move files to their real location" step on deploy.

6. **Mixed generated + hand-written in the same directory is explicit.** Generated files start with a `# GENERATED by platform/generators/<name>` header. Hand-written files either lack it or have a `# Hand-written, not platform-managed` header. Pre-commit hooks enforce the distinction.

7. **CUE version pinned via `.mise.toml`.** Contributors use the same CUE version; no "works on my machine" between cue 0.9 and cue 0.11.

## The `#Service` schema

### Full definition

```cue
// platform/schemas/service.cue
package schemas

import "strings"

#Service: {
    // ─── Identity ───────────────────────────────────────
    name:        =~"^[a-z][a-z0-9-]*[a-z0-9]$" & strings.MaxRunes(63)
    description: string
    owner:       *"platform" | string
    tags?:       [...string]

    // ─── Container / runtime (optional — infra services may omit) ─
    container?: {
        image:       string
        build_from?: string                      // path in repo; implies GH Actions build
        watchtower:  *true | false
        resources?: {
            cpu_limit?:      string              // e.g. "1" or "0.5"
            memory_limit?:   string              // e.g. "512M"
            cpu_reserve?:    string
            memory_reserve?: string
        }
        healthcheck?: {
            test:         [...string]            // docker HEALTHCHECK CMD form
            interval:     *"30s" | string
            timeout:      *"5s"  | string
            retries:      *3     | int
            start_period: *"20s" | string
        }
    }

    // ─── Network placement ──────────────────────────────
    network: {
        mode:    "rproxy-bridge" | "docker-servers-net" | "back-tier" | "dual" | "host"
        lan_ip?: =~"^192\\.168\\.59\\.[0-9]+$"  // required iff macvlan
        extra?:  [...string]

        // Non-HTTP ports exposed on the host/LAN (bypass nginx).
        // For SIP, DNS, raw TCP daemons.
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
        endpoint:         string             // references endpoints[].name
        upstream_dynamic: *true | false       // resolver 127.0.0.11 vs literal IP
        read_timeout:     *"3600s" | string
        send_timeout:     *"3600s" | string
        max_body_size:    *"10m" | string | "0"
        frame_options:    *"SAMEORIGIN" | "DENY"

        allow_insecure_http:     *false | true   // registry uses this
        extra_location_config?:  string           // escape hatch
        extra_server_config?:    string           // escape hatch
    }
    if (dns & {internal: _} != _|_) || (dns & {external: _} != _|_) {
        http: !=_|_
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
        env: string                       // env var in the container
        ref: =~"^secret/.*#.*$"           // "secret/<path>#<field>"
    }]

    // ─── Observability ──────────────────────────────────
    monitoring: {
        loki_logs: *true | false
        otel:      *true | false
        prometheus_scrape?: {
            endpoint: string              // references endpoints[].name
            path:     *"/metrics" | string
            interval: *"30s"      | string
        }
    }

    // ─── Dependencies ───────────────────────────────────
    depends_on?: [...string]              // validated against catalog

    // ─── Documentation ──────────────────────────────────
    notes?:   string
    runbook?: string
}
```

### Design choices locked in

1. **`container` is optional.** Services that are pure "external upstream + nginx vhost" (pointing at a LAN IP not managed here) can omit it.
2. **`endpoints` is optional.** Infrastructure daemons (bind9, twingate, cloudflare-tunnel, postfix-relay) have no user-facing HTTP endpoints.
3. **`http` is required iff `dns` is set.** CUE constraint enforces this. No "declared a hostname but never said how nginx should route it" mistakes.
4. **`http.endpoint` is a string name that references `endpoints[].name`.** CUE-validated in the catalog file.
5. **`monitoring` is always required** (though its fields are all defaulted). Forces every service to consciously opt in or out.
6. **`secrets` is structured `{env, ref}` pairs**, not bare refs, because the generator needs to know the target env var name.
7. **All regex constraints are closed** — cert is an enum, LAN IP must match `192.168.59.x`, internal DNS must end in `.lcamaral.com`, external DNS must end in `.cf.lcamaral.com`. Typos die at `cue vet`.
8. **Defaults are opinionated.** `watchtower: true`, `read_timeout: 3600s`, `max_body_size: 10m`, `loki_logs: true`, `otel: true`, `frame_options: SAMEORIGIN`. Override to change.

### Deliberately not in the schema

- TLS ciphers / protocols (hardcoded in the generator template, same everywhere)
- Security header values other than `frame_options` (canonical set enforced by generator)
- OTEL propagation flags (on by default; turn off via `monitoring.otel: false`)
- nginx `map` blocks (the shared `$connection_upgrade` map lives in `00-shared.conf`)
- Cloudflare tunnel name (hardcoded to `bologna` — one tunnel only)
- Vault mount path (hardcoded to `secret/` — one mount only)

### Example services

#### HTTP-facing, Docker-bridge upstream — homelab-portal

```cue
// platform/services/homelab-portal.cue
package services

services: "homelab-portal": {
    description: "Homelab login portal (SvelteKit + Keycloak)"
    container: {
        image:      "registry.cf.lcamaral.com/homelab-portal:latest"
        build_from: "apps/homelab-portal"
        resources: { cpu_limit: "1", memory_limit: "512M", memory_reserve: "128M" }
        healthcheck: {
            test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]
        }
    }
    network:   { mode: "rproxy-bridge" }
    endpoints: [{ name: "web", port: 3000, health: "/healthz" }]
    dns:       { external: "login.cf.lcamaral.com" }
    http: {
        cert:          "d.lcamaral.com"
        endpoint:      "web"
        read_timeout:  "60s"
        send_timeout:  "60s"
        max_body_size: "1m"
        frame_options: "DENY"
    }
    secrets: [
        { env: "KEYCLOAK_CLIENT_SECRET",  ref: "secret/homelab/keycloak/clients#homelab_portal_secret" },
        { env: "SESSION_SECRET",          ref: "secret/homelab/portal#session_secret" },
        { env: "SESSION_ENCRYPTION_KEY",  ref: "secret/homelab/portal#session_encryption_key" },
    ]
    depends_on: ["keycloak", "postfix-relay"]
    monitoring: { loki_logs: true, otel: true }
}
```

#### LAN IP upstream, no container — rundeck

```cue
// platform/services/rundeck.cue
package services

services: "rundeck": {
    description: "Rundeck automation server"
    network:     { mode: "docker-servers-net", lan_ip: "192.168.59.22" }
    endpoints:   [{ name: "web", port: 4440, scheme: "http" }]
    dns: {
        internal:          "rundeck.d.lcamaral.com"
        internal_aliases:  ["rundeck.home"]
    }
    http: {
        cert:             "d.lcamaral.com"
        endpoint:         "web"
        upstream_dynamic: false   // literal IP, not Docker DNS
    }
    monitoring: { loki_logs: true, otel: true }
}
```

#### Infrastructure daemon, non-HTTP — bind9

```cue
// platform/services/bind-dns.cue
package services

services: "bind-dns": {
    description: "Authoritative DNS for internal lcamaral.com zones"
    container: {
        image:     "internetsystemsconsortium/bind9:9.20"
        watchtower: false
    }
    network: {
        mode:   "docker-servers-net"
        lan_ip: "192.168.59.3"
        exposed_ports: [
            { port: 53, protocol: "tcp", name: "dns-tcp" },
            { port: 53, protocol: "udp", name: "dns-udp" },
        ]
    }
    monitoring: { loki_logs: true, otel: false }
}
```

Bind9 has no `endpoints`, no `dns` field, no `http`, no `secrets`, no `depends_on`. CUE accepts it because those are all optional. The nginx generator skips it (no `http` block). The docs generator still includes it in STATUS.md. Each generator handles the "this service doesn't apply to me" case naturally.

### Cross-service validation

```cue
// platform/services/_catalog.cue
package services

import "lcma.dev/platform/schemas"

// Every service indexed by name. The key must equal the service's name field.
services: [name=string]: schemas.#Service & {
    name: name  // key and field are unified
}

// Cross-service validation: every depends_on must reference a real service.
for svcName, svc in services {
    for dep in (*svc.depends_on | []) {
        services: "\(dep)": _  // fails vet if dep doesn't exist
    }
}

// Endpoint reference validation: http.endpoint must match one endpoints[].name.
for svcName, svc in services
if svc.http != _|_ {
    _endpointNames: {for e in svc.endpoints {(e.name): true}}
    svc: http: endpoint: _endpointNames[_] | *""  // vet fails if the ref is unknown
}
```

`cue vet ./platform/...` loads the whole package and catches typos, missing deps, bad endpoint refs, and schema violations before any generator runs.

## Generators

### Generator pattern

Each generator is a self-contained directory under `platform/generators/`. It contains:

- `gen.cue` — the CUE command definition, using `tool/file.Create` to write outputs
- One or more `.tmpl` files — Go `text/template` format, read by the generator
- `testdata/` — canonical input fixtures and expected rendered output for golden file tests

All generators share the same recipe: iterate over `services`, filter to the subset this generator cares about, render a template, write a file. The template uses standard Go `text/template` syntax via CUE's built-in `text/template` package binding.

### Example: nginx generator

```cue
// platform/generators/nginx/gen.cue
package nginx

import (
    "tool/file"
    "text/template"
    svc "lcma.dev/platform/services"
)

_templateFile: "vhost.tmpl"
_outputDir:    "../../../dockermaster/docker/compose/nginx-rproxy/vhost.d"

// Build the context object each service passes into the template.
_ctxFor: {
    [name=string]: {
        let s = svc.services[name]
        let e = [for ep in s.endpoints if ep.name == s.http.endpoint {ep}][0]
        name:            name
        hostname:        s.dns.external | s.dns.internal
        aliases:         (*s.dns.external_aliases | []) + (*s.dns.internal_aliases | [])
        http:            s.http
        upstream_host:   s.network.lan_ip | s.http.endpoint
        upstream_port:   e.port
        upstream_scheme: e.scheme
        upstream_path:   e.path
    }
}

// The command: read template, write one .conf file per service that has an http block.
command: gen: {
    readTemplate: file.Read & {
        filename: _templateFile
        contents: string
    }

    for name, s in svc.services
    if s.http != _|_ {
        "write-\(name)": file.Create & {
            filename: "\(_outputDir)/\(*s.dns.external | s.dns.internal).conf"
            contents: template.Execute(readTemplate.contents, _ctxFor[name])
        }
    }
}
```

Template file lives separately for IDE highlighting:

```gotemplate
{{/* platform/generators/nginx/vhost.tmpl */}}
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
  set $upstream_{{.name | replace "-" "_"}} {{.upstream_host}}:{{.upstream_port}};
  {{- end}}

  {{with .http.extra_server_config}}{{.}}{{end}}

  location {{.upstream_path}} {
    {{if .http.upstream_dynamic -}}
    proxy_pass {{.upstream_scheme}}://$upstream_{{.name | replace "-" "_"}};
    {{else -}}
    proxy_pass {{.upstream_scheme}}://{{.upstream_host}}:{{.upstream_port}};
    {{end}}
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

    {{with .http.extra_location_config}}{{.}}{{end}}
  }
}
```

### Shared nginx fragment

A new file `dockermaster/docker/compose/nginx-rproxy/vhost.d/00-shared.conf` — hand-written, not generated — defines the `$connection_upgrade` map once:

```nginx
# Hand-written, not platform-managed.
# Shared upgrade map consumed by all generated vhosts.
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}
```

Every generated vhost assumes `$connection_upgrade` is in scope and does not redefine it. The freeswitch vhost's current workaround (defining its own `$connection_upgrade_fs` map) disappears during SP1.

### Generator inventory

| Generator | Ships in | Writes to | Purpose |
|---|---|---|---|
| **nginx** | SP1 | `dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf` | Per-service nginx vhost |
| **docs** | SP2 | `dockermaster/docker/compose/STATUS_generated.md`, `inventory/docker-containers_generated.md` | Service tables |
| **prometheus** | SP3 | `dockermaster/docker/compose/prometheus/scrape_configs_generated.yml` | Prometheus scrape targets |
| **promtail** | SP3 | `dockermaster/docker/compose/reverse-proxy/promtail_scrape_generated.yml` | Loki log shipping targets |
| **bind9** | SP4 | `dockermaster/docker/compose/bind-dns/zones/d.lcamaral.com.generated.db` | Bind9 zone fragment |
| **cloudflare** | SP4 | `terraform/cloudflare/services_generated.tf.json` | Cloudflare DNS records + tunnel ingress rules |
| **portainer** | SP5 | `terraform/portainer/stacks_generated.tf.json`, `terraform/portainer/vault_generated.tf.json`, `terraform/portainer/stacks/*.yml` | Portainer stacks, Vault data sources, compose files |

### Output conventions

- **Generated files** start with a `# GENERATED by platform/generators/<name>` header.
- **Hand-written files** either lack the header or have a `# Hand-written, not platform-managed` header.
- **Generated Terraform** uses `.tf.json` extension and lives directly in the module root next to hand-written `.tf` files. Terraform reads both naturally.
- **Generated nginx vhosts** live in the same `vhost.d/` directory as the hand-written `00-default.conf` and `00-shared.conf`. Distinguished by header.
- **Generated compose files** in SP5 go into `terraform/portainer/stacks/*.yml` — same directory as today's hand-written ones, but all regenerated with the header.

## Workflow

### Local development

```
# Edit a service
vim platform/services/homelab-portal.cue

# Validate schema
make platform-vet

# Regenerate outputs (all generators)
make platform-gen

# Verify no unintended diffs
git diff dockermaster/ terraform/ inventory/

# Run tests
make platform-test

# Commit source + generated together
git add platform/ dockermaster/ terraform/ inventory/
git commit -m "feat(platform): add foo service"
```

### Makefile targets

```makefile
.PHONY: platform-gen platform-vet platform-diff platform-fmt platform-test

platform-gen:       ## Regenerate all platform outputs
	cd platform && cue cmd gen

platform-vet:       ## Validate the service catalog without generating
	cd platform && cue vet ./...

platform-diff:      ## Fail if generated files are out of date (for CI and pre-commit)
	cd platform && cue cmd gen
	git diff --exit-code -- \
	  dockermaster/docker/compose/nginx-rproxy/vhost.d/ \
	  dockermaster/docker/compose/bind-dns/zones/ \
	  dockermaster/docker/compose/prometheus/scrape_configs_generated.yml \
	  dockermaster/docker/compose/reverse-proxy/promtail_scrape_generated.yml \
	  terraform/cloudflare/services_generated.tf.json \
	  terraform/portainer/stacks_generated.tf.json \
	  terraform/portainer/vault_generated.tf.json \
	  terraform/portainer/stacks/ \
	  inventory/docker-containers_generated.md \
	  dockermaster/docker/compose/STATUS_generated.md

platform-fmt:       ## Format CUE files
	cd platform && cue fmt ./...

platform-test:      ## Run golden file tests per generator
	cd platform && for d in generators/*/testdata; do \
	  ... render fixtures, diff against expected ... ; \
	done
```

### Pre-commit hooks

Added to `.pre-commit-config.yaml`:

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
      files: (vhost\.d|generated).*\.(conf|json|yml|md|db)$
```

The third hook greps staged diffs for modifications to files whose header contains `GENERATED by platform/generators/`. Rejects commits that touch those files without a matching `platform/` source change in the same commit.

### CI

On every PR, a new GitHub Actions workflow `.github/workflows/platform-validate.yml`:

- Installs `cue` (version pinned via `.mise.toml`)
- Runs `make platform-vet` — schema check
- Runs `make platform-test` — golden file tests
- Runs `make platform-diff` — no drift
- Runs syntax checks on generated outputs: `nginx -t`, `terraform validate`, `promtool check config`, `named-checkzone`

### Deploy

Per sub-project, deploy is an rsync + reload sequence run from a developer machine after merge:

```bash
# SP1 (nginx)
rsync -av dockermaster/docker/compose/nginx-rproxy/vhost.d/ \
      dockermaster:/nfs/dockermaster/docker/nginx-rproxy/config/vhost.d/
ssh dockermaster 'docker exec rproxy nginx -t && docker exec rproxy nginx -s reload'

# SP3 (prometheus/promtail)
rsync -av dockermaster/docker/compose/prometheus/scrape_configs_generated.yml \
      dockermaster:/nfs/dockermaster/docker/prometheus/
ssh dockermaster 'docker kill --signal=HUP prometheus-prometheus-1'

# SP4 (cloudflare + bind9)
cd terraform/cloudflare && terraform apply
rsync -av dockermaster/docker/compose/bind-dns/zones/ dockermaster:/nfs/dockermaster/docker/bind-dns/zones/
ssh dockermaster 'docker exec bind-dns-bind9-1 rndc reload'

# SP5 (portainer stacks)
cd terraform/portainer && terraform apply -target=portainer_stack.X
# Verify per stack, then move to next
```

Upgrading to "GH Action runs the deploy step" is deliberately out of scope — manual deploys stay for the first cycle.

## Sub-project decomposition

### SP1: Schema + catalog + nginx generator

**Scope:**
- Write `platform/schemas/*.cue` — the full `#Service` schema
- Write `platform/services/*.cue` for all ~25 services (Terraform-managed + hand-written standalone + infra daemons)
- Write `platform/services/_catalog.cue` with cross-service validation
- Write `platform/generators/nginx/` — `gen.cue`, `vhost.tmpl`, `testdata/`
- Create `dockermaster/docker/compose/nginx-rproxy/vhost.d/00-shared.conf` (hand-written, defines `$connection_upgrade`)
- Regenerate all vhosts with canonical shape
- Add Makefile + pre-commit hooks + CI workflow
- Deploy: rsync + reload nginx
- Verify: 22-hostname smoke test + response header baseline diff

**Deliverables:**
- `platform/schemas/service.cue` (~200 lines)
- `platform/services/*.cue` (~25 files × ~25 lines avg = ~625 lines)
- `platform/generators/nginx/gen.cue` (~50 lines)
- `platform/generators/nginx/vhost.tmpl` (~80 lines)
- `platform/generators/nginx/testdata/` (3 fixtures + 3 expected outputs)
- `dockermaster/docker/compose/nginx-rproxy/vhost.d/*.conf` (22 regenerated + 1 new shared fragment)
- `Makefile` (root) + `.pre-commit-config.yaml` updates
- `.github/workflows/platform-validate.yml`

**Effort:** ~1.5–2 days

**Risk:** Low. No Terraform state, visual diff before deploy, response header baseline diff post-deploy.

**Preconditions:** The `custom-login-portal` PR is merged. SP1 starts on a fresh branch `platform-sp1-nginx` off main.

### SP2: Docs generator

**Scope:**
- Write `platform/generators/docs/` — `gen.cue`, `status-table.tmpl`, `docker-containers.tmpl`
- Regenerate `dockermaster/docker/compose/STATUS_generated.md` and `inventory/docker-containers_generated.md`
- Shrink the hand-written `STATUS.md` to "overview + link to generated table"
- Deploy: `git commit` is deploy; the files are consumed by humans reading the repo

**Deliverables:**
- `platform/generators/docs/gen.cue` (~40 lines)
- `platform/generators/docs/*.tmpl` (~60 lines total)
- Regenerated markdown files

**Effort:** 3–4 hours

**Risk:** Very low. No runtime impact.

**Ordering:** Immediately after SP1. Builds confidence the catalog is useful beyond nginx, delivers visible value fast.

### SP3: Observability generators

**Scope:**
- Write `platform/generators/prometheus/` — scrape config fragment generator
- Write `platform/generators/promtail/` — log shipping target generator
- Wire `prometheus.yml` to include `scrape_configs_generated.yml`
- Wire `promtail.yml` to include `promtail_scrape_generated.yml`
- Deploy: rsync + SIGHUP prometheus and promtail

**Deliverables:**
- `platform/generators/prometheus/gen.cue` + template (~60 lines total)
- `platform/generators/promtail/gen.cue` + template (~50 lines total)
- Regenerated YAML fragments
- Updated `prometheus.yml` and `promtail.yml` with `include` directives

**Effort:** 4–6 hours

**Risk:** Low. Reload, no state.

### SP4: DNS generators — bind9 + Cloudflare

**Scope:**
- Write `platform/generators/bind9/` — zone fragment generator
- Write `platform/generators/cloudflare/` — DNS record + tunnel ingress generator
- Generate `terraform/cloudflare/services_generated.tf.json`
- Migrate existing hand-written Cloudflare resources via `moved` blocks
- Generate bind9 zone fragment, included from parent zone via `$INCLUDE`
- Deploy: `terraform apply` (cloudflare), rsync + `rndc reload` (bind9)

**Deliverables:**
- `platform/generators/bind9/gen.cue` + template (~60 lines)
- `platform/generators/cloudflare/gen.cue` + template (~80 lines)
- `terraform/cloudflare/services_generated.tf.json`
- `terraform/cloudflare/main.tf` updates (add `moved` blocks, remove hand-written DNS records)
- Regenerated bind9 zone fragment

**Effort:** ~1 day

**Risk:** Medium. First Terraform state migration. DNS destroys are cheap (seconds of downtime worst case) so the blast radius is bounded.

**Migration recipe:**
1. Generate `services_generated.tf.json`
2. Add `moved { from = cloudflare_dns_record.login_cf_tunnel, to = cloudflare_dns_record.login ... }` blocks in `main.tf` for every renamed resource — **without** deleting the old HCL yet
3. `terraform plan` — should show zero changes
4. Delete the old HCL in `main.tf`
5. `terraform plan` — still zero changes
6. `terraform apply` — no-op
7. Confirm DNS still resolves via `dig`

For the tunnel ingress `cloudflare_zero_trust_tunnel_cloudflared_config.bologna`, the entire resource is regenerated — the generator writes the complete ingress list each time, so it's an in-place update rather than a state move.

### SP5: Portainer stack generator

**Scope:**
- Write `platform/generators/portainer/` — stacks + Vault data sources + compose files
- Generate `terraform/portainer/stacks_generated.tf.json` (replaces hand-written `portainer_stack` resources)
- Generate `terraform/portainer/vault_generated.tf.json` (replaces hand-written `vault_kv_secret_v2` data sources)
- Regenerate all 20 `terraform/portainer/stacks/*.yml` compose files
- Migrate Terraform state via `moved` blocks
- Ship in batches of 3–5 stacks per PR to bound blast radius
- Deploy: `terraform apply -target=portainer_stack.X` per stack, verify, repeat

**Deliverables (across 4–5 PRs):**
- `platform/generators/portainer/gen.cue` + templates (~120 lines)
- `terraform/portainer/stacks_generated.tf.json`
- `terraform/portainer/vault_generated.tf.json`
- 20 regenerated compose files
- `terraform/portainer/stacks.tf` updates (add `moved` blocks, remove hand-written resources batch by batch)

**Effort:** 2–3 days spread over 4–5 PRs

**Risk:** High. Touches every running container. Per-stack verification required.

**Batching:** 3–5 similar stacks per PR. First batch includes a low-risk stack (e.g. chisel) to exercise the rollback procedure.

**Rollback preflight:** Before the first production batch, deliberately simulate a rollback on chisel to verify the procedure works. Document the steps.

### Ordering and dependencies

```
SP1 ─▶ SP2 ─▶ SP3 ─┐
                    ├─▶ SP4 ─▶ SP5 (batched)
                    │
                    ▼
                (parallelizable)
```

- **SP1 must come first.** Everything depends on the schema + catalog.
- **SP2 and SP3 can ship in parallel** with each other (both only touch generators, no cross-interaction).
- **SP4 gates SP5.** SP4 is the first Terraform state migration; we want it battle-tested before SP5's bigger one.
- **SP5 is batched internally.** Each batch is its own PR.

**Estimated total effort:** ~5–7 days of engineering spread over 8–9 PRs (SP1 + SP2 + SP3 + SP4 + 4–5 batches of SP5).

## Migration strategy

### Canonical nginx vhost shape (SP1)

Every generated vhost in SP1 conforms to this canonical shape:

- `listen 80` block redirects to HTTPS (unless `allow_insecure_http: true`, used only by registry)
- `listen 443 ssl; http2 on;`
- Standard TLS block: `TLSv1.2 TLSv1.3`, `HIGH:!aNULL:!MD5`, session cache 10m, session timeout 10m
- Standard security headers: HSTS (initial `max-age=300`), X-Frame-Options from service (default `SAMEORIGIN`), X-Content-Type-Options `nosniff`, Referrer-Policy `strict-origin-when-cross-origin`
- `otel_trace_context propagate` at server scope
- If `upstream_dynamic: true`: `resolver 127.0.0.11 valid=10s ipv6=off` + `set $upstream_<name>`
- `location /` block with:
  - `proxy_pass` to the upstream
  - Proxy headers: Host, X-Real-IP, X-Forwarded-{For,Proto,Host,Port}
  - WebSocket upgrade: `Upgrade $http_upgrade; Connection $connection_upgrade`
  - Timeouts from service (default `3600s`)
  - `client_max_body_size` from service (default `10m`)
  - `otel_trace on; otel_trace_context inject;`

### Behavioral changes on deploy (SP1)

Every vhost gets these changes unless explicitly overridden:

**Added:**
- HSTS header — no existing vhost has it. Initial `max-age=300` (5 minutes) for safe rollback window. Bump to `31536000` (1 year) after a week of verification in a follow-up.
- `otel_trace_context propagate` at server scope on services missing it
- `otel_trace on; otel_trace_context inject;` in `location /` on services missing it
- `X-Forwarded-Host` and `X-Forwarded-Port` headers on services missing them
- WebSocket upgrade headers on services missing them

**Removed:**
- `auth_basic off;` (dead code on every vhost, never guarded anything)
- Inline `map $http_upgrade $connection_upgrade { ... }` blocks (hoisted to `00-shared.conf`)
- `proxy_hide_header WWW-Authenticate;` (inconsistent half-present, no clear pattern — drop; re-add per-vhost via `extra_location_config` if a service starts triggering auth prompts)

**Standardized:**
- `Referrer-Policy` upgraded from `no-referrer-when-downgrade` to `strict-origin-when-cross-origin` everywhere
- `X-Frame-Options: SAMEORIGIN` everywhere unless `frame_options: "DENY"` is set (rolls back portal's `DENY` unless explicitly restored)
- `proxy_read_timeout` / `proxy_send_timeout` default to `3600s` (matches most current values; `60s` for portal is an explicit override)
- `client_max_body_size` default to `10m`; services needing more (registry `0`, MinIO `100m`, Keycloak etc.) override explicitly

**Structural fixes:**
- `s3.d.lcamaral.com.conf` (currently 4 server blocks in one file) splits into two logical services — `s3.cf.lcamaral.com` (S3 API, port 9000) and `minio.cf.lcamaral.com` (console, port 9001) — each with its own generated file
- `00-default.conf` stays hand-written and is not part of the catalog (serves static files, not a reverse proxy)
- `auth.cf.lcamaral.com` upstream changes from `192.168.59.13` (LAN IP) to `keycloak` (Docker DNS) — same container, cleaner routing
- `.home` aliases dropped from 6 legacy vhosts (`dockermaster.home`, `docspell.home`, `n8n.home`, `netbox.home`, `portainer.home`, `rundeck.home`)
- `freeswitch`'s custom `$connection_upgrade_fs` map disappears — uses the shared `$connection_upgrade` from `00-shared.conf`

### Terraform state migration (SP4 and SP5)

The generator writes `.tf.json` files alongside hand-written `.tf` files. Since both declare the same resources (old HCL + new JSON), Terraform sees duplicates. To migrate without destroying resources:

1. **Generate first, don't delete HCL yet.** `terraform plan` will show new resources to create + existing resources to destroy.
2. **Add `moved` blocks in the hand-written `.tf`** mapping old addresses to new. Example:
   ```hcl
   moved {
     from = cloudflare_dns_record.login_cf_tunnel
     to   = cloudflare_dns_record.login
   }
   ```
3. **Run `terraform plan`** — should show zero changes (state refactor, no resource changes).
4. **Delete the old HCL** in the hand-written `.tf`.
5. **Run `terraform plan` again** — should still show zero changes.
6. **Run `terraform apply`** — no-op, state is cleanly migrated.

This procedure is rehearsed on a single low-risk resource in SP4 (chisel's DNS record) before migrating the rest.

### Portainer batching (SP5)

SP5 ships in 4–5 PRs, each moving 3–5 stacks. Each batch follows the same recipe:

1. Pick 3–5 stacks that are similar in shape (e.g. all simple single-container stacks, or all multi-container stacks).
2. Generate compose files + `stacks_generated.tf.json` entries.
3. Byte-diff generated compose files vs current hand-written ones. Reconcile any drift.
4. Add `moved` blocks in `stacks.tf`.
5. `terraform plan -target=portainer_stack.X` for each stack in the batch — expect zero changes.
6. `terraform apply -target=portainer_stack.X` — no-op.
7. Visual smoke-check: service still running, healthcheck green, curl-through-nginx returns expected response.
8. Commit, push, open PR, merge.

**First batch includes chisel** (lowest-risk stack) to exercise the rollback procedure on something non-critical before the critical stacks.

## Testing and validation

### Five layers

| Layer | Tool | Catches |
|---|---|---|
| **1. Schema** | `cue vet ./platform/...` | Typos, missing fields, bad enums, broken cross-refs |
| **2. Generator correctness** | `make platform-diff` | "Changed source but forgot to regenerate" |
| **3. Output syntax** | `nginx -t`, `terraform validate`, `promtool check`, `named-checkzone` | Generated text invalid for its consumer |
| **4. Migration equivalence** | `terraform plan` clean; byte-diff against current state | Generator doesn't match running reality |
| **5. Runtime smoke tests** | `curl`, `dig`, `docker inspect`, Prometheus `/api/v1/targets` | Deploy broke something |

### Golden file tests per generator

Each generator has a `testdata/` directory with 3 fixtures:

- A plain / canonical service (homelab-portal for nginx, say)
- A variation (keycloak for nginx — LAN IP upstream variant)
- An escape hatch (registry for nginx — `allow_insecure_http: true`)

`make platform-test` renders each fixture through the generator, diffs against the committed expected output, fails on mismatch. Runs in CI. Catches template regressions in isolation before they touch the full catalog.

### Drift prevention

Every generated file starts with:

```
# =============================================================================
# GENERATED by platform/generators/<name> — DO NOT EDIT BY HAND
# Source:     platform/services/<name>.cue
# Regenerate: make platform-gen
# =============================================================================
```

A pre-commit hook (`platform-no-manual-edits`) greps staged diffs for files containing this header. Rejects commits that modify such files without a matching `platform/` source change in the same commit. Combined with `platform-diff`, manual edits to generated files are nearly impossible to sneak through.

### Per-sub-project smoke tests

**SP1 — 22-hostname sweep + response header baseline diff:**

Before migration: capture `curl -I -k https://<host>/` headers for all 22 external and internal hostnames into `platform/generators/nginx/testdata/baseline/<host>.headers` (committed as snapshot).

After migration: re-capture and diff against baseline. Any header delta not explicitly enumerated in the "Behavioral changes" section above fails the check. Enumerated changes (HSTS added, Referrer-Policy upgraded, etc.) are expected and filtered from the diff.

**SP2:** Visual review of generated `STATUS_generated.md` vs previous hand-maintained version.

**SP3:** Query Prometheus `/api/v1/targets` — one target per service with `prometheus_scrape`. Query Loki — one stream per service with `loki_logs: true`.

**SP4:** `dig` each new DNS record, `terraform plan` clean.

**SP5 (per stack):** `docker inspect <stack>` healthcheck green, curl through nginx returns expected status.

### Rollback strategies

| SP | Rollback | Recovery |
|---|---|---|
| **SP1** | Revert commit, rsync previous vhosts to NFS, reload nginx | ~2 min |
| **SP2** | Revert commit | No prod impact |
| **SP3** | Revert commit, SIGHUP prometheus/promtail | ~1 min |
| **SP4** | Revert source, `terraform apply` | ~5 min |
| **SP5** | Per stack: revert `moved` block and `terraform apply -target=` from previous commit | ~5 min per stack |

Rollback for SP5 is pre-tested on chisel in the first batch before any critical stacks migrate.

## Risks

| Risk | Mitigation |
|---|---|
| Schema designed too narrowly, can't fit a service in SP5 | Full catalog written in SP1 — every service's shape is validated up front before a single generator beyond nginx is built |
| Generator template has a bug | Golden file tests per generator + committed generated files visible in PR diff |
| SP4 Terraform state migration destroys live DNS | `moved` blocks + per-resource `terraform plan` clean before apply; DNS destroys have minimal blast radius anyway |
| SP5 Portainer state migration breaks a live service | Batched to 3–5 stacks per PR, per-stack verification, rollback tested on chisel first |
| Someone hand-edits a generated file post-merge | Pre-commit grep for `GENERATED by` header + CI `make platform-diff` + header documentation |
| CUE version drift between contributors | Pin `cue` version in `.mise.toml` at the repo root |
| Aggressive standardization silently changes response headers | Response header baseline diff in SP1 smoke tests |
| Pre-commit hooks block unrelated branches during SP1 rollout | Test the hooks on a throwaway branch before merging the hook config |
| Generator performance with 25 services | Measure during SP1; `cue cmd gen` on 25 services expected <5s on a modern machine; optimize only if it's not |

## Out of scope (deliberately deferred)

- **Traefik migration** — evaluated and deferred. If future you decides to flip, the CUE catalog becomes input to Traefik labels instead of vhost files. The catalog survives the switch.
- **OIDC forward-auth gating** — protecting arbitrary services behind Keycloak via a forward-auth middleware. Adds a network hop and middleware contract. Separate future PRD.
- **Secret rotation automation** — Vault has primitives but we don't wire them. Refs stay static strings.
- **Multi-realm Keycloak, multi-tunnel Cloudflare** — only one of each exists. Schema gains fields when needed; existing services default.
- **Let's Encrypt certs / automatic cert rotation** — pfSense pushes certs today. Schema has cert as a closed enum; auto-cert is a new enum value and a new generator.
- **Service dependency graph / DOT / Mermaid diagrams** — catalog has enough data but the `docs` generator only emits markdown tables.
- **CI-triggered auto-deploy** — all 5 sub-projects still deploy by rsync+ssh from a human's machine after merge. Upgrading is a separate hardening PR.
- **Hand-written standalone Docker projects outside this repo** (LDAP, elastic-search, synology-search) — they get CUE service entries so they appear in the catalog and get nginx vhosts, but no Portainer stack generation since no compose file exists in this repo for them.

## Open questions deferred to implementation plans

These get decided when their sub-project is planned, not now:

- Exact Makefile target names (bike-shedding — nail in SP1's implementation plan)
- Which Cloudflare Terraform provider version is current in 2026 (verified during SP4)
- Whether bind9 gets a generated zone fragment via `$INCLUDE` or the whole zone regenerated (depends on bind9 stack's current layout; verified during SP4)
- The exact list of response header assertions for the SP1 baseline (captured at SP1 implementation time)
- Whether `watchtower.enable` labels live in the compose file or the `portainer_stack` resource (verified during SP5)
- CUE version to pin (verified against `mise` registry during SP1)

## Success criteria

The platform is successful when:

1. **Adding a new service is one file.** A new contributor edits `platform/services/foo.cue` and runs `make platform-gen`. No other files touched by hand.
2. **CUE vet catches typos before deploy.** Misspelled `depends_on`, broken endpoint refs, missing required fields all fail `cue vet` in pre-commit.
3. **No drift between the catalog and running reality.** `make platform-diff` stays clean on every branch. Generated files in git match what's on NFS and in Terraform.
4. **STATUS.md never lags reality.** Every service visible in the catalog is visible in generated docs within one commit.
5. **The 22 nginx vhosts are in git.** No more "source of truth is whatever I edited last on NFS."
6. **SP1–SP5 ship as 8–9 distinct PRs** (SP1, SP2, SP3, SP4, then 4–5 SP5 batches), each independently mergeable with standalone value.
7. **Zero production incidents** during migration sub-projects, per sub-project smoke tests passing cleanly.

## References

- CUE documentation: https://cuelang.org/docs/
- CUE `tool/file` package: https://cuelang.org/docs/reference/command/cue-help-cmd/
- CUE `text/template` binding: https://pkg.go.dev/cuelang.org/go/pkg/text/template
- Terraform JSON configuration: https://developer.hashicorp.com/terraform/language/syntax/json
- Terraform `moved` blocks: https://developer.hashicorp.com/terraform/language/modules/develop/refactoring
- The 2026-04-10 homelab portal design: `docs/superpowers/specs/2026-04-10-homelab-portal-design.md`
- The 2026-04-10 homelab portal implementation plan: `docs/superpowers/plans/2026-04-10-homelab-portal.md`
