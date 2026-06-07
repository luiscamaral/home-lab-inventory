#!/usr/bin/env python3
"""Generate the "WiFi Probes — Household Coverage" Grafana dashboard JSON.

Single-pane view of the ESP32-C5 WiFi probe fleet: one probe per room, each a
synthetic dual-band client exposing Prometheus /metrics on :9100. Rooms are
separated by the scrape-time `room` label (see the wifi-probe job in
terraform/portainer/locals.tf). Drop the output in
terraform/portainer/stacks/grafana-dashboards/ and `terraform apply`.

Design follows the internet-network-overview generator: panels are declarative
"spec" dicts, a single renderer (mk) turns a spec into a Grafana panel, and an
explicit LINES layout assigns a gap-free 24-wide grid. The panel set comes from
a multi-agent design pass (fleet / health / link / probe / survey), covering all
17 metrics the firmware exposes. Re-run to regenerate:

    python3 scripts/grafana/build_wifi_probes_overview.py

Band-alternating quirk: the single radio alternates 5g<->2g, so each band's
link+probe series refresh only once per ~50-110s cycle while Prometheus scrapes
every 15s. Counters therefore use a generous $window interval var (default 15m),
and snapshot panels use last_over_time(...[$window]) so a band that is briefly
off-air keeps its last value instead of blanking.
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "thanos"}
HERE = pathlib.Path(__file__).resolve()
OUT = HERE.parents[2] / "terraform/portainer/stacks/grafana-dashboards/wifi-probes-overview.json"

JOB = 'job="wifi-probe"'

# ── threshold presets ─────────────────────────────────────────────────────────
# RSSI: higher (closer to 0) is better -> steps ascend red->yellow->green.
RSSI = [{"color": "red", "value": None}, {"color": "yellow", "value": -75}, {"color": "green", "value": -67}]
# Heap: higher is better.
HEAP = [{"color": "red", "value": None}, {"color": "yellow", "value": 20000}, {"color": "green", "value": 40000}]
# Latency (s): lower is better.
LAT = [{"color": "green", "value": None}, {"color": "yellow", "value": 0.15}, {"color": "red", "value": 0.5}]
# Success ratio: higher is better.
RATIO = [{"color": "red", "value": None}, {"color": "yellow", "value": 0.95}, {"color": "green", "value": 0.999}]
# Disconnect count over window: lower is better.
DISC = [{"color": "green", "value": None}, {"color": "yellow", "value": 1}, {"color": "red", "value": 5}]
# Last-success age (s): lower is better; thresholds set past one ~110s band cycle.
AGE = [{"color": "green", "value": None}, {"color": "yellow", "value": 180}, {"color": "red", "value": 600}]
# Co-channel AP count: lower is better.
CONG = [{"color": "green", "value": None}, {"color": "yellow", "value": 3}, {"color": "red", "value": 5}]
GREEN = [{"color": "green", "value": None}]

# 0/1 and status value mappings
UPDOWN = [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"},
                                        "1": {"text": "UP", "color": "green"}}}]
OKFAIL = [{"type": "value", "options": {"0": {"text": "FAIL", "color": "red"},
                                        "1": {"text": "OK", "color": "green"}}}]
HTTP204 = [{"type": "value", "options": {"0": {"text": "timeout", "color": "red"},
                                         "204": {"text": "204 OK", "color": "green"}}}]

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
    if s.get("min") is not None:
        defs["min"] = s["min"]
    if s.get("max") is not None:
        defs["max"] = s["max"]
    common = {"id": nid(), "title": s.get("title", ""), "datasource": DS,
              "gridPos": gp, "description": s.get("desc", "")}

    if t == "stat":
        defs["color"] = {"mode": "thresholds"}
        return {**common, "type": "stat",
                "fieldConfig": {"defaults": defs, "overrides": s.get("overrides", [])},
                "options": {"reduceOptions": {"calcs": [s.get("reducer", "lastNotNull")],
                                              "fields": "", "values": False},
                            "colorMode": s.get("colormode", "background"), "graphMode": "none",
                            "textMode": s.get("textmode", "auto"), "justifyMode": "auto",
                            "orientation": "auto"},
                "targets": targets}

    if t == "timeseries":
        custom = {"drawStyle": "line", "lineInterpolation": s.get("interp", "stepBefore"),
                  "lineWidth": 1, "fillOpacity": s.get("fill", 10), "gradientMode": "opacity",
                  "showPoints": s.get("points", "auto"), "pointSize": 6, "spanNulls": True,
                  "stacking": {"mode": "none", "group": "A"}}
        defs["color"] = {"mode": s.get("colormode", "palette-classic")}
        defs["custom"] = custom
        return {**common, "type": "timeseries",
                "fieldConfig": {"defaults": defs, "overrides": s.get("overrides", [])},
                "options": {"legend": {"displayMode": "table", "placement": "bottom",
                                       "calcs": s.get("calcs", ["lastNotNull", "max"])},
                            "tooltip": {"mode": "multi", "sort": "desc"}},
                "targets": targets}

    if t == "bargauge":
        defs["color"] = {"mode": "thresholds"}
        return {**common, "type": "bargauge",
                "fieldConfig": {"defaults": defs, "overrides": s.get("overrides", [])},
                "options": {"reduceOptions": {"calcs": [s.get("reducer", "lastNotNull")], "values": False},
                            "orientation": "horizontal", "displayMode": "gradient",
                            "minVizWidth": 0, "minVizHeight": 10, "showUnfilled": True},
                "targets": targets}

    if t == "state-timeline":
        return {**common, "type": "state-timeline",
                "fieldConfig": {"defaults": {"color": {"mode": "thresholds"},
                                             "custom": {"fillOpacity": 80, "lineWidth": 0},
                                             "thresholds": thr(s.get("steps") or GREEN),
                                             "mappings": s.get("mappings", [])},
                                "overrides": []},
                "options": {"mergeValues": True, "showValue": s.get("showvalue", "never"),
                            "rowHeight": 0.9,
                            "legend": {"displayMode": "list", "placement": "bottom"}},
                "targets": targets}

    if t == "table":
        for tg in targets:
            tg["format"] = "table"
            tg["instant"] = True
            tg["range"] = False
        return {**common, "type": "table",
                "fieldConfig": {"defaults": {"custom": {"filterable": True, "align": "auto",
                                                        "cellOptions": {"type": "auto"}},
                                             "mappings": s.get("mappings", [])},
                                "overrides": s.get("overrides", [])},
                "options": {"showHeader": True, "footer": {"show": False}},
                "transformations": s.get("transforms", []),
                "targets": targets}

    raise ValueError("unknown panel type: " + t)


# ── table transform helpers ───────────────────────────────────────────────────
NOISE = ["Time", "__name__", "job", "instance", "cluster", "replica", "region",
         "source", "monitor", "endpoint", "container", "namespace", "pod"]


def organize(rename, extra_exclude=None, keep=None, index=None):
    excl = {k: True for k in NOISE if k not in (keep or [])}
    for k in (extra_exclude or []):
        excl[k] = True
    opts = {"excludeByName": excl, "renameByName": rename}
    if index:
        opts["indexByName"] = index
    return [{"id": "merge", "options": {}}, {"id": "organize", "options": opts}]


def col_override(name, props):
    return {"matcher": {"id": "byName", "options": name}, "properties": props}


# Table joins use `merge`, which only collapses frames that share an IDENTICAL
# label set. So every target in a multi-metric table is decorated to carry the
# same labels: identity columns via group_left from build_info, AP columns via
# group_left from bssid_info. (group_left copies labels, multiplying by the =1
# info-metric value leaves the real value unchanged.)
def with_identity(value_expr):
    return (f'{value_expr} * on (instance) group_left(version, idf, chip, location) '
            f'wifi_probe_build_info{{{JOB}, room=~"$room"}}')


def with_bssid(value_expr):
    return (f'{value_expr} * on (instance, band) group_left(bssid, ssid, auth) '
            f'last_over_time(wifi_client_bssid_info{{{JOB}, room=~"$room", band=~"$band"}}[$window])')


def ratio_by(grp):
    return (f'sum(increase(probe_success_total{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}) '
            f'/ clamp_min(sum(increase(probe_attempts_total{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}), 1)')


def avglat_by(grp):
    return (f'sum(increase(probe_duration_seconds_sum{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}) '
            f'/ clamp_min(sum(increase(probe_duration_seconds_count{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}), 1)')


# ══ FLEET — household verdict strip (8 stats, w=3 h=4) ═════════════════════════
fleet = [
    {"type": "stat", "title": "📡 Probes Up", "unit": "percentunit", "decimals": 0, "steps":
     [{"color": "red", "value": None}, {"color": "yellow", "value": 0.99}, {"color": "green", "value": 1}],
     "desc": "Fraction of wifi-probe scrape targets Prometheus can reach (band-independent up{}). "
             "or vector(0) keeps an empty/no-target fleet at a clear 0 instead of No data.",
     "targets": [T(f'(count(up{{{JOB}, room=~"$room"}} == 1) / count(up{{{JOB}, room=~"$room"}})) or vector(0)', "up")]},
    {"type": "stat", "title": "🏠 Rooms Covered", "unit": "none", "decimals": 0, "colormode": "value",
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
     "desc": "Distinct rooms with at least one live probe right now. Green at ≥1 so a single-room (or "
             "$room-filtered) deployment isn't falsely degraded.",
     "targets": [T(f'count(count by (room) (up{{{JOB}, room=~"$room"}} == 1)) or vector(0)', "rooms")]},
    {"type": "stat", "title": "🌐 Worst-Room Internet", "unit": "none", "decimals": 0, "mappings": OKFAIL,
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
     "desc": "internet_https (generate_204) reachability of the weakest room. max-by-room = a room is OK if "
             "EITHER band reached the internet (avoids a false FAIL from the stale off-band); outer min = "
             "FAIL only if some room has no working band.",
     "targets": [T(f'min(max by (room) (probe_success{{{JOB}, probe="internet_https", room=~"$room", band=~"$band"}}))', "worst")]},
    {"type": "stat", "title": "📶 Weakest Link RSSI", "unit": "dBm", "decimals": 0, "steps": RSSI,
     "desc": "Most negative connected-link RSSI across selected rooms/bands.",
     "targets": [T(f'min(wifi_client_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}})', "weakest")]},
    {"type": "stat", "title": "🔌 Disconnects ($window)", "unit": "none", "decimals": 0, "steps": DISC,
     "desc": "Total WiFi disconnects over $window (includes expected band-switch flaps).",
     "targets": [T(f'sum(increase(wifi_client_disconnect_total{{{JOB}, room=~"$room"}}[$window]))', "disc")]},
    {"type": "stat", "title": "🧠 Min Free Heap", "unit": "bytes", "decimals": 0, "steps": HEAP,
     "desc": "Lowest free heap among selected probes — closest-to-OOM device.",
     "targets": [T(f'min(wifi_probe_heap_free_bytes{{{JOB}, room=~"$room"}})', "min heap")]},
    {"type": "stat", "title": "⏱️ Max Probe Staleness", "unit": "s", "decimals": 0, "steps": AGE,
     "desc": "Oldest probe last-success age. NOTE: a never-succeeded probe emits no age series; pair with Probes Failing.",
     "targets": [T(f'max(probe_last_success_age_seconds{{{JOB}, room=~"$room", band=~"$band"}})', "stalest")]},
    {"type": "stat", "title": "❌ Probes Failing", "unit": "none", "decimals": 0, "steps": DISC,
     "desc": "Count of room×probe×band checks whose last attempt failed. or vector(0) keeps a healthy 0 green.",
     "targets": [T(f'count(probe_success{{{JOB}, room=~"$room", band=~"$band"}} == 0) or vector(0)', "failing")]},
]

# ══ HEALTH — device identity + system ═════════════════════════════════════════
health = [
    {"type": "table", "title": "🏷️ Probe identity & build — per room", "unit": "none",
     "desc": "One row per probe: build_info labels (incl. firmware self-reported location) joined with "
             "uptime, free heap, and live connected flag. Compare `Self-reported room` to `Room` (scrape "
             "label) to confirm a probe is physically where its target claims.",
     "targets": [
         T(with_identity(f'max by (room, instance) (wifi_probe_uptime_seconds{{{JOB}, room=~"$room"}})'), "uptime"),
         T(with_identity(f'max by (room, instance) (wifi_probe_heap_free_bytes{{{JOB}, room=~"$room"}})'), "heap"),
         T(with_identity(f'max by (room, instance) (wifi_client_connected{{{JOB}, room=~"$room"}})'), "conn")],
     "transforms": organize(
         {"room": "Room", "instance": "Probe", "version": "FW", "idf": "IDF", "chip": "Chip",
          "location": "Self-reported room", "Value #A": "Uptime", "Value #B": "Heap free",
          "Value #C": "Connected"}, keep=["instance"]),
     "overrides": [
         col_override("Uptime", [{"id": "unit", "value": "s"}]),
         col_override("Heap free", [{"id": "unit", "value": "bytes"}]),
         col_override("Connected", [{"id": "mappings", "value": UPDOWN},
                                    {"id": "custom.cellOptions", "value": {"type": "color-background"}}])]},
    {"type": "timeseries", "title": "⏱️ Uptime since boot — per room", "unit": "s", "fill": 5,
     "desc": "Sawtooth that drops to ~0 marks a reboot/crash. Device-level (not band-gated).",
     "targets": [T(f'wifi_probe_uptime_seconds{{{JOB}, room=~"$room"}}', "{{room}} ({{instance}})")]},
    {"type": "timeseries", "title": "🧠 Free heap — leak watch", "unit": "bytes", "steps": HEAP,
     "colormode": "thresholds", "desc": "Downward drift over hours = leak → predicts an OOM reboot. "
     "Second series is the per-$window low-water mark.",
     "targets": [T(f'wifi_probe_heap_free_bytes{{{JOB}, room=~"$room"}}', "{{room}} free"),
                 T(f'min_over_time(wifi_probe_heap_free_bytes{{{JOB}, room=~"$room"}}[$window])', "{{room}} min/$window")]},
    {"type": "timeseries", "title": "🔌 Disconnects — increase/$window", "unit": "none", "decimals": 0,
     "steps": DISC, "colormode": "thresholds", "desc": "increase() over the generous $window (band-alternating "
     "counter only advances ~once/cycle). No band label on this counter.",
     "targets": [T(f'increase(wifi_client_disconnect_total{{{JOB}, room=~"$room"}}[$window])', "{{room}} disc/$window")]},
    {"type": "state-timeline", "title": "📶 Connected state — band-switch flaps", "steps":
     [{"color": "red", "value": None}, {"color": "green", "value": 1}], "mappings": UPDOWN,
     "desc": "One lane per room. max by(room,instance) suppresses cosmetic single-scrape dips on band switch; "
     "a sustained red band is a real outage.",
     "targets": [T(f'max by (room, instance) (wifi_client_connected{{{JOB}, room=~"$room"}})', "{{room}}")]},
]

# ══ LINK — WiFi link quality ══════════════════════════════════════════════════
link = [
    {"type": "timeseries", "title": "RSSI by room & band", "unit": "dBm", "decimals": 0, "steps": RSSI,
     "colormode": "thresholds", "points": "always", "calcs": ["lastNotNull", "min", "max"],
     "desc": "Sparse staircase: each band refreshes ~once/cycle and is absent during the other band's phase. "
     "stepBefore + spanNulls hold the last value; points mark real samples.",
     "targets": [T(f'wifi_client_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}', "{{room}} {{band}}")]},
    {"type": "bargauge", "title": "Current RSSI per room (band-split)", "unit": "dBm", "decimals": 0,
     "steps": RSSI, "min": -90, "max": -30, "desc": "last_over_time over $window so a band that's briefly "
     "off-air keeps its last reading instead of dropping out.",
     "targets": [T(f'last_over_time(wifi_client_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}[$window])',
                   "{{room}} {{band}}", instant=True)]},
    {"type": "table", "title": "Current link detail per room", "unit": "none",
     "desc": "RSSI + channel + BSSID/SSID/auth per room×band. group_left carries the AP labels onto each "
             "value so the frames share one label set; last_over_time keeps a briefly off-air band populated.",
     "targets": [
         T(with_bssid(f'last_over_time(wifi_client_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}[$window])'), "rssi", instant=True),
         T(with_bssid(f'last_over_time(wifi_client_channel{{{JOB}, room=~"$room", band=~"$band"}}[$window])'), "ch", instant=True)],
     "transforms": organize(
         {"room": "Room", "band": "Band", "bssid": "BSSID", "ssid": "SSID", "auth": "Auth",
          "Value #A": "RSSI (dBm)", "Value #B": "Channel"}),
     "overrides": [
         col_override("RSSI (dBm)", [{"id": "custom.cellOptions", "value": {"type": "color-background"}},
                                     {"id": "thresholds", "value": thr(RSSI)}, {"id": "decimals", "value": 0}]),
         col_override("Channel", [{"id": "decimals", "value": 0}])]},
    {"type": "state-timeline", "title": "Link channel over time (roams)", "showvalue": "auto",
     "steps": GREEN, "desc": "Channel as labeled segments per room/band — spot 5g DFS moves or 2g 1/6/11 hops.",
     "targets": [T(f'wifi_client_channel{{{JOB}, room=~"$room", band=~"$band"}}', "{{room}} {{band}}")]},
]

# ══ PROBE — reachability SLA (core) ═══════════════════════════════════════════
probe = [
    {"type": "stat", "title": "✅ Checks passing %", "unit": "percentunit", "decimals": 1, "steps": RATIO,
     "desc": "Share of room×probe×band checks whose last attempt succeeded. A fraction (not a raw count) so "
             "the verdict stays correct when you filter $room or $band.",
     "targets": [T(f'sum(probe_success{{{JOB}, room=~"$room", band=~"$band"}}) '
                   f'/ count(probe_success{{{JOB}, room=~"$room", band=~"$band"}})', "passing")]},
    {"type": "stat", "title": "📉 Worst success ratio", "unit": "percentunit", "decimals": 3, "steps": RATIO,
     "desc": "Single worst room×probe success ratio over $window. clamp_min avoids 0/0; prefer $window ≥15m.",
     "targets": [T(f'min({ratio_by("room, probe")})', "min ratio")]},
    {"type": "stat", "title": "⏱️ Stalest probe age", "unit": "s", "decimals": 0, "steps": AGE,
     "desc": "Oldest last-success across room×probe. Never-succeeded probes are omitted here — see the matrix.",
     "targets": [T(f'max(probe_last_success_age_seconds{{{JOB}, room=~"$room", band=~"$band"}})', "max age")]},
    {"type": "stat", "title": "🌐 HTTPS status (204?)", "unit": "none", "decimals": 0, "mappings": HTTP204,
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 204}, {"color": "yellow", "value": 205}],
     "desc": "Worst internet_https code. 204 = clean internet; 200/302 = captive portal / DNS hijack; 0 = timeout.",
     "targets": [T(f'min(probe_http_status_code{{{JOB}, room=~"$room", band=~"$band", probe="internet_https"}})', "min code")]},
    {"type": "state-timeline", "title": "🎯 Probe success matrix — room × probe × band", "steps":
     [{"color": "red", "value": None}, {"color": "green", "value": 1}], "mappings": OKFAIL,
     "desc": "THE core SLA view: OK/FAIL lane per room×probe×band over time. spanNulls holds value across the "
     "off-band phase. Per-band lanes expose a band-specific dead spot.",
     "targets": [T(f'probe_success{{{JOB}, room=~"$room", band=~"$band"}}', "{{room}} · {{probe}} · {{band}}")]},
    {"type": "timeseries", "title": "Success ratio over $window (room × probe)", "unit": "percentunit",
     "decimals": 4, "steps": RATIO, "colormode": "thresholds", "calcs": ["lastNotNull", "min"],
     "desc": "Δsuccess/Δattempts over $window, bands merged per room×probe. Generous window smooths the "
     "per-cycle quantization; clamp_min avoids 0/0 gaps.",
     "targets": [T(ratio_by("room, probe"), "{{room}} · {{probe}}")]},
    {"type": "timeseries", "title": "Live probe latency — last attempt", "unit": "s", "decimals": 3,
     "steps": LAT, "colormode": "thresholds", "desc": "probe_last_duration_seconds per room×probe×band. Coarse "
     "staircase (one step/cycle); flat held segments between cycles are normal.",
     "targets": [T(f'probe_last_duration_seconds{{{JOB}, room=~"$room", band=~"$band"}}', "{{room}} · {{probe}} · {{band}}")]},
    {"type": "timeseries", "title": "Avg probe latency over $window", "unit": "s", "decimals": 3, "steps": LAT,
     "colormode": "thresholds", "desc": "Δsum/Δcount windowed mean (the only panel over duration_sum/_count). "
     "Bands merged; clamp_min guards empty windows.",
     "targets": [T(avglat_by("room, probe"), "{{room}} · {{probe}}")]},
    {"type": "timeseries", "title": "HTTPS status code over time", "unit": "none", "decimals": 0,
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 204}, {"color": "yellow", "value": 205}],
     "colormode": "thresholds", "desc": "internet_https code per room/band — a flip 204→200/302 marks a captive "
     "portal; 0 marks a hard timeout.",
     "targets": [T(f'probe_http_status_code{{{JOB}, room=~"$room", band=~"$band", probe="internet_https"}}', "{{room}} · {{band}}")]},
    {"type": "table", "title": "📋 Probe SLA matrix — room × probe × band", "unit": "none", "decimals": 3,
     "desc": "Dense per-(room,probe,band) sheet joining every probe metric. A blank Success-age next to Up=0 is "
     "the silently-failing / never-succeeded signature. target column confirms each probe is aimed correctly.",
     "targets": [
         T(f'probe_success{{{JOB}, room=~"$room", band=~"$band"}}', "up", instant=True),
         T(ratio_by("room, probe, band, target, type, instance"), "ratio", instant=True),
         T(f'probe_last_duration_seconds{{{JOB}, room=~"$room", band=~"$band"}}', "lastlat", instant=True),
         T(avglat_by("room, probe, band, target, type, instance"), "avglat", instant=True),
         T(f'probe_last_success_age_seconds{{{JOB}, room=~"$room", band=~"$band"}}', "age", instant=True),
         T(f'probe_attempts_total{{{JOB}, room=~"$room", band=~"$band"}}', "att", instant=True)],
     "transforms": organize(
         {"room": "Room", "probe": "Probe", "band": "Band", "target": "Target",
          "Value #A": "Up", "Value #B": "Ratio", "Value #C": "Last (s)", "Value #D": "Avg (s)",
          "Value #E": "Age (s)", "Value #F": "Attempts"},
         extra_exclude=["type"]),
     "overrides": [
         col_override("Up", [{"id": "mappings", "value": OKFAIL},
                             {"id": "custom.cellOptions", "value": {"type": "color-background"}}]),
         col_override("Ratio", [{"id": "unit", "value": "percentunit"}, {"id": "decimals", "value": 3}]),
         col_override("Last (s)", [{"id": "unit", "value": "s"}]),
         col_override("Avg (s)", [{"id": "unit", "value": "s"}]),
         col_override("Age (s)", [{"id": "unit", "value": "s"}, {"id": "decimals", "value": 0}])]},
    {"type": "bargauge", "title": "Probe freshness — last-success age", "unit": "s", "decimals": 0, "steps": AGE,
     "desc": "Ranks every room×probe by staleness. CAVEAT: a never-succeeded probe shows NO bar — cross-check "
     "the success matrix (always has a lane).",
     "targets": [T(f'max by (room, probe) (probe_last_success_age_seconds{{{JOB}, room=~"$room", band=~"$band"}})',
                   "{{room}} · {{probe}}", instant=True)]},
]

# ══ SURVEY — what each room sees ══════════════════════════════════════════════
survey = [
    {"type": "table", "title": "📡 Surveyed APs per room (RSSI desc)", "unit": "dBm", "decimals": 0,
     "desc": "Passive-scan AP list per room×band×BSSID. The same BSSID at different RSSI from different rooms "
     "is your coverage map. Top ~6 APs per band; an empty table = scan not yet populated for that band.",
     "targets": [T(f'wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}', "ap", instant=True)],
     "transforms": organize(
         {"room": "Room", "band": "Band", "ssid": "SSID", "bssid": "BSSID", "channel": "Ch", "Value": "RSSI"}) +
         [{"id": "sortBy", "options": {"fields": "", "sort": [{"field": "RSSI", "desc": True}]}}],
     "overrides": [col_override("RSSI", [{"id": "custom.cellOptions", "value": {"type": "color-background"}},
                                         {"id": "thresholds", "value": thr(RSSI)}])]},
    {"type": "bargauge", "title": "Best AP RSSI per room (strongest seen)", "unit": "dBm", "decimals": 0,
     "steps": RSSI, "min": -90, "max": -30, "desc": "Strongest AP each room can hear, per band — the single-number "
     "coverage verdict. A red bar flags a dead-spot room; an absent bar = no AP heard on that band.",
     "targets": [T(f'max by (room, band) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}})',
                   "{{room}} {{band}}", instant=True)]},
    {"type": "timeseries", "title": "Best AP RSSI per room — trend", "unit": "dBm", "decimals": 0, "steps": RSSI,
     "colormode": "thresholds", "desc": "Coverage drift / interference fades. Stair-stepped due to per-cycle scan "
     "refresh; do not rate()-smooth a gauge.",
     "targets": [T(f'max by (room, band) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}})', "{{room}} {{band}}")]},
    {"type": "bargauge", "title": "Channel occupancy — distinct BSSIDs/channel", "unit": "none", "decimals": 0,
     "steps": CONG, "desc": "Co-channel congestion: distinct APs seen per channel/band. Inner max-by dedupes a "
     "BSSID seen from several rooms. LOWER is better (opposite polarity to RSSI). Undercounts (top-6 cap).",
     "targets": [T(f'count by (channel, band) (max by (channel, band, bssid) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))',
                   "ch {{channel}} ({{band}})", instant=True)]},
    {"type": "stat", "title": "📻 Airspace inventory", "unit": "none", "decimals": 0, "colormode": "value",
     "steps": [{"color": "blue", "value": None}], "textmode": "value_and_name",
     "desc": "Distinct radios (BSSIDs), networks (SSIDs), and channels in the current room/band scan.",
     "targets": [
         T(f'count(count by (bssid) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))', "BSSIDs"),
         T(f'count(count by (ssid) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))', "SSIDs"),
         T(f'count(count by (channel) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))', "Channels")]},
]

# ── explicit gap-free layout: (height, [(title, width), ...]) lines sum to 24 ──
LINES = {
    "fleet": [(4, [(p["title"], 3) for p in fleet])],
    "health": [
        (8, [("🏷️ Probe identity & build — per room", 24)]),
        (8, [("⏱️ Uptime since boot — per room", 8), ("🧠 Free heap — leak watch", 8), ("🔌 Disconnects — increase/$window", 8)]),
        (7, [("📶 Connected state — band-switch flaps", 24)]),
    ],
    "link": [
        (8, [("RSSI by room & band", 16), ("Current RSSI per room (band-split)", 8)]),
        (9, [("Current link detail per room", 24)]),
        (7, [("Link channel over time (roams)", 24)]),
    ],
    "probe": [
        (4, [("✅ Checks passing %", 6), ("📉 Worst success ratio", 6), ("⏱️ Stalest probe age", 6), ("🌐 HTTPS status (204?)", 6)]),
        (8, [("🎯 Probe success matrix — room × probe × band", 24)]),
        (8, [("Success ratio over $window (room × probe)", 12), ("Live probe latency — last attempt", 12)]),
        (8, [("Avg probe latency over $window", 12), ("HTTPS status code over time", 12)]),
        (10, [("📋 Probe SLA matrix — room × probe × band", 24)]),
        (8, [("Probe freshness — last-success age", 24)]),
    ],
    "survey": [
        (10, [("📡 Surveyed APs per room (RSSI desc)", 24)]),
        (8, [("Best AP RSSI per room (strongest seen)", 12), ("Best AP RSSI per room — trend", 12)]),
        (8, [("Channel occupancy — distinct BSSIDs/channel", 12), ("📻 Airspace inventory", 12)]),
    ],
}


def assemble(specs, key):
    pool = {s["title"]: s for s in specs}
    out = []
    for h, items in LINES[key]:
        for title, w in items:
            if title not in pool:
                raise KeyError(f"{key}: no panel titled {title!r} (have: {sorted(pool)})")
            s = dict(pool[title])
            s["w"], s["h"] = w, h
            out.append(s)
    return out


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


ROWS = [
    {"title": None, "open": True, "panels": assemble(fleet, "fleet")},
    {"title": "🎯 Probe Results — reachability SLA (per room × probe)", "open": True, "panels": assemble(probe, "probe")},
    {"title": "📶 WiFi Link Quality — RSSI / channel / BSSID", "open": True, "panels": assemble(link, "link")},
    {"title": "🩺 Device Health & Identity", "open": False, "panels": assemble(health, "health")},
    {"title": "📡 AP Survey — what each room sees (passive scan)", "open": False, "panels": assemble(survey, "survey")},
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
    "uid": "wifi-probes-overview",
    "title": "📡 WiFi Probes — Household Coverage",
    "description": "Per-room ESP32-C5 WiFi probe fleet: fleet verdict strip, reachability SLA "
                   "(gateway/DNS/internet/HTTPS), link quality (RSSI/channel/BSSID), device health, "
                   "and per-room AP survey. Rooms come from the scrape-time `room` label. "
                   "Generated by scripts/grafana/build_wifi_probes_overview.py.",
    "tags": ["wifi", "esp32", "wifi-probe", "wireless", "homelab", "coverage", "overview"],
    "timezone": "browser", "schemaVersion": 39, "version": 1, "editable": True, "weekStart": "",
    "refresh": "30s", "time": {"from": "now-6h", "to": "now"}, "timepicker": {},
    "annotations": {"list": [
        {"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True,
         "hide": True, "iconColor": "rgba(0, 211, 255, 1)", "name": "Annotations & Alerts", "type": "dashboard"},
        {"datasource": DS, "enable": True, "hide": False, "iconColor": "rgba(245, 54, 54, 1)",
         "name": "Probe down", "expr": f'up{{{JOB}, room=~"$room"}} == 0',
         "titleFormat": "{{room}} probe down", "step": "30s"},
    ]},
    "links": [
        {"title": "ESP32-C5 WiFi Probe (repo)", "type": "link",
         "url": "https://github.com/luiscamaral/esp32-c5-wifi-probe", "icon": "external link",
         "targetBlank": True, "asDropdown": False, "tags": []},
    ],
    "templating": {"list": [
        {"name": "room", "type": "query", "datasource": DS,
         "query": {"query": f'label_values(up{{{JOB}}}, room)', "refId": "StandardVariableQuery"},
         "refresh": 2, "includeAll": True, "multi": True, "allValue": ".*",
         "current": {"text": "All", "value": "$__all"}, "sort": 1, "label": "Room"},
        {"name": "band", "type": "query", "datasource": DS,
         "query": {"query": f'label_values(probe_success{{{JOB}}}, band)', "refId": "StandardVariableQuery"},
         "refresh": 2, "includeAll": True, "multi": True, "allValue": ".*",
         "current": {"text": "All", "value": "$__all"}, "sort": 1, "label": "Band"},
        {"name": "window", "type": "interval", "label": "Rate window",
         "query": "5m,15m,30m,1h,6h,12h", "auto": False, "auto_count": 30,
         "auto_min": "10s", "refresh": 2,
         "current": {"text": "15m", "value": "15m"},
         "options": [{"text": w, "value": w, "selected": w == "15m"} for w in
                     ["5m", "15m", "30m", "1h", "6h", "12h"]]},
    ]},
    "panels": panels,
}

OUT.write_text(json.dumps(dashboard, indent=2, sort_keys=True) + "\n")
n_rows = sum(1 for p in panels if p["type"] == "row")
n_leaf = sum(1 for p in panels if p["type"] != "row") + sum(len(p.get("panels", [])) for p in panels if p["type"] == "row")
print(f"wrote {OUT}\n  rows={n_rows}  leaf-panels={n_leaf}  total-ids={_id}")
