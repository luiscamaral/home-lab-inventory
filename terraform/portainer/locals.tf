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
          - targets: [192.168.4.233:9100]
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
          - targets: [192.168.4.233:8080]
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
            replacement: snmp-exporter:9116

      # ── Thanos self-scrape (sidecar-1, query, store-gw) ─────────────
      - job_name: thanos
        static_configs:
          - targets: [192.168.59.20:10902]
            labels: { instance: thanos-sidecar-1 }
          - targets: [192.168.59.21:10902]
            labels: { instance: thanos-store-gw }
          - targets: [192.168.59.26:10902]
            labels: { instance: thanos-query }

      # TODO Phase 3: home-assistant via /api/prometheus.
      # Requires Vault secret secret/homelab/home-assistant/metrics_token
      # (DECISIONS.md Q8). Bearer-token-file plumbing TBD.
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
          - targets: [192.168.4.233:9100]
            labels: { instance: nas }

      - job_name: cadvisor
        static_configs:
          - targets: [192.168.48.45:8080]
            labels: { instance: ds-1 }
          - targets: [192.168.48.46:8080]
            labels: { instance: ds-2 }
          - targets: [192.168.48.44:8080]
            labels: { instance: dockermaster }
          - targets: [192.168.4.233:8080]
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
            replacement: snmp-exporter:9116

      - job_name: thanos
        static_configs:
          - targets: [192.168.59.20:10902]
            labels: { instance: thanos-sidecar-1 }
          - targets: [192.168.59.21:10902]
            labels: { instance: thanos-store-gw }
          - targets: [192.168.59.26:10902]
            labels: { instance: thanos-query }
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
}
