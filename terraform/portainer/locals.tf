# ──────────────────────────────────────────────
# Monitoring config strings (Phase 1 + Phase 2 seeds)
#
# These locals render as multi-line strings and are passed into the
# corresponding Portainer stack templatefile() calls (e.g. prometheus.yml.tftpl
# expects ${prometheus_config} and ${objstore_config} template vars).
#
# Two near-identical scrape configs (`_a` / `_b`) — the ONLY difference is
# `external_labels.replica`. Prometheus does NOT support `external_labels`
# via CLI flags; they MUST live in YAML, hence the duplication.
#
# Phase scope:
# - Phase 1: prometheus-1 (replica A) + sidecar-1 + AM-1 + extracted host
#   exporters on ds-1.
# - Phase 2: prometheus-2 + AM-2 on the NAS.
# - Phase 3: fills the rest of the exporters.
# Targets that don't exist yet sit in the scrape config from day 1
# (Prometheus marks them up=0 until they land — better than churning the
# config on every phase).
#
# Editing protocol: edit once for each replica (yes, both blocks). The
# `replica:` line is the ONLY intended divergence between them. Run
# `terraform fmt` and YAML-lint each EOT body before commit.
#
# Source-of-truth references:
#   generated/prometheus-thanos-monitoring/06-dashboards-and-alerting.md
#   generated/prometheus-thanos-monitoring/RECON-FINDINGS.md
# ──────────────────────────────────────────────

