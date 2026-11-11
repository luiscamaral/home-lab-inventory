#!/usr/bin/env python3
"""End-to-end test of zot SSO (Keycloak OIDC), API keys and access control. No browser.

It creates two disposable Keycloak users in realm `homelab` (an admin that is put in the
`zot-admins` group, and a plain user), logs both into zot with the scripted authorization-code
flow, creates API keys, then pushes, pulls and deletes `homelab/e2e-test` and checks that the
non-admin is denied pushes and deletes. Everything is removed at the end (`cleanup` always runs
in `all`).

Group membership note: `keycloak_group_memberships.zot_admins` (terraform/portainer/keycloak.tf) is
AUTHORITATIVE. While the test admin is a member, a plan that includes that resource shows drift,
and an apply of it would remove the test user. The test never touches Terraform state: the user is
added through the Keycloak admin API and deleted again (deleting the user removes the membership),
and `cleanup` fails loudly if the group members differ from the snapshot taken in `setup`.
Do not run a Terraform apply that includes `keycloak_group_memberships.zot_admins` meanwhile.

Usage (needs `requests`: `uv run --no-project --quiet --with requests python scripts/zot-e2e.py ...`):

    scripts/zot-e2e.py probe            # read-only: Keycloak reachable, group, users absent, login form
    scripts/zot-e2e.py setup            # creates the users (Keycloak write) -> prints the state dir
    scripts/zot-e2e.py run STATE_DIR    # logins, API keys, push/pull/delete, denials, evidence (zot write)
    scripts/zot-e2e.py cleanup STATE_DIR
    scripts/zot-e2e.py all              # setup + run + cleanup (cleanup in a finally block)

Auth: Keycloak admin password from env KC_ADMIN_PASSWORD, or Vault `secret/homelab/keycloak` (field
`admin_password`) with VAULT_ADDR/VAULT_TOKEN set. Docker steps run over ssh on `--docker-host`
(default dockerserver-2) with a throw-away DOCKER_CONFIG directory that is removed afterwards.
Secrets (passwords, API keys) live only in the 0700 state directory and in memory.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

ZOT = "https://zot.d.lcamaral.com"
KC = "https://keycloak.d.lcamaral.com"
REALM = "homelab"
GROUP = "zot-admins"
REPO = "homelab/e2e-test"
ADMIN_USER = "zot-e2e-test"
PLAIN_USER = "zot-e2e-user"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36"
MANIFEST_ACCEPT = ", ".join(
    [
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    ]
)

results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> bool:
    results.append((name, ok, detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" -- {detail}" if detail else ""), flush=True)
    return ok


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------- Keycloak admin API
class Keycloak:
    def __init__(self) -> None:
        pw = os.environ.get("KC_ADMIN_PASSWORD")
        if not pw:
            pw = subprocess.run(
                ["vault", "kv", "get", "-field=admin_password", "secret/homelab/keycloak"],
                capture_output=True, text=True, check=True,
            ).stdout.strip()
        r = requests.post(
            f"{KC}/realms/master/protocol/openid-connect/token",
            data={"client_id": "admin-cli", "username": "admin", "password": pw, "grant_type": "password"},
            timeout=30,
        )
        r.raise_for_status()
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {r.json()['access_token']}"

    def call(self, method: str, path: str, **kw) -> requests.Response:
        kw.setdefault("timeout", 30)
        return self.s.request(method, f"{KC}/admin/realms/{REALM}{path}", **kw)

    def group_id(self) -> str:
        r = self.call("GET", "/groups", params={"search": GROUP, "exact": "true"})
        r.raise_for_status()
        ids = [g["id"] for g in r.json() if g["name"] == GROUP]
        if len(ids) != 1:
            raise SystemExit(f"expected exactly one group {GROUP}, got {len(ids)}")
        return ids[0]

    def members(self, gid: str) -> list[str]:
        r = self.call("GET", f"/groups/{gid}/members", params={"max": 200})
        r.raise_for_status()
        return sorted(u["username"] for u in r.json())

    def user_exists(self, name: str) -> bool:
        """True if any user's username, email or name contains `name` (the realm uses the email as username)."""
        r = self.call("GET", "/users", params={"search": name})
        r.raise_for_status()
        return bool(r.json())

    def create_user(self, username: str, password: str) -> tuple[str, str]:
        """Create the user; return (id, login name). With "email as username" Keycloak stores the email as username."""
        body = {
            "username": username,
            "email": f"{username}@lcamaral.com",
            "firstName": "Zot",
            "lastName": "Test",
            "enabled": True,
            "emailVerified": True,
            "requiredActions": [],
            "credentials": [{"type": "password", "value": password, "temporary": False}],
        }
        r = self.call("POST", "/users", json=body)
        if r.status_code != 201:
            raise SystemExit(f"create {username}: {r.status_code} {r.text[:200]}")
        uid = r.headers["Location"].rsplit("/", 1)[1]
        got = self.call("GET", f"/users/{uid}")
        got.raise_for_status()
        return uid, got.json()["username"]


