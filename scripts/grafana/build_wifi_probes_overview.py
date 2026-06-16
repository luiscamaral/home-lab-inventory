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
a multi-agent design pass (fleet / health / link / probe / survey), covering the
key metrics the firmware exposes (link, probe, heap, survey, error stages). Re-run
to regenerate:

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
# Push freshness: 1 = uptime advanced within $window (probe still pushing), 0 = stale.
PUSHING = [{"type": "value", "options": {"0": {"text": "STALE", "color": "red"},
                                         "1": {"text": "PUSHING", "color": "green"}}}]
# Pipeline error rate (refused / send-failed points/s): zero is good, any is bad.
ERRRATE = [{"color": "green", "value": None}, {"color": "red", "value": 0.001}]
# probe_last_error_stage enum -> human label (matches firmware probe stage codes).
ERRSTAGE = [{"type": "value", "options": {
    "0": {"text": "ok", "color": "green"}, "1": {"text": "dns", "color": "yellow"},
    "2": {"text": "tcp", "color": "orange"}, "3": {"text": "tls", "color": "red"},
    "4": {"text": "http", "color": "red"}, "5": {"text": "timeout", "color": "red"},
    "6": {"text": "internal", "color": "purple"}}}]

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
                  "stacking": {"mode": "normal" if s.get("stack") else "none", "group": "A"}}
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
# topk(1, ...) by (instance) on the RHS: after an OTA the 30m cache holds 2+ build_info
# series per instance (old+new version), so a bare RHS would make the group_left a
# many-to-one join → the identity table errors and blanks for 30m on every deploy.
def with_identity(value_expr):
    return (f'{value_expr} * on (instance) group_left(version, idf, chip, location) '
            f'topk(1, wifi_probe_build_info{{{JOB}, room=~"$room"}}) by (instance)')


def with_bssid(value_expr):
    return (f'{value_expr} * on (instance, band) group_left(bssid, ssid, auth) '
            f'last_over_time(wifi_client_bssid_info{{{JOB}, room=~"$room", band=~"$band"}}[$window])')


def ratio_by(grp):
    return (f'sum(increase(probe_success_total{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}) '
            f'/ clamp_min(sum(increase(probe_attempts_total{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}), 1)')


def avglat_by(grp):
    return (f'sum(increase(probe_duration_seconds_sum{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}) '
            f'/ clamp_min(sum(increase(probe_duration_seconds_count{{{JOB}, room=~"$room", band=~"$band"}}[$window])) by ({grp}), 1)')


# Real request latency: TTFB for the HTTPS probe (its total is ~95% fixed TLS-handshake
# crypto on the MCU, not network — see the handshake panel), total duration for ICMP/DNS
# (no handshake, so their total IS the round-trip). Firmware emits probe_http_ttfb_seconds
# ONLY on a successful HTTP connect (guards last_connect_us==0), so a FAILING https probe
# has no ttfb and would vanish. Three clauses: (1) non-http totals, (2) http ttfb (success),
# (3) http total for FAILING probes only — `unless on(...)` subtracts the succeeding-http
# series (which already have ttfb) so a healthy probe shows ttfb alone, never ttfb+total.
# A bare `or probe_last_duration_seconds{...type="http"}` would NOT dedup: the differing
# __name__ makes the default `or` keep both series.
def reallat():
    return (f'(probe_last_duration_seconds{{{JOB}, room=~"$room", band=~"$band", type!="http"}} '
            f'or probe_http_ttfb_seconds{{{JOB}, room=~"$room", band=~"$band"}} '
            f'or (probe_last_duration_seconds{{{JOB}, room=~"$room", band=~"$band", type="http"}} '
            f'unless on (room, instance, probe, band, target) '
            f'probe_http_ttfb_seconds{{{JOB}, room=~"$room", band=~"$band"}}))')


def reallat_avg(grp):
    return f'avg by ({grp}) (avg_over_time({reallat()}[$window:1m]))'


