#!/usr/bin/env python3
"""Build the homelab glass panel dashboard JSON.

Edit this file, not the JSON. Run it to rewrite
terraform/portainer/stacks/grafana-dashboards/homelab-glass.json.
Design: docs/operations/2026-11-22-glass-panel-design.md.
"""

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "terraform/portainer/stacks/grafana-dashboards/homelab-glass.json"
DS = {"type": "prometheus", "uid": "thanos"}
GREEN, ORANGE, RED, GREY = "green", "orange", "red", "text"

# (panel title, refId) pairs that may return nothing on a healthy system. The live test allows only these.
MAY_BE_EMPTY = {("Platform", "E"), ("Firing alerts", "A"), ("Targets down", "A")}


def steps(*pairs):
    pairs = [pairs[0]] + [(c, v) for c, v in pairs[1:] if v is not None]
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for c, v in pairs]}


def low_good(orange, red):
    return steps((GREEN, None), (ORANGE, orange), (RED, red))


def high_good(red_below, green_from):
    return steps((RED, None), (ORANGE, red_below), (GREEN, green_from))


def mapping(**values):
    return [{"type": "value", "options": {k: {"text": t, "color": c, "index": i}
                                          for i, (k, (t, c)) in enumerate(values.items())}}]


def target(ref, expr, legend="", instant=True, fmt="time_series", key=None):
    del key  # readability only: names the query at the call site
    return {"datasource": DS, "editorMode": "code", "expr": expr, "legendFormat": legend, "refId": ref,
            "instant": instant, "range": not instant, "format": fmt}


def link(title, uid):
    return {"title": title, "url": f"/d/{uid}", "targetBlank": False}


