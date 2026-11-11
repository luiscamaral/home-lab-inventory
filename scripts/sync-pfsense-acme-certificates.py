#!/usr/bin/env python3
"""
Reconcile pfSense ACME certificate DEFINITIONS from `pfsense/acme-certificates.yml`
to the live pfSense REST API (Services > ACME Certificates).

Source of truth: pfsense/acme-certificates.yml
Managed per cert: descr, status, acmeaccount, keylength, preferredchain, oscpstaple,
                  dnssleep, renewafter and the domain list (name, method, status).
NOT managed here: post-renewal actions (scripts/sync-pfsense-acme-actions.py), ACME
                  account keys, global ACME settings. A cert that exists on pfSense but is
                  not in the YAML is only reported; nothing is ever deleted.

Usage:
    scripts/sync-pfsense-acme-certificates.py                       # dry run, all certs
    scripts/sync-pfsense-acme-certificates.py --check               # dry run, exit 1 on a diff
    scripts/sync-pfsense-acme-certificates.py --cert X --apply      # create/patch one cert
    scripts/sync-pfsense-acme-certificates.py --cert X --issue      # issue (first time) and wait
    scripts/sync-pfsense-acme-certificates.py --cert X --renew      # force a renewal and wait

--apply and --issue/--renew need --cert (one cert at a time, like terraform -target).
--issue/--renew talk to Let's Encrypt and write/remove a DNS TXT record at DreamHost, so
they are always an explicit separate step. After the run, the script prints the issued
certificate's subject/SAN/dates as pfSense sees them (/cf/conf/acme/<name>.crt).

Why ssh + 127.0.0.1:56880 and not https://pfsense.home.lcamaral.com/api/v2:
every ACME call is slow on this pfSense (about 40 s for a single cert read, about 57 s for the
list: the PHP worker spends the time forking `sysctl` through shaper.inc's getSchedulers()).
The HAProxy front end has `timeout server 30000`, so through HAProxy these endpoints return
504 although the API itself answers 200 after the delay. Going straight to the local web
server avoids HAProxy. Timeouts here are 170 s.

Secrets: the pfSense API token comes from the macOS Keychain (`pfsense-api-token`). The
DreamHost DNS token is write-only in the REST API (never returned), so it can't be diffed.
It is read from Vault (`secret/homelab/dreamhost`, field `api_token`; VAULT_ADDR defaults to
the direct address, VAULT_TOKEN from the Keychain `vault-root-token`) and only sent when a
`dns_dreamhost` domain is created. Requests are sent to curl on pfSense through stdin
(`curl --config -`), so neither token appears in any process list.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
CERTS_YAML = REPO_ROOT / "pfsense" / "acme-certificates.yml"
ACTIONS_YAML = REPO_ROOT / "pfsense" / "acme-actions.yml"

API_BASE = "http://127.0.0.1:56880/api/v2"
P_CERTS = "/services/acme/certificates"
P_CERT = "/services/acme/certificate"
P_DOMAIN = "/services/acme/certificate/domain"
P_ISSUE = "/services/acme/certificate/issue"
P_RENEW = "/services/acme/certificate/renew"
P_ISSUANCES = "/services/acme/certificate/issuances"
ACME_DIR = "/cf/conf/acme"

CERT_FIELDS = ("descr", "status", "acmeaccount", "keylength", "preferredchain", "oscpstaple",
               "dnssleep", "renewafter")
DOMAIN_FIELDS = ("method", "status")

VAULT_ADDR_DEFAULT = "http://192.168.59.25:8200"
VAULT_DREAMHOST_PATH = "secret/homelab/dreamhost"
VAULT_DREAMHOST_FIELD = "api_token"
API_TIMEOUT_S = 170


class Fail(Exception):
    pass


# --------------------------------------------------------------------------- secrets


def keychain(service: str) -> str:
    user = subprocess.check_output(["whoami"], text=True).strip()
    try:
        return subprocess.check_output(
            ["security", "find-generic-password", "-w", "-s", service, "-a", user], text=True).strip()
    except subprocess.CalledProcessError as e:
        raise Fail(f"Keychain item '{service}' not found: {e}")


_dreamhost_token: str | None = None


def dreamhost_token() -> str:
    global _dreamhost_token
    if _dreamhost_token is None:
        env = dict(os.environ)
        env.setdefault("VAULT_ADDR", VAULT_ADDR_DEFAULT)
        env.setdefault("VAULT_TOKEN", keychain("vault-root-token"))
        try:
            _dreamhost_token = subprocess.check_output(
                ["vault", "kv", "get", f"-field={VAULT_DREAMHOST_FIELD}", VAULT_DREAMHOST_PATH],
                text=True, env=env).strip()
        except subprocess.CalledProcessError as e:
            raise Fail(f"could not read {VAULT_DREAMHOST_PATH} from Vault: {e}")
    return _dreamhost_token


# ------------------------------------------------------------------------------- api


def _cfg_quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def api(method: str, path: str, token: str, body: dict | None = None,
        timeout_s: int = API_TIMEOUT_S) -> dict:
    """Call the pfSense REST API on 127.0.0.1:56880 over ssh; secrets go through stdin."""
    cfg = [f"url = {_cfg_quote(API_BASE + path)}",
           f"request = {_cfg_quote(method)}",
           f"header = {_cfg_quote('X-API-Key: ' + token)}",
           f"header = {_cfg_quote('Content-Type: application/json')}"]
    if body is not None:
        cfg.append(f"data-binary = {_cfg_quote(json.dumps(body))}")
    r = subprocess.run(
        ["ssh", "-o", "ConnectTimeout=10", "pfsense", f"curl -s --max-time {timeout_s} --config -"],
        input="\n".join(cfg) + "\n", capture_output=True, text=True, check=False, timeout=timeout_s + 20)
    if r.returncode != 0:
        raise Fail(f"{method} {path}: ssh/curl failed (rc={r.returncode}): {r.stderr.strip()[:200]}")
    out = r.stdout.strip()
    if not out:
        raise Fail(f"{method} {path}: empty response (timeout?)")
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        raise Fail(f"{method} {path}: invalid JSON: {out[:200]}")
    if data.get("code", 200) >= 400:
        raise Fail(f"{method} {path}: API {data.get('code')} {data.get('response_id')}: {data.get('message')}")
    return data


def fetch_live(token: str) -> list[dict]:
    return api("GET", P_CERTS, token).get("data", [])


# ------------------------------------------------------------------------------ model


def load_desired() -> list[dict]:
    if not CERTS_YAML.exists():
        raise Fail(f"{CERTS_YAML} not found")
    doc = yaml.safe_load(CERTS_YAML.read_text()) or {}
    certs = doc.get("certificates") or []
    for c in certs:
        c.setdefault("oscpstaple", False)
        c.setdefault("dnssleep", None)
        c["keylength"] = str(c.get("keylength", "4096"))
        for d in c.get("domains", []):
            d.setdefault("status", "enable")
    return certs


def desired_actions(cert_name: str) -> list[dict]:
    if not ACTIONS_YAML.exists():
        return []
    for e in yaml.safe_load(ACTIONS_YAML.read_text()) or []:
        if e.get("cert") == cert_name:
            return [{"command": a["command"], "method": a.get("method", "shellcommand"),
                     "status": a.get("status", "active")} for a in e.get("actions", [])]
    return []


def norm(v):
    if v in ("", None):
        return None
    if isinstance(v, bool):
        return v
    return str(v)


def plan_cert(want: dict, live: dict | None) -> list[str]:
    """Human-readable list of differences ([] = in sync). A missing cert yields ['CREATE']."""
    if live is None:
        return ["CREATE"]
    diffs = []
    for f in CERT_FIELDS:
        w, l = norm(want.get(f)), norm(live.get(f))
        if w != l:
            diffs.append(f"{f}: live={live.get(f)!r} want={want.get(f)!r}")
    live_dom = {d["name"]: d for d in live.get("a_domainlist", [])}
    want_dom = {d["name"]: d for d in want.get("domains", [])}
    for n in want_dom.keys() - live_dom.keys():
        diffs.append(f"domain +{n}")
    for n in live_dom.keys() - want_dom.keys():
        diffs.append(f"domain -{n}")
    for n in want_dom.keys() & live_dom.keys():
        for f in DOMAIN_FIELDS:
            if norm(want_dom[n].get(f)) != norm(live_dom[n].get(f)):
                diffs.append(f"domain {n} {f}: live={live_dom[n].get(f)!r} want={want_dom[n].get(f)!r}")
    return diffs


def domain_body(d: dict) -> dict:
    body = {"name": d["name"], "method": d["method"], "status": d.get("status", "enable")}
    if d["method"] == "dns_dreamhost":
        body["dh_api_key"] = dreamhost_token()
    return body


def cert_body(want: dict) -> dict:
    body = {f: want[f] for f in CERT_FIELDS if f in want and not (f == "dnssleep" and want[f] is None)}
    body["keylength"] = str(body["keylength"])
    return body


# ----------------------------------------------------------------------------- apply


def apply_cert(want: dict, live: dict | None, token: str) -> None:
    if live is None:
        body = cert_body(want)
        body["a_domainlist"] = [domain_body(d) for d in want["domains"]]
        body["a_actionlist"] = desired_actions(want["name"])
        print(f"  POST {P_CERT} (create {want['name']}, {len(body['a_domainlist'])} domain(s), "
              f"{len(body['a_actionlist'])} action(s)); this takes about a minute ...")
        api("POST", P_CERT, token, body)
        print("  created")
        return

    cid = live["id"]
    patch = {f: want.get(f) for f in CERT_FIELDS if norm(want.get(f)) != norm(live.get(f))}
    if patch:
        patch = {k: (str(v) if k == "keylength" else v) for k, v in patch.items()}
        print(f"  PATCH {P_CERT} id={cid}: {sorted(patch)}")
        api("PATCH", P_CERT, token, {"id": cid, **patch})

    live_dom = {d["name"]: d for d in live.get("a_domainlist", [])}
    want_dom = {d["name"]: d for d in want.get("domains", [])}
    for name, d in want_dom.items():
        if name not in live_dom:
            print(f"  POST {P_DOMAIN} (+{name})")
            api("POST", P_DOMAIN, token, {"parent_id": cid, **domain_body(d)})
        else:
            changed = {f: d.get(f) for f in DOMAIN_FIELDS if norm(d.get(f)) != norm(live_dom[name].get(f))}
            if changed:
                print(f"  PATCH {P_DOMAIN} {name}: {sorted(changed)}")
                api("PATCH", P_DOMAIN, token, {"parent_id": cid, "id": live_dom[name]["id"], **changed})
    # delete extras last, highest id first so earlier ids stay valid
    extras = sorted((d for n, d in live_dom.items() if n not in want_dom), key=lambda d: -d["id"])
    for d in extras:
        print(f"  DELETE {P_DOMAIN} (-{d['name']})")
        api("DELETE", f"{P_DOMAIN}?parent_id={cid}&id={d['id']}", token)


# ------------------------------------------------------------------- issue / renew


_SECRET_RE = re.compile(r"((?:token|key|secret|password|api)[A-Za-z_]*['\"= :]+)([A-Za-z0-9_\-+/=.]{8,})", re.I)


def redact(s: str) -> str:
    return _SECRET_RE.sub(lambda m: m.group(1) + "<redacted>", s)


def show_cert_files(name: str) -> None:
    cmd = (f"for e in crt key fullchain ca; do ls -l {ACME_DIR}/{name}.$e 2>&1 | awk '{{print $1, $5, $6, $7, $8, $9}}'; done; "
           f"openssl x509 -in {ACME_DIR}/{name}.crt -noout -subject -issuer -dates -ext subjectAltName 2>&1")
    r = subprocess.run(["ssh", "pfsense", cmd], capture_output=True, text=True, check=False)
    for line in r.stdout.splitlines():
        print("   ", line)


def issue_or_renew(name: str, token: str, renew: bool) -> bool:
    path = P_RENEW if renew else P_ISSUE
    print(f"  POST {path} certificate={name}")
    api("POST", path, token, {"certificate": name})
    deadline = time.time() + 20 * 60
    last = ""
    while time.time() < deadline:
        time.sleep(20)
        for it in api("GET", P_ISSUANCES, token).get("data", []):
            if it.get("certificate") != name:
                continue
            status = it.get("status")
            if status != last:
                print(f"  issuance status: {status}")
                last = status
            if status == "completed":
                log = redact(it.get("result_log") or "")
                tail = [ln for ln in log.splitlines() if ln.strip()][-12:]
                print("  result_log (tail):")
                for ln in tail:
                    print("    " + ln[:200])
                ok = bool(re.search(r"cert(ificate)? success|Cert success|Your cert is in", log, re.I)) \
                    and not re.search(r"\bError\b|fail", log, re.I)
                print(f"  acme.sh outcome: {'success' if ok else 'NOT clearly successful (check the log above)'}")
                print(f"  files on pfSense ({ACME_DIR}):")
                show_cert_files(name)
                return ok
    print("  timed out waiting for the issuance to complete (20 min)")
    return False


# -------------------------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cert", action="append", metavar="NAME", help="limit to this cert (repeatable)")
    ap.add_argument("--apply", action="store_true", help="create/patch (needs --cert)")
    ap.add_argument("--issue", action="store_true", help="issue the cert and wait (needs --cert)")
    ap.add_argument("--renew", action="store_true", help="force a renewal and wait (needs --cert)")
    ap.add_argument("--check", action="store_true", help="dry run; exit 1 if anything differs")
    args = ap.parse_args()

    if (args.apply or args.issue or args.renew) and not args.cert:
        ap.error("--apply/--issue/--renew need --cert (one cert at a time)")
    if (args.issue or args.renew) and (args.apply or args.check or (args.issue and args.renew)):
        ap.error("--issue/--renew are standalone steps")
    if args.check and args.apply:
        ap.error("--check is a dry-run mode")

    try:
        token = keychain("pfsense-api-token")
        desired = load_desired()
        print("Reading ACME certificates from pfSense (the API takes about a minute) ...")
        live = fetch_live(token)
        live_by = {c["name"]: c for c in live}
        print(f"  {len(live)} certificate(s) on pfSense, {len(desired)} in the YAML")

        targets = [c for c in desired if not args.cert or c["name"] in args.cert]
        if args.cert:
            unknown = set(args.cert) - {c["name"] for c in desired}
            if unknown:
                raise Fail(f"not in {CERTS_YAML.name}: {sorted(unknown)}")

        if args.issue or args.renew:
            name = args.cert[0]
            if name not in live_by:
                raise Fail(f"{name} does not exist on pfSense yet; run --apply first")
            ok = issue_or_renew(name, token, renew=args.renew)
            return 0 if ok else 3

        any_diff = False
        for want in targets:
            lv = live_by.get(want["name"])
            diffs = plan_cert(want, lv)
            print(f"\n=== {want['name']} ===")
            if not diffs:
                print("  in sync")
                continue
            any_diff = True
            for d in diffs:
                print(f"  {'+' if d == 'CREATE' else '~'} {d}")
            if args.apply:
                apply_cert(want, lv, token)

        unmanaged = sorted(set(live_by) - {c["name"] for c in desired})
        if unmanaged:
            print(f"\nNote: on pfSense but not in the YAML (left alone): {unmanaged}")

        if not args.apply:
            print("\nAll certificate definitions match." if not any_diff
                  else "\nDifferences found. Re-run with --cert NAME --apply.")
        return 1 if (args.check and any_diff) else 0
    except Fail as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
