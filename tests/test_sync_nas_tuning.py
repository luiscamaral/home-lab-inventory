"""Unit tests for scripts/sync-nas-tuning.py (no network, no NAS access)."""

from __future__ import annotations

import importlib.util
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "scripts" / "sync-nas-tuning.py"
CONFIG = REPO_ROOT / "nas" / "tuning" / "sysctl.yml"

spec = importlib.util.spec_from_file_location("sync_nas_tuning", SCRIPT)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod  # dataclasses resolve annotations via sys.modules
spec.loader.exec_module(mod)

VALID = """---
script_path: /usr/local/etc/rc.d/zz-test.sh  # trailing comment
sysctl:
  vm.dirty_background_bytes: 67108864
  vm.dirty_bytes: 268435456
restore:
  vm.dirty_background_ratio: 10
  vm.dirty_ratio: 20
"""


@pytest.fixture
def cfg():
    return mod.load_config_text(VALID)


# ---------------------------------------------------------------- config ---


def test_repo_config_loads_and_is_sane():
    c = mod.load_config_text(CONFIG.read_text())
    assert c.script_path.startswith("/usr/local/etc/rc.d/")
    assert c.sysctl["vm.dirty_background_bytes"] < c.sysctl["vm.dirty_bytes"]
    assert set(c.restore) == {"vm.dirty_ratio", "vm.dirty_background_ratio"}


def test_mini_parser_matches_pyyaml_on_repo_config():
    yaml = pytest.importorskip("yaml")
    text = CONFIG.read_text()
    assert mod.mini_parse(text) == yaml.safe_load(text)


def test_mini_parser_alone_produces_valid_config():
    c = mod.validate(mod.mini_parse(VALID))
    assert c.sysctl == {"vm.dirty_background_bytes": 67108864,
                        "vm.dirty_bytes": 268435456}
    assert c.script_path == "/usr/local/etc/rc.d/zz-test.sh"


@pytest.mark.parametrize("bad, msg", [
    (VALID.replace("vm.dirty_bytes:", "vm.dirty_bytes;rm -rf /:"), "invalid sysctl key"),
    (VALID.replace("268435456", "'1; reboot'"), "non-negative integer"),
    (VALID.replace("268435456", "-1"), "non-negative integer"),
    (VALID.replace("268435456", "true"), "non-negative integer"),
    (VALID.replace("/usr/local/etc/rc.d/zz-test.sh", "/etc/sysctl.conf"), "script_path"),
    (VALID.replace("zz-test.sh", "../../../etc/x.sh"), "script_path"),
    (VALID + "extra: 1\n", "unknown top-level"),
    ("script_path: /usr/local/etc/rc.d/a.sh\nsysctl:\nrestore:\n  vm.x: 1\n", "non-empty"),
])
def test_validate_rejects(bad, msg):
    with pytest.raises(mod.ConfigError, match=msg):
        mod.load_config_text(bad)


def test_mini_parser_rejects_orphan_indent():
    with pytest.raises(mod.ConfigError, match="outside a section"):
        mod.mini_parse("  vm.x: 1\n")


# ---------------------------------------------------------------- render ---


def test_render_is_deterministic_and_contains_values(cfg):
    a, b = mod.render_hook(cfg), mod.render_hook(cfg)
    assert a == b
    assert a.startswith("#!/bin/sh\n")
    assert "vm.dirty_background_bytes=67108864 vm.dirty_bytes=268435456" in a
    assert "vm.dirty_background_ratio=10 vm.dirty_ratio=20" in a
    assert "DO NOT EDIT ON THE NAS" in a


def test_rendered_hook_passes_sh_n(cfg, tmp_path):
    hook = tmp_path / "hook.sh"
    hook.write_text(mod.render_hook(cfg))
    subprocess.run(["sh", "-n", str(hook)], check=True)


@pytest.mark.skipif(shutil.which("shellcheck") is None, reason="shellcheck absent")
def test_rendered_hook_passes_shellcheck(cfg, tmp_path):
    hook = tmp_path / "hook.sh"
    hook.write_text(mod.render_hook(cfg))
    subprocess.run(["shellcheck", "-s", "sh", str(hook)], check=True)


