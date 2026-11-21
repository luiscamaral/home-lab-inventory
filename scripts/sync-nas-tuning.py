#!/usr/bin/env python3
"""
Sync repo-managed kernel tuning (sysctl) to the Synology NAS.

Source of truth: nas/tuning/sysctl.yml
Apply mechanism: render a boot hook into /usr/local/etc/rc.d/<name>.sh and run
                 it once (`<hook> start`) to apply live. DSM's pkg-rclocal.sh
                 runs every /usr/local/etc/rc.d/*.sh with `start` at boot, so
                 the values persist across reboots and DSM updates without
                 touching DSM-regenerated files (/etc/sysctl.conf).

Why a custom script: DSM has no API/Terraform provider for kernel tunables, and
hand-placing the hook is forbidden (operating rule #1). This mirrors the
scripts/sync-*.py convention (dry-run by default, --apply to push).

Access: `ssh nas` logs in as an unprivileged admin; installing into rc.d and
writing sysctls need root. The sudo password is read from the macOS Keychain
(`nas-sudo-password`, fallback Vault secret/homelab/nas-sudo-password) only for
--apply/--rollback, and is passed to `sudo -S` on stdin — never on a command
line, never printed.

Workflow:
    scripts/sync-nas-tuning.py              # dry-run: hook diff + live vs desired
    scripts/sync-nas-tuning.py --check      # dry-run, exit 1 on any drift
    scripts/sync-nas-tuning.py --apply      # install hook, apply, verify
    scripts/sync-nas-tuning.py --rollback   # restore DSM defaults, remove hook
"""

from __future__ import annotations

import argparse
import difflib
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Optional

try:
    import yaml  # preferred; may be absent on a bare system python
except ModuleNotFoundError:  # pragma: no cover - exercised on bare pythons
    yaml = None

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = REPO_ROOT / "nas" / "tuning" / "sysctl.yml"
CONFIG_REL = "nas/tuning/sysctl.yml"

SSH_TARGET = "nas"
SSH_TIMEOUT = 60
SYSCTL_BIN = "/usr/sbin/sysctl"
KEYCHAIN_SERVICE = "nas-sudo-password"
VAULT_PATH = "secret/homelab/nas-sudo-password"

KEY_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")
HOOK_PATH_RE = re.compile(r"^/usr/local/etc/rc\.d/[A-Za-z0-9_.-]+\.sh$")
# OpenSSH on DSM prints a PQ-kex warning on every connection; not an error.
SSH_NOISE_RE = re.compile(r"^\*\* .*$", re.MULTILINE)


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class Config:
    script_path: str
    sysctl: Dict[str, int]
    restore: Dict[str, int]


# --------------------------------------------------------------------------
# Config parsing / validation (pure)
# --------------------------------------------------------------------------


def _scalar(raw: str):
    v = raw.split("#", 1)[0].strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if v in ("true", "false"):
        return v == "true"
    return v


def mini_parse(text: str) -> dict:
    """Parse the two-level mapping shape of sysctl.yml without PyYAML.

    Supports top-level `key: scalar` and `key:` followed by indented
    `child: scalar` lines; comments and the `---` marker are ignored.
    Anything else is rejected rather than guessed at.
    """
    data: dict = {}
    section: Optional[str] = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.split("#", 1)[0].strip() or raw.strip() == "---":
            continue
        indented = raw[0] in " \t"
        if ":" not in raw:
            raise ConfigError(f"line {lineno}: expected 'key: value'")
        key, value = raw.split(":", 1)
        key = key.strip()
        value_clean = value.split("#", 1)[0].strip()
        if not indented:
            if value_clean:
                data[key] = _scalar(value)
                section = None
            else:
                data[key] = {}
                section = key
        else:
            if section is None:
                raise ConfigError(f"line {lineno}: indented key outside a section")
            data[section][key] = _scalar(value)
    return data


