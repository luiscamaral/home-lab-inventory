#!/usr/bin/env python3
"""Tests for the Keycloak hardening (phase K): lockout (K2), reset-credentials flow (K3), events (K4).

Every test creates its OWN disposable users through the admin API on the LAN name and deletes them again in a
`finally` block. It never touches `admin`, the real account or any existing user.

    scripts/keycloak-hardening-test.py lockout [--realm homelab|master]
    scripts/keycloak-hardening-test.py reset   [--realm homelab] --mail-to ADDR
    scripts/keycloak-hardening-test.py events  [--realm homelab|master]
    scripts/keycloak-hardening-test.py probe   # read-only: admin API, realm settings, flow list

Needs `requests`: `uv run --no-project --quiet --with requests python scripts/keycloak-hardening-test.py ...`.
Admin password: env KC_ADMIN_PASSWORD, or Vault `secret/homelab/keycloak` (VAULT_ADDR/VAULT_TOKEN set).

lockout   K2: 3 wrong passwords -> locked (attack-detection API says so, and the right password fails too);
          admin unlock; the right password works again. `homelab` uses the browser login form, `master` the
          admin-cli password grant on the LAN name.
reset     K3: user WITHOUT OTP: "forgot password" is denied and no mail is queued; user WITH OTP (TOTP enrolled
          through the CONFIGURE_TOTP required action, code computed here): the OTP form appears, a wrong code is
          refused, the right code leads to "email sent", and the relay log shows the mail to --mail-to.
events    K4: a login creates a LOGIN event, an admin API write creates an admin event with representation, and
          the stored password value is masked.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import html
import os
import re
import secrets
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urljoin

import requests

KC = "https://keycloak.d.lcamaral.com"  # admin API and master realm (LAN name)
PUBLIC = "https://auth.cf.lcamaral.com"  # issuer host of the user realms (what browsers use)
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36"
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> bool:
    results.append((name, ok, detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" -- {detail}" if detail else ""), flush=True)
    return ok


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Admin:
    """Keycloak admin API client; fetches a fresh token when the (1 minute on master) one is about to expire."""

    def __init__(self) -> None:
        self.pw = os.environ.get("KC_ADMIN_PASSWORD") or subprocess.run(
            ["vault", "kv", "get", "-field=admin_password", "secret/homelab/keycloak"],
            capture_output=True, text=True, check=True).stdout.strip()
        self.tok = ""
        self.exp = 0.0

    def token(self) -> str:
        if time.time() > self.exp:
            r = requests.post(f"{KC}/realms/master/protocol/openid-connect/token", timeout=30, data={
                "client_id": "admin-cli", "username": "admin", "password": self.pw, "grant_type": "password"})
            r.raise_for_status()
            self.tok = r.json()["access_token"]
            self.exp = time.time() + 40
        return self.tok

    def call(self, method: str, path: str, **kw) -> requests.Response:
        kw.setdefault("timeout", 30)
        kw.setdefault("headers", {})["Authorization"] = f"Bearer {self.token()}"
        return requests.request(method, f"{KC}/admin/realms{path}", **kw)

    def create_user(self, realm: str, name: str, email: str, password: str, actions: list[str] | None = None) -> str:
        body = {"username": name, "email": email, "firstName": "KC", "lastName": "Test", "enabled": True,
                "emailVerified": True, "requiredActions": actions or [],
                "credentials": [{"type": "password", "value": password, "temporary": False}]}
        r = self.call("POST", f"/{realm}/users", json=body)
        if r.status_code != 201:
            raise SystemExit(f"create user {name} in {realm}: HTTP {r.status_code} {r.text[:200]}")
        return r.headers["Location"].rsplit("/", 1)[1]

    def user(self, realm: str, uid: str) -> dict:
        return self.call("GET", f"/{realm}/users/{uid}").json()

    def delete_user(self, realm: str, uid: str) -> int:
        return self.call("DELETE", f"/{realm}/users/{uid}").status_code


# ---------------------------------------------------------------- browser flow helpers (realm != master)
def auth_url(realm: str) -> str:
    """Authorization request of the built-in public client `account-console` (it requires PKCE)."""
    digest = hashlib.sha256(secrets.token_urlsafe(32).encode()).digest()
    challenge = base64.urlsafe_b64encode(digest).decode().rstrip("=")
    return (f"{PUBLIC}/realms/{realm}/protocol/openid-connect/auth?client_id=account-console&response_type=code"
            f"&scope=openid&redirect_uri={PUBLIC}/realms/{realm}/account/&state=hardening-test"
            f"&code_challenge={challenge}&code_challenge_method=S256")


def form_of(page: str, ident: str | None = None) -> tuple[str, dict]:
    """Return (action URL, hidden inputs) of the first (or the named) <form>."""
    pat = rf'<form[^>]*id="{ident}"[^>]*>' if ident else r"<form[^>]*>"
    m = re.search(pat, page)
    if not m:
        raise RuntimeError("form not found")
    action = html.unescape(re.search(r'action="([^"]+)"', m.group(0)).group(1))
    body = page[m.end():page.find("</form>", m.end())]
    hidden = {html.unescape(n): html.unescape(v) for n, v in re.findall(
        r'<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)"', body)}
    return action, hidden


def password_login(realm: str, username: str, password: str) -> tuple[bool, str]:
    """Browser form login. Returns (success, short description)."""
    s = requests.Session()
    s.headers["User-Agent"] = UA
    page = s.get(auth_url(realm), timeout=30).text
    action, _ = form_of(page, "kc-form-login")
    r = s.post(action, data={"username": username, "password": password, "credentialId": ""},
               allow_redirects=False, timeout=30)
    if r.status_code == 302 and "code=" in r.headers.get("Location", ""):
        return True, "302 with an authorization code"
    err = re.search(r'kc-feedback-text">([^<]+)<', r.text)
    return False, f"HTTP {r.status_code} {html.unescape(err.group(1)).strip() if err else ''}"


def grant_login(realm: str, username: str, password: str) -> tuple[bool, str]:
    """admin-cli password grant (used for master, whose users have no browser clients we want to touch)."""
    r = requests.post(f"{KC}/realms/{realm}/protocol/openid-connect/token", timeout=30, data={
        "client_id": "admin-cli", "username": username, "password": password, "grant_type": "password"})
    return r.status_code == 200, f"HTTP {r.status_code} {r.json().get('error_description', r.json().get('error', ''))}"


def totp(secret_b32: str, at: float | None = None) -> str:
    key = base64.b32decode(secret_b32.replace(" ", "").upper() + "=" * (-len(secret_b32.replace(" ", "")) % 8))
    counter = int((at or time.time()) // 30)
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    off = mac[-1] & 0x0F
    return f"{(struct.unpack('>I', mac[off:off + 4])[0] & 0x7FFFFFFF) % 1000000:06d}"


def wait_next_step() -> None:
    """code_reusable=false: the same TOTP time step cannot be used twice, so wait for the next one."""
    time.sleep(30 - (time.time() % 30) + 1)


# ---------------------------------------------------------------- tests
def test_lockout(a: Admin, realm: str) -> None:
    name = f"kc-lock-{secrets.token_hex(3)}"
    email = f"{name}@lcamaral.com"
    pw = secrets.token_urlsafe(24)
    login = (lambda u, p: grant_login(realm, u, p)) if realm == "master" else (lambda u, p: password_login(realm, u, p))
    uid = a.create_user(realm, name, email, pw)
    uname = a.user(realm, uid)["username"]
    t0 = utcnow()
    try:
        r = a.call("GET", f"/{realm}")
        check(f"{realm}: brute force protection is on", r.json().get("bruteForceProtected") is True,
              f"failureFactor={r.json().get('failureFactor')} wait={r.json().get('waitIncrementSeconds')}s "
              f"permanent={r.json().get('permanentLockout')}")
        ok, d = login(uname, pw)
        check(f"{realm}: correct password works before any failure", ok, d)
        for i in (1, 2, 3):
            ok, d = login(uname, "wrong-" + secrets.token_hex(4))
            st = a.call("GET", f"/{realm}/attack-detection/brute-force/users/{uid}").json()
            print(f"  bad login {i}: {d} | numFailures={st.get('numFailures')} disabled={st.get('disabled')}")
            time.sleep(2)  # stay clear of the quick-login check (failures < 1 s apart)
        st = a.call("GET", f"/{realm}/attack-detection/brute-force/users/{uid}").json()
        check(f"{realm}: user is disabled after 3 failures", st.get("disabled") is True, str(st))
        ok, d = login(uname, pw)
        check(f"{realm}: the CORRECT password is refused while locked", not ok, d)
        u = a.user(realm, uid)
        check(f"{realm}: lockout is temporary (user stays enabled, not permanently disabled)", u.get("enabled") is True)
        r = a.call("DELETE", f"/{realm}/attack-detection/brute-force/users/{uid}")
        check(f"{realm}: admin unlock (attack-detection DELETE)", r.status_code == 204, f"HTTP {r.status_code}")
        ok, d = login(uname, pw)
        check(f"{realm}: correct password works again after unlock", ok, d)
        ev = a.call("GET", f"/{realm}/events", params={"user": uid, "type": "USER_DISABLED_BY_TEMPORARY_LOCKOUT",
                                                       "dateFrom": t0[:10]})
        print(f"  lockout events recorded (needs K4): {len(ev.json()) if ev.status_code == 200 else ev.status_code}")
    finally:
        check(f"{realm}: test user deleted", a.delete_user(realm, uid) == 204)


def enroll_totp(a: Admin, realm: str, uid: str, username: str, password: str) -> str:
    """Log in once with the CONFIGURE_TOTP required action pending, enrol, and return the base32 secret."""
    s = requests.Session()
    s.headers["User-Agent"] = UA
    page = s.get(auth_url(realm), timeout=30).text
    action, _ = form_of(page, "kc-form-login")
    r = s.post(action, data={"username": username, "password": password, "credentialId": ""},
               allow_redirects=True, timeout=30)
    secret = re.search(r'id="kc-totp-secret-key"[^>]*>([^<]+)<', r.text)
    if not secret:
        raise RuntimeError(f"no TOTP setup page after login (HTTP {r.status_code})")
    secret_b32 = html.unescape(secret.group(1)).replace(" ", "").strip()
    action, hidden = form_of(r.text, "kc-totp-settings-form")
    hidden.update({"totp": totp(secret_b32), "userLabel": "hardening-test"})
    r = s.post(action, data=hidden, allow_redirects=False, timeout=30)
    if r.status_code != 302:
        raise RuntimeError(f"TOTP enrolment not accepted: HTTP {r.status_code}")
    return secret_b32


def relay_log(since: str) -> str:
    return subprocess.run(["ssh", "dockermaster", f"docker logs --since {since} postfix-relay 2>&1"],
                          capture_output=True, text=True, timeout=60).stdout


def forgot(realm: str, username: str) -> tuple[requests.Session, requests.Response]:
    s = requests.Session()
    s.headers["User-Agent"] = UA
    page = s.get(auth_url(realm), timeout=30).text
    m = re.search(r'href="([^"]*login-actions/reset-credentials[^"]*)"', page)
    if not m:
        raise RuntimeError("no 'Forgot Password?' link on the login page (reset_password_allowed off?)")
    page = s.get(urljoin(PUBLIC, html.unescape(m.group(1))), timeout=30).text
    action, hidden = form_of(page)
    hidden.update({"username": username})
    return s, s.post(action, data=hidden, timeout=30)


def test_reset(a: Admin, realm: str, mail_to: str) -> None:
    if realm == "master":
        raise SystemExit("reset test is for user realms (master has reset_password_allowed=false)")
    tag = secrets.token_hex(3)
    plain = f"kc-reset-noop-{tag}@lcamaral.com"
    otpu_local, _, domain = mail_to.partition("@")
    otpu = f"{otpu_local.split('+')[0]}+kc-reset-otp-{tag}@{domain}"
    pw = secrets.token_urlsafe(24)
    ids: list[str] = []
    t0 = utcnow()
    try:
        plain_id = a.create_user(realm, plain, plain, pw)
        ids.append(plain_id)
        otp_id = a.create_user(realm, otpu, otpu, pw, actions=["CONFIGURE_TOTP"])
        ids.append(otp_id)
        otp_name = a.user(realm, otp_id)["username"]
        secret = enroll_totp(a, realm, otp_id, otp_name, pw)
        check("otp user: TOTP enrolled through the CONFIGURE_TOTP required action", True)

        # --- user without OTP: denied, no mail
        _, r = forgot(realm, plain)
        denied = bool(re.search(r"kc-error-message|Access denied|not allowed|denied", r.text, re.I))
        has_form = "kc-otp-login-form" in r.text or 'name="otp"' in r.text
        info = re.search(r'kc-feedback-text">([^<]+)<', r.text)
        check("no-otp user: forgot password is DENIED (error page, no OTP form, no 'email sent' message)",
              denied and not has_form and not (info and "email" in info.group(1).lower()),
              (html.unescape(info.group(1)).strip() if info else f"HTTP {r.status_code}"))
        time.sleep(3)
        check("no-otp user: no mail was queued for it", plain not in relay_log(t0))

        # --- unknown user: same treatment as the no-otp user (no enumeration through a different page)
        _, r = forgot(realm, f"kc-reset-nobody-{tag}@lcamaral.com")
        check("unknown user: denied like the no-otp user", bool(re.search(r"kc-error-message|denied", r.text, re.I))
              and "kc-otp-login-form" not in r.text)

        # --- user with OTP: OTP form, wrong code refused, right code -> email sent
        wait_next_step()
        s, r = forgot(realm, otp_name)
        check("otp user: the OTP form is shown after choosing the user", 'name="otp"' in r.text,
              f"HTTP {r.status_code}")
        action, hidden = form_of(r.text)
        hidden.update({"otp": "000000"})
        r = s.post(action, data=hidden, timeout=30)
        check("otp user: a wrong code is refused (form shown again)", 'name="otp"' in r.text)
        t1 = utcnow()
        action, hidden = form_of(r.text)
        hidden.update({"otp": totp(secret)})
        r = s.post(action, data=hidden, timeout=30)
        info = re.search(r'kc-feedback-text">([^<]+)<', r.text)
        check("otp user: the right code leads to the 'email sent' page",
              bool(info) and "email" in info.group(1).lower(),
              html.unescape(info.group(1)).strip() if info else f"HTTP {r.status_code}")
        sent = ""
        for _ in range(10):
            time.sleep(3)
            sent = "\n".join(line for line in relay_log(t1).splitlines() if otp_name in line and "to=<" in line)
            if re.search(r"status=(sent|deferred)|queued", sent) or "from=<" in relay_log(t1):
                break
        check(f"relay: mail to {otp_name} reached postfix-relay (status line)",
              bool(re.search(r"status=(sent|deferred)", sent)), sent.splitlines()[-1][:200] if sent else "no line")
        ev = a.call("GET", f"/{realm}/events", params={"user": otp_id, "type": "SEND_RESET_PASSWORD"})
        print(f"  SEND_RESET_PASSWORD events (needs K4): {len(ev.json()) if ev.status_code == 200 else ev.status_code}")
    finally:
        for uid in ids:
            check(f"{realm}: test user deleted", a.delete_user(realm, uid) == 204)


def test_events(a: Admin, realm: str) -> None:
    name = f"kc-ev-{secrets.token_hex(3)}"
    email = f"{name}@lcamaral.com"
    pw = secrets.token_urlsafe(24)
    t0 = utcnow()
    cfg = a.call("GET", f"/{realm}/events/config").json()
    check(f"{realm}: events config", cfg.get("eventsEnabled") and cfg.get("adminEventsEnabled")
          and cfg.get("adminEventsDetailsEnabled") and cfg.get("eventsExpiration") == 7776000, str({
              k: cfg.get(k) for k in ("eventsEnabled", "eventsExpiration", "adminEventsEnabled",
                                      "adminEventsDetailsEnabled")}))
    uid = a.create_user(realm, name, email, pw)
    uname = a.user(realm, uid)["username"]
    try:
        ok, d = (grant_login(realm, uname, pw) if realm == "master" else password_login(realm, uname, pw))
        check(f"{realm}: login succeeds", ok, d)
        time.sleep(2)
        ev = a.call("GET", f"/{realm}/events", params={"user": uid, "type": "LOGIN", "max": 5}).json()
        check(f"{realm}: a LOGIN event was stored for the test user", len(ev) >= 1, f"{len(ev)} event(s)")
        ad = a.call("GET", f"/{realm}/admin-events", params={"resourceTypes": "USER", "operationTypes": "CREATE",
                                                             "dateFrom": t0[:10], "max": 50}).json()
        mine = [e for e in ad if e.get("resourcePath", "").endswith(uid)]
        check(f"{realm}: the user CREATE is in the admin events, with the representation", bool(mine)
              and bool(mine[0].get("representation")), f"{len(mine)} match(es)")
        if mine and mine[0].get("representation"):
            rep = mine[0]["representation"]
            check(f"{realm}: the password value is not stored in clear text", pw not in rep)
    finally:
        check(f"{realm}: test user deleted", a.delete_user(realm, uid) == 204)


def probe(a: Admin) -> None:
    for realm in ("homelab", "master"):
        r = a.call("GET", f"/{realm}").json()
        print(f"{realm}: brute={r.get('bruteForceProtected')} failureFactor={r.get('failureFactor')} "
              f"wait={r.get('waitIncrementSeconds')} reset={r.get('maxDeltaTimeSeconds')} "
              f"permanent={r.get('permanentLockout')} events={r.get('eventsEnabled')} "
              f"admin={r.get('adminEventsEnabled')} "
              f"resetFlow={r.get('resetCredentialsFlow')!r} smtp={r.get('smtpServer', {}).get('host')!r}")
    check("keycloak admin API reachable on the LAN name", True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("test", choices=["probe", "lockout", "reset", "events"])
    ap.add_argument("--realm", default="homelab")
    ap.add_argument("--mail-to", help="mailbox for the OTP user's reset mail (a +tag is added to the local part)")
    args = ap.parse_args()
    a = Admin()
    if args.test == "probe":
        probe(a)
    elif args.test == "lockout":
        test_lockout(a, args.realm)
    elif args.test == "reset":
        if not args.mail_to:
            raise SystemExit("--mail-to is required for the reset test")
        test_reset(a, args.realm, args.mail_to)
    else:
        test_events(a, args.realm)
    bad = [n for n, ok, _ in results if not ok]
    print(f"\n{len(results) - len(bad)} passed, {len(bad)} failed" + (f": {bad}" if bad else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