locals {
  # ──────────────────────────────────────────────
  # prometheus.yml — replica A (prometheus-1 on ds-1)
  # ──────────────────────────────────────────────
  prometheus_scrape_config_a = <<-EOT
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: homelab
        replica: A
        region: local

    rule_files:
      - /etc/prometheus/rules/*.yml

    alerting:
      alertmanagers:
        - scheme: http
          static_configs:
            - targets:
                # alertmanager-1 — Phase 1, ds-1 macvlan
                - 192.168.59.27:9093
                # alertmanager-2 — Phase 2, NAS home-net (up=0 until Phase 2)
                - 192.168.4.238:9093

    scrape_configs:
      # ── Prometheus self-scrape ──────────────────────────────────────
      - job_name: prometheus
        static_configs:
          - targets:
              - 192.168.59.19:9090
            labels:
              instance: prometheus-1
          - targets:
              - 192.168.4.237:9090
            labels:
              instance: prometheus-2

      # ── node_exporter — host metrics ────────────────────────────────
      # Phase 1 deploys node-exporter on ds-1 only. ds-2/dockermaster/NAS
      # land in Phase 3; listed now so the config doesn't churn (up=0 OK).
      - job_name: node
        static_configs:
          - targets: [192.168.48.45:9100]
            labels: { instance: ds-1 }
          - targets: [192.168.48.46:9100]
            labels: { instance: ds-2 }
          - targets: [192.168.48.44:9100]
            labels: { instance: dockermaster }
          - targets: [192.168.0.50:9100]
            labels: { instance: nas }

      # ── cadvisor — container metrics ────────────────────────────────
      - job_name: cadvisor
        static_configs:
          - targets: [192.168.48.45:8080]
            labels: { instance: ds-1 }
          - targets: [192.168.48.46:8080]
            labels: { instance: ds-2 }
          - targets: [192.168.48.44:8080]
            labels: { instance: dockermaster }
          - targets: [192.168.0.50:8080]
            labels: { instance: nas }

      # ── snmp_exporter — pfSense (T0) ────────────────────────────────
      - job_name: snmp-pfsense
        scrape_interval: 15s
        scrape_timeout: 10s
        metrics_path: /snmp
        params:
          module: [pfsense]
        static_configs:
          - targets:
              - pfsense1.srv.lcamaral.com
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.29:9116

      # ── Thanos self-scrape (sidecar-1, query, store-gw) ─────────────
      - job_name: thanos
        static_configs:
          - targets: [192.168.59.20:10902]
            labels: { instance: thanos-sidecar-1 }
          - targets: [192.168.59.21:10902]
            labels: { instance: thanos-store-gw }
          - targets: [192.168.59.26:10902]
            labels: { instance: thanos-query }

      # ── Phase 3a: Vault (3-node Raft cluster) ───────────────────────
      # Listener is plain HTTP on the macvlan IP (TLS terminates at
      # nginx-rproxy). Requires `telemetry.unauthenticated_metrics_access
      # = true` in each node's config.hcl — see PHASE-3a stack edits.
      # Followers 307-redirect /v1/sys/metrics by default unless the
      # unauth-metrics flag is set; without it, we'd need a token AND
      # `prometheus.honor_redirects` cleverness.
      - job_name: vault
        scheme: http
        metrics_path: /v1/sys/metrics
        params:
          format: [prometheus]
        static_configs:
          - targets: [192.168.59.25:8200]
            labels: { instance: vault-1 }
          - targets: [192.168.59.9:8200]
            labels: { instance: vault-2 }
          - targets: [192.168.59.15:8200]
            labels: { instance: vault-3 }

      # ── Phase 3a: Keycloak (Quarkus management interface, port 9000) ─
      # KC_METRICS_ENABLED=true exposes /metrics on the management port.
      # See PHASE-3a stack edits to keycloak.yml + keycloak-2.yml.
      - job_name: keycloak
        metrics_path: /metrics
        static_configs:
          - targets: [192.168.59.13:9000]
            labels: { instance: keycloak-1 }
          - targets: [192.168.59.43:9000]
            labels: { instance: keycloak-2 }

      # ── Phase 3a: MinIO cluster metrics (v2 endpoint) ───────────────
      # Bearer JWT auth — generated from a dedicated `metrics` svcacct
      # (DECISIONS.md Phase 3 lock). The JWT itself comes from
      # `mc admin prometheus generate ALIAS metrics-svcacct` and rotates
      # whenever that svcacct does.
      # TODO: bearer JWT setup — Prometheus expects the file at
      # /etc/prometheus/tokens/minio_jwt. Two options:
      #   (a) bind-mount a static file generated out of band
      #   (b) Vault-agent sidecar that templates it
      # Until either is wired, this job will scrape with no auth and
      # fail with 401 — acceptable until plumbing lands.
      - job_name: minio
        metrics_path: /minio/v2/metrics/cluster
        bearer_token_file: /etc/prometheus/tokens/minio_jwt
        static_configs:
          - targets: [192.168.59.17:9000]
            labels: { instance: minio-1 }
          - targets: [192.168.59.37:9000]
            labels: { instance: minio-2 }

      # ── Phase 3a: Cloudflared tunnel replicas ───────────────────────
      # Each cloudflared exposes /metrics on :9080 (set via the
      # `--metrics 0.0.0.0:9080` flag in the existing command line).
      # The container is bridge-only by default; we dual-home each
      # replica onto docker-servers-net at the IPs below — see
      # PHASE-3a stack edits to cloudflare-tunnel{,-2,-3}.yml.
      - job_name: cloudflared
        metrics_path: /metrics
        static_configs:
          - targets: [192.168.59.30:9080]
            labels: { instance: cloudflare-tunnel-1 }
          - targets: [192.168.59.31:9080]
            labels: { instance: cloudflare-tunnel-2 }
          - targets: [192.168.59.32:9080]
            labels: { instance: cloudflare-tunnel-3 }

      # ── Phase 3a: Docker registry (debug HTTP listener) ─────────────
      # Registry exposes /metrics on the debug listener (default :5001)
      # only when `http.debug.addr=:5001` + `http.debug.prometheus.enabled=true`
      # are set in /etc/docker/registry/config.yml on the host.
      # TODO: ssh dockermaster, edit
      #   /nfs/dockermaster/docker/registry/config.yml
      # to add the http.debug block (see
      # https://distribution.github.io/distribution/about/configuration/#http
      # for syntax), then `docker compose restart` the registry stack.
      # Until that lands the target will be up=0 (port closed); this is
      # documented and acceptable.
      - job_name: registry
        metrics_path: /metrics
        static_configs:
          - targets: [192.168.59.16:5001]
            labels: { instance: registry-1 }

      # ── Phase 3a: Watchtower (HTTP API on :8080) ────────────────────
      # WATCHTOWER_HTTP_API_METRICS=true (already set) exposes /v1/metrics
      # behind the same bearer token as the update-trigger API. Two
      # replicas: dm + ds-1 (per stacks.tf watchtower + watchtower_dm).
      # The container is bridge-only by default; we dual-home onto
      # docker-servers-net at the IPs below — see PHASE-3a stack edit
      # to watchtower.yml.
      # TODO: bearer token wiring — same pattern as MinIO. Token lives
      # in Vault at secret/homelab/watchtower (key: api_token). For now
      # use a bearer_token_file at /etc/prometheus/tokens/watchtower
      # populated out of band; long-term Vault-agent sidecar.
      - job_name: watchtower
        metrics_path: /v1/metrics
        bearer_token_file: /etc/prometheus/tokens/watchtower
        static_configs:
          - targets: [192.168.59.33:8080]
            labels: { instance: watchtower-dm }
          - targets: [192.168.59.36:8080]
            labels: { instance: watchtower-ds1 }

      # ── Phase 3h: blackbox_exporter probes ──────────────────────────
      # T4 cadence (60s) per DECISIONS.md Q2; ssl-expiry only every 5m.
      # Targets discovered from JSON files mounted under
      # /etc/prometheus/blackbox-targets/ via docker `configs:` (see
      # prometheus.yml.tftpl). The relabel chain rewrites __address__
      # to the blackbox service so the actual scrape goes to the prober,
      # while `instance` remains the human-readable target.
      - job_name: blackbox-http
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [http_2xx]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/http-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      - job_name: blackbox-icmp
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [icmp]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/icmp-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      - job_name: blackbox-ssl
        # Cert expiry — alerts fire on days remaining; 5m sampling is plenty.
        scrape_interval: 5m
        metrics_path: /probe
        params:
          module: [ssl_expiry]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/ssl-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      - job_name: blackbox-dns
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [dns_lcamaral]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/dns-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      # ── Phase 3c: pve-exporter — Proxmox VE node metrics ────────────
      # Same __param_target rewrite pattern as snmp-exporter and blackbox:
      # scrape targets are PVE nodes, but __address__ gets relabeled to
      # the pve-exporter (192.168.59.35:9221) so it walks the API on
      # Prometheus's behalf. 30s cadence — PVE state doesn't change fast
      # enough to warrant 15s, and the API call is non-trivial.
      - job_name: pve
        scrape_interval: 30s
        metrics_path: /pve
        params:
          target: [192.168.7.11]
        static_configs:
          - targets:
              - 192.168.7.11
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.35:9221

      # ── Phase 3d: Home Assistant /api/prometheus ────────────────────
      # T3 cadence (60s) per DECISIONS.md Q2 — HA exposes one metric per
      # entity per state, which gets large fast. Bearer token comes from
      # the dedicated `prometheus-scrape` user (DECISIONS.md Q8); rendered
      # to /etc/prometheus/tokens/ha_token via docker `configs:` (see
      # prometheus.yml.tftpl). The reverse-proxy origin cert is for
      # *.home.lcamaral.com — hostname matches but skip-verify keeps the
      # cert-rotation blast-radius off the scrape config.
      # Permissive cardinality per DECISIONS.md Phase 3 lock: drop only
      # the four obvious-noise classes below; refine after first scrape.
      - job_name: home-assistant
        scrape_interval: 60s
        metrics_path: /api/prometheus
        scheme: https
        tls_config:
          insecure_skip_verify: true
        authorization:
          type: Bearer
          credentials_file: /etc/prometheus/tokens/ha_token
        static_configs:
          - targets: ['ha.home.lcamaral.com']
            labels:
              instance: home-assistant
        metric_relabel_configs:
          - source_labels: [__name__]
            regex: 'sun_.*|update_.*|weather_.*|.*_diagnostics$'
            action: drop

      # ── Phase 3e: pihole-exporter (3 instances) ─────────────────────
      # T2 cadence (30s) — eko/pihole-exporter shape is small (~50 series
      # per instance) so the per-pihole INTERVAL=30s on the exporter side
      # is the real budget; Prometheus scrape can match.
      # IPs:
      #   192.168.59.41  pihole-exporter-1 (dm)   → pihole-1 (LXC 192.168.100.254)
      #   192.168.59.42  pihole-exporter-2 (ds-1) → pihole-2 (192.168.59.50)
      #   192.168.4.240  pihole-exporter-3 (NAS)  → pihole-3 (192.168.4.236)
      - job_name: pihole
        scrape_interval: 30s
        static_configs:
          - targets: ['192.168.59.41:9617']
            labels:
              instance: pihole-1
          - targets: ['192.168.59.42:9617']
            labels:
              instance: pihole-2
          - targets: ['192.168.4.240:9617']
            labels:
              instance: pihole-3

      # ── Phase 3f: Rundeck native /metrics endpoint ──────────────────
      # Scrape directly at the rundeck container IP (192.168.59.22:4440)
      # to avoid going through nginx-rproxy for an internal-only metric.
      # Bearer token comes from a dedicated read-only Rundeck API token
      # (Vault: secret/homelab/rundeck, field api_token), rendered to
      # /etc/prometheus/tokens/rundeck_api via docker `configs:` (see
      # prometheus.yml.tftpl). Same wiring pattern as ha_token /
      # watchtower_token; will migrate to a Vault-agent sidecar when
      # the shared template-renderer pattern lands.
      - job_name: rundeck
        scrape_interval: 60s
        metrics_path: /api/40/metrics/metrics
        bearer_token_file: /etc/prometheus/tokens/rundeck_api
        static_configs:
          - targets: ['192.168.59.22:4440']
            labels:
              instance: rundeck-1

      # ── Phase 3f: Twingate (no scrape — see note) ───────────────────
      # The connector exposes /metrics natively (TWINGATE_METRICS_PORT
      # set in twingate-a.yml / twingate-b.yml) but binds [::]:9999 and
      # our macvlan has IPv6 fully unloaded, so the listener never
      # comes up. Connector itself stays Online. Re-enable this job the
      # day docker-servers-net gets IPv6 (or we move the connector to a
      # dual-stack bridge). Coverage gap is small — connector state
      # changes rarely and the blackbox-tcp probe already covers
      # control-plane reachability.

      # ── Phase 3f: blackbox TCP probes ───────────────────────────────
      # TCP-handshake-only probes for services with no native metrics
      # (FreeSWITCH SIP 5060, RustDesk hbbs/hbbr, Portainer 9443 etc.).
      # Same relabel chain as the other blackbox-* jobs: __param_target
      # carries the host:port from file_sd, __address__ is rewritten to
      # the blackbox-exporter so the actual scrape goes to the prober,
      # `instance` keeps the human-readable target.
      - job_name: blackbox-tcp
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [tcp_connect]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/tcp-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115
  EOT

  # ──────────────────────────────────────────────
  # prometheus.yml — replica B (prometheus-2 on NAS)
  # ──────────────────────────────────────────────
  prometheus_scrape_config_b = <<-EOT
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: homelab
        replica: B
        region: local

    rule_files:
      - /etc/prometheus/rules/*.yml

    alerting:
      alertmanagers:
        - scheme: http
          static_configs:
            - targets:
                - 192.168.59.27:9093
                - 192.168.4.238:9093

    scrape_configs:
      - job_name: prometheus
        static_configs:
          - targets: [192.168.59.19:9090]
            labels: { instance: prometheus-1 }
          - targets: [192.168.4.237:9090]
            labels: { instance: prometheus-2 }

      - job_name: node
        static_configs:
          - targets: [192.168.48.45:9100]
            labels: { instance: ds-1 }
          - targets: [192.168.48.46:9100]
            labels: { instance: ds-2 }
          - targets: [192.168.48.44:9100]
            labels: { instance: dockermaster }
          - targets: [192.168.0.50:9100]
            labels: { instance: nas }

      - job_name: cadvisor
        static_configs:
          - targets: [192.168.48.45:8080]
            labels: { instance: ds-1 }
          - targets: [192.168.48.46:8080]
            labels: { instance: ds-2 }
          - targets: [192.168.48.44:8080]
            labels: { instance: dockermaster }
          - targets: [192.168.0.50:8080]
            labels: { instance: nas }

      - job_name: snmp-pfsense
        scrape_interval: 15s
        scrape_timeout: 10s
        metrics_path: /snmp
        params:
          module: [pfsense]
        static_configs:
          - targets:
              - pfsense1.srv.lcamaral.com
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.29:9116

      - job_name: thanos
        static_configs:
          - targets: [192.168.59.20:10902]
            labels: { instance: thanos-sidecar-1 }
          - targets: [192.168.59.21:10902]
            labels: { instance: thanos-store-gw }
          - targets: [192.168.59.26:10902]
            labels: { instance: thanos-query }

      # ── Phase 3a: Vault (3-node Raft cluster) ───────────────────────
      # Mirror of replica-A job. See replica-A comment for context.
      - job_name: vault
        scheme: http
        metrics_path: /v1/sys/metrics
        params:
          format: [prometheus]
        static_configs:
          - targets: [192.168.59.25:8200]
            labels: { instance: vault-1 }
          - targets: [192.168.59.9:8200]
            labels: { instance: vault-2 }
          - targets: [192.168.59.15:8200]
            labels: { instance: vault-3 }

      # ── Phase 3a: Keycloak (Quarkus management interface, port 9000) ─
      - job_name: keycloak
        metrics_path: /metrics
        static_configs:
          - targets: [192.168.59.13:9000]
            labels: { instance: keycloak-1 }
          - targets: [192.168.59.43:9000]
            labels: { instance: keycloak-2 }

      # ── Phase 3a: MinIO cluster metrics (v2 endpoint) ───────────────
      # TODO: bearer JWT setup — see replica-A comment.
      - job_name: minio
        metrics_path: /minio/v2/metrics/cluster
        bearer_token_file: /etc/prometheus/tokens/minio_jwt
        static_configs:
          - targets: [192.168.59.17:9000]
            labels: { instance: minio-1 }
          - targets: [192.168.59.37:9000]
            labels: { instance: minio-2 }

      # ── Phase 3a: Cloudflared tunnel replicas ───────────────────────
      - job_name: cloudflared
        metrics_path: /metrics
        static_configs:
          - targets: [192.168.59.30:9080]
            labels: { instance: cloudflare-tunnel-1 }
          - targets: [192.168.59.31:9080]
            labels: { instance: cloudflare-tunnel-2 }
          - targets: [192.168.59.32:9080]
            labels: { instance: cloudflare-tunnel-3 }

      # ── Phase 3a: Docker registry (debug HTTP listener) ─────────────
      # TODO: enable http.debug on host config.yml — see replica-A.
      - job_name: registry
        metrics_path: /metrics
        static_configs:
          - targets: [192.168.59.16:5001]
            labels: { instance: registry-1 }

      # ── Phase 3a: Watchtower (HTTP API on :8080) ────────────────────
      # TODO: bearer token wiring — see replica-A comment.
      - job_name: watchtower
        metrics_path: /v1/metrics
        bearer_token_file: /etc/prometheus/tokens/watchtower
        static_configs:
          - targets: [192.168.59.33:8080]
            labels: { instance: watchtower-dm }
          - targets: [192.168.59.36:8080]
            labels: { instance: watchtower-ds1 }

      # ── Phase 3h: blackbox_exporter probes ──────────────────────────
      # Mirror of replica-A jobs. See replica-A comments for context.
      - job_name: blackbox-http
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [http_2xx]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/http-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      - job_name: blackbox-icmp
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [icmp]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/icmp-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      - job_name: blackbox-ssl
        scrape_interval: 5m
        metrics_path: /probe
        params:
          module: [ssl_expiry]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/ssl-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      - job_name: blackbox-dns
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [dns_lcamaral]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/dns-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115

      # ── Phase 3c: pve-exporter — Proxmox VE node metrics ────────────
      # Mirror of replica-A job; exporter runs on dockermaster macvlan.
      - job_name: pve
        scrape_interval: 30s
        metrics_path: /pve
        params:
          target: [192.168.7.11]
        static_configs:
          - targets:
              - 192.168.7.11
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.35:9221

      # ── Phase 3d: Home Assistant /api/prometheus ────────────────────
      # Mirror of replica-A job. See replica-A comment for context.
      - job_name: home-assistant
        scrape_interval: 60s
        metrics_path: /api/prometheus
        scheme: https
        tls_config:
          insecure_skip_verify: true
        authorization:
          type: Bearer
          credentials_file: /etc/prometheus/tokens/ha_token
        static_configs:
          - targets: ['ha.home.lcamaral.com']
            labels:
              instance: home-assistant
        metric_relabel_configs:
          - source_labels: [__name__]
            regex: 'sun_.*|update_.*|weather_.*|.*_diagnostics$'
            action: drop

      # ── Phase 3e: pihole-exporter (3 instances) ─────────────────────
      # Mirror of replica-A job. See replica-A comment for context.
      - job_name: pihole
        scrape_interval: 30s
        static_configs:
          - targets: ['192.168.59.41:9617']
            labels:
              instance: pihole-1
          - targets: ['192.168.59.42:9617']
            labels:
              instance: pihole-2
          - targets: ['192.168.4.240:9617']
            labels:
              instance: pihole-3

      # ── Phase 3f: Rundeck native /metrics ───────────────────────────
      # Mirror of replica-A job. See replica-A comment for context.
      - job_name: rundeck
        scrape_interval: 60s
        metrics_path: /api/40/metrics/metrics
        bearer_token_file: /etc/prometheus/tokens/rundeck_api
        static_configs:
          - targets: ['192.168.59.22:4440']
            labels:
              instance: rundeck-1

      # ── Phase 3f: Twingate (no scrape — see replica-A note) ─────────

      # ── Phase 3f: blackbox TCP probes ───────────────────────────────
      # Mirror of replica-A job. See replica-A comment for context.
      - job_name: blackbox-tcp
        scrape_interval: 60s
        metrics_path: /probe
        params:
          module: [tcp_connect]
        file_sd_configs:
          - files: ['/etc/prometheus/blackbox-targets/tcp-targets.json']
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 192.168.59.45:9115
  EOT

  # ──────────────────────────────────────────────
  # alertmanager.yml — routing tree from 06-dashboards-and-alerting.md
  #
  # All severities → email luiscamaral+homelab@gmail.com via the existing
  # postfix-relay (no auth, internal only). `info` is a black-hole so rule
  # files can use `severity=info` for debugging without spamming.
  # ──────────────────────────────────────────────
  alertmanager_config = <<-EOT
    global:
      smtp_smarthost: postfix-relay.d.lcamaral.com:25
      smtp_from: 'alertmanager@lcamaral.com'
      smtp_require_tls: false

    route:
      receiver: default
      group_by: [alertname, cluster]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - matchers:
            - severity="critical"
          receiver: email-critical
          group_wait: 10s
          repeat_interval: 1h
          continue: false
        - matchers:
            - severity="warning"
          receiver: email-warning
          group_interval: 15m
          repeat_interval: 6h
        - matchers:
            - severity="info"
          receiver: log-only

    receivers:
      - name: default
        email_configs:
          - to: 'luiscamaral+homelab@gmail.com'
            send_resolved: true
            headers:
              Subject: '[ALERT] {{ .CommonLabels.alertname }} on {{ .CommonLabels.instance }}'

      - name: email-critical
        email_configs:
          - to: 'luiscamaral+homelab@gmail.com'
            send_resolved: true
            headers:
              Subject: '[CRIT] {{ .CommonLabels.alertname }}'

      - name: email-warning
        email_configs:
          - to: 'luiscamaral+homelab@gmail.com'
            send_resolved: true
            headers:
              Subject: '[WARN] {{ .CommonLabels.alertname }}'

      - name: log-only
  EOT

  # ──────────────────────────────────────────────
  # blackbox_exporter — Phase 3h
  #
  # blackbox.yml module library used by the `blackbox-*` Prometheus jobs.
  # Modules:
  #   http_2xx         — HTTP probe; accepts 200/301/302; insecure TLS OK
  #                      (cf-tunnel origins use snakeoil certs)
  #   http_2xx_strict  — HTTP probe; accepts only 200 (kept for future use)
  #   icmp             — raw-socket ping (requires NET_RAW on container)
  #   tcp_connect      — TCP handshake only
  #   ssl_expiry       — TCP+TLS handshake; emits probe_ssl_earliest_cert_expiry
  #   dns_lcamaral     — DNS A query for vault.d.lcamaral.com (resolver health)
  # ──────────────────────────────────────────────
  blackbox_config = <<-EOT
    modules:
      http_2xx:
        prober: http
        timeout: 5s
        http:
          preferred_ip_protocol: ip4
          valid_status_codes: [200, 301, 302]
          tls_config:
            insecure_skip_verify: true
      http_2xx_strict:
        prober: http
        timeout: 5s
        http:
          preferred_ip_protocol: ip4
          valid_status_codes: [200]
      icmp:
        prober: icmp
        timeout: 5s
        icmp:
          preferred_ip_protocol: ip4
      tcp_connect:
        prober: tcp
        timeout: 5s
      ssl_expiry:
        prober: tcp
        timeout: 10s
        tcp:
          tls: true
          tls_config:
            insecure_skip_verify: true
      dns_lcamaral:
        prober: dns
        timeout: 5s
        dns:
          query_name: vault.d.lcamaral.com
          query_type: A
          preferred_ip_protocol: ip4
  EOT

  # ──────────────────────────────────────────────
  # blackbox file_sd target lists — Phase 3h
  #
  # Each local renders the JSON body Prometheus reads via file_sd_configs.
  # Mounted into prometheus-1 and prometheus-2 at
  # /etc/prometheus/blackbox-targets/<name>.json via docker `configs:`
  # (see prometheus.yml.tftpl + prometheus-2.yml.tftpl). Editing these
  # locals re-renders the stack template, terraform sees the diff,
  # Portainer redeploys — no host filesystem coupling.
  #
  # JSON shape: a single-element array of {targets: [...]}. When more
  # structure is needed (per-target labels, env grouping), split into
  # multiple objects in the same file.
  # ──────────────────────────────────────────────
  blackbox_http_targets = jsonencode([
    {
      targets = [
        "https://vault.d.lcamaral.com",
        "https://keycloak.d.lcamaral.com",
        "https://prometheus.d.lcamaral.com",
        "https://s3.d.lcamaral.com",
        "https://portainer.d.lcamaral.com",
        "https://registry.cf.lcamaral.com",
        "https://login.cf.lcamaral.com",
        "https://auth.cf.lcamaral.com",
      ]
    }
  ])

  blackbox_icmp_targets = jsonencode([
    {
      targets = [
        "192.168.4.1",   # pfSense LAN gateway
        "192.168.7.11",  # NAS home-net
        "192.168.48.44", # dockermaster
        "192.168.48.45", # ds-1
        "192.168.48.46", # ds-2
        "192.168.4.236", # pihole-3 (NAS)
        "192.168.16.2",  # secondary gateway
      ]
    }
  ])

  blackbox_ssl_targets = jsonencode([
    {
      targets = [
        "vault.d.lcamaral.com:443",
        "keycloak.d.lcamaral.com:443",
        "registry.cf.lcamaral.com:443",
        "login.cf.lcamaral.com:443",
        "auth.cf.lcamaral.com:443",
        "ha.home.lcamaral.com:443",
      ]
    }
  ])

  blackbox_dns_targets = jsonencode([
    {
      targets = [
        "192.168.100.254:53", # pihole-1 (LXC 10000)
        "192.168.59.50:53",   # pihole-2 (ds-1 macvlan)
        "192.168.4.236:53",   # pihole-3 (NAS)
        "192.168.4.1:53",     # pfSense Unbound
      ]
    }
  ])

  # Phase 3f — TCP-handshake probes for services with no native metrics.
  # FreeSWITCH: native ESL exporter deferred (znerol/freeswitch_exporter
  # is finicky); blackbox TCP on SIP 5060 is the pragmatic fallback.
  # RustDesk hbbs/hbbr: no native metrics; tcp_connect against the well-
  # known control + relay ports tells us the daemon is at least bound.
  blackbox_tcp_targets = jsonencode([
    {
      targets = [
        # FreeSWITCH SIP signalling (Phase 3f — native ESL exporter deferred)
        "freeswitch.d.lcamaral.com:5060",
        # RustDesk hbbs (NAT type test, ID server, TCP hole-punching)
        "hbbs.d.lcamaral.com:21115",
        "hbbs.d.lcamaral.com:21116",
        "hbbs.d.lcamaral.com:21118",
        # RustDesk hbbr (relay)
        "hbbr.d.lcamaral.com:21117",
        "hbbr.d.lcamaral.com:21119",
      ]
    }
  ])
}
