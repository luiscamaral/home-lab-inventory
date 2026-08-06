#!/usr/bin/env python3
"""Sync pfSense firewall aliases from pfsense/firewall-aliases.yml.

Reconciles general-purpose host/network/port aliases against the declarative
source via the pfSense REST API. Idempotent: matches aliases by name,
PATCHes drift, POSTs what's missing.

Usage:
    uv run --no-project --with pyyaml scripts/sync-pfsense-firewall-aliases.py            # dry-run
    uv run --no-project --with pyyaml scripts/sync-pfsense-firewall-aliases.py --apply

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
SPEC = Path(__file__).resolve().parent.parent / "pfsense" / "firewall-aliases.yml"
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
    code, cur = api("GET", "/firewall/aliases?limit=0")
    by_name = {a["name"]: a for a in cur.get("data", [])}
    for a in spec.get("aliases", []):
        want_addr = [str(x) for x in a["address"]]
        want_detail = [str(x) for x in a.get("detail", [])]
        existing = by_name.get(a["name"])
        body = {"name": a["name"], "type": a["type"], "address": want_addr,
                "detail": want_detail, "descr": a.get("descr", "")}
        if existing is None:
            do("POST", "/firewall/alias", body, f"create alias {a['name']}")
        else:
            cur_addr = [str(x) for x in existing.get("address", [])]
            cur_detail = [str(x) for x in existing.get("detail", [])]
            if cur_addr != want_addr or cur_detail != want_detail:
                body["id"] = existing["id"]
                do("PATCH", "/firewall/alias", body, f"update alias {a['name']}")
            else:
                print(f"  ok  alias {a['name']} already matches")


def main() -> int:
    argparse.ArgumentParser(description=__doc__).parse_known_args()
    spec = yaml.safe_load(SPEC.read_text())
    mode = "APPLY" if APPLY else "DRY-RUN (pass --apply to execute)"
    print(f"pfSense firewall-aliases sync — {mode}\nsource: {SPEC}")
    sync_aliases(spec)
    if APPLY:
        print("\n== applying (filter reload) ==")
        code, resp = api("POST", "/firewall/apply", {})
        print(f"  POST /firewall/apply -> {code}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
