#!/usr/bin/env python3
"""Sync pfSense dummynet limiters + queues + aliases from pfsense/traffic-shaper.yml.

Reconciles the WAN traffic-shaper (limiters, child queues) and the P2P
classification aliases against the declarative source via the pfSense REST API.
Idempotent: matches limiters/queues/aliases by name, PATCHes drift, POSTs what's
missing. Order-sensitive floating rules are printed for GUI entry (the
/firewall/rules endpoint 504s on this router's 142-rule set).

Usage:
    uv run --no-project --with pyyaml scripts/sync-pfsense-traffic-shaper.py            # dry-run
    uv run --no-project --with pyyaml scripts/sync-pfsense-traffic-shaper.py --apply

Auth: API token from macOS Keychain (service `pfsense-api-token`). TLS verified
(pfSense serves a real Let's Encrypt *.home.lcamaral.com cert via HAProxy).
"""
import argparse
import json
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import yaml

BASE = "https://pfsense.home.lcamaral.com/api/v2"
SPEC = Path(__file__).resolve().parent.parent / "pfsense" / "traffic-shaper.yml"
CTX = ssl.create_default_context()  # verify TLS

APPLY = "--apply" in sys.argv


def token() -> str:
    return subprocess.check_output(
        ["security", "find-generic-password", "-a", os.environ["USER"], "-s", "pfsense-api-token", "-w"]
    ).decode().strip()


TOKEN = token()


def api(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"X-API-Key": TOKEN, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=45) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:300]}


def do(method: str, path: str, body: dict, what: str) -> bool:
    """Execute a mutating call (or print it in dry-run). Returns success."""
    if not APPLY:
        print(f"  DRY-RUN {method} {path}  {json.dumps(body)}")
        return True
    code, resp = api(method, path, body)
    ok = code in (200, 201)
    flag = "OK " if ok else "ERR"
    print(f"  {flag} {method} {path} -> {code}  {'' if ok else json.dumps(resp)[:200]}")
    return ok


def sync_aliases(spec: dict) -> None:
    print("\n== aliases ==")
    code, cur = api("GET", "/firewall/aliases")
    by_name = {a["name"]: a for a in cur.get("data", [])}
    for a in spec.get("aliases", []):
        want_addr = [str(x) for x in a["address"]]
        existing = by_name.get(a["name"])
        body = {"name": a["name"], "type": a["type"], "address": want_addr,
                "descr": a.get("descr", "")}
        if existing is None:
            do("POST", "/firewall/alias", body, f"create alias {a['name']}")
        elif [str(x) for x in existing.get("address", [])] != want_addr:
            body["id"] = existing["id"]
            do("PATCH", "/firewall/alias", body, f"update alias {a['name']}")
        else:
            print(f"  ok  alias {a['name']} already matches")


def sync_limiters(spec: dict) -> None:
    print("\n== limiters + queues ==")
    code, cur = api("GET", "/firewall/traffic_shaper/limiters")
    lim_by_name = {l["name"]: l for l in cur.get("data", [])}
    for lim in spec.get("limiters", []):
        live = lim_by_name.get(lim["name"])
        if live is None:
            print(f"  !! limiter {lim['name']} not found on device — skipping (create in GUI first)")
            continue
        lid = live["id"]
        # scheduler
        if live.get("sched") != lim["scheduler"]:
            do("PATCH", "/firewall/traffic_shaper/limiter",
               {"id": lid, "sched": lim["scheduler"]}, f"{lim['name']} sched->{lim['scheduler']}")
        else:
            print(f"  ok  {lim['name']} sched already {lim['scheduler']}")
        # bandwidth (first bandwidth item)
        bw_item = (live.get("bandwidth") or [{}])[0]
        if bw_item.get("bw") != lim["bandwidth_mbit"]:
            do("PATCH", "/firewall/traffic_shaper/limiter/bandwidth",
               {"parent_id": lid, "id": bw_item.get("id", 0),
                "bw": lim["bandwidth_mbit"], "bwscale": "Mb"},
               f"{lim['name']} bw->{lim['bandwidth_mbit']}Mb")
        else:
            print(f"  ok  {lim['name']} bw already {lim['bandwidth_mbit']}Mb")
        # queues
        q_by_name = {q["name"]: q for q in live.get("queue", [])}
        for q in lim["queues"]:
            liveq = q_by_name.get(q["name"])
            if liveq is None:
                # aqm must be droptail — codel/pie writes 500 (pfrest 2.8_2 model bug:
                # queue `ecn` field condition references a non-existent `sched` field).
                do("POST", "/firewall/traffic_shaper/limiter/queue",
                   {"parent_id": lid, "name": q["name"], "weight": q["weight"],
                    "aqm": q["aqm"], "mask": "none", "enabled": True,
                    "description": f"{q['name']} (weight {q['weight']})"},
                   f"create queue {q['name']}")
            elif liveq.get("weight") != q["weight"]:
                # PATCH weight only — sending aqm on an update trips the same ecn bug.
                do("PATCH", "/firewall/traffic_shaper/limiter/queue",
                   {"parent_id": lid, "id": liveq["id"], "weight": q["weight"]},
                   f"update queue {q['name']} weight={q['weight']}")
            else:
                print(f"  ok  queue {q['name']} weight already {q['weight']}")


def print_rules(spec: dict) -> None:
    print("\n== classification rules (documented; created via API — see notes) ==")
    print("   pfrest lacks match-action + dest-invert, so these are pass/quick rules.")
    print("   HARDEN in GUI: set destination -> NET_Private_LANS + invert (internet-only).")
    for r in spec.get("rules", []):
        print(f"  - {r['description']}")
        for k in ("action", "floating", "interface", "direction", "quick", "source",
                  "protocol", "destination", "destination_port", "in_pipe", "out_pipe"):
            if k in r:
                print(f"      {k}: {r[k]}")


def main() -> int:
    argparse.ArgumentParser(description=__doc__).parse_known_args()
    spec = yaml.safe_load(SPEC.read_text())
    mode = "APPLY" if APPLY else "DRY-RUN (pass --apply to execute)"
    print(f"pfSense traffic-shaper sync — {mode}\nsource: {SPEC}")
    sync_aliases(spec)
    sync_limiters(spec)
    if APPLY:
        print("\n== applying (filter reload) ==")
        code, resp = api("POST", "/firewall/apply", {})
        print(f"  POST /firewall/apply -> {code}")
    print_rules(spec)
    return 0


if __name__ == "__main__":
    sys.exit(main())
