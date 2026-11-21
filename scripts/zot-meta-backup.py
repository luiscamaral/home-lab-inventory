#!/usr/bin/env python3
"""
Nightly consistent copy of zot's BoltDB metadata (meta.db) to the NAS, keeping 7 days.

Runs as the `zot-meta-backup` sidecar of the zot stack (python:3.13-alpine, `zot-meta` mounted
read-only, `/nfs/dockermaster/docker/zot/backup` mounted read-write). Not a standalone tool.

Why not a plain `cp`: BoltDB is single-writer and zot holds an exclusive lock on the file, so no
other process can open it (not even with bbolt's read-only mode), and a copy made while zot commits a
transaction can be torn. BoltDB never overwrites a committed page in place (copy-on-write, then it
flips one of two meta pages), so a copy of a quiet file is a valid database. The sidecar copies only
when the file did not change during the copy (same size and mtime before and after) and the copy
passes a structural check of the two meta pages (magic, version, FNV-1a checksum, file covers the
high-water page). Otherwise it retries (a pull rewrites meta.db for the pull timestamp) for up to
`ATTEMPTS` x `RETRY_SECONDS`; if it never gets a clean copy it logs ERROR and tries again the next day.
It does not stop or pause zot.

Metrics: a tiny HTTP server (`METRICS_PORT`, default 9199, 0 = off) serves `/metrics` for Prometheus
(`zot_meta_backup_*`: last success and attempt timestamps, last attempt result, size, txid, generations). The sidecar
shares zot's network namespace, so Prometheus scrapes it at zot's address; the `ZotMetaBackupStale` alert reads it.

One file per UTC day (`meta.db.YYYYMMDD`, replaced if run again the same day), newest `KEEP` kept,
plus `latest.json` (time, file, size, sha256, txid). The first run is `FIRST_DELAY` seconds after the
sidecar starts, then every `INTERVAL_HOURS`.
"""
from __future__ import annotations

import hashlib
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
import re
import shutil
import struct
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SRC = Path(os.environ.get("SRC", "/meta/meta.db"))
DEST = Path(os.environ.get("DEST", "/backup"))
KEEP = int(os.environ.get("KEEP", "7"))
ATTEMPTS = int(os.environ.get("ATTEMPTS", "12"))
RETRY_SECONDS = float(os.environ.get("RETRY_SECONDS", "5"))
INTERVAL_HOURS = float(os.environ.get("INTERVAL_HOURS", "24"))
FIRST_DELAY = float(os.environ.get("FIRST_DELAY", "120"))
METRICS_PORT = int(os.environ.get("METRICS_PORT", "9199"))
STATE = {"attempt_ts": 0.0, "attempt_ok": 0}

MAGIC = 0xED0CDAED
VERSION = 2
META_FLAG = 0x04
DAY_RE = re.compile(r"^meta\.db\.(\d{8})$")


def log(level: str, msg: str) -> None:
    print(f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} {level} {msg}", flush=True)


def fnv64a(data: bytes) -> int:
    h = 0xCBF29CE484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def parse_meta(buf: bytes, offset: int):
    """Return (txid, pgid_high_water, page_size) of a valid meta page at `offset`, else None."""
    if len(buf) < offset + 16 + 64:
        return None
    _pid, flags, _count, _ovf = struct.unpack_from("<QHHI", buf, offset)
    if flags != META_FLAG:
        return None
    m = offset + 16
    magic, version, page_size, _mflags = struct.unpack_from("<IIII", buf, m)
    _root, _seq, _freelist, pgid, txid, checksum = struct.unpack_from("<QQQQQQ", buf, m + 16)
    if magic != MAGIC or version != VERSION or page_size < 1024:
        return None
    if fnv64a(buf[m:m + 56]) != checksum:
        return None
    return txid, pgid, page_size


def check_bolt(path: Path) -> tuple[bool, str, int]:
    """Structural check of a BoltDB file. Returns (ok, reason, txid)."""
    size = path.stat().st_size
    with path.open("rb") as f:
        head = f.read(65536)
        m0 = parse_meta(head, 0)
        page_size = m0[2] if m0 else None
        m1 = None
        if page_size:
            f.seek(page_size)
            m1 = parse_meta(f.read(page_size), 0)
    metas = [m for m in (m0, m1) if m]
    if not metas:
        return False, "no valid meta page (magic/version/checksum)", 0
    txid, pgid, page_size = max(metas, key=lambda m: m[0])
    if size < pgid * page_size:
        return False, f"file ({size} B) shorter than high-water page {pgid} x {page_size}", txid
    return True, "ok", txid


