#!/usr/bin/env python3
"""Sync Omada controller site settings from hosts/omada-controller/site-settings.json.

Only the top-level setting blocks listed under "settings" are managed (today: remoteLog).
Read:  GET  /{omadacId}/api/v2/sites/{siteId}/setting
Write: PATCH the same path with only the managed blocks. It writes once and reads the result back.
       It never retries a write: after a failure, read the live setting first.
Login: the controller login from Vault (vault_path in the manifest). Nothing is printed or stored.

Usage:
    scripts/sync-omada-site-settings.py          # plan: show the diff, change nothing
    scripts/sync-omada-site-settings.py --apply  # write and verify
"""

import argparse
import http.cookiejar
import json
import os
import ssl
import subprocess
import sys
import urllib.request
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / "hosts/omada-controller/site-settings.json"
VAULT_ADDR = "http://192.168.59.25:8200"


def vault_field(path, field):
    token = subprocess.run(["security", "find-generic-password", "-w", "-a", "lamaral", "-s", "vault-root-token"],
                           capture_output=True, text=True, check=True).stdout.strip()
    env = {**os.environ, "VAULT_ADDR": VAULT_ADDR, "VAULT_TOKEN": token}
    return subprocess.run(["vault", "kv", "get", f"-field={field}", path], capture_output=True, text=True,
                          check=True, env=env).stdout.strip()


class Omada:
    def __init__(self, base, username, password):
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE  # the controller uses a self-signed certificate
        self.opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context),
                                                  urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.base, self.token = base, None
        self.cid = self.call("GET", "/api/info", prefix=False)["omadacId"]
        self.token = self.call("POST", "/api/v2/login", {"username": username, "password": password})["token"]

    def call(self, method, path, body=None, prefix=True):
        url = self.base + (f"/{self.cid}" if prefix else "") + path
        headers = {"Content-Type": "application/json", **({"Csrf-Token": self.token} if self.token else {})}
        data = json.dumps(body).encode() if body is not None else None
        reply = json.load(self.opener.open(urllib.request.Request(url, data, headers, method=method), timeout=30))
        if reply.get("errorCode") != 0:
            raise RuntimeError(f"{method} {path}: errorCode {reply.get('errorCode')} {reply.get('msg', '')}")
        return reply.get("result")

    def site_id(self, name):
        sites = self.call("GET", "/api/v2/sites?currentPage=1&currentPageSize=100")["data"]
        ids = [s["id"] for s in sites if s["name"] == name]
        if len(ids) != 1:
            raise RuntimeError(f"expected one site named {name!r}, found {len(ids)}")
        return ids[0]

    def logout(self):
        try:
            self.call("POST", "/api/v2/logout", {})
        except (OSError, RuntimeError):
            pass


def changes(live, wanted):
    return {block: (live.get(block), value) for block, value in wanted.items()
            if {k: live.get(block, {}).get(k) for k in value} != value}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    omada = None
    try:
        omada = Omada(manifest["controller"], vault_field(manifest["vault_path"], "username"),
                      vault_field(manifest["vault_path"], "password"))
        path = f"/api/v2/sites/{omada.site_id(manifest['site'])}/setting"
        diff = changes(omada.call("GET", path), manifest["settings"])
        for block, (old, new) in diff.items():
            print(f"{manifest['site']} {block}: {json.dumps(old)} -> {json.dumps(new)}")
        if not diff:
            print("No changes.")
        elif args.apply:
            omada.call("PATCH", path, {block: new for block, (_, new) in diff.items()})
            left = changes(omada.call("GET", path), manifest["settings"])
            if left:
                raise RuntimeError(f"readback differs after the write: {left}. Do not retry; read the live setting.")
            print("Written and verified.")
    except (OSError, RuntimeError, subprocess.SubprocessError, KeyError, ValueError) as exc:
        sys.exit(f"{exc}\nRead the live Omada setting before retrying.")
    finally:
        if omada:
            omada.logout()


if __name__ == "__main__":
    main()