def load_config_text(text: str) -> Config:
    data = yaml.safe_load(text) if yaml is not None else mini_parse(text)
    return validate(data)


def _validate_map(name: str, value) -> Dict[str, int]:
    if not isinstance(value, dict) or not value:
        raise ConfigError(f"'{name}' must be a non-empty mapping")
    out: Dict[str, int] = {}
    for k, v in value.items():
        if not isinstance(k, str) or not KEY_RE.match(k):
            raise ConfigError(f"{name}: invalid sysctl key {k!r}")
        # bool is an int subclass — reject it explicitly.
        if isinstance(v, bool) or not isinstance(v, int) or v < 0:
            raise ConfigError(f"{name}.{k}: value must be a non-negative integer")
        out[k] = v
    return out


def validate(data) -> Config:
    if not isinstance(data, dict):
        raise ConfigError("config must be a mapping")
    unknown = set(data) - {"script_path", "sysctl", "restore"}
    if unknown:
        raise ConfigError(f"unknown top-level keys: {sorted(unknown)}")
    path = data.get("script_path")
    if not isinstance(path, str) or not HOOK_PATH_RE.match(path):
        raise ConfigError("script_path must be /usr/local/etc/rc.d/<name>.sh")
    return Config(
        script_path=path,
        sysctl=_validate_map("sysctl", data.get("sysctl")),
        restore=_validate_map("restore", data.get("restore")),
    )


# --------------------------------------------------------------------------
# Rendering (pure)
# --------------------------------------------------------------------------


def _kv_args(values: Dict[str, int]) -> str:
    return " ".join(f"{k}={v}" for k, v in values.items())


def render_hook(cfg: Config) -> str:
    keys = " ".join(list(cfg.sysctl) + [k for k in cfg.restore if k not in cfg.sysctl])
    return f"""#!/bin/sh
# Managed by home-lab-inventory IaC -- DO NOT EDIT ON THE NAS.
# Source: {CONFIG_REL}
# Apply:  scripts/sync-nas-tuning.py --apply
# Run at boot by DSM pkg-rclocal.sh as `$0 start`.

SYSCTL={SYSCTL_BIN}
TAG=iac-nas-tuning

set_all() {{
    rc=0
    for kv in "$@"; do
        if ! "$SYSCTL" -q -w "$kv"; then
            logger -t "$TAG" "failed to set $kv"
            rc=1
        fi
    done
    return "$rc"
}}

case "${{1:-}}" in
    start)
        set_all {_kv_args(cfg.sysctl)}
        rc=$?
        logger -t "$TAG" "start: applied {_kv_args(cfg.sysctl)} (rc=$rc)"
        exit "$rc"
        ;;
    restore)
        set_all {_kv_args(cfg.restore)}
        exit $?
        ;;
    status)
        "$SYSCTL" {keys}
        ;;
    stop)
        : # nothing to tear down at shutdown
        ;;
    *)
        echo "usage: $0 {{start|stop|status|restore}}" >&2
        exit 2
        ;;
esac
"""