# ---------------------------------------------------------------- zot OIDC flow
def zot_login(username: str, password: str) -> requests.Session:
    """Scripted authorization-code flow: zot -> Keycloak form -> callback -> zot session cookie."""
    s = requests.Session()
    s.headers["User-Agent"] = UA
    r = s.get(f"{ZOT}/zot/auth/login", params={"provider": "oidc", "callback_ui": "/home"},
              allow_redirects=False, timeout=30)
    if r.status_code != 302 or "openid-connect/auth" not in r.headers.get("Location", ""):
        raise RuntimeError(f"login did not redirect to Keycloak: {r.status_code} {r.headers.get('Location')}")
    form = s.get(r.headers["Location"], timeout=30)
    m = re.search(r'id="kc-form-login"[^>]*action="([^"]+)"', form.text)
    if form.status_code != 200 or not m:
        raise RuntimeError(f"no Keycloak login form (HTTP {form.status_code})")
    r = s.post(html.unescape(m.group(1)), data={"username": username, "password": password, "credentialId": ""},
               allow_redirects=False, timeout=30)
    loc = r.headers.get("Location", "")
    if r.status_code != 302 or "/zot/auth/callback/oidc" not in loc:
        raise RuntimeError(f"Keycloak did not redirect to the zot callback: {r.status_code} {loc[:120]}")
    r = s.get(loc, allow_redirects=False, timeout=30)
    if r.status_code not in (301, 302, 303) or "session" not in s.cookies.keys():
        raise RuntimeError(f"zot callback gave HTTP {r.status_code}, cookies {list(s.cookies.keys())}")
    # zot honours the session cookie only on requests that carry this header (the UI sends it); without it the
    # request is treated as anonymous and POST /zot/auth/apikey fails with 500 "user data operations are not allowed".
    s.headers["X-ZOT-API-CLIENT"] = "zot-ui"
    return s