# ══ FLEET — household verdict strip (8 stats, w=3 h=4) ═════════════════════════
fleet = [
    {"type": "stat", "title": "📡 Probes Reporting", "unit": "percentunit", "decimals": 0, "steps":
     [{"color": "red", "value": None}, {"color": "yellow", "value": 0.99}, {"color": "green", "value": 1}],
     "desc": "Fraction of rooms whose probe data is FRESH — uptime advanced within $window. Cutover-agnostic: "
             "holds whether Prometheus scrapes probes directly or via the OTLP collector cache (which serves the "
             "last push for 30m). sum-of-bool numerator (not count) so it never vanishes at a total outage; "
             "or vector(0) keeps an empty fleet at a clear 0 instead of No data.",
     "targets": [T(f'(sum(changes(wifi_probe_uptime_seconds{{{JOB}, room=~"$room"}}[$window]) > bool 0) '
                   f'/ count(wifi_probe_uptime_seconds{{{JOB}, room=~"$room"}})) or vector(0)', "fresh")]},
    {"type": "stat", "title": "🏠 Rooms Covered", "unit": "none", "decimals": 0, "colormode": "value",
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
     "desc": "Distinct rooms reporting probe data. Green at ≥1 so a single-room (or $room-filtered) "
             "deployment isn't falsely degraded.",
     "targets": [T(f'count(count by (room) (wifi_probe_uptime_seconds{{{JOB}, room=~"$room"}})) or vector(0)', "rooms")]},
    {"type": "stat", "title": "🌐 Worst-Room Internet", "unit": "none", "decimals": 0, "mappings": OKFAIL,
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
     "desc": "internet_https (generate_204) reachability of the weakest room, on its recently-reported working "
             "band. max-by-room = a room is OK if EITHER band reached the internet (avoids a false FAIL from the "
             "stale off-band); outer min = FAIL only if some room has no working band. probe_success is "
             "freshness-gated (changes(uptime)>0) so a dead probe's cache-frozen success can't show green.",
     "targets": [T(f'min(max by (room) (probe_success{{{JOB}, probe="internet_https", room=~"$room", band=~"$band"}} '
                   f'and on (instance) (changes(wifi_probe_uptime_seconds{{{JOB}}}[$window]) > 0)))', "worst")]},
    {"type": "stat", "title": "📶 Weakest Link RSSI", "unit": "dBm", "decimals": 0, "steps": RSSI,
     "desc": "Most negative connected-link RSSI across selected rooms/bands.",
     "targets": [T(f'min(wifi_client_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}})', "weakest")]},
    {"type": "stat", "title": "🔌 Disconnects ($window)", "unit": "none", "decimals": 0, "steps": DISC,
     "desc": "Unexpected WiFi disconnects over $window. Excludes the ~once-per-cycle band-switch flaps, so a "
             "healthy probe sits at 0.",
     "targets": [T(f'sum(increase(wifi_client_unexpected_disconnect_total{{{JOB}, room=~"$room"}}[$window]))', "disc")]},
    {"type": "stat", "title": "🧠 Min Contiguous Heap", "unit": "bytes", "decimals": 0, "steps": HEAP,
     "desc": "Smallest largest-contiguous free block among selected probes — the real OOM predictor (what the "
             "HeapLow alert fires on, <32768). A big total heap can still OOM if it's fragmented.",
     "targets": [T(f'min(wifi_probe_heap_largest_free_block_bytes{{{JOB}, room=~"$room"}})', "min heap")]},
    {"type": "stat", "title": "⏱️ Max Probe Staleness", "unit": "s", "decimals": 0, "steps": AGE,
     "desc": "Oldest probe last-success age. NOTE: a never-succeeded probe emits no age series; pair with Probes "
             "Failing. Frozen at last push for a dead probe — read with Per-room push freshness.",
     "targets": [T(f'max(probe_last_success_age_seconds{{{JOB}, room=~"$room", band=~"$band"}})', "stalest")]},
    {"type": "stat", "title": "❌ Probes Failing", "unit": "none", "decimals": 0, "steps": DISC,
     "desc": "Count of room×probe×band checks that are failing OR stale: an explicit last-attempt failure "
             "(success==0 on a fresh probe) OR a probe whose uptime hasn't advanced within $window (cache-frozen, "
             "counted as failing so a dead probe frozen at success=1 can't read green). or vector(0) keeps a "
             "healthy 0 green.",
     "targets": [T(f'count((probe_success{{{JOB}, room=~"$room", band=~"$band"}} == 0 '
                   f'and on (instance) (changes(wifi_probe_uptime_seconds{{{JOB}}}[$window]) > 0)) '
                   f'or (probe_success{{{JOB}, room=~"$room", band=~"$band"}} '
                   f'unless on (instance) (changes(wifi_probe_uptime_seconds{{{JOB}}}[$window]) > 0))) '
                   f'or vector(0)', "failing")]},
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
     "colormode": "thresholds", "desc": "Downward drift over hours = leak → predicts an OOM reboot. min-free is "
     "the firmware's since-boot low-water mark; largest-block is the biggest contiguous free block (the real OOM "
     "predictor — a high free total can still OOM if fragmented).",
     "targets": [T(f'wifi_probe_heap_free_bytes{{{JOB}, room=~"$room"}}', "{{room}} free"),
                 T(f'wifi_probe_heap_min_free_bytes{{{JOB}, room=~"$room"}}', "{{room}} min-free"),
                 T(f'wifi_probe_heap_largest_free_block_bytes{{{JOB}, room=~"$room"}}', "{{room}} largest-block")]},
    {"type": "timeseries", "title": "🔌 Disconnects — increase/$window", "unit": "none", "decimals": 0,
     "steps": DISC, "colormode": "thresholds", "desc": "Unexpected-disconnect increase() over the generous $window "
     "(excludes the once-per-cycle band-switch flaps, so a healthy probe stays flat at 0). No band label on this "
     "counter.",
     "targets": [T(f'increase(wifi_client_unexpected_disconnect_total{{{JOB}, room=~"$room"}}[$window])', "{{room}} disc/$window")]},
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
             "the verdict stays correct when you filter $room or $band. Numerator is freshness-gated "
             "(changes(uptime)>0) — a cache-frozen dead probe drops out of the numerator but stays in the full "
             "denominator, so it drags the verdict down instead of falsely passing.",
     "targets": [T(f'sum(probe_success{{{JOB}, room=~"$room", band=~"$band"}} '
                   f'and on (instance) (changes(wifi_probe_uptime_seconds{{{JOB}}}[$window]) > 0)) '
                   f'/ count(probe_success{{{JOB}, room=~"$room", band=~"$band"}})', "passing")]},
    {"type": "stat", "title": "📉 Worst success ratio", "unit": "percentunit", "decimals": 3, "steps": RATIO,
     "desc": "Single worst room×probe success ratio over $window. clamp_min avoids 0/0; prefer $window ≥15m.",
     "targets": [T(f'min({ratio_by("room, probe")})', "min ratio")]},
    {"type": "stat", "title": "⏱️ Stalest probe age", "unit": "s", "decimals": 0, "steps": AGE,
     "desc": "Oldest last-success across room×probe. Never-succeeded probes are omitted here — see the matrix. "
             "Frozen at last push for a dead probe — read with Per-room push freshness.",
     "targets": [T(f'max(probe_last_success_age_seconds{{{JOB}, room=~"$room", band=~"$band"}})', "max age")]},
    {"type": "stat", "title": "🌐 HTTPS status (204?)", "unit": "none", "decimals": 0, "mappings": HTTP204,
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 204}, {"color": "yellow", "value": 205}],
     "desc": "Worst non-zero internet_https code. 204 = clean internet; 200/302 = captive portal / DNS hijack; "
             "0 = timeout. != 0 drops timeout zeros so a concurrent band timeout can't mask a captive-portal "
             "200/302; or vector(0) shows a clean 0 (timeout) when every band is timing out.",
     "targets": [T(f'min(probe_http_status_code{{{JOB}, room=~"$room", band=~"$band", probe="internet_https"}} != 0) '
                   f'or vector(0)', "min code")]},
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
    {"type": "timeseries", "title": "📨 Request latency — TTFB (HTTPS) / RTT", "unit": "s", "decimals": 3,
     "steps": LAT, "colormode": "thresholds", "desc": "Real request latency per room×probe×band: TTFB for the HTTPS "
     "probe (its total is ~95% fixed TLS-handshake crypto on the MCU, not network), total duration for ICMP/DNS "
     "(no handshake → total IS the RTT). Coarse staircase (one step/cycle); held segments are normal. The HTTPS "
     "handshake cost lives in the next panel so it doesn't false-red here.",
     "targets": [T(reallat(), "{{room}} · {{probe}} · {{band}}")]},
    {"type": "timeseries", "title": "Avg request latency over $window", "unit": "s", "decimals": 3, "steps": LAT,
     "colormode": "thresholds", "desc": "Windowed mean of the real request latency (TTFB for HTTPS, total for "
     "ICMP/DNS), bands merged per room×probe. avg_over_time over a subquery smooths the per-cycle quantization.",
     "targets": [T(reallat_avg("room, probe"), "{{room}} · {{probe}}")]},
    {"type": "timeseries", "title": "🌐 HTTPS handshake vs TTFB (internet_https)", "unit": "s", "decimals": 3,
     "colormode": "palette-classic", "calcs": ["lastNotNull", "max"],
     "desc": "Splits the HTTPS probe: connect = DNS+TCP+TLS handshake (the ~0.7 s fixed TLS-crypto cost on the C5 "
     "MCU — NOT network, ~10-20× a real CPU), TTFB = the real request round-trip (~20 ms, matches curl). A connect "
     "spike (esp. with err_stage=tls / err_esp=0x8017) = a TLS regression like the 0.9.1 heap-OOM TLS failure; TTFB "
     "is the real internet-latency signal. No threshold colouring — the ~0.7 s connect is expected here.",
     "targets": [T(f'probe_http_connect_seconds{{{JOB}, room=~"$room", band=~"$band", probe="internet_https"}}', "{{room}} {{band}} · connect"),
                 T(f'probe_http_ttfb_seconds{{{JOB}, room=~"$room", band=~"$band", probe="internet_https"}}', "{{room}} {{band}} · ttfb")]},
    {"type": "timeseries", "title": "HTTPS status code over time", "unit": "none", "decimals": 0,
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 204}, {"color": "yellow", "value": 205}],
     "colormode": "thresholds", "desc": "internet_https code per room/band — a flip 204→200/302 marks a captive "
     "portal; 0 marks a hard timeout.",
     "targets": [T(f'probe_http_status_code{{{JOB}, room=~"$room", band=~"$band", probe="internet_https"}}', "{{room}} · {{band}}")]},
    {"type": "table", "title": "📋 Probe SLA matrix — room × probe × band", "unit": "none", "decimals": 3,
     "desc": "Dense per-(room,probe,band) sheet joining every probe metric. A blank Success-age next to Up=0 is "
     "the silently-failing / never-succeeded signature. target column confirms each probe is aimed correctly. "
     "Last/Avg = real request latency (TTFB for HTTPS, total for ICMP/DNS).",
     "targets": [
         T(f'probe_success{{{JOB}, room=~"$room", band=~"$band"}}', "up", instant=True),
         T(ratio_by("room, probe, band, target, type, instance"), "ratio", instant=True),
         T(reallat(), "lastlat", instant=True),
         T(reallat_avg("room, probe, band, target, type, instance"), "avglat", instant=True),
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
     "the success matrix (always has a lane). Frozen at last push for a dead probe — read with Per-room push "
     "freshness.",
     "targets": [T(f'max by (room, probe) (probe_last_success_age_seconds{{{JOB}, room=~"$room", band=~"$band"}})',
                   "{{room}} · {{probe}}", instant=True)]},
    {"type": "state-timeline", "title": "🚦 Probe error stage", "mappings": ERRSTAGE, "showvalue": "auto",
     "steps": [{"color": "green", "value": None}, {"color": "yellow", "value": 1}, {"color": "red", "value": 3}],
     "desc": "Last error stage per room×probe×band over time (the WifiProbeInternetDown alert points here): "
     "0 ok · 1 dns · 2 tcp · 3 tls · 4 http · 5 timeout · 6 internal. A sustained tls/timeout lane pins the "
     "failing stage of a down probe.",
     "targets": [T(f'probe_last_error_stage{{{JOB}, room=~"$room", band=~"$band"}}', "{{room}} · {{probe}} · {{band}}")]},
    {"type": "timeseries", "title": "📊 Errors by stage / $window", "unit": "none", "decimals": 0,
     "fill": 25, "stack": True, "desc": "increase() of probe_errors_total bucketed by failing stage over $window, "
     "summed per room×probe×stage. Stacked so the dominant failure mode (dns / tcp / tls / http / timeout) for a "
     "flaky probe is obvious.",
     "targets": [T(f'sum by (room, probe, stage) (increase(probe_errors_total{{{JOB}, room=~"$room", band=~"$band"}}[$window]))',
                   "{{room}} · {{probe}} · {{stage}}")]},
    {"type": "timeseries", "title": "p95 latency over $window (ICMP/DNS)", "unit": "s", "decimals": 3,
     "steps": LAT, "colormode": "thresholds", "desc": "histogram_quantile p95 of probe_duration_seconds for the "
     "round-trip probes (gateway / internet_ip / lan_dns), per room×probe. HTTPS is EXCLUDED — its total is "
     "TLS-handshake-dominated; use the TTFB / handshake panels for HTTPS. NOTE: the histogram observes ALL attempts "
     "incl. failures at full duration, so a p95 spike can be failures — cross-check the success matrix.",
     "targets": [T(f'histogram_quantile(0.95, sum by (le, room, probe) (rate(probe_duration_seconds_bucket'
                   f'{{{JOB}, room=~"$room", band=~"$band", type!="http"}}[$window])))', "{{room}} · {{probe}}")]},
]

