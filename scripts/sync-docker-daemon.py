#!/usr/bin/env python3
"""
Sync repo-managed Docker daemon config to the three Docker hosts.

Source of truth: hosts/<host>/etc/docker/daemon.json
Destination:     /etc/docker/daemon.json   (root:root, 0644)

Hosts (ssh alias == directory name under hosts/):

    dockermaster    Portainer server runs here (local socket, endpoint 3), no agent
    dockerserver-1  portainer-agent, endpoint 9
    dockerserver-2  portainer-agent, endpoint 13

The NAS (Synology) is deliberately not managed here.

Modes:

    scripts/sync-docker-daemon.py                     # dry run, all hosts: JSON diff
    scripts/sync-docker-daemon.py --check             # same, exit 1 if any host differs
    scripts/sync-docker-daemon.py --host ds-2 --apply
    scripts/sync-docker-daemon.py --host ds-2 --apply --restart

--apply (needs --host, one host at a time):
    1. upload the repo file to a temp path on the host
    2. `dockerd --validate --config-file <tmp>`; abort on failure (nothing is installed)
    3. back up the live file to /etc/docker/daemon.json.bak-<ts>
    4. install atomically (same-directory temp file + rename)
    It does NOT restart dockerd. daemon.json is only read at start, so the change
    is inert until the next restart (or --restart).

--restart (needs --apply; always restarts the chosen host, even if the file did not change):
    1. record the running containers and their health
    2. `systemctl restart docker`, wait for the daemon
    3. restart the host's portainer-agent (stale socket otherwise; dockermaster has none,
       its Portainer server container comes back through its restart policy)
    4. verify: same running set, no unhealthy container, the daemon reports the settings
       from the repo file (live-restore, log driver, registry mirrors), and the Portainer
       endpoint status is 1 (up) via the API
    If dockerd does not come back, the backup is restored and dockerd restarted once.
    Any other failed verification exits non-zero and leaves the host as it is.

Restart cost: without live-restore (dockermaster today) every container stops and
starts again, and Portainer is down meanwhile. With live-restore (ds-1, ds-2) containers
keep running.

Sudo: every host uses SUDO_ASKPASS=$HOME/.config/bin/answer (`sudo -A`), as in
scripts/sync-host-network.py. Portainer API auth: admin password from Vault
(`secret/homelab/portainer`) with the Vault token from the macOS Keychain
(`vault-root-token`); VAULT_ADDR defaults to the direct address (the vhost flaps).
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import shlex
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HOSTS_DIR = REPO_ROOT / "hosts"
DEST = "/etc/docker/daemon.json"

PORTAINER_URL = "https://192.168.59.2:9443"
VAULT_ADDR_DEFAULT = "http://192.168.59.25:8200"
VAULT_PORTAINER_PATH = "secret/homelab/portainer"
KEYCHAIN_VAULT_TOKEN_SERVICE = "vault-root-token"

SUDO = "SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A"

DOCKERD_WAIT_S = 120
CONTAINERS_WAIT_S = 240
PORTAINER_WAIT_S = 180


@dataclass(frozen=True)
class Host:
    ssh: str  # ssh alias; also the directory name under hosts/
    endpoint_id: int  # Portainer endpoint id
    agent: str | None  # portainer-agent container name; None = no agent on this host


HOSTS: dict[str, Host] = {
    "dm": Host("dockermaster", 3, None),
    "ds-1": Host("dockerserver-1", 9, "portainer-agent"),
    "ds-2": Host("dockerserver-2", 13, "portainer-agent"),
}


class Fail(Exception):
    pass


# --------------------------------------------------------------------------- ssh


def ssh_run(host: Host, cmd: str, stdin: str | None = None, timeout: int = 120) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["ssh", "-o", "ConnectTimeout=10", host.ssh, cmd],
        input=stdin, capture_output=True, text=True, check=False, timeout=timeout,
    )


def ssh_ok(host: Host, cmd: str, stdin: str | None = None, timeout: int = 120) -> str:
    r = ssh_run(host, cmd, stdin=stdin, timeout=timeout)
    if r.returncode != 0:
        raise Fail(f"{host.ssh}: `{cmd}` failed (rc={r.returncode}): {(r.stderr or r.stdout).strip()}")
    return r.stdout


# ------------------------------------------------------------------------- files


def repo_file(host: Host) -> Path:
    return HOSTS_DIR / host.ssh / "etc" / "docker" / "daemon.json"


def normalize(text: str) -> str:
    return json.dumps(json.loads(text), indent=2, sort_keys=True) + "\n"


def fetch_live(host: Host) -> str | None:
    """Live daemon.json text, or None when the file is absent."""
    r = ssh_run(host, f"test -e {DEST} && cat {DEST}")
    if r.returncode == 1 and not r.stdout:
        return None
    if r.returncode != 0:
        raise Fail(f"{host.ssh}: reading {DEST} failed: {r.stderr.strip()}")
    return r.stdout


def diff_host(label: str, host: Host) -> tuple[bool, str]:
    """Return (differs, printable diff) for repo vs live, compared as normalized JSON."""
    path = repo_file(host)
    if not path.is_file():
        raise Fail(f"{label}: {path.relative_to(REPO_ROOT)} missing in repo")
    want = normalize(path.read_text())
    live_raw = fetch_live(host)
    if live_raw is None:
        return True, f"  {DEST} is missing on {host.ssh}; would CREATE:\n" + "".join(
            f"+ {line}" for line in want.splitlines(keepends=True))
    have = normalize(live_raw)
    if have == want:
        return False, ""
    d = difflib.unified_diff(
        have.splitlines(keepends=True), want.splitlines(keepends=True),
        fromfile=f"live:{host.ssh}:{DEST}", tofile=f"repo:{path.relative_to(REPO_ROOT)}")
    return True, "".join(d)


# ------------------------------------------------------------------------- apply


def apply_file(label: str, host: Host) -> str | None:
    """Validate + back up + install. Returns the backup path (None if nothing changed)."""
    differs, _ = diff_host(label, host)
    if not differs:
        print("  no change to install")
        return None

    content = repo_file(host).read_text()
    tmp = ssh_ok(host, "mktemp /tmp/daemon.json.XXXXXX").strip()
    try:
        ssh_ok(host, f"cat > {tmp}", stdin=content)
        r = ssh_run(host, f"{SUDO} dockerd --validate --config-file {tmp}")
        if r.returncode != 0:
            raise Fail(f"{host.ssh}: dockerd --validate rejected the file: {(r.stderr or r.stdout).strip()}")
        print(f"  dockerd --validate: {(r.stdout or r.stderr).strip()}")

        ts = time.strftime("%Y%m%d-%H%M%S")
        backup = f"{DEST}.bak-{ts}"
        staged = f"{DEST}.new"
        ssh_ok(host, (
            f"set -e; if [ -e {DEST} ]; then {SUDO} cp -p {DEST} {backup}; fi; "
            f"{SUDO} install -o root -g root -m 0644 {tmp} {staged}; "
            f"{SUDO} mv -f {staged} {DEST}"))
        print(f"  installed {DEST} (backup: {backup})")
        return backup
    finally:
        ssh_run(host, f"rm -f {tmp}")


# ----------------------------------------------------------------------- restart


def running_set(host: Host) -> dict[str, str]:
    """{container name: health ('' if no healthcheck)} for running containers."""
    out = ssh_ok(host, "docker ps --format '{{.Names}}' | sort")
    names = [n for n in out.split() if n]
    if not names:
        return {}
    fmt = "{{.Name}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}"
    out = ssh_ok(host, f"docker inspect -f '{fmt}' " + " ".join(shlex.quote(n) for n in names))
    res: dict[str, str] = {}
    for line in out.splitlines():
        name, _, health = line.partition("|")
        res[name.lstrip("/")] = health.strip()
    return res


def wait_for(what: str, fn, timeout_s: int, interval_s: int = 3):
    deadline = time.time() + timeout_s
    last = None
    while time.time() < deadline:
        try:
            ok, last = fn()
        except (Fail, subprocess.TimeoutExpired, OSError) as e:
            ok, last = False, str(e)
        if ok:
            return last
        time.sleep(interval_s)
    raise Fail(f"timed out after {timeout_s}s waiting for {what} (last: {last})")


def docker_info(host: Host) -> dict:
    r = ssh_run(host, "docker info --format '{{json .}}'", timeout=30)
    if r.returncode != 0:
        raise Fail(r.stderr.strip())
    return json.loads(r.stdout)


def check_daemon_settings(host: Host, info: dict) -> list[str]:
    """Compare what the running daemon reports with the keys in the repo file."""
    want = json.loads(repo_file(host).read_text())
    problems: list[str] = []
    if "live-restore" in want and bool(want["live-restore"]) != bool(info.get("LiveRestoreEnabled")):
        problems.append(f"live-restore: want {want['live-restore']}, daemon has {info.get('LiveRestoreEnabled')}")
    if "log-driver" in want and want["log-driver"] != info.get("LoggingDriver"):
        problems.append(f"log-driver: want {want['log-driver']}, daemon has {info.get('LoggingDriver')}")
    if "registry-mirrors" in want:
        have = sorted(m.rstrip("/") for m in (info.get("RegistryConfig") or {}).get("Mirrors") or [])
        if sorted(m.rstrip("/") for m in want["registry-mirrors"]) != have:
            problems.append(f"registry-mirrors: want {want['registry-mirrors']}, daemon has {have}")
    return problems


def portainer_jwt() -> str:
    env = dict(os.environ)
    env.setdefault("VAULT_ADDR", VAULT_ADDR_DEFAULT)
    if "VAULT_TOKEN" not in env:
        user = subprocess.check_output(["whoami"], text=True).strip()
        env["VAULT_TOKEN"] = subprocess.check_output(
            ["security", "find-generic-password", "-w", "-s", KEYCHAIN_VAULT_TOKEN_SERVICE, "-a", user],
            text=True).strip()
    pw = subprocess.check_output(
        ["vault", "kv", "get", "-field=admin_password", VAULT_PORTAINER_PATH], text=True, env=env).strip()
    code, body = portainer_request("POST", "/api/auth", body={"username": "admin", "password": pw})
    if code != 200:
        raise Fail(f"portainer auth failed ({code})")
    return json.loads(body)["jwt"]


def portainer_request(method: str, path: str, jwt: str | None = None, body: dict | None = None):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(f"{PORTAINER_URL}{path}", method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(body).encode()
    if jwt:
        req.add_header("Authorization", f"Bearer {jwt}")
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def endpoint_up(host: Host) -> tuple[bool, str]:
    # Re-authenticate each poll: on dockermaster the Portainer server itself restarts.
    try:
        jwt = portainer_jwt()
        code, body = portainer_request("GET", f"/api/endpoints/{host.endpoint_id}", jwt=jwt)
    except (urllib.error.URLError, OSError, subprocess.CalledProcessError, Fail) as e:
        return False, f"portainer unreachable: {e}"
    if code != 200:
        return False, f"GET endpoint {host.endpoint_id} -> {code}"
    status = json.loads(body).get("Status")
    if status != 1:
        return False, f"endpoint {host.endpoint_id} Status={status}"
    # Status can read 1 while the agent still holds a stale docker.sock; the proxied call proves it.
    code, _ = portainer_request("GET", f"/api/endpoints/{host.endpoint_id}/docker/containers/json", jwt=jwt)
    return code == 200, f"endpoint {host.endpoint_id} Status=1, proxied docker API -> {code}"


def restart_and_verify(label: str, host: Host, backup: str | None) -> None:
    before = running_set(host)
    print(f"  {len(before)} containers running before restart")

    print("  systemctl restart docker ...")
    ssh_ok(host, f"{SUDO} systemctl restart docker", timeout=300)
    try:
        info = wait_for("dockerd", lambda: (True, docker_info(host)), DOCKERD_WAIT_S)
    except Fail as e:
        if backup:
            print(f"  dockerd did not come back ({e}); restoring {backup} and restarting once")
            ssh_ok(host, f"{SUDO} cp -p {backup} {DEST} && {SUDO} systemctl restart docker", timeout=300)
        raise Fail(f"{host.ssh}: dockerd not healthy after restart" + (" (backup restored)" if backup else ""))
    print("  dockerd is up")

    if host.agent:
        print(f"  restarting {host.agent} ...")
        ssh_ok(host, f"docker restart {shlex.quote(host.agent)}")
    else:
        print("  no portainer-agent on this host (Portainer server returns via its restart policy)")

    def containers_back():
        now = running_set(host)
        missing = sorted(set(before) - set(now))
        bad = sorted(n for n, h in now.items() if h == "unhealthy")
        return (not missing and not bad), f"missing={missing} unhealthy={bad}"

    wait_for("containers to return and be healthy", containers_back, CONTAINERS_WAIT_S, interval_s=5)
    after = running_set(host)
    extra = sorted(set(after) - set(before))
    print(f"  running set restored ({len(after)} containers; new since before: {extra or 'none'})")

    problems = check_daemon_settings(host, info)
    if problems:
        raise Fail(f"{host.ssh}: daemon settings differ from the repo file: {'; '.join(problems)}")
    print("  daemon settings match the repo file")

    detail = wait_for("Portainer endpoint up", lambda: endpoint_up(host), PORTAINER_WAIT_S, interval_s=5)
    print(f"  portainer: {detail}")


# -------------------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", choices=list(HOSTS), help="limit to one host (required with --apply)")
    ap.add_argument("--apply", action="store_true", help="validate, back up and install (no restart)")
    ap.add_argument("--restart", action="store_true",
                    help="with --apply: restart dockerd + portainer-agent and verify")
    ap.add_argument("--check", action="store_true", help="dry run; exit 1 if any host differs")
    args = ap.parse_args()

    if args.apply and not args.host:
        ap.error("--apply requires --host (one host at a time)")
    if args.restart and not args.apply:
        ap.error("--restart requires --apply")
    if args.check and args.apply:
        ap.error("--check is a dry-run mode")

    targets = [args.host] if args.host else list(HOSTS)
    any_diff = False
    try:
        for label in targets:
            host = HOSTS[label]
            print(f"\n=== {label} ({host.ssh}) ===")
            differs, text = diff_host(label, host)
            any_diff |= differs
            print(text.rstrip() if differs else "  no diff (repo == live)")
            if args.apply:
                backup = apply_file(label, host)
                if args.restart:
                    restart_and_verify(label, host, backup)
                elif backup:
                    print("  NOT restarted: the change is inert until dockerd restarts (use --restart)")
    except Fail as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        return 2

    if not args.apply:
        print("\nAll hosts match." if not any_diff else "\nDiffs found. Re-run with --host <h> --apply.")
    return 1 if (args.check and any_diff) else 0


if __name__ == "__main__":
    sys.exit(main())
