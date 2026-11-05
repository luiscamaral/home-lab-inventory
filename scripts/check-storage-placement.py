#!/usr/bin/env python3
"""Storage placement guard (pre-commit + report).

Policy: docs/architecture/storage-policy.md
Register: docs/architecture/storage-register.yml

Default rule: application data lives on the NAS export mounted at
/nfs/dockermaster/ on every Docker host. Any local persistent mount
(host bind outside that path, or a Docker named volume not backed by the
NAS) is a VIOLATION unless it has a register entry.

Enforcement:
  - unregistered local storage            -> FAIL (undocumented = violation)
  - register entry class=exception        -> must have an allowed
                                             exception_class and a reason
  - register entry class=violation        -> allowed (recorded debt), printed
  - register entry whose file/service/target no longer exists -> FAIL (stale)

Usage:
  scripts/check-storage-placement.py [FILES...]   # pre-commit passes changed files
  scripts/check-storage-placement.py --report     # full scan, debt summary, exit 0
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
REGISTER = REPO / "docs" / "architecture" / "storage-register.yml"
# NAS-backed paths: any export mounted under /nfs/ (same path on every host that
# uses it), plus /volume2/ which is the NAS host's own data disk.
NAS_PREFIXES = ("/nfs/", "/volume2/")
NAS_ROOT = "/nfs/dockermaster/"  # default namespace for new application data
SCAN_ROOTS = ["terraform/portainer/stacks", "dockermaster/docker", "dockerserver-1", "dockerserver-2", "nas/docker"]
PRUNE_DIRS = {".worktrees", ".terraform", "node_modules", "generated", "docs", "mcp", "_archive", ".history", ".git"}

# Host runtime plumbing is not application data. Binds under these paths are
# ignored. Anything else that is a host path is treated as local storage.
RUNTIME_PREFIXES = (
    "/var/run/docker.sock", "/run/docker.sock", "/var/run", "/run/udev", "/run/systemd",
    "/proc", "/sys", "/dev", "/etc/localtime", "/etc/timezone", "/etc/hostname",
    "/etc/hosts", "/etc/resolv.conf", "/etc/machine-id", "/usr/share/zoneinfo",
    "/var/lib/docker", "/var/log", "/var/lib/node_exporter/textfile_collector",
)
RUNTIME_EXACT = {"/"}

ALLOWED_EXCEPTION_CLASSES = {
    "postgres",   # PostgreSQL data directory (needs local disk for fsync / repmgr)
    "raft",       # Raft / consensus stores (NFS latency breaks heartbeats)
    "tsdb",       # Time-series DB write-heavy stores (Prometheus, Mimir, Tempo)
    "sqlite",     # SQLite / BoltDB files (NFS locking corrupts them)
    "cache",      # Rebuildable caches
    "scratch",    # Rebuildable scratch / compactor working dirs
    "other",      # Anything else: reason must be specific
}


def is_runtime(source: str) -> bool:
    if source in RUNTIME_EXACT:
        return True
    return any(source == p or source.startswith(p + "/") for p in RUNTIME_PREFIXES)


def discover_files() -> list[Path]:
    found: list[Path] = []
    for root in SCAN_ROOTS:
        base = REPO / root
        if not base.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in PRUNE_DIRS]
            for name in filenames:
                if name.endswith((".yml", ".yaml")):
                    found.append(Path(dirpath) / name)
    return sorted(found)


def load_compose(path: Path):
    try:
        data = yaml.safe_load(path.read_text())
    except Exception as exc:  # noqa: BLE001 - report and skip unparseable files
        return None, f"parse error: {exc}"
    if not isinstance(data, dict) or "services" not in data:
        return None, None
    return data, None


def named_volume_is_nas(decl) -> bool:
    if not isinstance(decl, dict):
        return False
    opts = decl.get("driver_opts") or {}
    device = str(opts.get("device", ""))
    return decl.get("driver") == "local" and str(opts.get("type", "")) == "none" and device.startswith(NAS_PREFIXES)


def findings_for(path: Path, data: dict) -> list[dict]:
    rel = str(path.relative_to(REPO))
    top_volumes = data.get("volumes") or {}
    out: list[dict] = []
    for svc_name, svc in (data.get("services") or {}).items():
        for vol in svc.get("volumes") or []:
            kind = source = target = None
            if isinstance(vol, str):
                parts = vol.split(":")
                if len(parts) < 2:
                    continue
                source, target = parts[0], parts[1]
                if source.startswith(("./", "../")) or source == ".":
                    continue  # repo-relative config files, not persistent data
                if source.startswith("/"):
                    kind = "bind"
                else:
                    kind = "volume"
            elif isinstance(vol, dict):
                vtype = vol.get("type", "volume")
                source, target = str(vol.get("source", "")), vol.get("target")
                if vtype == "bind":
                    kind = "bind"
                elif vtype == "volume":
                    kind = "volume"
                else:
                    continue
            else:
                continue
            if not target:
                continue

            if kind == "bind":
                if source.startswith(NAS_PREFIXES) or is_runtime(source):
                    continue
                out.append({"file": rel, "service": svc_name, "target": target, "kind": "local-bind", "source": source})
            else:
                decl = top_volumes.get(source)
                if decl is not None and named_volume_is_nas(decl):
                    continue
                # Undeclared named volume refs are treated as local too (compose would reject them anyway).
                out.append({"file": rel, "service": svc_name, "target": target, "kind": "local-volume", "source": source})
    return out


def load_register():
    if not REGISTER.exists():
        return [], [f"register missing: {REGISTER.relative_to(REPO)}"]
    data = yaml.safe_load(REGISTER.read_text()) or {}
    entries = data.get("entries") or []
    errors: list[str] = []
    for i, e in enumerate(entries):
        where = f"register entry #{i + 1} ({e.get('file')}:{e.get('service')}:{e.get('target')})"
        cls = e.get("class")
        if cls not in ("exception", "violation"):
            errors.append(f"{where}: class must be 'exception' or 'violation'")
        if not e.get("reason") or len(str(e["reason"]).strip()) < 40:
            errors.append(f"{where}: 'reason' is required (min 40 characters)")
        if cls == "exception" and e.get("exception_class") not in ALLOWED_EXCEPTION_CLASSES:
            errors.append(f"{where}: exception_class must be one of {sorted(ALLOWED_EXCEPTION_CLASSES)}")
        if cls == "violation" and e.get("status") not in ("open", "planned"):
            errors.append(f"{where}: violation status must be 'open' or 'planned'")
    return entries, errors


LIVE_HOSTS = ["dockermaster", "dockerserver-1", "dockerserver-2", "nas"]
LIVE_MARK = "__VOLUMES__"


def live_findings(host: str) -> list[dict]:
    """Inspect real containers on a host over ssh (read-only docker inspect)."""
    script = (
        'export PATH=$PATH:/usr/local/bin; docker ps -aq | xargs -r docker inspect; '
        f'echo {LIVE_MARK}; docker volume ls -q | xargs -r docker volume inspect'
    )
    proc = subprocess.run(
        ["ssh", "-o", "ConnectTimeout=20", host, script],
        capture_output=True, text=True, timeout=300,
    )
    out = proc.stdout
    if LIVE_MARK not in out:
        raise RuntimeError(f"{host}: no inspection output (rc={proc.returncode}): {proc.stderr.strip()[:200]}")
    containers_raw, volumes_raw = out.split(LIVE_MARK, 1)
    containers = json.loads(containers_raw.strip() or "[]")
    volumes = {v["Name"]: v for v in json.loads(volumes_raw.strip() or "[]")}
    findings: list[dict] = []
    for c in containers:
        name = c["Name"].lstrip("/")
        for m in c.get("Mounts") or []:
            target = m.get("Destination")
            if m.get("Type") == "bind":
                source = m.get("Source", "")
                if source.startswith(NAS_PREFIXES) or is_runtime(source):
                    continue
                kind, src = "local-bind", source
            elif m.get("Type") == "volume":
                vol = volumes.get(m.get("Name", ""), {})
                opts = vol.get("Options") or {}
                if str(opts.get("device", "")).startswith(NAS_PREFIXES) and str(opts.get("type", "")) == "none":
                    continue
                kind, src = "local-volume", m.get("Name") or "(anonymous)"
            else:
                continue
            findings.append({"file": f"live:{host}", "service": name, "target": target, "kind": kind, "source": src})
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--live", action="store_true", help="inspect running hosts over ssh (read-only)")
    args = ap.parse_args()

    if args.live:
        entries, errors = load_register()
        by_key = {(e.get("file"), e.get("service"), str(e.get("target"))): e for e in entries}
        rows: list[dict] = []
        for host in LIVE_HOSTS:
            try:
                rows.extend(live_findings(host))
            except Exception as exc:  # noqa: BLE001 - keep auditing other hosts
                print(f"WARN {host}: {exc}")
        print("== LIVE local persistent storage (default = violation)")
        for f in sorted(rows, key=lambda x: (x["file"], x["service"], str(x["target"]))):
            e = by_key.get((f["file"], f["service"], str(f["target"])))
            status = "UNREGISTERED" if not e else f"{e['class']}:{e.get('exception_class') or e.get('status')}"
            print(f"  [{status}] {f['file']} :: {f['service']} {f['kind']} {f['source']} -> {f['target']}")
        found = {(f["file"], f["service"], str(f["target"])) for f in rows}
        for e in entries:
            if str(e.get("file", "")).startswith("live:") and (e["file"], e["service"], str(e["target"])) not in found:
                errors.append(f"stale live entry: {e['file']} {e['service']} no longer mounts {e['target']}")
        unreg = [f for f in rows if (f["file"], f["service"], str(f["target"])) not in by_key]
        print(f"\nTotals: {len(rows)} live local mounts, {len(unreg)} unregistered")
        for err in errors:
            print(f"ERROR: {err}")
        return 1 if (unreg or errors) else 0


    entries, errors = load_register()
    by_key = {(e.get("file"), e.get("service"), str(e.get("target"))): e for e in entries}

    all_findings: list[dict] = []
    parse_problems: list[str] = []
    file_set = discover_files()
    for path in file_set:
        data, err = load_compose(path)
        rel = str(path.relative_to(REPO))
        if err:
            parse_problems.append(f"{rel}: {err}")
            continue
        if data is None:
            continue
        all_findings.extend(findings_for(path, data))

    # Stale register entries: file missing, service missing, or target no longer mounted.
    present = {(f["file"], f["service"], str(f["target"])) for f in all_findings}
    compose_services: dict[str, set[str]] = {}
    for path in file_set:
        data, _ = load_compose(path)
        if data:
            compose_services[str(path.relative_to(REPO))] = set((data.get("services") or {}).keys())
    for e in entries:
        f, s, t = e.get("file"), e.get("service"), str(e.get("target"))
        if str(f).startswith("live:"):
            continue  # live entries are validated by --live, which knows what is running
        if e.get("manual"):
            # Writable-layer data (not a mount) cannot be seen by the scan; only the file/service must exist.
            if f not in compose_services:
                errors.append(f"stale register entry: file not found: {f} ({s}:{t})")
            continue
        if f not in compose_services:
            errors.append(f"stale register entry: file not found: {f} ({s}:{t})")
        elif s not in compose_services[f]:
            errors.append(f"stale register entry: service not found: {f}:{s}")
        elif (f, s, t) not in present:
            errors.append(f"stale register entry: {f}:{s} no longer mounts {t}")

    unregistered = [f for f in all_findings if (f["file"], f["service"], str(f["target"])) not in by_key]

    if args.report:
        print("== Local persistent storage (default = violation)")
        for f in sorted(all_findings, key=lambda x: (x["file"], x["service"], x["target"])):
            e = by_key.get((f["file"], f["service"], str(f["target"])))
            status = "UNREGISTERED" if not e else f"{e['class']}:{e.get('exception_class') or e.get('status')}"
            print(f"  [{status}] {f['file']} :: {f['service']} {f['kind']} {f['source']} -> {f['target']}")
        debt = [e for e in entries if e.get("class") == "violation"]
        exc = [e for e in entries if e.get("class") == "exception"]
        print(f"\nTotals: {len(all_findings)} local mounts, {len(exc)} documented exceptions, {len(debt)} recorded violations, {len(unregistered)} unregistered")
        for p in parse_problems:
            print(f"WARN parse: {p}")
        for err in errors:
            print(f"ERROR: {err}")
        return 0

    # Pre-commit mode: fail on unregistered findings in the changed files, and on any register error.
    changed = {str(Path(p).resolve().relative_to(REPO)) for p in args.files if Path(p).resolve().is_relative_to(REPO)} if args.files else None
    fails = [f for f in unregistered if changed is None or f["file"] in changed]
    for f in fails:
        print(
            f"FAIL {f['file']} :: service '{f['service']}' mounts local {f['kind']} '{f['source']}' at {f['target']}\n"
            f"     Default is NAS (under {NAS_ROOT} or another /nfs/ export). Move it, or add a register entry with a reason:\n"
            f"     docs/architecture/storage-register.yml (see docs/architecture/storage-policy.md)"
        )
    for err in errors:
        print(f"FAIL register: {err}")
    if fails or errors:
        return 1
    print(f"storage placement OK ({len(all_findings)} local mounts, all registered)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