def parse_sysctl_output(text: str) -> Dict[str, int]:
    """Parse `sysctl k1 k2` output (`key = value` lines)."""
    out: Dict[str, int] = {}
    for line in text.splitlines():
        m = re.match(r"^\s*([a-z0-9_.]+)\s*=\s*(-?\d+)\s*$", line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


@dataclass
class Plan:
    hook_status: str  # "up to date" | "CREATE" | "UPDATE"
    hook_diff: List[str]
    live: Dict[str, Optional[int]]
    drift: Dict[str, int]

    @property
    def changes(self) -> int:
        return (self.hook_status != "up to date") + len(self.drift)


def make_plan(cfg: Config, rendered: str, remote_hook: Optional[str],
              live: Dict[str, int]) -> Plan:
    if remote_hook == rendered:
        status, diff = "up to date", []
    else:
        status = "CREATE" if remote_hook is None else "UPDATE"
        diff = list(difflib.unified_diff(
            (remote_hook or "").splitlines(), rendered.splitlines(),
            fromfile=f"nas:{cfg.script_path}", tofile="rendered", lineterm=""))
    live_desired = {k: live.get(k) for k in cfg.sysctl}
    drift = {k: v for k, v in cfg.sysctl.items() if live.get(k) != v}
    return Plan(status, diff, live_desired, drift)


# --------------------------------------------------------------------------
# Remote access
# --------------------------------------------------------------------------

Runner = Callable[..., subprocess.CompletedProcess]


def _clean(stderr: str) -> str:
    return SSH_NOISE_RE.sub("", stderr or "").strip()


class Remote:
    def __init__(self, runner: Runner = subprocess.run,
                 password_fn: Optional[Callable[[], str]] = None):
        self._run = runner
        self._password_fn = password_fn or get_sudo_password
        self._password: Optional[str] = None

    def ssh(self, cmd: str, stdin: Optional[str] = None) -> subprocess.CompletedProcess:
        try:
            return self._run(
                ["ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
                 SSH_TARGET, cmd],
                input=stdin, capture_output=True, text=True,
                check=False, timeout=SSH_TIMEOUT)
        except subprocess.TimeoutExpired:
            sys.exit(f"error: ssh {SSH_TARGET} timed out after {SSH_TIMEOUT}s")

    def sudo(self, cmd: str) -> subprocess.CompletedProcess:
        if self._password is None:
            self._password = self._password_fn()
        return self.ssh(f"sudo -S -p '' sh -c {shlex.quote(cmd)}",
                        stdin=self._password + "\n")

    def read_file(self, path: str) -> Optional[str]:
        q = shlex.quote(path)
        r = self.ssh(f"if [ -f {q} ]; then cat {q}; else exit 3; fi")
        if r.returncode == 3:
            return None
        if r.returncode != 0:
            sys.exit(f"error: reading nas:{path} failed: {_clean(r.stderr)}")
        return r.stdout

    def read_sysctl(self, keys: List[str]) -> Dict[str, int]:
        r = self.ssh(f"{SYSCTL_BIN} " + " ".join(shlex.quote(k) for k in keys))
        if r.returncode != 0:
            sys.exit(f"error: reading sysctls failed: {_clean(r.stderr)}")
        return parse_sysctl_output(r.stdout)

    def install_hook(self, path: str, content: str) -> None:
        stage = self.ssh(
            "umask 077; t=$(mktemp /tmp/iac-nas-tuning.XXXXXX) && cat > \"$t\" "
            "&& echo \"$t\"", stdin=content)
        tmp = stage.stdout.strip()
        if stage.returncode != 0 or not tmp.startswith("/tmp/iac-nas-tuning."):
            sys.exit(f"error: staging hook failed: {_clean(stage.stderr)}")
        q_tmp, q_path = shlex.quote(tmp), shlex.quote(path)
        r = self.sudo(f"install -o root -g root -m 0755 {q_tmp} {q_path}; "
                      f"rc=$?; rm -f {q_tmp}; exit $rc")
        if r.returncode != 0:
            sys.exit(f"error: installing {path} failed: {_clean(r.stderr)}")

    def run_hook(self, path: str, action: str) -> None:
        r = self.sudo(f"{shlex.quote(path)} {shlex.quote(action)}")
        if r.returncode != 0:
            sys.exit(f"error: `{path} {action}` failed (rc={r.returncode}): "
                     f"{_clean(r.stderr)}")

    def set_sysctls(self, values: Dict[str, int]) -> None:
        r = self.sudo(f"{SYSCTL_BIN} -q -w {_kv_args(values)}")
        if r.returncode != 0:
            sys.exit(f"error: sysctl -w failed: {_clean(r.stderr)}")

    def remove(self, path: str) -> None:
        r = self.sudo(f"rm -f {shlex.quote(path)}")
        if r.returncode != 0:
            sys.exit(f"error: removing {path} failed: {_clean(r.stderr)}")


def get_sudo_password() -> str:
    """Keychain first, Vault second. Never logged."""
    r = subprocess.run(
        ["security", "find-generic-password", "-w", "-s", KEYCHAIN_SERVICE],
        capture_output=True, text=True, check=False)
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.rstrip("\n")
    r = subprocess.run(
        ["vault", "kv", "get", "-field=password", VAULT_PATH],
        capture_output=True, text=True, check=False)
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.rstrip("\n")
    sys.exit(f"error: NAS sudo password not found in Keychain "
             f"({KEYCHAIN_SERVICE}) or Vault ({VAULT_PATH})")


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def print_plan(cfg: Config, plan: Plan) -> None:
    print(f"  hook {cfg.script_path}: {plan.hook_status}")
    for line in plan.hook_diff:
        print(f"    {line}")
    for k, want in cfg.sysctl.items():
        have = plan.live.get(k)
        mark = "ok" if have == want else "CHANGE"
        print(f"  {k}: live={have} desired={want}  [{mark}]")


def verify_live(remote: Remote, values: Dict[str, int]) -> bool:
    live = remote.read_sysctl(list(values))
    ok = True
    for k, want in values.items():
        if live.get(k) != want:
            print(f"  VERIFY FAIL {k}: live={live.get(k)} expected={want}")
            ok = False
    return ok


def cmd_sync(cfg: Config, remote: Remote, apply: bool, check: bool) -> int:
    rendered = render_hook(cfg)
    plan = make_plan(cfg, rendered, remote.read_file(cfg.script_path),
                     remote.read_sysctl(list(cfg.sysctl)))
    print_plan(cfg, plan)

    if plan.changes == 0:
        print("NAS tuning up to date.")
        return 0
    if not apply:
        print(f"\n{plan.changes} change(s) pending — re-run with --apply.")
        return 1 if check else 0

    if plan.hook_status != "up to date":
        remote.install_hook(cfg.script_path, rendered)
        print(f"  INSTALLED {cfg.script_path}")
    remote.run_hook(cfg.script_path, "start")
    print(f"  RAN {cfg.script_path} start")

    ok = remote.read_file(cfg.script_path) == rendered
    if not ok:
        print("  VERIFY FAIL hook content differs from rendered")
    ok = verify_live(remote, cfg.sysctl) and ok
    print("Verified." if ok else "Verification FAILED.")
    return 0 if ok else 1


def cmd_rollback(cfg: Config, remote: Remote) -> int:
    remote.set_sysctls(cfg.restore)
    print(f"  RESTORED {_kv_args(cfg.restore)}")
    remote.remove(cfg.script_path)
    print(f"  REMOVED {cfg.script_path}")
    ok = verify_live(remote, cfg.restore)
    if remote.read_file(cfg.script_path) is not None:
        print(f"  VERIFY FAIL {cfg.script_path} still present")
        ok = False
    print("Rolled back." if ok else "Rollback verification FAILED.")
    return 0 if ok else 1


def main(argv: Optional[List[str]] = None, remote: Optional[Remote] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true",
                      help="install hook, apply live, verify")
    mode.add_argument("--check", action="store_true",
                      help="dry-run; exit 1 if anything would change")
    mode.add_argument("--rollback", action="store_true",
                      help="restore DSM defaults and remove the hook")
    parser.add_argument("--config", type=Path, default=CONFIG_PATH,
                        help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    try:
        cfg = load_config_text(args.config.read_text())
    except (OSError, ConfigError) as exc:
        sys.exit(f"error: {args.config}: {exc}")

    remote = remote or Remote()
    if args.rollback:
        return cmd_rollback(cfg, remote)
    return cmd_sync(cfg, remote, apply=args.apply, check=args.check)


if __name__ == "__main__":
    sys.exit(main())
