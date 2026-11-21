#!/usr/bin/env python3
"""Generate the "switch24a — Core Switch Ports" Grafana dashboard JSON.

Per-port view of the TP-Link TL-SG3428X core switch (192.168.32.39), scraped
by the `snmp-switch24a` Prometheus job (IF-MIB through snmp-exporter). It was
added on 2026-11-16 to track receive errors on Te1/0/25 (AP-2.5G switch) and
Te1/0/27 (pfSense ix0). See docs/network/2026-11-16-network-instability-check.md.

Drop the output in terraform/portainer/stacks/grafana-dashboards/ and apply
terraform/portainer, then redeploy the grafana stack. Re-run to regenerate:

    python3 scripts/grafana/build_switch24a_ports.py

All PromQL was checked against Thanos Query (192.168.59.26:10902).
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "thanos"}
HERE = pathlib.Path(__file__).resolve()
OUT = HERE.parents[2] / "terraform/portainer/stacks/grafana-dashboards/switch24a.json"

SW = 'instance="switch24a"'
PORTS = SW + ', ifName=~"$port"'
PHYS = SW + ', ifName=~".*Ethernet.*"'
TE25 = SW + ', ifIndex="49177"'
TE27 = SW + ', ifIndex="49179"'

GREEN = [{"color": "green", "value": None}]
ERR = [{"color": "green", "value": None}, {"color": "yellow", "value": 0.1}, {"color": "red", "value": 5}]


def target(expr, legend="", ref="A", instant=False):
    t = {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": ref}
    if instant:
        t.update({"instant": True, "range": False, "format": "table"})
    return t


def stat(title, expr, unit="short", thresholds=GREEN, desc="", decimals=None):
    p = {
        "type": "stat", "title": title, "description": desc, "datasource": DS,
        "targets": [target(expr)],
        "fieldConfig": {"defaults": {"unit": unit, "thresholds": {"mode": "absolute", "steps": thresholds},
                                     "color": {"mode": "thresholds"}}, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "background", "graphMode": "area", "textMode": "auto"},
    }
    if decimals is not None:
        p["fieldConfig"]["defaults"]["decimals"] = decimals
    return p


def ts(title, targets, unit="short", desc="", overrides=None, stack=False):
    return {
        "type": "timeseries", "title": title, "description": desc, "datasource": DS,
        "targets": targets,
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "custom": {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 10, "showPoints": "never",
                           "spanNulls": False, "stacking": {"mode": "normal" if stack else "none"}},
            },
            "overrides": overrides or [],
        },
        "options": {"legend": {"displayMode": "table", "placement": "right", "calcs": ["mean", "max", "lastNotNull"],
                               "sortBy": "Max", "sortDesc": True},
                    "tooltip": {"mode": "multi", "sort": "desc"}},
    }


def row(title):
    return {"type": "row", "title": title, "collapsed": False, "panels": []}


# Each line: list of (panel, width, height). Rows take a full line of height 1.
LINES = [
    [(row("Health"), 24, 1)],
    [
        (stat("Scrape up", f"up{{job=\"snmp-switch24a\"}}", thresholds=[{"color": "red", "value": None},
                                                                        {"color": "green", "value": 1}],
              desc="1 when the snmp-switch24a scrape succeeds. The path to the switch is routed through pfSense, "
                   "so an ix0 outage also shows here."), 4, 4),
        (stat("Switch uptime", f"sysUpTime{{{SW}}} / 100", unit="s"), 4, 4),
        (stat("Ports up", f"count(ifOperStatus{{{PHYS}}} == 1)"), 4, 4),
        (stat("All input errors /s", f"sum(rate(ifInErrors{{{SW}}}[5m]))", unit="short", thresholds=ERR,
              decimals=2), 4, 4),
        (stat("Te1/0/25 input errors /s", f"rate(ifInErrors{{{TE25}}}[5m])", thresholds=ERR, decimals=2,
              desc="Uplink to the AP-2.5G switch."), 4, 4),
        (stat("Te1/0/27 input errors /s", f"rate(ifInErrors{{{TE27}}}[5m])", thresholds=ERR, decimals=2,
              desc="Link to pfSense ix0."), 4, 4),
    ],
    [(row("Errors and discards"), 24, 1)],
    [
        (ts("Input errors per port /s", [target(f"rate(ifInErrors{{{PORTS}}}[5m]) > 0", "{{ifName}}")],
            desc="Ports with no errors are hidden."), 12, 8),
        (ts("Discards per port /s", [
            target(f"rate(ifInDiscards{{{PORTS}}}[5m]) > 0", "in {{ifName}}", "A"),
            target(f"rate(ifOutDiscards{{{PORTS}}}[5m]) > 0", "out {{ifName}}", "B"),
            target(f"rate(ifOutErrors{{{PORTS}}}[5m]) > 0", "out-err {{ifName}}", "C"),
        ], desc="Ports with no discards or output errors are hidden."), 12, 8),
    ],
    [
        (ts("Te1/0/27 errors vs pfSense ix0 remote faults", [
            target(f"rate(ifInErrors{{{TE27}}}[5m])", "switch Te1/0/27 input errors /s", "A"),
            target('rate(pfsense_ix0_remote_faults_total{device="ix0"}[5m])', "pfSense ix0 remote faults /s", "B"),
            target('max(pfsense_ix0_large_frame_loss_percent)', "pfSense 1400 B loss %", "C"),
        ], desc="Both ends of the pfSense uplink. Remote faults and loss use the right axis.",
            overrides=[{"matcher": {"id": "byRegexp", "options": "pfSense.*"},
                        "properties": [{"id": "custom.axisPlacement", "value": "right"}]}]), 24, 9),
    ],
    [(row("Traffic"), 24, 1)],
    [
        (ts("Inbound per port", [target(f"rate(ifHCInOctets{{{PORTS}}}[5m]) * 8 > 0", "{{ifName}}")],
            unit="bps"), 12, 9),
        (ts("Outbound per port", [target(f"rate(ifHCOutOctets{{{PORTS}}}[5m]) * 8 > 0", "{{ifName}}")],
            unit="bps"), 12, 9),
    ],
    [(row("Port state"), 24, 1)],
    [
        (ts("Link state changes (per 5 min)", [
            target(f"changes(ifLastChange{{{PORTS}}}[5m]) > 0", "{{ifName}}")],
            desc="Counts changes of ifLastChange. Any value means the port changed state."), 12, 8),
        (ts("Port oper status (1 = up)", [target(f"ifOperStatus{{{PORTS}}} == bool 1", "{{ifName}}")],
            desc="1 when up, 0 when down. Unused ports stay at 0."), 12, 8),
    ],
]

TABLE = {
    "type": "table", "title": "Port table", "datasource": DS,
    "targets": [
        target(f"ifOperStatus{{{PORTS}}}", "", "A", instant=True),
        target(f"ifHighSpeed{{{PORTS}}}", "", "B", instant=True),
        target(f"(scalar(sysUpTime{{{SW}}}) - ifLastChange{{{PORTS}}}) / 100", "", "C", instant=True),
        target(f"ifInErrors{{{PORTS}}}", "", "D", instant=True),
        target(f"rate(ifInErrors{{{PORTS}}}[5m])", "", "E", instant=True),
        target(f"ifOutDiscards{{{PORTS}}}", "", "F", instant=True),
    ],
    "transformations": [
        {"id": "merge", "options": {}},
        {"id": "organize", "options": {
            "excludeByName": {"Time": True, "ifAlias": True, "ifDescr": True, "__name__": True, "job": True,
                              "instance": True, "cluster": True, "region": True, "replica": True},
            "renameByName": {"ifName": "Port", "ifIndex": "ifIndex", "Value #A": "Status", "Value #B": "Speed (Mb/s)",
                             "Value #C": "Since last change", "Value #D": "In errors (since boot)",
                             "Value #E": "In errors /s", "Value #F": "Out discards (since boot)"}}},
    ],
    "fieldConfig": {
        "defaults": {"custom": {"align": "auto"}},
        "overrides": [
            {"matcher": {"id": "byName", "options": "Status"}, "properties": [
                {"id": "mappings", "value": [{"type": "value", "options": {
                    "1": {"text": "up", "color": "green"}, "2": {"text": "down", "color": "red"},
                    "7": {"text": "lowerLayerDown", "color": "orange"}}}]},
                {"id": "custom.cellOptions", "value": {"type": "color-text"}}]},
            {"matcher": {"id": "byName", "options": "Since last change"}, "properties": [{"id": "unit", "value": "s"}]},
            {"matcher": {"id": "byName", "options": "In errors /s"}, "properties": [
                {"id": "decimals", "value": 2},
                {"id": "thresholds", "value": {"mode": "absolute", "steps": ERR}},
                {"id": "custom.cellOptions", "value": {"type": "color-background"}}]},
        ],
    },
    "options": {"showHeader": True, "sortBy": [{"displayName": "In errors /s", "desc": True}]},
}
LINES.append([(TABLE, 24, 12)])


def build():
    panels, y, pid = [], 0, 1
    for line in LINES:
        x, h_max = 0, 0
        for panel, w, h in line:
            panel = dict(panel)
            panel["id"] = pid
            panel["gridPos"] = {"h": h, "w": w, "x": x, "y": y}
            panels.append(panel)
            pid += 1
            x += w
            h_max = max(h_max, h)
        assert x == 24, f"line width {x} != 24"
        y += h_max
    return {
        "uid": "switch24a",
        "title": "switch24a — Core Switch Ports",
        "description": "TL-SG3428X per-port IF-MIB counters (snmp-switch24a job). Generated by "
                       "scripts/grafana/build_switch24a_ports.py.",
        "tags": ["homelab", "network", "switch", "snmp"],
        "schemaVersion": 39,
        "editable": True,
        "refresh": "30s",
        "time": {"from": "now-6h", "to": "now"},
        "timezone": "browser",
        "templating": {"list": [{
            "name": "port", "label": "Port", "type": "query", "datasource": DS,
            "query": {"query": f"label_values(ifOperStatus{{{PHYS}}}, ifName)",
                      "refId": "StandardVariableQuery"},
            "definition": f"label_values(ifOperStatus{{{PHYS}}}, ifName)",
            "includeAll": True, "multi": True, "allValue": ".*Ethernet.*",
            "current": {"selected": True, "text": ["All"], "value": ["$__all"]},
            "refresh": 2, "sort": 3,
        }]},
        "annotations": {"list": []},
        "links": [{"title": "pfSense", "type": "dashboards", "tags": ["pfsense"], "asDropdown": True}],
        "panels": panels,
    }


if __name__ == "__main__":
    OUT.write_text(json.dumps(build(), indent=2, sort_keys=True) + "\n")
    print(f"wrote {OUT}")