# ══ SURVEY — what each room sees ══════════════════════════════════════════════
survey = [
    {"type": "table", "title": "📡 Surveyed APs per room (RSSI desc)", "unit": "dBm", "decimals": 0,
     "desc": "Passive-scan AP list per room×band×BSSID, enriched with the operator-assigned name (wifi_ap_info, "
     "set via PATCH /aps — blank if the BSSID isn't named). The same BSSID at different RSSI from different rooms "
     "is your coverage map. Top ~6 APs per band; an empty table = scan not yet populated for that band.",
     "targets": [
         T(f'wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}', "rssi", instant=True),
         T(f'wifi_ap_info{{{JOB}, room=~"$room"}} and on (bssid, instance) '
           f'wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}', "info", instant=True)],
     "transforms": organize(
         {"room": "Room", "band": "Band", "ssid": "SSID", "bssid": "BSSID", "channel": "Ch",
          "name": "AP name", "Value #A": "RSSI"}, extra_exclude=["Value #B", "location"]) +
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
     "steps": CONG, "desc": "Co-channel congestion: distinct APs seen per channel/band, as seen by the selected "
     "room(s), not the whole airspace. Inner max-by dedupes a BSSID seen from several rooms. LOWER is better "
     "(opposite polarity to RSSI). Undercounts (top-6 cap).",
     "targets": [T(f'count by (channel, band) (max by (channel, band, bssid) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))',
                   "ch {{channel}} ({{band}})", instant=True)]},
    {"type": "stat", "title": "📻 Airspace inventory", "unit": "none", "decimals": 0, "colormode": "value",
     "steps": [{"color": "blue", "value": None}], "textmode": "value_and_name",
     "desc": "Distinct radios (BSSIDs), networks (SSIDs), and channels in the current room/band scan — as seen by "
             "the selected room(s), not the whole airspace.",
     "targets": [
         T(f'count(count by (bssid) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))', "BSSIDs"),
         T(f'count(count by (ssid) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))', "SSIDs"),
         T(f'count(count by (channel) (wifi_ap_rssi_dbm{{{JOB}, room=~"$room", band=~"$band"}}))', "Channels")]},
]

