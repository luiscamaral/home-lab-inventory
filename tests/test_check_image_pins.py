"""Tests for scripts/check-image-pins.sh (no network)."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "scripts" / "check-image-pins.sh"


def run(tmp_path: Path, image: str) -> subprocess.CompletedProcess[str]:
    f = tmp_path / "stack.yml"
    f.write_text(f"services:\n  app:\n    image: {image}\n")
    return subprocess.run(["bash", str(SCRIPT), str(f)], capture_output=True, text=True, check=False)


@pytest.mark.parametrize(
    "image",
    [
        "postgres:17",
        "redis:7",
        "mysql:8",
        "foo/bar:1.2.3",
        "foo/bar:v1.2",
        "postgres:17.9",
        "registry.local:5000/foo:1.0",
        "localhost:5000/foo:1.0",
        "registry:5000/foo:1.0",
        "ghcr.io/project-zot/zot:v2.1.22",
        "foo/bar@sha256:" + "a" * 64,
        "zot.d.lcamaral.com/homelab/la-rundeck:latest",
    ],
)
def test_accepted(tmp_path: Path, image: str) -> None:
    r = run(tmp_path, image)
    assert r.returncode == 0, r.stdout


@pytest.mark.parametrize(
    "image",
    [
        "registry:5000",
        "registry.local:5000",
        "localhost:5000",
        "registry.local:5000/foo",
        "registry:5000/foo",
        "foo/bar",
        "postgres",
        "postgres:latest",
        "foo/bar:latest",
        "foo/bar:stable",
    ],
)
def test_rejected(tmp_path: Path, image: str) -> None:
    r = run(tmp_path, image)
    assert r.returncode == 1, r.stdout