def _fake_env(cfg, tmp_path, fail_key=None):
    """Render the hook against a fake sysctl that logs its args."""
    log = tmp_path / "calls.log"
    fake = tmp_path / "sysctl"
    fail = f'case "$*" in *{fail_key}*) exit 1;; esac\n' if fail_key else ""
    fake.write_text(f'#!/bin/sh\n{fail}echo "$*" >> {log}\n')
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
    hook = tmp_path / "hook.sh"
    hook.write_text(mod.render_hook(cfg).replace(mod.SYSCTL_BIN, str(fake)))
    hook.chmod(0o755)
    # Neutralise logger so tests don't write to the host syslog.
    bindir = tmp_path / "bin"
    bindir.mkdir()
    (bindir / "logger").write_text("#!/bin/sh\nexit 0\n")
    (bindir / "logger").chmod(0o755)
    env = {**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}"}
    return hook, log, env


def test_hook_start_applies_in_order(cfg, tmp_path):
    hook, log, env = _fake_env(cfg, tmp_path)
    r = subprocess.run([str(hook), "start"], env=env, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert log.read_text().splitlines() == [
        "-q -w vm.dirty_background_bytes=67108864",
        "-q -w vm.dirty_bytes=268435456",
    ]


def test_hook_restore_and_stop_and_usage(cfg, tmp_path):
    hook, log, env = _fake_env(cfg, tmp_path)
    assert subprocess.run([str(hook), "restore"], env=env).returncode == 0
    assert log.read_text().splitlines() == [
        "-q -w vm.dirty_background_ratio=10", "-q -w vm.dirty_ratio=20"]
    assert subprocess.run([str(hook), "stop"], env=env).returncode == 0
    assert subprocess.run([str(hook)], env=env, capture_output=True).returncode == 2


def test_hook_start_continues_and_fails_on_bad_key(cfg, tmp_path):
    hook, log, env = _fake_env(cfg, tmp_path, fail_key="dirty_background_bytes")
    r = subprocess.run([str(hook), "start"], env=env)
    assert r.returncode == 1
    # second key still attempted after the first failed
    assert log.read_text().splitlines() == ["-q -w vm.dirty_bytes=268435456"]


# ------------------------------------------------------------------ plan ---


def test_parse_sysctl_output():
    out = "vm.dirty_bytes = 0\nvm.dirty_ratio = 20\nsysctl: noise\n"
    assert mod.parse_sysctl_output(out) == {"vm.dirty_bytes": 0, "vm.dirty_ratio": 20}


def test_plan_up_to_date(cfg):
    r = mod.render_hook(cfg)
    p = mod.make_plan(cfg, r, r, dict(cfg.sysctl))
    assert p.changes == 0 and p.hook_status == "up to date"


def test_plan_create_and_drift(cfg):
    p = mod.make_plan(cfg, mod.render_hook(cfg), None, {"vm.dirty_bytes": 0})
    assert p.hook_status == "CREATE"
    assert p.drift == cfg.sysctl
    assert p.changes == 3


def test_plan_update_has_diff(cfg):
    p = mod.make_plan(cfg, mod.render_hook(cfg), "#!/bin/sh\nold\n", dict(cfg.sysctl))
    assert p.hook_status == "UPDATE" and any(d.startswith("-old") for d in p.hook_diff)


# ------------------------------------------------------ commands (fake) ---


class FakeRemote(mod.Remote):
    """In-memory NAS: a file table plus a sysctl table with kernel semantics
    (writing a *_ratio zeroes its *_bytes twin and vice versa)."""

    TWINS = {"vm.dirty_ratio": "vm.dirty_bytes",
             "vm.dirty_background_ratio": "vm.dirty_background_bytes"}

    def __init__(self, sysctls, files=None, break_apply=False):
        self.files = dict(files or {})
        self.sysctls = dict(sysctls)
        self.calls = []
        self.break_apply = break_apply

    def _write(self, k, v):
        self.sysctls[k] = v
        for a, b in self.TWINS.items():
            if k == a:
                self.sysctls[b] = 0
            if k == b:
                self.sysctls[a] = 0

    def read_file(self, path):
        return self.files.get(path)

    def read_sysctl(self, keys):
        return {k: self.sysctls[k] for k in keys if k in self.sysctls}

    def install_hook(self, path, content):
        self.calls.append(("install", path))
        self.files[path] = content

    def run_hook(self, path, action):
        self.calls.append(("run", path, action))
        if not self.break_apply:
            for k, v in mod.load_config_text(VALID).sysctl.items():
                self._write(k, v)

    def set_sysctls(self, values):
        self.calls.append(("set", dict(values)))
        for k, v in values.items():
            self._write(k, v)

    def remove(self, path):
        self.calls.append(("rm", path))
        self.files.pop(path, None)


DSM_DEFAULTS = {"vm.dirty_ratio": 20, "vm.dirty_background_ratio": 10,
                "vm.dirty_bytes": 0, "vm.dirty_background_bytes": 0}


def _write_cfg(tmp_path):
    p = tmp_path / "sysctl.yml"
    p.write_text(VALID)
    return ["--config", str(p)]


def test_dry_run_changes_nothing(tmp_path, capsys):
    fr = FakeRemote(DSM_DEFAULTS)
    assert mod.main(_write_cfg(tmp_path), remote=fr) == 0
    assert fr.calls == [] and fr.files == {}
    assert "3 change(s) pending" in capsys.readouterr().out


def test_check_exits_1_on_drift(tmp_path):
    assert mod.main(_write_cfg(tmp_path) + ["--check"], remote=FakeRemote(DSM_DEFAULTS)) == 1


def test_apply_then_idempotent(tmp_path, cfg):
    fr = FakeRemote(DSM_DEFAULTS)
    assert mod.main(_write_cfg(tmp_path) + ["--apply"], remote=fr) == 0
    assert fr.calls == [("install", cfg.script_path), ("run", cfg.script_path, "start")]
    assert fr.files[cfg.script_path] == mod.render_hook(cfg)
    assert fr.sysctls["vm.dirty_bytes"] == 268435456
    fr.calls.clear()
    assert mod.main(_write_cfg(tmp_path) + ["--apply"], remote=fr) == 0
    assert fr.calls == []  # nothing to do second time
    assert mod.main(_write_cfg(tmp_path) + ["--check"], remote=fr) == 0


def test_apply_reports_failed_verification(tmp_path):
    fr = FakeRemote(DSM_DEFAULTS, break_apply=True)
    assert mod.main(_write_cfg(tmp_path) + ["--apply"], remote=fr) == 1


def test_apply_reruns_hook_when_only_live_drifted(tmp_path, cfg):
    fr = FakeRemote(DSM_DEFAULTS, files={cfg.script_path: mod.render_hook(cfg)})
    assert mod.main(_write_cfg(tmp_path) + ["--apply"], remote=fr) == 0
    assert fr.calls == [("run", cfg.script_path, "start")]


def test_rollback_restores_defaults_and_removes_hook(tmp_path, cfg):
    fr = FakeRemote(DSM_DEFAULTS)
    mod.main(_write_cfg(tmp_path) + ["--apply"], remote=fr)
    assert mod.main(_write_cfg(tmp_path) + ["--rollback"], remote=fr) == 0
    assert fr.sysctls == DSM_DEFAULTS
    assert cfg.script_path not in fr.files


# ------------------------------------------------- real Remote plumbing ---


def test_sudo_password_only_on_stdin():
    seen = []

    def runner(argv, **kw):
        seen.append((argv, kw.get("input")))
        return subprocess.CompletedProcess(argv, 0, "", "")

    secret = "s3cr3t-pw"  # noqa: S105 - test fixture, not a credential
    r = mod.Remote(runner=runner, password_fn=lambda: secret)
    r.set_sysctls({"vm.dirty_bytes": 1})
    r.run_hook("/usr/local/etc/rc.d/zz-test.sh", "start")
    for argv, stdin in seen:
        assert all(secret not in a for a in argv)
        assert stdin == secret + "\n"
        assert argv[:2] == ["ssh", "-o"] and "nas" in argv


def test_password_fetched_once():
    calls = []

    def pw():
        calls.append(1)
        return "x"

    r = mod.Remote(runner=lambda a, **k: subprocess.CompletedProcess(a, 0, "", ""),
                   password_fn=pw)
    r.set_sysctls({"vm.dirty_bytes": 1})
    r.remove("/usr/local/etc/rc.d/zz-test.sh")
    assert len(calls) == 1


def test_read_file_missing_returns_none():
    r = mod.Remote(runner=lambda a, **k: subprocess.CompletedProcess(a, 3, "", ""))
    assert r.read_file("/usr/local/etc/rc.d/zz-test.sh") is None


def test_install_hook_rejects_bad_stage_path():
    r = mod.Remote(runner=lambda a, **k: subprocess.CompletedProcess(a, 0, "/etc/evil\n", ""),
                   password_fn=lambda: "x")
    with pytest.raises(SystemExit, match="staging hook failed"):
        r.install_hook("/usr/local/etc/rc.d/zz-test.sh", "#!/bin/sh\n")