# ══ OTLP PIPELINE — push freshness + collector health ═════════════════════════
# The probes PUSH OTLP/HTTP to the collector, which caches each series for 30m
# (metric_expiration) and serves them on :8889 for Prometheus — bridging the
# band-switch dark windows. These panels watch the pipeline: per-room push
# freshness (the liveness signal now that `up` is the collector, not the probe)
# and collector throughput/health from its :8888 self-telemetry.
OTELJOB = 'job="otel-collector"'
otlp = [
    {"type": "stat", "title": "🔌 Collector", "unit": "none", "decimals": 0, "mappings": UPDOWN,
     "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}],
     "desc": "otel-collector scrape target up. DOWN = the whole push pipeline is blind (no room reports). "
             "Pairs with the OtelCollectorDown alert.",
     "targets": [T(f'max(up{{{OTELJOB}}})', "up")]},
    {"type": "stat", "title": "🧠 Collector RAM", "unit": "bytes", "decimals": 0, "steps": GREEN,
     "colormode": "value",
     "desc": "Collector resident memory. metric_expiration (30m) bounds the held series; watch for unbounded growth.",
     "targets": [T(f'max(otelcol_process_memory_rss{{{OTELJOB}}})', "rss")]},
    {"type": "stat", "title": "📥 Refused pts/s", "unit": "short", "decimals": 3, "steps": ERRRATE,
     "desc": "Receiver-refused datapoints/s — should be 0. Nonzero = malformed pushes or backpressure.",
     "targets": [T(f'sum(rate(otelcol_receiver_refused_metric_points{{{OTELJOB}}}[$window]))', "refused")]},
    {"type": "stat", "title": "📤 Send-fail pts/s", "unit": "short", "decimals": 3, "steps": ERRRATE,
     "desc": "Exporter send-failed datapoints/s — should be 0. Nonzero = the :8889 Prometheus exporter is unhealthy.",
     "targets": [T(f'sum(rate(otelcol_exporter_send_failed_metric_points{{{OTELJOB}}}[$window]))', "failed")]},
    {"type": "timeseries", "title": "📈 Ingest throughput — accepted vs exported pts/s", "unit": "short",
     "decimals": 2, "steps": GREEN, "desc": "Datapoints/s the collector accepts from probe pushes (and re-exports "
     "to Prometheus). Each room pushes ~7 chunks per ~50-110s band cycle; a room going silent steps this down.",
     "targets": [T(f'sum(rate(otelcol_receiver_accepted_metric_points{{{OTELJOB}}}[$window]))', "accepted"),
                 T(f'sum(rate(otelcol_exporter_sent_metric_points{{{OTELJOB}}}[$window]))', "exported")]},
    {"type": "state-timeline", "title": "🟢 Per-room push freshness", "steps":
     [{"color": "red", "value": None}, {"color": "green", "value": 1}], "mappings": PUSHING,
     "desc": "Per room: 1 = a push advanced uptime within the last 6m (PUSHING), 0 = STALE. The direct per-room "
     "liveness signal now that `up` reflects the collector, not each probe. 6m > one band cycle so a healthy "
     "room never flaps.",
     "targets": [T(f'clamp_max(changes(wifi_probe_uptime_seconds{{{JOB}, room=~"$room"}}[6m]), 1)', "{{room}}")]},
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
        (8, [("Success ratio over $window (room × probe)", 12), ("📨 Request latency — TTFB (HTTPS) / RTT", 12)]),
        (8, [("Avg request latency over $window", 12), ("🌐 HTTPS handshake vs TTFB (internet_https)", 12)]),
        (8, [("HTTPS status code over time", 12), ("p95 latency over $window (ICMP/DNS)", 12)]),
        (10, [("📋 Probe SLA matrix — room × probe × band", 24)]),
        (8, [("Probe freshness — last-success age", 24)]),
        (8, [("🚦 Probe error stage", 12), ("📊 Errors by stage / $window", 12)]),
    ],
    "survey": [
        (10, [("📡 Surveyed APs per room (RSSI desc)", 24)]),
        (8, [("Best AP RSSI per room (strongest seen)", 12), ("Best AP RSSI per room — trend", 12)]),
        (8, [("Channel occupancy — distinct BSSIDs/channel", 12), ("📻 Airspace inventory", 12)]),
    ],
    "otlp": [
        (4, [("🔌 Collector", 6), ("🧠 Collector RAM", 6), ("📥 Refused pts/s", 6), ("📤 Send-fail pts/s", 6)]),
        (8, [("📈 Ingest throughput — accepted vs exported pts/s", 12), ("🟢 Per-room push freshness", 12)]),
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
    {"title": "🔌 OTLP Push Pipeline — collector & per-room freshness", "open": False, "panels": assemble(otlp, "otlp")},
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
         "name": "Probe not reporting", "expr": f'changes(wifi_probe_uptime_seconds{{{JOB}, room=~"$room"}}[10m]) == 0',
         "titleFormat": "{{room}} not reporting", "step": "30s"},
    ]},
    "links": [
        {"title": "ESP32-C5 WiFi Probe (repo)", "type": "link",
         "url": "https://github.com/luiscamaral/esp32-c5-wifi-probe", "icon": "external link",
         "targetBlank": True, "asDropdown": False, "tags": []},
    ],
    "templating": {"list": [
        {"name": "room", "type": "query", "datasource": DS,
         "query": {"query": f'label_values(wifi_probe_uptime_seconds{{{JOB}}}, room)', "refId": "StandardVariableQuery"},
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
