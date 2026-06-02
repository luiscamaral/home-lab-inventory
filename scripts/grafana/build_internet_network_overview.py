#!/usr/bin/env python3
"""Generate the "Internet & Network — Overview" Grafana dashboard JSON.

Single-pane NOC board provisioned via Terraform (Portainer configs:). Drop the
output in terraform/portainer/stacks/grafana-dashboards/ and `terraform apply`.

All panels read the `thanos` Prometheus datasource. Metric/label names were
verified live against Thanos Query (192.168.59.26:10902) before authoring — see
the design doc under docs/superpowers/specs/. Re-run this script to regenerate:

    python3 scripts/grafana/build_internet_network_overview.py

Why a generator instead of hand-edited JSON: the interface/throughput rows loop
over the same metric family, and gridPos packing is mechanical. Keeping it in
code makes re-thresholding or adding a VLAN a one-line change, not a 1500-line
JSON diff.
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "thanos"}
OUT = (
    pathlib.Path(__file__).resolve().parents[2]
    / "terraform/portainer/stacks/grafana-dashboards/internet-network-overview.json"
)

# Pi-hole query_status values that count as "blocked" (verified live).
BLOCKED = "DENYLIST.*|GRAVITY.*|REGEX.*|EXTERNAL_BLOCKED.*|SPECIAL_DOMAIN"
# node_exporter virtual/bridge devices to exclude from "top talker" rollups.
# Use RE2 "[.]" for the literal dot — a backslash here would be eaten by PromQL's
# own string parser (and again by JSON), producing a 400 on the query.
VIRT_DEV = "lo|veth.*|docker.*|docker0|br-.*|bond0[.].*|enc0|tap.*"

_id = 0


def nid():
    global _id
    _id += 1
    return _id


# ── layout cursor: packs panels left→right into 24-wide rows ──────────────────
class Grid:
    def __init__(self, y=0):
        self.x, self.y, self.rowh = 0, y, 0

    def place(self, w, h):
        if self.x + w > 24:
            self.y += self.rowh
            self.x, self.rowh = 0, 0
        pos = {"h": h, "w": w, "x": self.x, "y": self.y}
        self.x += w
        self.rowh = max(self.rowh, h)
        return pos

    def newline(self):
        if self.x:
            self.y += self.rowh
            self.x, self.rowh = 0, 0

    def advance(self, h=1):
        self.newline()
        pos = {"h": h, "w": 24, "x": 0, "y": self.y}
        self.y += h
        return pos


def thr(steps):
    return {"mode": "absolute", "steps": steps}


def target(expr, legend="", instant=False):
    return {
        "datasource": DS,
        "expr": expr,
        "legendFormat": legend,
        "range": not instant,
        "instant": instant,
        "refId": chr(65 + target._n % 26),
    }


target._n = 0


def tgt(expr, legend="", instant=False):
    t = target(expr, legend, instant)
    target._n += 1
    return t


def stat(title, gp, expr, unit="none", steps=None, mappings=None,
         color="thresholds", colormode="background", legend="", decimals=None):
    steps = steps or [{"color": "green", "value": None}]
    fc = {
        "defaults": {
            "unit": unit,
            "color": {"mode": color},
            "thresholds": thr(steps),
            "mappings": mappings or [],
        },
        "overrides": [],
    }
    if decimals is not None:
        fc["defaults"]["decimals"] = decimals
    return {
        "id": nid(), "type": "stat", "title": title, "datasource": DS,
        "gridPos": gp, "fieldConfig": fc,
        "options": {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "colorMode": colormode, "graphMode": "area", "justifyMode": "auto",
            "textMode": "auto", "orientation": "auto",
        },
        "targets": [tgt(expr, legend)],
    }


def timeseries(title, gp, targets, unit="none", steps=None, fill=10,
               stack=False, neg_legends=(), desc=""):
    steps = steps or [{"color": "green", "value": None}]
    custom = {
        "drawStyle": "line", "lineInterpolation": "smooth", "lineWidth": 1,
        "fillOpacity": fill, "gradientMode": "opacity", "showPoints": "never",
        "spanNulls": True, "axisCenteredZero": bool(neg_legends),
        "stacking": {"mode": "normal" if stack else "none", "group": "A"},
    }
    overrides = []
    for nl in neg_legends:
        overrides.append({
            "matcher": {"id": "byFrameRefID", "options": nl},
            "properties": [{"id": "custom.transform", "value": "negative-Y"}],
        })
    return {
        "id": nid(), "type": "timeseries", "title": title, "datasource": DS,
        "gridPos": gp, "description": desc,
        "fieldConfig": {
            "defaults": {
                "unit": unit, "color": {"mode": "palette-classic"},
                "custom": custom, "thresholds": thr(steps),
            },
            "overrides": overrides,
        },
        "options": {
            "legend": {"displayMode": "table", "placement": "bottom",
                       "calcs": ["lastNotNull", "max"]},
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
        "targets": targets,
    }


def piechart(title, gp, expr, legend):
    return {
        "id": nid(), "type": "piechart", "title": title, "datasource": DS,
        "gridPos": gp,
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "palette-classic"}},
                        "overrides": []},
        "options": {
            "reduceOptions": {"calcs": ["lastNotNull"], "values": False},
            "pieType": "donut", "legend": {"displayMode": "table", "placement": "right",
                                           "values": ["value", "percent"]},
        },
        "targets": [tgt(expr, legend)],
    }


def state_timeline(title, gp, expr, legend):
    return {
        "id": nid(), "type": "state-timeline", "title": title, "datasource": DS,
        "gridPos": gp,
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "custom": {"fillOpacity": 80, "lineWidth": 0},
                "thresholds": thr([{"color": "red", "value": None},
                                   {"color": "green", "value": 1}]),
                "mappings": [
                    {"type": "value", "options": {"0": {"text": "DOWN", "color": "red"},
                                                   "1": {"text": "UP", "color": "green"}}},
                ],
            },
            "overrides": [],
        },
        "options": {"mergeValues": True, "showValue": "never", "rowHeight": 0.9,
                    "legend": {"displayMode": "list", "placement": "bottom"}},
        "targets": [tgt(expr, legend)],
    }


def table(title, gp, targets, transformations, overrides=None):
    return {
        "id": nid(), "type": "table", "title": title, "datasource": DS, "gridPos": gp,
        "fieldConfig": {"defaults": {"custom": {"filterable": True, "align": "auto"}},
                        "overrides": overrides or []},
        "options": {"showHeader": True, "footer": {"show": False}},
        "transformations": transformations,
        "targets": targets,
    }


def row(title, collapsed):
    return {"id": nid(), "type": "row", "title": title, "collapsed": collapsed,
            "panels": [], "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0}}


# Threshold presets ───────────────────────────────────────────────────────────
RTT = [{"color": "green", "value": None}, {"color": "yellow", "value": 30}, {"color": "red", "value": 80}]
LOSS = [{"color": "green", "value": None}, {"color": "yellow", "value": 1}, {"color": "red", "value": 2}]
JIT = [{"color": "green", "value": None}, {"color": "yellow", "value": 10}, {"color": "red", "value": 30}]
CERT = [{"color": "red", "value": None}, {"color": "yellow", "value": 14}, {"color": "green", "value": 30}]
UPDN = [{"color": "red", "value": None}, {"color": "green", "value": 1}]

panels = []
g = Grid(0)

# ── VERDICT STRIP (always visible) ────────────────────────────────────────────
panels.append(stat("🌐 WAN1 RTT", g.place(3, 4),
                   'pfsense_gateway_delay_seconds{gateway="WAN1GW"}*1000', "ms", RTT))
panels.append(stat("WAN1 Loss", g.place(3, 4),
                   'pfsense_gateway_loss_ratio{gateway="WAN1GW"}*100', "percent", LOSS))
panels.append(stat("WAN2 RTT", g.place(3, 4),
                   'pfsense_gateway_delay_seconds{gateway="WAN2_DHCP"}*1000', "ms", RTT))
panels.append(stat("WAN2 Loss", g.place(3, 4),
                   'pfsense_gateway_loss_ratio{gateway="WAN2_DHCP"}*100', "percent", LOSS))
panels.append(stat("WAN ↓ total", g.place(3, 4),
                   'sum(rate(ifHCInOctets{ifAlias=~"WAN1|WAN2"}[5m])*8)', "bps",
                   [{"color": "green", "value": None}], color="thresholds", colormode="value"))
panels.append(stat("DNS resolvers up", g.place(3, 4),
                   'sum(probe_success{job="blackbox-dns"})', "none",
                   [{"color": "red", "value": None}, {"color": "yellow", "value": 3},
                    {"color": "green", "value": 4}]))
panels.append(stat("🛡️ Pi-hole block %", g.place(3, 4),
                   f'sum(pihole_query_by_status{{query_status=~"{BLOCKED}"}}) '
                   f'/ sum(pihole_query_by_status) * 100', "percent",
                   [{"color": "blue", "value": None}], color="thresholds", colormode="value",
                   decimals=1))
panels.append(stat("🩺 Cert expiry (min, d)", g.place(3, 4),
                   'min(probe_ssl_earliest_cert_expiry - time()) / 86400', "none",
                   CERT, decimals=0))

# ── ROW 1: Internet / WAN (open) ──────────────────────────────────────────────
panels.append(row("🌐 Internet / WAN — uplink quality & failover", False))
g.advance()  # consume the row header line
panels.append(timeseries("Gateway RTT (ms)", g.place(8, 8),
              [tgt('pfsense_gateway_delay_seconds*1000', "{{gateway}}")], "ms", RTT))
panels.append(timeseries("Packet Loss (%)", g.place(8, 8),
              [tgt('pfsense_gateway_loss_ratio*100', "{{gateway}}")], "percent", LOSS))
panels.append(timeseries("Jitter / stddev (ms)", g.place(8, 8),
              [tgt('pfsense_gateway_stddev_seconds*1000', "{{gateway}}")], "ms", JIT))
panels.append(timeseries("WAN Throughput (in ↑ / out ↓)", g.place(12, 8),
              [tgt('rate(ifHCInOctets{ifAlias=~"WAN1|WAN2"}[5m])*8', "{{ifAlias}} in"),
               tgt('rate(ifHCOutOctets{ifAlias=~"WAN1|WAN2"}[5m])*8', "{{ifAlias}} out")],
              "bps", neg_legends=("B",)))
panels.append(timeseries("External DNS lookup time (ms)", g.place(12, 8),
              [tgt('probe_dns_lookup_time_seconds{job="blackbox-dns"}*1000', "{{instance}}")],
              "ms", [{"color": "green", "value": None}, {"color": "yellow", "value": 50},
                     {"color": "red", "value": 200}]))

# ── ROW 2: Interface Throughput & Errors (open) ───────────────────────────────
panels.append(row("🔀 Interface Throughput & Errors — per VLAN/iface", False))
g.advance()
panels.append(timeseries("Inbound by interface (bits/s)", g.place(12, 8),
              [tgt('rate(ifHCInOctets{job="snmp-pfsense", ifAlias=~"$interface"}[5m])*8',
                   "{{ifAlias}}")], "bps"))
panels.append(timeseries("Outbound by interface (bits/s)", g.place(12, 8),
              [tgt('rate(ifHCOutOctets{job="snmp-pfsense", ifAlias=~"$interface"}[5m])*8',
                   "{{ifAlias}}")], "bps"))
panels.append(timeseries("Interface errors & discards (/s)", g.place(12, 7),
              [tgt('rate(ifInErrors{ifAlias=~"$interface"}[5m])', "{{ifAlias}} in-err"),
               tgt('rate(ifOutErrors{ifAlias=~"$interface"}[5m])', "{{ifAlias}} out-err"),
               tgt('rate(ifInDiscards{ifAlias=~"$interface"}[5m])', "{{ifAlias}} in-disc"),
               tgt('rate(ifOutDiscards{ifAlias=~"$interface"}[5m])', "{{ifAlias}} out-disc")],
              "pps", [{"color": "green", "value": None}, {"color": "red", "value": 1}]))
# Interface summary table: merge in/out rates by ifAlias.
panels.append(table("Interface summary (current)", g.place(12, 7),
    [tgt('rate(ifHCInOctets{job="snmp-pfsense", ifAlias=~"$interface"}[5m])*8', "", instant=True),
     tgt('rate(ifHCOutOctets{job="snmp-pfsense", ifAlias=~"$interface"}[5m])*8', "", instant=True)],
    [
        {"id": "joinByField", "options": {"byField": "ifAlias", "mode": "outer"}},
        {"id": "organize", "options": {
            "excludeByName": {"Time": True, "Time 1": True, "Time 2": True, "__name__": True,
                              "__name__ 1": True, "__name__ 2": True, "cluster": True,
                              "cluster 1": True, "cluster 2": True, "instance": True,
                              "instance 1": True, "instance 2": True, "job": True,
                              "job 1": True, "job 2": True, "region": True, "region 1": True,
                              "region 2": True, "ifDescr": True, "ifDescr 1": True,
                              "ifDescr 2": True, "ifIndex": True, "ifIndex 1": True,
                              "ifIndex 2": True, "ifName": True, "ifName 1": True,
                              "ifName 2": True},
            "renameByName": {"ifAlias": "Interface", "Value #A": "In (bps)",
                             "Value #B": "Out (bps)"},
        }},
    ],
    overrides=[
        {"matcher": {"id": "byRegexp", "options": ".*bps.*"},
         "properties": [{"id": "unit", "value": "bps"}]},
    ]))
panels.append(timeseries("Per-host top talkers — rx (bits/s)", g.place(12, 7),
              [tgt(f'topk(8, rate(node_network_receive_bytes_total{{device!~"{VIRT_DEV}"}}[5m])*8)',
                   "{{instance}} · {{device}}")], "bps"))
panels.append(timeseries("Per-host top talkers — tx (bits/s)", g.place(12, 7),
              [tgt(f'topk(8, rate(node_network_transmit_bytes_total{{device!~"{VIRT_DEV}"}}[5m])*8)',
                   "{{instance}} · {{device}}")], "bps"))

# ── ROW 3: DNS & Pi-hole (collapsed) ──────────────────────────────────────────
r3 = row("🧭 DNS & Pi-hole — resolution & ad-blocking", True)
gc = Grid(0)
r3["panels"].append(state_timeline("DNS resolver up", gc.place(24, 4),
                    'probe_success{job="blackbox-dns"}', "{{instance}}"))
r3["panels"].append(timeseries("DNS resolver lookup time (ms)", gc.place(12, 8),
                    [tgt('probe_dns_lookup_time_seconds{job="blackbox-dns"}*1000', "{{instance}}")],
                    "ms", [{"color": "green", "value": None}, {"color": "yellow", "value": 50},
                           {"color": "red", "value": 200}]))
r3["panels"].append(piechart("Pi-hole query status mix", gc.place(6, 8),
                    'sum by (query_status) (pihole_query_by_status)', "{{query_status}}"))
r3["panels"].append(stat("Block %", gc.place(6, 4),
                    f'sum(pihole_query_by_status{{query_status=~"{BLOCKED}"}}) '
                    f'/ sum(pihole_query_by_status) * 100', "percent",
                    [{"color": "blue", "value": None}], color="thresholds",
                    colormode="value", decimals=1))
r3["panels"].append(stat("Gravity domains", gc.place(3, 4),
                    'max(pihole_domains_being_blocked)', "short",
                    [{"color": "purple", "value": None}], colormode="value"))
r3["panels"].append(stat("Active clients", gc.place(3, 4),
                    'max(pihole_client_count)', "short",
                    [{"color": "blue", "value": None}], colormode="value"))
r3["panels"].append(timeseries("Pi-hole queries in window by instance", gc.place(24, 7),
                    [tgt('pihole_query_count', "{{instance}}")], "short"))
panels.append(r3)
g.advance()

# ── ROW 4: Firewall (collapsed) ───────────────────────────────────────────────
r4 = row("🛡️ Firewall (pflog) — pass vs block", True)
gc = Grid(0)
pass_pkts = ('rate(pfLogInterfaceIp4PktsInPass[5m]) + rate(pfLogInterfaceIp4PktsOutPass[5m]) '
             '+ rate(pfLogInterfaceIp6PktsInPass[5m]) + rate(pfLogInterfaceIp6PktsOutPass[5m])')
drop_pkts = ('rate(pfLogInterfaceIp4PktsInDrop[5m]) + rate(pfLogInterfaceIp4PktsOutDrop[5m]) '
             '+ rate(pfLogInterfaceIp6PktsInDrop[5m]) + rate(pfLogInterfaceIp6PktsOutDrop[5m])')
r4["panels"].append(timeseries("Pass vs Block — packets/s", gc.place(12, 8),
                    [tgt(pass_pkts, "pass"), tgt(drop_pkts, "block")], "pps", fill=20))
r4["panels"].append(timeseries("Logged bytes/s (in ↑ / out ↓)", gc.place(12, 8),
                    [tgt('rate(pfLogInterfaceIp4BytesIn[5m]) + rate(pfLogInterfaceIp6BytesIn[5m])', "in"),
                     tgt('rate(pfLogInterfaceIp4BytesOut[5m]) + rate(pfLogInterfaceIp6BytesOut[5m])', "out")],
                    "Bps", neg_legends=("B",)))
r4["panels"].append(stat("Block rate (pkt/s)", gc.place(6, 4), drop_pkts, "pps",
                    [{"color": "green", "value": None}, {"color": "yellow", "value": 1},
                     {"color": "red", "value": 10}], colormode="value", decimals=2))
r4["panels"].append(stat("Pass rate (pkt/s)", gc.place(6, 4), pass_pkts, "pps",
                    [{"color": "green", "value": None}], colormode="value", decimals=2))
panels.append(r4)
g.advance()

# ── ROW 5: Service Reachability (collapsed) ───────────────────────────────────
r5 = row("🩺 Service Reachability — blackbox probes", True)
gc = Grid(0)
r5["panels"].append(state_timeline("Probe UP matrix (all blackbox jobs)", gc.place(24, 9),
                    'probe_success', "{{job}} · {{instance}}"))
r5["panels"].append(stat("Probes Up %", gc.place(6, 4),
                    'sum(probe_success{instance!~"https://rustdesk.*"}) '
                    '/ count(probe_success{instance!~"https://rustdesk.*"}) * 100', "percent",
                    [{"color": "red", "value": None}, {"color": "yellow", "value": 90},
                     {"color": "green", "value": 100}], decimals=1))
r5["panels"].append(timeseries("Probe duration (ms)", gc.place(18, 8),
                    [tgt('probe_duration_seconds*1000', "{{job}} · {{instance}}")], "ms",
                    [{"color": "green", "value": None}, {"color": "yellow", "value": 500},
                     {"color": "red", "value": 2000}]))
r5["panels"].append(table("HTTP status codes", gc.place(12, 8),
    [tgt('probe_http_status_code', "", instant=True)],
    [{"id": "organize", "options": {
        "excludeByName": {"Time": True, "__name__": True, "cluster": True, "region": True},
        "renameByName": {"job": "Job", "instance": "Target", "Value": "HTTP code"},
        "indexByName": {"instance": 0, "job": 1, "Value": 2}}}],
    overrides=[{"matcher": {"id": "byName", "options": "HTTP code"},
                "properties": [{"id": "custom.cellOptions", "value": {"type": "color-text"}},
                               {"id": "thresholds", "value": thr(
                                   [{"color": "green", "value": None},
                                    {"color": "yellow", "value": 300},
                                    {"color": "red", "value": 400}])}]}]))
r5["panels"].append(table("SSL cert expiry (days, soonest first)", gc.place(12, 8),
    [tgt('(probe_ssl_earliest_cert_expiry - time()) / 86400', "", instant=True)],
    [{"id": "filterFieldsByName", "options": {"include": {"pattern": "instance|job|Value"}}},
     {"id": "organize", "options": {
         "renameByName": {"job": "Job", "instance": "Target", "Value": "Days left"},
         "indexByName": {"instance": 0, "job": 1, "Value": 2}}},
     {"id": "sortBy", "options": {"fields": "", "sort": [{"field": "Days left", "desc": False}]}}],
    overrides=[{"matcher": {"id": "byName", "options": "Days left"},
                "properties": [{"id": "unit", "value": "none"}, {"id": "decimals", "value": 0},
                               {"id": "custom.cellOptions", "value": {"type": "color-background"}},
                               {"id": "thresholds", "value": thr(CERT)}]}]))
r5["panels"].append({
    "id": nid(), "type": "text", "title": "", "datasource": None,
    "gridPos": gc.place(24, 3),
    "options": {"mode": "markdown", "content":
        "ℹ️ **Known false-positive:** `rustdesk.home` / `rustdesk-relay.home` report "
        "`probe_success=0` on plain-GET probes because they are **WebSocket-only** "
        "upstreams (they answer `101 Switching Protocols`, not `200`). They are "
        "**excluded** from the *Probes Up %* tile. See memory "
        "`blackbox-rproxy WebSocket false positive`."}})
panels.append(r5)
g.advance()

# ── Dashboard envelope ────────────────────────────────────────────────────────
dashboard = {
    "uid": "internet-network-overview",
    "title": "🌐 Internet & Network — Overview",
    "description": "Single-pane NOC view: dual-WAN uplink quality, interface "
                   "throughput, DNS/Pi-hole, firewall, and service reachability. "
                   "Generated by scripts/grafana/build_internet_network_overview.py.",
    "tags": ["network", "internet", "wan", "dns", "blackbox", "homelab", "overview"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "editable": True,
    "weekStart": "",
    "refresh": "30s",
    "time": {"from": "now-6h", "to": "now"},
    "timepicker": {},
    "annotations": {"list": [{
        "builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"},
        "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts", "type": "dashboard"}]},
    "links": [
        {"title": "pfSense WAN Quality", "type": "dashboards", "tags": ["pfsense", "wan"],
         "asDropdown": False, "targetBlank": False, "icon": "external link"},
        {"title": "Pi-hole", "type": "dashboards", "tags": ["pihole"],
         "asDropdown": False, "targetBlank": False, "icon": "external link"},
        {"title": "Blackbox", "type": "dashboards", "tags": ["blackbox"],
         "asDropdown": False, "targetBlank": False, "icon": "external link"},
        {"title": "Node Exporter", "type": "dashboards", "tags": ["node-exporter"],
         "asDropdown": False, "targetBlank": False, "icon": "external link"},
    ],
    "templating": {"list": [
        {"name": "interface", "type": "query", "datasource": DS,
         "query": {"query": 'label_values(ifHCInOctets{job="snmp-pfsense"}, ifAlias)',
                   "refId": "StandardVariableQuery"},
         "refresh": 2, "includeAll": True, "multi": True, "allValue": ".*",
         "current": {"text": "All", "value": "$__all"}, "sort": 1, "label": "Interface"},
        {"name": "pihole", "type": "query", "datasource": DS,
         "query": {"query": "label_values(pihole_query_count, instance)",
                   "refId": "StandardVariableQuery"},
         "refresh": 2, "includeAll": True, "multi": True, "allValue": ".*",
         "current": {"text": "All", "value": "$__all"}, "sort": 1, "label": "Pi-hole"},
    ]},
    "panels": panels,
}

# sort_keys matches the repo's pretty-format-json pre-commit hook so regeneration
# is a no-op for the hook (no churn).
OUT.write_text(json.dumps(dashboard, indent=2, sort_keys=True) + "\n")
print(f"wrote {OUT}  ({len(panels)} top-level panels, {_id} total ids)")
