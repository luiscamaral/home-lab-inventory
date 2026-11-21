"""Tests for scripts/zot-meta-backup.py (no zot, no network): consistent copy, rotation, metrics."""

from __future__ import annotations

import importlib.util
import json
import struct
import sys
import urllib.error
import urllib.request
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "zot-meta-backup.py"
PAGE = 4096


def load(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("SRC", str(tmp_path / "meta.db"))
    monkeypatch.setenv("DEST", str(tmp_path / "backup"))
    monkeypatch.setenv("KEEP", "3")
    monkeypatch.setenv("RETRY_SECONDS", "0")
    spec = importlib.util.spec_from_file_location("zot_meta_backup", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def meta_page(mod, pgid: int, txid: int, high_water: int) -> bytes:
    page = bytearray(PAGE)
    struct.pack_into("<QHHI", page, 0, pgid, mod.META_FLAG, 0, 0)
    body = struct.pack("<IIII", mod.MAGIC, mod.VERSION, PAGE, 0) + struct.pack("<QQQQQ", 3, 0, 2, high_water, txid)
    struct.pack_into("<56s", page, 16, body)
    struct.pack_into("<Q", page, 16 + 56, mod.fnv64a(body))
    return bytes(page)


def write_db(mod, path: Path, txid: int = 7, pages: int = 8) -> None:
    data = bytearray(PAGE * pages)
    data[0:PAGE] = meta_page(mod, 0, txid - 1, pages)
    data[PAGE:2 * PAGE] = meta_page(mod, 1, txid, pages)
    path.write_bytes(bytes(data))


def test_check_accepts_valid_and_rejects_torn(monkeypatch, tmp_path):
    mod = load(monkeypatch, tmp_path)
    db = tmp_path / "meta.db"
    write_db(mod, db, txid=9)
    ok, why, txid = mod.check_bolt(db)
    assert ok and txid == 9, why
    db.write_bytes(db.read_bytes()[: PAGE * 3])  # truncated below the high-water page
    assert not mod.check_bolt(db)[0]
    db.write_bytes(b"\0" * PAGE * 2)
    assert not mod.check_bolt(db)[0]


def test_backup_rotation_and_latest(monkeypatch, tmp_path):
    mod = load(monkeypatch, tmp_path)
    write_db(mod, tmp_path / "meta.db", txid=11)
    dest = tmp_path / "backup"
    dest.mkdir()
    for day in ("20260101", "20260102", "20260103", "20260104"):
        (dest / f"meta.db.{day}").write_bytes(b"old")
    assert mod.run_once()
    days = sorted(p.name for p in dest.iterdir() if p.name.startswith("meta.db."))
    assert days[:2] == ["meta.db.20260103", "meta.db.20260104"] and len(days) == 3  # KEEP=3: oldest two removed
    info = json.loads((dest / "latest.json").read_text())
    assert info["txid"] == 11 and info["size"] == PAGE * 8 and len(info["sha256"]) == 64
    assert mod.check_bolt(dest / info["file"])[0]


def test_failure_when_source_missing_or_invalid(monkeypatch, tmp_path):
    mod = load(monkeypatch, tmp_path)
    assert not mod.run_once()  # no source
    (tmp_path / "meta.db").write_bytes(b"x" * PAGE * 2)
    monkeypatch.setattr(mod, "ATTEMPTS", 2)
    assert not mod.run_once()
    assert mod.STATE["attempt_ok"] == 0


def test_metrics_endpoint(monkeypatch, tmp_path):
    mod = load(monkeypatch, tmp_path)
    write_db(mod, tmp_path / "meta.db", txid=5)
    assert mod.run_once()
    monkeypatch.setattr(mod, "METRICS_PORT", 0)
    from http.server import HTTPServer

    srv = HTTPServer(("127.0.0.1", 0), mod.MetricsHandler)
    import threading

    threading.Thread(target=srv.serve_forever, daemon=True).start()
    body = urllib.request.urlopen(f"http://127.0.0.1:{srv.server_port}/metrics", timeout=5).read().decode()
    with pytest.raises(urllib.error.HTTPError):
        urllib.request.urlopen(f"http://127.0.0.1:{srv.server_port}/other", timeout=2)
    srv.shutdown()
    vals = {line.split()[0]: float(line.split()[1]) for line in body.splitlines() if not line.startswith("#")}
    assert vals["zot_meta_backup_last_attempt_success"] == 1
    assert vals["zot_meta_backup_last_success_timestamp_seconds"] > 1.7e9
    assert vals["zot_meta_backup_txid"] == 5 and vals["zot_meta_backup_generations"] == 1
