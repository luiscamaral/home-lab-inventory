import importlib.util
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/sync-pfsense-dhcp-static-mappings.py"
spec = importlib.util.spec_from_file_location("dhcp_static_mappings", SCRIPT)
dhcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dhcp)

OMADA = {"ipaddr": "192.168.32.40", "hostname": "omada-controller", "descr": "Omada Controller TP-Link"}
MANIFEST_TEXT = (
    "mappings:\n"
    "  - {interface: lan, mac: '12:32:f0:cc:79:e5', ipaddr: 192.168.32.40,"
    " hostname: omada-controller, descr: Omada Controller TP-Link}\n"
    "  - {interface: opt2, mac: 'aa:bb:cc:dd:ee:ff', ipaddr: 192.168.0.23}\n"
)
OTHER = {("opt2", "aa:bb:cc:dd:ee:ff"): {"ipaddr": "192.168.0.23", "hostname": "", "descr": "drift", "index": 0}}
WITH_OMADA = {**OTHER, ("lan", "12:32:f0:cc:79:e5"): {**OMADA, "index": 0}}
ARGS = ["--only", "lan", "12:32:F0:CC:79:E5"]


@pytest.fixture
def manifest(tmp_path):
    path = tmp_path / "mappings.yml"
    path.write_text(MANIFEST_TEXT)
    return path


def run(argv, manifest, live, php):
    with patch.object(dhcp, "MANIFEST", manifest), patch.object(dhcp, "fetch_live", side_effect=live), \
         patch.object(dhcp, "php_run", php), patch.object(sys, "argv", ["sync", *argv]):
        return dhcp.main()


def test_apply_writes_selected_mapping_once_then_verifies(manifest):
    php = patch.object(dhcp, "php_run", return_value={"ok": True, "action": "create"}).start()
    try:
        assert run(["--apply", *ARGS], manifest, [OTHER, WITH_OMADA], php) == 0
    finally:
        patch.stopall()
    assert php.call_count == 1
    payload = php.call_args.args[0]
    assert payload["op"] == "upsert" and payload["dry"] is False
    assert (payload["interface"], payload["ipaddr"]) == ("lan", "192.168.32.40")


def test_dry_run_validates_without_writing(manifest):
    php = patch.object(dhcp, "php_run", return_value={"ok": True, "action": "create"}).start()
    try:
        assert run(ARGS, manifest, [OTHER], php) == 0
    finally:
        patch.stopall()
    assert php.call_count == 1
    assert php.call_args.args[0]["dry"] is True


def test_unknown_outcome_stops_and_never_resends(manifest):
    php = patch.object(dhcp, "php_run", side_effect=dhcp.OutcomeUnknown("no answer")).start()
    try:
        with pytest.raises(SystemExit, match="Do NOT retry"):
            run(["--apply", *ARGS], manifest, [OTHER], php)
    finally:
        patch.stopall()
    assert php.call_count == 1


def test_answer_without_live_change_is_an_error(manifest):
    php = patch.object(dhcp, "php_run", return_value={"ok": True, "action": "create"}).start()
    try:
        with pytest.raises(SystemExit, match="live config does not match"):
            run(["--apply", *ARGS], manifest, [OTHER, OTHER], php)
    finally:
        patch.stopall()


def test_only_unknown_mapping_fails_before_live_access(manifest):
    with patch.object(dhcp, "MANIFEST", manifest), patch.object(dhcp, "fetch_live") as fetch, \
         patch.object(sys, "argv", ["sync", "--only", "lan", "00:00:00:00:00:00"]):
        with pytest.raises(SystemExit, match="expected one mapping"):
            dhcp.main()
    fetch.assert_not_called()


def test_activate_runs_alone_and_calls_once():
    with patch.object(dhcp, "php_run", return_value={"ok": True}) as php, \
         patch.object(sys, "argv", ["sync", "--activate"]):
        assert dhcp.main() == 0
    php.assert_called_once_with({"op": "activate"})


def test_activate_rejects_mapping_options():
    with patch.object(sys, "argv", ["sync", "--activate", "--apply"]):
        with pytest.raises(SystemExit, match="runs alone"):
            dhcp.main()


def fake_ssh(stdout="", returncode=0, stderr=""):
    return patch.object(dhcp.subprocess, "run",
                        return_value=SimpleNamespace(stdout=stdout, returncode=returncode, stderr=stderr))


def test_php_run_reads_last_json_line_past_php_notices():
    with fake_ssh('PHP Deprecated: noise\n{"ok": true, "action": "create"}\n') as ssh:
        assert dhcp.php_run({"op": "upsert"}) == {"ok": True, "action": "create"}
    sent = ssh.call_args.kwargs["input"]
    assert '"op": "upsert"' in sent and "@@PAYLOAD@@" not in sent


def test_php_run_refusal_is_an_error_not_unknown():
    with fake_ssh('{"ok": false, "error": "192.168.32.56 is inside the dynamic range"}\n', returncode=1):
        with pytest.raises(SystemExit, match="inside the dynamic range"):
            dhcp.php_run({"op": "upsert"})


def test_php_run_without_json_is_unknown():
    with fake_ssh("Segmentation fault", returncode=139):
        with pytest.raises(dhcp.OutcomeUnknown):
            dhcp.php_run({"op": "upsert"})


def test_php_run_timeout_is_unknown():
    with patch.object(dhcp.subprocess, "run", side_effect=subprocess.TimeoutExpired("ssh", 120)):
        with pytest.raises(dhcp.OutcomeUnknown, match="no answer"):
            dhcp.php_run({"op": "upsert"})


def test_template_has_one_payload_slot():
    assert dhcp.PHP_TEMPLATE.count("@@PAYLOAD@@") == 1
