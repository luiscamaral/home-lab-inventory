#!/usr/bin/env python3
"""Generate the "Internet & Network — Overview" Grafana dashboard JSON.

Single-pane NOC board provisioned via Terraform (Portainer configs:). Drop the
output in terraform/portainer/stacks/grafana-dashboards/ and `terraform apply`.

Design is declarative: BASE panels are defined inline as uniform "spec" dicts,
and the validated additions from the multi-agent coverage review are loaded
verbatim from internet-network-additions.json (sibling file) and appended to
their rows. A single renderer (mk) turns a spec into a Grafana panel and a
layout pass assigns gridPos. Re-run to regenerate:

    python3 scripts/grafana/build_internet_network_overview.py

Every metric/label name and all PromQL was verified live against Thanos Query
(192.168.59.26:10902). See docs/superpowers/specs/ for the design + coverage
review. Coverage after the review: ~88/100.
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "thanos"}
HERE = pathlib.Path(__file__).resolve()
OUT = HERE.parents[2] / "terraform/portainer/stacks/grafana-dashboards/internet-network-overview.json"
ADDITIONS = HERE.parent / "internet-network-additions.json"

BLOCKED = "DENYLIST.*|GRAVITY.*|REGEX.*|EXTERNAL_BLOCKED.*|SPECIAL_DOMAIN"
VIRT_DEV = "lo|veth.*|docker.*|docker0|br-.*|bond0[.].*|enc0|tap.*"
WAN2_CAVEAT = ("Note: WAN2_DHCP dpinger monitors 192.168.12.1 (the ISP-modem "
               "next-hop on the LAN, ~1ms), not an external host — it reflects "
               "modem reachability only. WAN1GW monitors 8.8.8.8 (external).")

# ── threshold presets ─────────────────────────────────────────────────────────
RTT = [{"color": "green", "value": None}, {"color": "yellow", "value": 30}, {"color": "red", "value": 80}]
LOSS = [{"color": "green", "value": None}, {"color": "yellow", "value": 1}, {"color": "red", "value": 2}]
JIT = [{"color": "green", "value": None}, {"color": "yellow", "value": 10}, {"color": "red", "value": 30}]
CERT = [{"color": "red", "value": None}, {"color": "yellow", "value": 14}, {"color": "green", "value": 30}]
DNSL = [{"color": "green", "value": None}, {"color": "yellow", "value": 50}, {"color": "red", "value": 200}]
GREEN = [{"color": "green", "value": None}]

_id = 0


def nid():
    global _id
    _id += 1
    return _id


def thr(steps):
    return {"mode": "absolute", "steps": steps}


def T(expr, legend="", instant=False):
    return {"expr": expr, "legend": legend, "instant": instant}


# ── generic panel renderer ────────────────────────────────────────────────────
def mk(s, gp):
    t = s["type"]
    targets = []
    for i, x in enumerate(s.get("targets", [])):
        targets.append({
            "datasource": DS, "expr": x["expr"], "legendFormat": x.get("legend", ""),
            "instant": x.get("instant", False), "range": not x.get("instant", False),
            "refId": chr(65 + i),
        })
    defs = {"unit": s.get("unit", "none"), "thresholds": thr(s.get("steps") or GREEN),
            "mappings": s.get("mappings", [])}
    if s.get("decimals") is not None:
        defs["decimals"] = s["decimals"]
    common = {"id": nid(), "title": s.get("title", ""), "datasource": DS,
              "gridPos": gp, "description": s.get("desc", "")}

    if t == "stat":
        defs["color"] = {"mode": "thresholds"}
        return {**common, "type": "stat",
                "fieldConfig": {"defaults": defs, "overrides": s.get("overrides", [])},
                "options": {"reduceOptions": {"calcs": [s.get("reducer", "lastNotNull")],
                                              "fields": "", "values": False},
                            "colorMode": s.get("colormode", "background"), "graphMode": "area",
                            "textMode": s.get("textmode", "auto"), "justifyMode": "auto",
                            "orientation": "auto"},
                "targets": targets}

    if t == "timeseries":
        custom = {"drawStyle": "line", "lineInterpolation": "smooth", "lineWidth": 1,
                  "fillOpacity": s.get("fill", 10), "gradientMode": "opacity",
                  "showPoints": "never", "spanNulls": True,
                  "axisCenteredZero": bool(s.get("negY")),
                  "stacking": {"mode": "normal" if s.get("stack") else "none", "group": "A"}}
        defs["color"] = {"mode": "palette-classic"}
        defs["custom"] = custom
        overrides = list(s.get("overrides", []))
        for ref in (s.get("negY") or []):
            overrides.append({"matcher": {"id": "byFrameRefID", "options": ref},
                              "properties": [{"id": "custom.transform", "value": "negative-Y"}]})
        return {**common, "type": "timeseries",
                "fieldConfig": {"defaults": defs, "overrides": overrides},
                "options": {"legend": {"displayMode": "table", "placement": "bottom",
                                       "calcs": ["lastNotNull", "max"]},
                            "tooltip": {"mode": "multi", "sort": "desc"}},
                "targets": targets}

    if t == "piechart":
        defs["color"] = {"mode": "palette-classic"}
        return {**common, "type": "piechart",
                "fieldConfig": {"defaults": defs, "overrides": []},
                "options": {"reduceOptions": {"calcs": ["lastNotNull"], "values": False},
                            "pieType": "donut" if s.get("donut", True) else "pie",
                            "legend": {"displayMode": "table", "placement": "right",
                                       "values": ["value", "percent"]}},
                "targets": targets}

    if t == "bargauge":
        defs["color"] = {"mode": "thresholds"}
        return {**common, "type": "bargauge",
                "fieldConfig": {"defaults": defs, "overrides": s.get("overrides", [])},
                "options": {"reduceOptions": {"calcs": ["lastNotNull"], "values": False},
                            "orientation": "horizontal", "displayMode": "gradient",
                            "minVizWidth": 0, "minVizHeight": 10, "showUnfilled": True},
                "targets": targets}

    if t == "state-timeline":
        if s.get("binary", True):
            steps = [{"color": "red", "value": None}, {"color": "green", "value": 1}]
            mappings = [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"},
                                                      "1": {"text": "UP", "color": "green"}}}]
        else:
            steps = s.get("steps") or GREEN
            mappings = s.get("mappings", [])
        return {**common, "type": "state-timeline",
                "fieldConfig": {"defaults": {"color": {"mode": "thresholds"},
                                             "custom": {"fillOpacity": 80, "lineWidth": 0},
                                             "thresholds": thr(steps), "mappings": mappings},
                                "overrides": []},
                "options": {"mergeValues": True, "showValue": "never", "rowHeight": 0.9,
                            "legend": {"displayMode": "list", "placement": "bottom"}},
                "targets": targets}

    if t == "table":
        return {**common, "type": "table",
                "fieldConfig": {"defaults": {"custom": {"filterable": True, "align": "auto"},
                                             "mappings": s.get("mappings", [])},
                                "overrides": s.get("overrides", [])},
                "options": {"showHeader": True, "footer": {"show": False}},
                "transformations": s.get("transforms", []),
                "targets": targets}

    if t == "text":
        return {**common, "type": "text", "datasource": None,
                "options": {"mode": "markdown", "content": s.get("content", "")}}

    raise ValueError("unknown panel type: " + t)


# ── layout: pack specs left→right into 24-wide rows from y0 ────────────────────
def pack(specs, y0):
    x = y = 0
    rowh = 0
    out = []
    y = y0
    for s in specs:
        w, h = s.get("w", 12), s.get("h", 8)
        if x + w > 24:
            y += rowh
            x = rowh = 0
        out.append(mk(s, {"h": h, "w": w, "x": x, "y": y}))
        x += w
        rowh = max(rowh, h)
    return out, (y + rowh)


GENERIC_TABLE_TFM = [
    {"id": "merge", "options": {}},
    {"id": "organize", "options": {"excludeByName": {
        "Time": True, "__name__": True, "cluster": True, "region": True, "job": True,
        "monitor": True, "source": True}, "renameByName": {}}},
]


def load_additions():
    """Load validated additions from the review, convert to spec dicts by row_key."""
    by_row = {}
    for a in json.loads(ADDITIONS.read_text()):
        s = {
            "type": a["type"], "title": a["title"],
            "targets": [T(t["expr"], t.get("legend", ""), t.get("instant", False)) for t in a["targets"]],
            "unit": a.get("unit", "none"), "steps": a.get("steps") or GREEN,
            "decimals": a.get("decimals"), "w": a.get("w", 12), "h": a.get("h", 8),
            "desc": a.get("desc", ""),
        }
        h = a.get("hints", {})
        if h.get("binary") is False:
            s["binary"] = False
        if h.get("textmode"):
            s["textmode"] = h["textmode"]
            s["colormode"] = "value"
        if h.get("table") or a["type"] == "table":
            s["transforms"] = GENERIC_TABLE_TFM
        if a["type"] in ("stat", "bargauge") and "colormode" not in s:
            s["colormode"] = "value" if a["type"] == "bargauge" else "background"
        by_row.setdefault(a["row_key"], []).append(s)
    return by_row


# ══ BASE panels ═══════════════════════════════════════════════════════════════
verdict = [
    {"type": "stat", "title": "🌐 WAN1 RTT", "w": 3, "h": 4, "unit": "ms", "steps": RTT,
     "targets": [T('pfsense_gateway_delay_seconds{gateway="WAN1GW"}*1000')]},
    {"type": "stat", "title": "WAN1 Loss", "w": 3, "h": 4, "unit": "percent", "steps": LOSS,
     "targets": [T('pfsense_gateway_loss_ratio{gateway="WAN1GW"}*100')]},
    {"type": "stat", "title": "WAN2 RTT", "w": 3, "h": 4, "unit": "ms", "steps": RTT, "desc": WAN2_CAVEAT,
     "targets": [T('pfsense_gateway_delay_seconds{gateway="WAN2_DHCP"}*1000')]},
    {"type": "stat", "title": "WAN2 Loss", "w": 3, "h": 4, "unit": "percent", "steps": LOSS, "desc": WAN2_CAVEAT,
     "targets": [T('pfsense_gateway_loss_ratio{gateway="WAN2_DHCP"}*100')]},
    {"type": "stat", "title": "WAN ↓ total", "w": 3, "h": 4, "unit": "bps", "colormode": "value",
     "targets": [T('sum(rate(ifHCInOctets{ifAlias=~"WAN1|WAN2"}[$__rate_interval])*8)')]},
    {"type": "stat", "title": "DNS resolvers up", "w": 3, "h": 4, "unit": "none",
     "steps": [{"color": "red", "value": None}, {"color": "yellow", "value": 3}, {"color": "green", "value": 4}],
     "targets": [T('sum(probe_success{job="blackbox-dns"})')]},
    {"type": "stat", "title": "🛡️ Pi-hole block %", "w": 3, "h": 4, "unit": "percent", "colormode": "value", "decimals": 1,
     "steps": [{"color": "blue", "value": None}],
     "targets": [T(f'sum(pihole_query_by_status{{query_status=~"{BLOCKED}"}}) / sum(pihole_query_by_status) * 100')]},
    {"type": "stat", "title": "🩺 Cert expiry (min, d)", "w": 3, "h": 4, "unit": "none", "decimals": 0, "steps": CERT,
     "targets": [T('min(probe_ssl_earliest_cert_expiry - time()) / 86400')]},
]

wan = [
    {"type": "timeseries", "title": "Gateway RTT (ms)", "w": 8, "h": 8, "unit": "ms", "steps": RTT,
     "targets": [T('pfsense_gateway_delay_seconds*1000', "{{gateway}}")]},
    {"type": "timeseries", "title": "Packet Loss (%)", "w": 8, "h": 8, "unit": "percent", "steps": LOSS, "desc": WAN2_CAVEAT,
     "targets": [T('pfsense_gateway_loss_ratio*100', "{{gateway}}")]},
    {"type": "timeseries", "title": "Jitter / stddev (ms)", "w": 8, "h": 8, "unit": "ms", "steps": JIT,
     "targets": [T('pfsense_gateway_stddev_seconds*1000', "{{gateway}}")]},
    {"type": "timeseries", "title": "WAN Throughput (in ↑ / out ↓)", "w": 12, "h": 8, "unit": "bps", "negY": ["B"],
     "targets": [T('rate(ifHCInOctets{ifAlias=~"WAN1|WAN2"}[$__rate_interval])*8', "{{ifAlias}} in"),
                 T('rate(ifHCOutOctets{ifAlias=~"WAN1|WAN2"}[$__rate_interval])*8', "{{ifAlias}} out")]},
    {"type": "timeseries", "title": "External DNS lookup time (ms)", "w": 12, "h": 8, "unit": "ms", "steps": DNSL,
     "targets": [T('probe_dns_lookup_time_seconds{job="blackbox-dns"}*1000', "{{instance}}")]},
]

interface = [
    {"type": "timeseries", "title": "Inbound by interface (bits/s)", "w": 12, "h": 8, "unit": "bps",
     "targets": [T('rate(ifHCInOctets{job="snmp-pfsense", ifAlias=~"$interface"}[$__rate_interval])*8', "{{ifAlias}}")]},
    {"type": "timeseries", "title": "Outbound by interface (bits/s)", "w": 12, "h": 8, "unit": "bps",
     "targets": [T('rate(ifHCOutOctets{job="snmp-pfsense", ifAlias=~"$interface"}[$__rate_interval])*8', "{{ifAlias}}")]},
    {"type": "timeseries", "title": "Interface errors & discards (/s)", "w": 12, "h": 7, "unit": "pps",
     "steps": [{"color": "green", "value": None}, {"color": "red", "value": 1}],
     "targets": [T('rate(ifInErrors{ifAlias=~"$interface"}[$__rate_interval])', "{{ifAlias}} in-err"),
                 T('rate(ifOutErrors{ifAlias=~"$interface"}[$__rate_interval])', "{{ifAlias}} out-err"),
                 T('rate(ifInDiscards{ifAlias=~"$interface"}[$__rate_interval])', "{{ifAlias}} in-disc"),
                 T('rate(ifOutDiscards{ifAlias=~"$interface"}[$__rate_interval])', "{{ifAlias}} out-disc")]},
    {"type": "table", "title": "Interface summary (current)", "w": 12, "h": 7,
     "targets": [T('rate(ifHCInOctets{job="snmp-pfsense", ifAlias=~"$interface"}[$__rate_interval])*8', instant=True),
                 T('rate(ifHCOutOctets{job="snmp-pfsense", ifAlias=~"$interface"}[$__rate_interval])*8', instant=True)],
     "transforms": [
         {"id": "joinByField", "options": {"byField": "ifAlias", "mode": "outer"}},
         {"id": "organize", "options": {"excludeByName": {
             "Time": True, "Time 1": True, "Time 2": True, "__name__": True, "__name__ 1": True,
             "__name__ 2": True, "cluster": True, "cluster 1": True, "cluster 2": True, "instance": True,
             "instance 1": True, "instance 2": True, "job": True, "job 1": True, "job 2": True,
             "region": True, "region 1": True, "region 2": True, "ifDescr": True, "ifDescr 1": True,
             "ifDescr 2": True, "ifIndex": True, "ifIndex 1": True, "ifIndex 2": True, "ifName": True,
             "ifName 1": True, "ifName 2": True},
             "renameByName": {"ifAlias": "Interface", "Value #A": "In (bps)", "Value #B": "Out (bps)"}}}],
     "overrides": [{"matcher": {"id": "byRegexp", "options": ".*bps.*"},
                    "properties": [{"id": "unit", "value": "bps"}]}]},
    {"type": "timeseries", "title": "Per-host top talkers — rx (bits/s)", "w": 12, "h": 7, "unit": "bps",
     "targets": [T(f'topk(8, rate(node_network_receive_bytes_total{{device!~"{VIRT_DEV}"}}[$__rate_interval])*8)',
                   "{{instance}} · {{device}}")]},
    {"type": "timeseries", "title": "Per-host top talkers — tx (bits/s)", "w": 12, "h": 7, "unit": "bps",
     "targets": [T(f'topk(8, rate(node_network_transmit_bytes_total{{device!~"{VIRT_DEV}"}}[$__rate_interval])*8)',
                   "{{instance}} · {{device}}")]},
]

dns = [
    {"type": "state-timeline", "title": "DNS resolver up", "w": 24, "h": 4,
     "targets": [T('probe_success{job="blackbox-dns"}', "{{instance}}")]},
    {"type": "timeseries", "title": "DNS resolver lookup time (ms)", "w": 12, "h": 8, "unit": "ms", "steps": DNSL,
     "targets": [T('probe_dns_lookup_time_seconds{job="blackbox-dns"}*1000', "{{instance}}")]},
    {"type": "piechart", "title": "Pi-hole query status mix", "w": 6, "h": 8, "unit": "short",
     "targets": [T('sum by (query_status) (pihole_query_by_status)', "{{query_status}}")]},
    {"type": "stat", "title": "Block %", "w": 6, "h": 4, "unit": "percent", "colormode": "value", "decimals": 1,
     "steps": [{"color": "blue", "value": None}],
     "targets": [T(f'sum(pihole_query_by_status{{query_status=~"{BLOCKED}"}}) / sum(pihole_query_by_status) * 100')]},
    {"type": "stat", "title": "Gravity domains", "w": 3, "h": 4, "unit": "short", "colormode": "value",
     "steps": [{"color": "purple", "value": None}], "targets": [T('max(pihole_domains_being_blocked)')]},
    {"type": "stat", "title": "Active clients", "w": 3, "h": 4, "unit": "short", "colormode": "value",
     "steps": [{"color": "blue", "value": None}], "targets": [T('max(pihole_client_count)')]},
    {"type": "timeseries", "title": "Pi-hole queries in window by instance", "w": 24, "h": 7, "unit": "short",
     "targets": [T('pihole_query_count', "{{instance}}")]},
]

PASS = ('rate(pfLogInterfaceIp4PktsInPass[$__rate_interval]) + rate(pfLogInterfaceIp4PktsOutPass[$__rate_interval]) '
        '+ rate(pfLogInterfaceIp6PktsInPass[$__rate_interval]) + rate(pfLogInterfaceIp6PktsOutPass[$__rate_interval])')
DROP = ('rate(pfLogInterfaceIp4PktsInDrop[$__rate_interval]) + rate(pfLogInterfaceIp4PktsOutDrop[$__rate_interval]) '
        '+ rate(pfLogInterfaceIp6PktsInDrop[$__rate_interval]) + rate(pfLogInterfaceIp6PktsOutDrop[$__rate_interval])')
firewall = [
    {"type": "timeseries", "title": "pflog: Pass vs Block — packets/s", "w": 12, "h": 8, "unit": "pps", "fill": 20,
     "targets": [T(PASS, "pass"), T(DROP, "block")]},
    {"type": "timeseries", "title": "pflog: Logged bytes/s (in ↑ / out ↓)", "w": 12, "h": 8, "unit": "Bps", "negY": ["B"],
     "targets": [T('rate(pfLogInterfaceIp4BytesIn[$__rate_interval]) + rate(pfLogInterfaceIp6BytesIn[$__rate_interval])', "in"),
                 T('rate(pfLogInterfaceIp4BytesOut[$__rate_interval]) + rate(pfLogInterfaceIp6BytesOut[$__rate_interval])', "out")]},
    {"type": "stat", "title": "pflog block rate (pkt/s)", "w": 6, "h": 4, "unit": "pps", "colormode": "value", "decimals": 2,
     "steps": [{"color": "green", "value": None}, {"color": "yellow", "value": 1}, {"color": "red", "value": 10}],
     "targets": [T(DROP)]},
    {"type": "stat", "title": "pflog pass rate (pkt/s)", "w": 6, "h": 4, "unit": "pps", "colormode": "value", "decimals": 2,
     "targets": [T(PASS)]},
]

reach = [
    {"type": "state-timeline", "title": "Probe UP matrix (all blackbox jobs)", "w": 24, "h": 9,
     "targets": [T('probe_success', "{{job}} · {{instance}}")]},
    {"type": "stat", "title": "Probes Up %", "w": 6, "h": 4, "unit": "percent", "decimals": 1,
     "steps": [{"color": "red", "value": None}, {"color": "yellow", "value": 90}, {"color": "green", "value": 100}],
     "targets": [T('sum(probe_success{instance!~"https://rustdesk.*"}) / count(probe_success{instance!~"https://rustdesk.*"}) * 100')]},
    {"type": "timeseries", "title": "Probe duration (ms)", "w": 18, "h": 8, "unit": "ms",
     "steps": [{"color": "green", "value": None}, {"color": "yellow", "value": 500}, {"color": "red", "value": 2000}],
     "targets": [T('probe_duration_seconds*1000', "{{job}} · {{instance}}")]},
    {"type": "table", "title": "HTTP status codes", "w": 12, "h": 8,
     "targets": [T('probe_http_status_code', instant=True)],
     "transforms": [{"id": "organize", "options": {
         "excludeByName": {"Time": True, "__name__": True, "cluster": True, "region": True},
         "renameByName": {"job": "Job", "instance": "Target", "Value": "HTTP code"},
         "indexByName": {"instance": 0, "job": 1, "Value": 2}}}],
     "overrides": [{"matcher": {"id": "byName", "options": "HTTP code"},
                    "properties": [{"id": "custom.cellOptions", "value": {"type": "color-text"}},
                                   {"id": "thresholds", "value": thr([{"color": "green", "value": None},
                                                                      {"color": "yellow", "value": 300},
                                                                      {"color": "red", "value": 400}])}]}]},
    {"type": "table", "title": "SSL cert expiry (days, soonest first)", "w": 12, "h": 8,
     "targets": [T('(probe_ssl_earliest_cert_expiry - time()) / 86400', instant=True)],
     "transforms": [
         {"id": "filterFieldsByName", "options": {"include": {"pattern": "instance|job|Value"}}},
         {"id": "organize", "options": {"renameByName": {"job": "Job", "instance": "Target", "Value": "Days left"},
                                        "indexByName": {"instance": 0, "job": 1, "Value": 2}}},
         {"id": "sortBy", "options": {"fields": "", "sort": [{"field": "Days left", "desc": False}]}}],
     "overrides": [{"matcher": {"id": "byName", "options": "Days left"},
                    "properties": [{"id": "unit", "value": "none"}, {"id": "decimals", "value": 0},
                                   {"id": "custom.cellOptions", "value": {"type": "color-background"}},
                                   {"id": "thresholds", "value": thr(CERT)}]}]},
    {"type": "text", "title": "", "w": 24, "h": 3,
     "content": ("ℹ️ **Known false-positive:** `rustdesk.home` / `rustdesk-relay.home` report "
                 "`probe_success=0` on plain-GET probes because they are **WebSocket-only** upstreams "
                 "(they answer `101 Switching Protocols`). They are **excluded** from the *Probes Up %* "
                 "tile and *Per-target availability*. See memory `blackbox-rproxy WebSocket false positive`.")},
]

# ── explicit line layout: every line sums to width 24 with a uniform height ────
# (height, [(panel-title, width), ...]) — keeps the grid gap-free and aligned.
adds = load_additions()

LINES = {
    "wan": [
        (8, [("Gateway RTT (ms)", 8), ("Packet Loss (%)", 8), ("Jitter / stddev (ms)", 8)]),
        (8, [("WAN Throughput (in ↑ / out ↓)", 8), ("WAN link utilization vs capacity (%)", 8), ("External DNS lookup time (ms)", 8)]),
        (4, [("Per-WAN availability % (window)", 8), ("WAN latency-SLO breach % (delay>80ms, window)", 8), ("WAN failover events (100%-loss down intervals)", 8)]),
        (8, [("WAN jitter ratio (stddev / RTT)", 12), ("WAN1 vs WAN2 — SLA comparison", 12)]),
    ],
    "cloudflare": [
        (4, [("🟧 Tunnel edge connections (min HA)", 8), ("Cloudflared replicas up", 8), ("Tunnel error ratio %", 8)]),
        (8, [("Edge responses by HTTP status class (/s)", 12), ("Tunnel HA connections per replica", 12)]),
        (8, [("QUIC RTT to Cloudflare edge (ms)", 12), ("QUIC packet loss on tunnel uplink (/s)", 12)]),
    ],
    "interface": [
        (8, [("Inbound by interface (bits/s)", 12), ("Outbound by interface (bits/s)", 12)]),
        (8, [("Interface utilization % vs link capacity", 12), ("Packet rate (pps) per VLAN", 12)]),
        (8, [("Interface errors & discards (/s)", 12), ("Errors & discards as % of inbound packets (per VLAN)", 12)]),
        (8, [("Broadcast/multicast share of inbound packets (per VLAN)", 12), ("Host NIC drops & errors (node_exporter, all hosts)", 12)]),
        (8, [("Link flaps — carrier changes (host NICs)", 12), ("Interface summary (current)", 12)]),
        (8, [("Per-host top talkers — rx (bits/s)", 12), ("Per-host top talkers — tx (bits/s)", 12)]),
        (5, [("Interface up/down — physical link state", 24)]),
        (5, [("Interface MTU (per VLAN) — config sanity", 24)]),
    ],
    "dns": [
        (4, [("DNS resolver up", 24)]),
        (4, [("Internal DNS probe — answer succeeded (validity matrix)", 24)]),
        (4, [("Block %", 8), ("Gravity domains", 8), ("Active clients", 8)]),
        (8, [("DNS resolver lookup time (ms)", 12), ("Live DNS QPS per Pi-hole", 12)]),
        (8, [("Cache-hit ratio per Pi-hole (live)", 12), ("Resolution failure share per Pi-hole (NXDOMAIN/SERVFAIL/REFUSED %)", 12)]),
        (8, [("Pi-hole query status mix", 6), ("Answer source split — cache vs blocklist vs forwarded upstream", 6), ("Query type mix (A / AAAA / HTTPS / PTR …)", 6), ("Reply outcome mix (resolution quality)", 6)]),
        (8, [("Blocklist (gravity) size drift across the 3 Pi-holes", 12), ("External DNS probe phase breakdown (connect / request / resolve)", 12)]),
        (6, [("Pi-hole queries in window by instance", 24)]),
    ],
    "firewall": [
        (8, [("Block rate by VLAN (pkts/s)", 18), ("Top-blocked VLAN (now)", 6)]),
        (8, [("Block-vs-pass ratio by VLAN (%)", 12), ("Blocked bytes by VLAN (bytes/s)", 12)]),
        (8, [("WAN inbound blocks — internet attack surface (pkts/s)", 12), ("IPv4 vs IPv6 blocked traffic (pkts/s)", 12)]),
        (8, [("pflog: Pass vs Block — packets/s", 12), ("pflog: Logged bytes/s (in ↑ / out ↓)", 12)]),
        (4, [("pflog block rate (pkt/s)", 12), ("pflog pass rate (pkt/s)", 12)]),
    ],
    "reach": [
        (8, [("Probe UP matrix (all blackbox jobs)", 24)]),
        (8, [("Per-target availability % (window SLA)", 12), ("ICMP reachability — internal LAN & gateways (UP matrix)", 12)]),
        (8, [("Probes Up %", 6), ("Probe duration (ms)", 18)]),
        (8, [("Probe latency percentiles (p50 / p95 / p99)", 12), ("HTTP probe phase breakdown (resolve/connect/tls/processing/transfer)", 12)]),
        (8, [("ICMP RTT to internal hosts & gateways", 12), ("HTTP status code over time", 12)]),
        (5, [("RustDesk relay/signal TCP reachability", 24)]),
        (8, [("HTTP status codes", 12), ("SSL cert expiry (days, soonest first)", 12)]),
    ],
    "path": [
        (7, [("Ingress/DNS path uptime & restarts", 24)]),
        (5, [("Service restarts — last 24h", 6), ("Per-service uptime & last restart", 18)]),
    ],
}


def assemble(base, key, extra=None):
    """Order base+addition specs into the explicit LINES grid, setting w/h."""
    pool = {s["title"]: s for s in (base + adds.get(key, []))}
    out = []
    for h, items in LINES[key]:
        for title, w in items:
            if title not in pool:
                raise KeyError(f"{key}: no panel titled {title!r} (have: {sorted(pool)})")
            s = pool[title]
            s["w"], s["h"] = w, h
            out.append(s)
    if extra:
        out.extend(extra)
    return out


wsnote = next(s for s in reach if s["type"] == "text")
wsnote["w"], wsnote["h"] = 24, 3

ROWS = [
    {"key": "verdict", "title": None, "open": True, "panels": verdict},
    {"key": "wan", "title": "🌐 Internet / WAN — uplink quality & failover", "open": True, "panels": assemble(wan, "wan")},
    {"key": "cloudflare", "title": "🟧 Cloudflare Tunnel / Edge — public ingress health", "open": True, "panels": assemble([], "cloudflare")},
    {"key": "interface", "title": "🔀 Interface Throughput & Errors — per VLAN/iface", "open": False, "panels": assemble(interface, "interface")},
    {"key": "dns", "title": "🧭 DNS & Pi-hole — resolution & ad-blocking", "open": False, "panels": assemble(dns, "dns")},
    {"key": "firewall", "title": "🛡️ Firewall — per-VLAN block/pass", "open": False, "panels": assemble(firewall, "firewall")},
    {"key": "reach", "title": "🩺 Service Reachability — blackbox probes", "open": False, "panels": assemble([s for s in reach if s["type"] != "text"], "reach", extra=[wsnote])},
    {"key": "path", "title": "🔌 Path Health & Uptime — ingress/DNS services", "open": False, "panels": assemble([], "path")},
]

# ── layout pass → panels[] with gridPos ───────────────────────────────────────
panels = []
y = 0
for r in ROWS:
    if r["title"] is None:
        rendered, y = pack(r["panels"], y)
        panels.extend(rendered)
        continue
    if r["open"]:
        panels.append({"id": nid(), "type": "row", "title": r["title"], "collapsed": False,
                       "panels": [], "gridPos": {"h": 1, "w": 24, "x": 0, "y": y}})
        y += 1
        rendered, y = pack(r["panels"], y)
        panels.extend(rendered)
    else:
        children, _ = pack(r["panels"], y + 1)
        panels.append({"id": nid(), "type": "row", "title": r["title"], "collapsed": True,
                       "panels": children, "gridPos": {"h": 1, "w": 24, "x": 0, "y": y}})
        y += 1

# ── dashboard envelope ────────────────────────────────────────────────────────
dashboard = {
    "uid": "internet-network-overview",
    "title": "🌐 Internet & Network — Overview",
    "description": "Single-pane NOC view: dual-WAN uplink quality, Cloudflare tunnel edge, "
                   "interface throughput, DNS/Pi-hole, per-VLAN firewall, service reachability "
                   "and path health. Generated by scripts/grafana/build_internet_network_overview.py.",
    "tags": ["network", "internet", "wan", "dns", "blackbox", "cloudflare", "homelab", "overview"],
    "timezone": "browser", "schemaVersion": 39, "version": 1, "editable": True, "weekStart": "",
    "refresh": "30s", "time": {"from": "now-6h", "to": "now"}, "timepicker": {},
    "annotations": {"list": [
        {"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True,
         "hide": True, "iconColor": "rgba(0, 211, 255, 1)", "name": "Annotations & Alerts", "type": "dashboard"},
        {"datasource": DS, "enable": True, "hide": False, "iconColor": "rgba(245, 54, 54, 1)",
         "name": "WAN failover (gateway down)", "expr": "pfsense_gateway_loss_ratio == 1",
         "titleFormat": "{{gateway}} 100% loss / down", "step": "30s"},
        {"datasource": DS, "enable": False, "hide": False, "iconColor": "rgba(255, 152, 0, 1)",
         "name": "Service restart", "tagKeys": "job",
         "expr": 'changes(process_start_time_seconds{job=~"nginx|cloudflared|pihole|vault"}[$__interval]) > 0',
         "titleFormat": "{{job}} restart", "step": "60s"},
    ]},
    "links": [
        {"title": "pfSense WAN Quality", "type": "dashboards", "tags": ["pfsense", "wan"], "asDropdown": False, "targetBlank": False, "icon": "external link"},
        {"title": "Pi-hole", "type": "dashboards", "tags": ["pihole"], "asDropdown": False, "targetBlank": False, "icon": "external link"},
        {"title": "Blackbox", "type": "dashboards", "tags": ["blackbox"], "asDropdown": False, "targetBlank": False, "icon": "external link"},
        {"title": "Node Exporter", "type": "dashboards", "tags": ["node-exporter"], "asDropdown": False, "targetBlank": False, "icon": "external link"},
    ],
    "templating": {"list": [
        {"name": "interface", "type": "query", "datasource": DS,
         "query": {"query": 'label_values(ifHCInOctets{job="snmp-pfsense"}, ifAlias)', "refId": "StandardVariableQuery"},
         "refresh": 2, "includeAll": True, "multi": True, "allValue": ".*",
         "current": {"text": "All", "value": "$__all"}, "sort": 1, "label": "Interface"},
        {"name": "pihole", "type": "query", "datasource": DS,
         "query": {"query": "label_values(pihole_query_count, instance)", "refId": "StandardVariableQuery"},
         "refresh": 2, "includeAll": True, "multi": True, "allValue": ".*",
         "current": {"text": "All", "value": "$__all"}, "sort": 1, "label": "Pi-hole"},
    ]},
    "panels": panels,
}

OUT.write_text(json.dumps(dashboard, indent=2, sort_keys=True) + "\n")
n_rows = sum(1 for p in panels if p["type"] == "row")
n_leaf = sum(1 for p in panels if p["type"] != "row") + sum(len(p.get("panels", [])) for p in panels if p["type"] == "row")
print(f"wrote {OUT}\n  rows={n_rows}  leaf-panels={n_leaf}  total-ids={_id}")