def consistent_copy(tmp: Path) -> tuple[bool, str, int]:
    last = "never tried"
    for attempt in range(1, ATTEMPTS + 1):
        st1 = SRC.stat()
        shutil.copyfile(SRC, tmp)
        st2 = SRC.stat()
        if (st1.st_size, st1.st_mtime_ns) != (st2.st_size, st2.st_mtime_ns):
            last = "source changed while copying"
        else:
            ok, why, txid = check_bolt(tmp)
            if ok:
                return True, f"attempt {attempt}", txid
            last = why
        log("INFO", f"copy attempt {attempt}/{ATTEMPTS} rejected: {last}")
        time.sleep(RETRY_SECONDS)
    return False, last, 0


def rotate() -> list[str]:
    days = sorted((p for p in DEST.iterdir() if DAY_RE.match(p.name)), key=lambda p: p.name, reverse=True)
    removed = []
    for p in days[KEEP:]:
        p.unlink()
        removed.append(p.name)
    return removed


def metrics_text() -> str:
    """Prometheus text format. Last success comes from latest.json so it survives a restart of the sidecar."""
    last_ts, size, txid = 0.0, 0, 0
    try:
        info = json.loads((DEST / "latest.json").read_text())
        last_ts = datetime.fromisoformat(info["time"]).timestamp()
        size, txid = int(info["size"]), int(info["txid"])
    except (OSError, ValueError, KeyError):
        pass
    gens = len([p for p in DEST.iterdir() if DAY_RE.match(p.name)]) if DEST.is_dir() else 0
    rows = [
        ("last_success_timestamp_seconds", "Unix time of the last consistent backup (0 = none yet)", last_ts),
        ("last_attempt_timestamp_seconds", "Unix time of the last backup attempt in this process (0 = none yet)",
         STATE["attempt_ts"]),
        ("last_attempt_success", "1 if the last attempt in this process succeeded, else 0", STATE["attempt_ok"]),
        ("size_bytes", "Size of the latest backup", size),
        ("txid", "BoltDB transaction id of the latest backup", txid),
        ("generations", "Number of daily generations kept", gens),
    ]
    out = []
    for name, helptext, value in rows:
        out += [f"# HELP zot_meta_backup_{name} {helptext}", f"# TYPE zot_meta_backup_{name} gauge",
                f"zot_meta_backup_{name} {value:g}"]
    return "\n".join(out) + "\n"


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?")[0] != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = metrics_text().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args) -> None:  # keep the log for backup lines
        pass


def serve_metrics() -> None:
    if METRICS_PORT:
        srv = HTTPServer(("0.0.0.0", METRICS_PORT), MetricsHandler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        log("INFO", f"metrics on :{METRICS_PORT}/metrics")


def run_once() -> bool:
    STATE["attempt_ts"] = time.time()
    STATE["attempt_ok"] = 0
    ok = _run_once()
    STATE["attempt_ok"] = int(ok)
    return ok


def _run_once() -> bool:
    if not SRC.is_file():
        log("ERROR", f"{SRC} not found")
        return False
    DEST.mkdir(parents=True, exist_ok=True)
    tmp = DEST / ".meta.db.tmp"
    ok, why, txid = consistent_copy(tmp)
    if not ok:
        tmp.unlink(missing_ok=True)
        log("ERROR", f"no consistent copy of {SRC}: {why}")
        return False
    with tmp.open("rb") as f:
        os.fsync(f.fileno())
    final = DEST / f"meta.db.{datetime.now(timezone.utc).strftime('%Y%m%d')}"
    os.replace(tmp, final)
    sha = hashlib.sha256(final.read_bytes()).hexdigest()
    info = {"time": datetime.now(timezone.utc).isoformat(timespec="seconds"), "file": final.name,
            "size": final.stat().st_size, "sha256": sha, "txid": txid}
    (DEST / "latest.json").write_text(json.dumps(info) + "\n")
    removed = rotate()
    log("INFO", f"backup ok: {final.name} {info['size']} B txid={txid} sha256={sha[:12]} ({why}); "
                f"kept {len([p for p in DEST.iterdir() if DAY_RE.match(p.name)])}, removed {removed}")
    return True


def main() -> int:
    if "--once" in sys.argv:
        return 0 if run_once() else 1
    serve_metrics()
    log("INFO", f"zot-meta-backup: first run in {FIRST_DELAY:.0f}s, then every {INTERVAL_HOURS:g} h; keep {KEEP}")
    time.sleep(FIRST_DELAY)
    while True:
        try:
            run_once()
        except Exception as e:  # keep the sidecar alive; the next day tries again
            log("ERROR", f"backup run failed: {e!r}")
        time.sleep(INTERVAL_HOURS * 3600)


if __name__ == "__main__":
    sys.exit(main())