class Board:
    def __init__(self):
        self.panels = []

    def add(self, panel):
        panel["id"] = len(self.panels) + 1
        panel.setdefault("datasource", DS)
        self.panels.append(panel)

    def row(self, title, y):
        self.add({"type": "row", "title": title, "collapsed": False, "panels": [],
                  "gridPos": {"h": 1, "w": 24, "x": 0, "y": y}})

    def stat(self, title, grid, targets, thresholds=None, unit="none", mappings=None, links=(),
             no_value="no data", overrides=(), text_mode="value", decimals=None, description=""):
        defaults = {"unit": unit, "noValue": no_value, "mappings": mappings or [],
                    "color": {"mode": "thresholds"},
                    "thresholds": thresholds or steps((GREY, None))}
        if decimals is not None:
            defaults["decimals"] = decimals
        self.add({"type": "stat", "title": title, "description": description, "gridPos": grid,
                  "targets": targets, "links": list(links),
                  "fieldConfig": {"defaults": defaults, "overrides": list(overrides)},
                  "options": {"colorMode": "background", "graphMode": "none", "justifyMode": "center",
                              "orientation": "auto", "textMode": text_mode, "wideLayout": True,
                              "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}})


def field(name, thresholds=None, unit=None, mappings=None, no_value=None, by="byName"):
    props = []
    if thresholds:
        props.append({"id": "thresholds", "value": thresholds})
    if unit:
        props.append({"id": "unit", "value": unit})
    if mappings:
        props.append({"id": "mappings", "value": mappings})
    if no_value:
        props.append({"id": "noValue", "value": no_value})
    return {"matcher": {"id": by, "options": name}, "properties": props}


def layer(board, title, x, items, links):
    """One stat panel per layer. items: (key, display name, expr, field settings)."""
    targets, overrides = [], []
    for i, (key, name, expr, settings) in enumerate(items):
        ref = chr(65 + i)
        targets.append(target(ref, expr, legend=name, key=key))
        overrides.append(field(ref, by="byFrameRefID", **settings))
    board.stat(title, {"h": 8, "w": 6, "x": x, "y": 5}, targets, overrides=overrides, links=links,
               text_mode="value_and_name")


def build():
    b = Board()
    b.row("Status", 0)
    tiles = [
        ("Critical alerts", 'count(ALERTS{alertstate="firing",severity="critical"}) or vector(0)',
         low_good(None, 1), "none", [], ()),
        ("Warning alerts", 'count(ALERTS{alertstate="firing",severity="warning"}) or vector(0)',
         steps((GREEN, None), (ORANGE, 1)), "none", [], ()),
        ("Targets down", "count(up == 0) or vector(0)", low_good(1, 3), "none", [],
         (link("Thanos & Prometheus", "thanos-prometheus-infra"),)),
        ("Internet loss (worst WAN)", "max(pfsense_gateway_loss_ratio) * 100", low_good(2, 50), "percent", [],
         (link("pfSense WAN Quality", "pfsense-wan-quality"),)),
        ("DNS answering", 'avg(probe_success{job="blackbox-dns"}) * 100', high_good(75, 100), "percent", [],
         (link("Internet & Network", "internet-network-overview"),)),
        ("Endpoints down", 'count(probe_success{job="blackbox-rproxy"} == 0) or vector(0)', low_good(1, 3),
         "none", [], (link("Blackbox", "blackbox-overview"),)),
        ("Next TLS expiry", "min((probe_ssl_earliest_cert_expiry - time()) / 86400)", high_good(7, 21), "d", [],
         (link("TLS Cert Expiry", "tls-cert-expiry"),)),
        ("Backup share used",
         ('max(pve_disk_usage_bytes{id="storage/proxmox/pve-backups"} / '
          'pve_disk_size_bytes{id="storage/proxmox/pve-backups"}) * 100'),
         low_good(85, 95), "percent", [], (link("Proxmox via Prometheus", "proxmox-pve"),)),
    ]
    for i, (title, expr, th, unit, maps, links) in enumerate(tiles):
        key = title.lower().replace(" ", "_").replace("(", "").replace(")", "")
        b.stat(title, {"h": 4, "w": 3, "x": 3 * i, "y": 1}, [target("A", expr, key=key)], th, unit, maps, links,
               decimals=0 if unit in ("none", "d") else 1)

    yes_no = mapping(**{"1": ("OK", GREEN), "0": ("Failed", RED)})
    b.row("Health by layer", 4)
    layer(b, "Network", 0, [
        ("wan_delay", "{{gateway}} ms", "max by (gateway) (pfsense_gateway_delay_seconds) * 1000",
         {"thresholds": low_good(80, 200), "unit": "none"}),
        ("switch_ports_up", "switch24a ports up", 'count(ifOperStatus{job="snmp-switch24a"} == 1)', {}),
        ("switch_errors", "switch24a input errors/s", 'sum(rate(ifInErrors{instance="switch24a"}[5m]))',
         {"thresholds": low_good(0.5, 10)}),
        ("wifi_stale", "WiFi probes stale",
         'count(ALERTS{alertname="WifiProbeStale",alertstate="firing"}) or vector(0)',
         {"thresholds": low_good(1, 3)}),
        ("tunnels", "Cloudflare tunnel connections", "sum(cloudflared_tunnel_ha_connections)",
         {"thresholds": high_good(6, 12)}),
    ], [link("Internet & Network", "internet-network-overview"), link("switch24a", "switch24a"),
        link("WiFi Probes", "wifi-probes-overview")])
    layer(b, "Compute", 6, [
        ("guests_running", "guests running", 'count(pve_up{id=~"(qemu|lxc)/.*"} == 1)', {}),
        ("onboot_stopped", "start at boot, stopped",
         ('count(((pve_onboot_status == 1) unless on(id) (pve_up == 1)) '
          'unless on(id) pve_guest_info{template="1"}) or vector(0)'),
         {"thresholds": low_good(None, 1)}),
        ("running_no_backup", "running, no backup job",
         "count(pve_not_backed_up_info and on(id) (pve_up == 1)) or vector(0)",
         {"thresholds": low_good(1, None)}),
        ("capacitor", "RAID capacitor", "min(homelab_smart_array_capacitor_ok)", {"mappings": yes_no}),
        ("bad_drives", "RAID drives not OK", "count(homelab_smart_array_physical_drive_ok == 0) or vector(0)",
         {"thresholds": low_good(None, 1)}),
        ("reboots", "hosts rebooted in 24h", "count((time() - node_boot_time_seconds) < 86400) or vector(0)",
         {"thresholds": low_good(1, None)}),
    ], [link("Proxmox via Prometheus", "proxmox-pve"), link("Proxmox storage", "proxmox-smart-array"),
        link("Node Exporter Full", "node-exporter-full")])
    layer(b, "Platform", 12, [
        ("containers", "containers running", 'count(container_last_seen{name!=""})', {}),
        ("container_starts", "containers started in 15 min",
         'count((time() - container_start_time_seconds{name!=""}) < 900) or vector(0)',
         {"thresholds": low_good(1, 5)}),
        ("prometheus_up", "Prometheus up", 'count(up{job="prometheus"} == 1)', {"thresholds": high_good(1, 2)}),
        ("alertmanager_up", "Alertmanager up", 'count(up{job="alertmanager"} == 1)',
         {"thresholds": high_good(1, 2)}),
        ("thanos_upload_age", "Thanos last upload",
         "time() - max(thanos_objstore_bucket_last_successful_upload_time > 0)",
         {"thresholds": low_good(7200, 21600), "unit": "s", "no_value": "never since restart"}),
    ], [link("Thanos & Prometheus", "thanos-prometheus-infra"), link("cAdvisor", "cadvisor")])
    layer(b, "Services", 18, [
        ("vault", "Vault", "min(vault_core_unsealed)",
         {"mappings": mapping(**{"1": ("Unsealed", GREEN), "0": ("Sealed", RED)})}),
        ("keycloak", "Keycloak up", 'sum(up{job="keycloak"})', {"thresholds": high_good(1, 2)}),
        ("postgres", "Postgres up", "sum(pg_up)", {"thresholds": high_good(2, 3)}),
        ("minio", "MinIO", "min(minio_cluster_health_status)",
         {"mappings": mapping(**{"1": ("Healthy", GREEN), "0": ("Unhealthy", RED)})}),
        ("minio_drives", "MinIO drives offline", "max(minio_cluster_drive_offline_total)",
         {"thresholds": low_good(None, 1)}),
        ("pihole", "Pi-hole up", 'sum(up{job="pihole"})', {"thresholds": high_good(2, 3)}),
        ("home_assistant", "Home Assistant", 'max(up{job="home-assistant"})', {"mappings": yes_no}),
    ], [link("Vault", "vault"), link("Keycloak", "keycloak-quarkus"), link("MinIO", "minio-cluster"),
        link("Pi-hole", "pihole-v6"), link("Home Assistant", "home-assistant-stats")])

    b.row("Capacity", 13)
    capacity = [
        ("Root disk used", 'node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"}',
         'node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"}', "{{instance}}", "node-exporter-full"),
        ("Memory used", "node_memory_MemAvailable_bytes", "node_memory_MemTotal_bytes", "{{instance}}",
         "node-exporter-full"),
    ]
    for i, (title, avail, size, legend, uid) in enumerate(capacity):
        expr = f"sort_desc(100 * (1 - {avail} / {size}))"
        b.add(bargauge(title, {"h": 7, "w": 6, "x": 6 * i, "y": 14},
                       [target("A", expr, legend, key=title.lower().replace(" ", "_"))], [link(title, uid)]))
    pve = ('sort_desc(label_replace(100 * pve_disk_usage_bytes{id=~"storage/.*"} / pve_disk_size_bytes{id=~"storage/.*"},'
           ' "pool", "$1", "id", "storage/[^/]+/(.*)"))')
    b.add(bargauge("Proxmox storage used", {"h": 7, "w": 6, "x": 12, "y": 14},
                   [target("A", pve, "{{pool}}", key="pve_storage")], [link("Proxmox via Prometheus", "proxmox-pve")]))
    nas = ('100 * (1 - node_filesystem_avail_bytes{instance="nas",mountpoint="/home"} / '
           'node_filesystem_size_bytes{instance="nas",mountpoint="/home"})')
    b.add(bargauge("NAS volume used", {"h": 7, "w": 6, "x": 18, "y": 14},
                   [target("A", nas, "NAS volume", key="nas_volume")], [link("Node Exporter Full", "node-exporter-full")]))

    b.row("What is firing", 21)
    rank = " or ".join(
        f'(max by (alertname, severity, instance, category) (ALERTS{{alertstate="firing",severity="{s}"}}) * {n})'
        for s, n in (("critical", 3), ("warning", 2), ("info", 1)))
    b.add(table("Firing alerts", {"h": 9, "w": 16, "x": 0, "y": 22},
                [target("A", rank, fmt="table", key="alerts_table")],
                {"alertname": "Alert", "severity": "Severity", "instance": "Instance", "category": "Category"},
                sort="Value", severity=True))
    b.add(table("Targets down", {"h": 9, "w": 8, "x": 16, "y": 22},
                [target("A", "max by (job, instance) (up == 0)", fmt="table", key="targets_down_table")],
                {"job": "Job", "instance": "Instance"}))

    b.row("Last 24 hours", 31)
    trends = [
        ("WAN delay (ms)", "max by (gateway) (pfsense_gateway_delay_seconds) * 1000", "{{gateway}}", "none",
         "pfsense-wan-quality"),
        ("Public endpoint success", 'avg(probe_success{job="blackbox-rproxy"}) * 100', "endpoints", "percent",
         "blackbox-overview"),
        ("CPU busy", '100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))',
         "{{instance}}", "percent", "node-exporter-full"),
    ]
    for i, (title, expr, legend, unit, uid) in enumerate(trends):
        b.add(timeseries(title, {"h": 8, "w": 8, "x": 8 * i, "y": 32},
                         [target("A", expr, legend, instant=False, key="trend_" + str(i))], unit, [link(title, uid)]))

    return {
        "uid": "homelab-glass", "title": "Homelab: Glass Panel", "tags": ["homelab", "overview"],
        "description": "One screen for the whole homelab. Built by scripts/build-glass-panel.py. "
                       "Design: docs/operations/2026-11-22-glass-panel-design.md.",
        "editable": True, "graphTooltip": 1, "id": None, "liveNow": False, "refresh": "1m",
        "schemaVersion": 39, "time": {"from": "now-24h", "to": "now"}, "timezone": "", "version": 1,
        "fiscalYearStartMonth": 0, "weekStart": "", "annotations": {"list": []}, "templating": {"list": []},
        "timepicker": {},
        "links": [{"title": "Homelab dashboards", "type": "dashboards", "tags": [], "asDropdown": True,
                   "includeVars": False, "keepTime": True, "targetBlank": False}],
        "panels": b.panels,
    }


def bargauge(title, grid, targets, links):
    return {"type": "bargauge", "title": title, "gridPos": grid, "targets": targets, "links": links,
            "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100, "decimals": 0,
                                         "noValue": "no data", "color": {"mode": "thresholds"},
                                         "thresholds": low_good(80, 90)}, "overrides": []},
            "options": {"displayMode": "lcd", "orientation": "horizontal", "showUnfilled": True,
                        "valueMode": "color", "namePlacement": "left", "sizing": "auto",
                        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}}


def table(title, grid, targets, rename, sort=None, severity=False):
    exclude = {"Time": True, "__name__": True}
    if severity:
        exclude["Value"] = True
    transforms = []
    if sort:
        transforms.append({"id": "sortBy", "options": {"fields": {}, "sort": [{"field": sort, "desc": True}]}})
    transforms.append({"id": "organize", "options": {"excludeByName": exclude, "renameByName": rename}})
    overrides = []
    if severity:
        overrides.append(field("Severity", mappings=mapping(
            critical=("critical", RED), warning=("warning", ORANGE), info=("info", "blue"))))
        overrides[0]["properties"].append({"id": "custom.cellOptions", "value": {"type": "color-background"}})
    return {"type": "table", "title": title, "gridPos": grid, "targets": targets, "transformations": transforms,
            "fieldConfig": {"defaults": {"custom": {"align": "auto"}, "noValue": "nothing"}, "overrides": overrides},
            "options": {"showHeader": True, "cellHeight": "sm"}}


def timeseries(title, grid, targets, unit, links):
    return {"type": "timeseries", "title": title, "gridPos": grid, "targets": targets, "links": links,
            "fieldConfig": {"defaults": {"unit": unit, "custom": {"lineWidth": 1, "fillOpacity": 0}},
                            "overrides": []},
            "options": {"legend": {"displayMode": "list", "placement": "bottom"},
                        "tooltip": {"mode": "multi", "sort": "desc"}}}


def main():
    OUT.write_text(json.dumps(build(), indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