def create_apikey(s: requests.Session, label: str) -> tuple[str, str]:
    exp = (datetime.now(timezone.utc) + timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
    r = s.post(f"{ZOT}/zot/auth/apikey", json={"label": label, "expirationDate": exp}, timeout=30)
    if r.status_code != 201:
        raise RuntimeError(f"apikey create: {r.status_code} {r.text[:200]}")
    d = r.json()
    return d["apiKey"], d["uuid"]


def reg(user: str, key: str | None, method: str, path: str, **kw) -> requests.Response:
    kw.setdefault("timeout", 60)
    auth = (user, key) if key else None
    return requests.request(method, f"{ZOT}{path}", auth=auth, **kw)


# ---------------------------------------------------------------- docker over ssh
def docker_ssh(host: str, user: str, key: str, body: str) -> subprocess.CompletedProcess:
    script = (
        "set -u; export LC_ALL=C; D=$(mktemp -d); export DOCKER_CONFIG=$D; trap 'rm -rf \"$D\"' EXIT; "
        f"U={shlex.quote(user)}; REF1=zot.d.lcamaral.com/{REPO}:1; REF2=zot.d.lcamaral.com/{REPO}:2; "
        "read -r KEY; "
        "printf '%s' \"$KEY\" | docker login zot.d.lcamaral.com -u \"$U\" --password-stdin 2>&1 | tail -1; "
        'mkdir "$D/ctx"; echo zot-e2e > "$D/ctx/f"; printf "FROM scratch\\nCOPY f /f\\n" > "$D/ctx/Dockerfile"; '
        "\n" + body
    )
    return subprocess.run(["ssh", host, "bash", "-c", shlex.quote(script)], input=key + "\n",
                          capture_output=True, text=True, timeout=300)


# ---------------------------------------------------------------- subcommands
def state_path(d: Path) -> Path:
    return d / "state.json"


def load(d: Path) -> dict:
    return json.loads(state_path(d).read_text())


def save(d: Path, st: dict) -> None:
    p = state_path(d)
    p.write_text(json.dumps(st, indent=2))
    p.chmod(0o600)


def cmd_probe(_a) -> int:
    kc = Keycloak()
    gid = kc.group_id()
    check("keycloak admin API reachable", True)
    check(f"group {GROUP} found", True, gid)
    print("  members:", kc.members(gid))
    for u in (ADMIN_USER, PLAIN_USER):
        check(f"test user {u} absent", not kc.user_exists(u))
    s = requests.Session()
    s.headers["User-Agent"] = UA
    r = s.get(f"{ZOT}/zot/auth/login", params={"provider": "oidc"}, allow_redirects=False, timeout=30)
    form = s.get(r.headers["Location"], timeout=30)
    check("keycloak login form reachable (scripted client, via the public path)",
          bool(re.search(r'id="kc-form-login"', form.text)), f"HTTP {form.status_code}")
    return 0 if all(ok for _, ok, _ in results) else 1


def setup() -> Path:
    kc = Keycloak()
    gid = kc.group_id()
    snapshot = kc.members(gid)
    for u in (ADMIN_USER, PLAIN_USER):
        if kc.user_exists(u):
            raise SystemExit(f"{u} already exists; refusing to reuse it (run cleanup or delete it by hand)")
    d = Path(tempfile.mkdtemp(prefix="zot-e2e-"))
    d.chmod(0o700)
    st = {"gid": gid, "snapshot": snapshot, "users": {}, "created": now()}
    save(d, st)
    for u in (ADMIN_USER, PLAIN_USER):
        pw = secrets.token_urlsafe(24)
        uid, login = kc.create_user(u, pw)
        st["users"][u] = {"id": uid, "password": pw, "login": login}
        save(d, st)
    r = kc.call("PUT", f"/users/{st['users'][ADMIN_USER]['id']}/groups/{gid}")
    check(f"{ADMIN_USER} added to {GROUP}", r.status_code == 204, f"HTTP {r.status_code}")
    admin_login = st["users"][ADMIN_USER]["login"]
    check("group members = snapshot + test admin",
          kc.members(gid) == sorted(snapshot + [admin_login]), str(kc.members(gid)))
    return d


def cmd_setup(_a) -> int:
    d = setup()
    print(f"STATE_DIR={d}")
    return 0


def cmd_run(a) -> int:
    d = Path(a.state_dir)
    st = load(d)
    t0 = now()
    st["t0"] = t0
    save(d, st)
    adm, pla = st["users"][ADMIN_USER]["login"], st["users"][PLAIN_USER]["login"]
    print(f"login names: {adm}, {pla}")
    print(f"T0={t0}")

    # --- admin: login, API key
    s_adm = zot_login(adm, st["users"][ADMIN_USER]["password"])
    check("admin: OIDC login produces a zot session", True)
    key_adm, uuid_adm = create_apikey(s_adm, "e2e-admin")
    st["users"][ADMIN_USER]["apikey_uuid"] = uuid_adm
    save(d, st)
    check("admin: API key created (zak_...)", key_adm.startswith("zak_"))
    r = reg(adm, key_adm, "GET", "/v2/_catalog")
    check("admin: API key works on /v2/_catalog", r.status_code == 200, f"HTTP {r.status_code}")

    # --- admin: real docker push / pull
    p = docker_ssh(a.docker_host, adm, key_adm,
                   'docker build -q -t "$REF1" "$D/ctx" >/dev/null && docker push "$REF1" 2>&1 | tail -2; '
                   'echo push_rc=${PIPESTATUS[0]}; docker rmi "$REF1" >/dev/null; '
                   'docker pull "$REF1" 2>&1 | grep -E "Digest|Status"; echo pull_rc=${PIPESTATUS[0]}; '
                   'docker rmi "$REF1" >/dev/null')
    out = p.stdout + p.stderr
    print("  docker (admin):", out.strip().replace("\n", " | ")[:500])
    check("admin: docker login + push homelab/e2e-test:1", "push_rc=0" in out and "digest: sha256:" in out)
    check("admin: docker pull it back", "pull_rc=0" in out and "Digest: sha256:" in out)
    m = re.search(r"digest: (sha256:[0-9a-f]{64})", out)
    h = reg(adm, key_adm, "HEAD", f"/v2/{REPO}/manifests/1", headers={"Accept": MANIFEST_ACCEPT})
    digest = h.headers.get("Docker-Content-Digest", "")
    same = h.status_code == 200 and (not m or m.group(1) == digest)
    check("admin: manifest visible, digest equals the pushed one", same, f"HTTP {h.status_code} {digest[:19]}")
    st["digest"] = digest
    save(d, st)

    # --- plain user: allowed to read, denied to write
    s_pla = zot_login(pla, st["users"][PLAIN_USER]["password"])
    check("plain: OIDC login produces a zot session", True)
    key_pla, uuid_pla = create_apikey(s_pla, "e2e-user")
    st["users"][PLAIN_USER]["apikey_uuid"] = uuid_pla
    save(d, st)
    r = reg(pla, key_pla, "GET", f"/v2/{REPO}/manifests/1", headers={"Accept": MANIFEST_ACCEPT})
    check("plain: can read (pull) homelab/e2e-test", r.status_code == 200, f"HTTP {r.status_code}")
    r = reg(None, None, "GET", f"/v2/{REPO}/manifests/1", headers={"Accept": MANIFEST_ACCEPT})
    check("anonymous: homelab/e2e-test denied", r.status_code == 401, f"HTTP {r.status_code}")
    r = reg(pla, key_pla, "POST", f"/v2/{REPO}/blobs/uploads/")
    check("plain: upload (push) denied", r.status_code == 403, f"HTTP {r.status_code}")
    r = reg(pla, key_pla, "DELETE", f"/v2/{REPO}/manifests/{digest}")
    check("plain: delete denied", r.status_code == 403, f"HTTP {r.status_code}")
    p = docker_ssh(a.docker_host, pla, key_pla,
                   'docker build -q -t "$REF2" "$D/ctx" >/dev/null; docker push "$REF2" 2>&1 | tail -2; '
                   'echo push_rc=${PIPESTATUS[0]}; docker rmi "$REF2" >/dev/null; '
                   'docker pull "$REF1" 2>&1 | grep -E "Digest|Status"; echo pull_rc=${PIPESTATUS[0]}; '
                   'docker rmi "$REF1" >/dev/null')
    out = p.stdout + p.stderr
    print("  docker (plain):", out.strip().replace("\n", " | ")[:500])
    check("plain: docker push is refused", "push_rc=0" not in out and "push_rc=" in out)
    check("plain: docker pull works", "pull_rc=0" in out)
    r = reg(adm, key_adm, "HEAD", f"/v2/{REPO}/manifests/1", headers={"Accept": MANIFEST_ACCEPT})
    check("image still present after the plain user's attempts", r.status_code == 200)

    # --- admin: delete through the API, then revoke keys
    r = reg(adm, key_adm, "DELETE", f"/v2/{REPO}/manifests/{digest}")
    check("admin: delete the test image by digest", r.status_code == 202, f"HTTP {r.status_code}")
    r = reg(adm, key_adm, "HEAD", f"/v2/{REPO}/manifests/1", headers={"Accept": MANIFEST_ACCEPT})
    check("admin: manifest gone", r.status_code == 404, f"HTTP {r.status_code}")
    for s, uuid, u in ((s_adm, uuid_adm, ADMIN_USER), (s_pla, uuid_pla, PLAIN_USER)):
        r = s.delete(f"{ZOT}/zot/auth/apikey", params={"id": uuid}, timeout=30)
        check(f"{u}: API key revoked", r.status_code == 200, f"HTTP {r.status_code}")
        st["users"][u].pop("apikey_uuid", None)
        save(d, st)
        if s.post(f"{ZOT}/zot/auth/logout", timeout=30).status_code == 405:
            s.get(f"{ZOT}/zot/auth/logout", timeout=30)
    r = reg(adm, key_adm, "GET", "/v2/_catalog")
    check("admin: revoked key no longer works", r.status_code == 401, f"HTTP {r.status_code}")

    evidence(a, t0)
    bad = [n for n, ok, _ in results if not ok]
    print(f"\n{len(results) - len(bad)} passed, {len(bad)} failed" + (f": {bad}" if bad else ""))
    return 1 if bad else 0


def evidence(a, t0: str) -> None:
    """rproxy access log lines from zot (192.168.59.5) and zot's own request log since t0.

    Token and userinfo calls happen on every login, so they must appear after t0. The jwks (certs) request
    happens only when zot verifies its first ID token after a start (the key set is then cached in the process),
    so it is looked up since zot's start time instead.
    """
    print("\n== evidence: rproxy -> Keycloak requests from 192.168.59.5 (LAN path)")
    cmd = "docker exec rproxy sh -c 'tail -c 80000000 /var/log/nginx/access.log | grep -E \"^192\\.168\\.59\\.5 \"'"
    p = subprocess.run(["ssh", "dockermaster", cmd], capture_output=True, text=True, timeout=120)
    started = subprocess.run(["ssh", "dockermaster", "docker inspect zot --format '{{.State.StartedAt}}'"],
                             capture_output=True, text=True, timeout=60).stdout.strip()
    t_start = datetime.strptime(started[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    t0d = datetime.strptime(t0, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    print(f"  (zot started {started[:19]}Z; this run started {t0})")
    seen = {"token": 0, "userinfo": 0, "certs_since_start": 0}
    for line in p.stdout.splitlines():
        m = re.search(r"\[(\d+/\w+/\d+:\d+:\d+:\d+) \+0000\] \"(\w+) (\S+)", line)
        if not m:
            continue
        ts = datetime.strptime(m.group(1), "%d/%b/%Y:%H:%M:%S").replace(tzinfo=timezone.utc)
        path = m.group(3)
        if ts >= t0d and "openid-connect/token" in path:
            seen["token"] += 1
        elif ts >= t0d and "openid-connect/userinfo" in path:
            seen["userinfo"] += 1
        elif ts >= t_start and "openid-connect/certs" in path:
            seen["certs_since_start"] += 1
        else:
            continue
        print("  ", line[:200])
    check("rproxy saw token + userinfo requests from 192.168.59.5 during the run", seen["token"] > 0
          and seen["userinfo"] > 0, str(seen))
    check("rproxy saw the jwks request from 192.168.59.5 since zot started (key set is cached afterwards)",
          seen["certs_since_start"] > 0, str(seen))
    print("\n== evidence: zot request log (registry + auth paths) since T0")
    p = subprocess.run(["ssh", "dockermaster", f"docker logs --since {t0} zot 2>&1"], capture_output=True, text=True,
                       timeout=120)
    for line in p.stdout.splitlines():
        try:
            j = json.loads(line)
        except ValueError:
            continue
        path = j.get("path", "")
        if j.get("message") == "HTTP API" and (REPO in path or "/zot/auth/" in path):
            print(f"   {j.get('time', '')[11:19]} {j.get('method'):6} {j.get('statusCode')} {path[:80]}")


def cmd_cleanup(a) -> int:
    d = Path(a.state_dir)
    st = load(d)
    ok = True
    kc = Keycloak()
    # leftovers of an interrupted run: revoke keys, delete the image
    for u, info in st["users"].items():
        if info.get("apikey_uuid"):
            try:
                sess = zot_login(info["login"], info["password"])
                sess.delete(f"{ZOT}/zot/auth/apikey", params={"id": info["apikey_uuid"]}, timeout=30)
            except Exception as e:  # noqa: BLE001
                print(f"  could not revoke the key of {u}: {e}")
                ok = False
    if st.get("digest"):
        try:
            s = zot_login(st["users"][ADMIN_USER]["login"], st["users"][ADMIN_USER]["password"])
            key, uuid = create_apikey(s, "e2e-cleanup")
            r = reg(st["users"][ADMIN_USER]["login"], key, "DELETE", f"/v2/{REPO}/manifests/{st['digest']}")
            print(f"  cleanup delete of the image: HTTP {r.status_code} (404 = already gone)")
            s.delete(f"{ZOT}/zot/auth/apikey", params={"id": uuid}, timeout=30)
        except Exception as e:  # noqa: BLE001
            print(f"  could not delete the image: {e}")
    for u, info in st["users"].items():
        r = kc.call("DELETE", f"/users/{info['id']}")
        check(f"keycloak user {u} deleted", r.status_code in (204, 404), f"HTTP {r.status_code}")
    members = kc.members(st["gid"])
    check(f"{GROUP} members back to the snapshot", members == st["snapshot"], f"{members} vs {st['snapshot']}")
    for u in (ADMIN_USER, PLAIN_USER):
        check(f"{u} gone from Keycloak", not kc.user_exists(u))
    shutil.rmtree(d, ignore_errors=True)
    check("state dir (passwords) removed", not d.exists())
    return 0 if ok and all(o for _, o, _ in results) else 1


def cmd_all(a) -> int:
    d = setup()
    a.state_dir = str(d)
    rc = 0
    try:
        rc = cmd_run(a)
    except Exception as e:  # noqa: BLE001
        print(f"run aborted: {e}")
        rc = 1
    finally:
        rc |= cmd_cleanup(a)
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--docker-host", default="dockerserver-2")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("probe")
    sub.add_parser("setup")
    sub.add_parser("all")
    for n in ("run", "cleanup"):
        sub.add_parser(n).add_argument("state_dir")
    a = ap.parse_args()
    return {"probe": cmd_probe, "setup": cmd_setup, "run": cmd_run, "cleanup": cmd_cleanup, "all": cmd_all}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
