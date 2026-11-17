import importlib.util
import sys
from pathlib import Path
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
DRIFTED = {("opt2", "aa:bb:cc:dd:ee:ff"): {"ipaddr": "192.168.0.23", "hostname": "", "descr": "drift", "index": 0}}


@pytest.fixture
def manifest(tmp_path):
    path = tmp_path / "mappings.yml"
    path.write_text(MANIFEST_TEXT)
    return path


def run(argv, manifest, live, write):
    with patch.object(dhcp, "MANIFEST", manifest), patch.object(dhcp, "fetch_live", side_effect=live), \
         patch.object(dhcp, "keychain_token", return_value="test"), \
         patch.object(dhcp, "write_api", write), patch.object(sys, "argv", ["sync", *argv]):
        return dhcp.main()


def test_only_writes_selected_mapping_once_then_verifies(manifest):
    created = {**DRIFTED, ("lan", "12:32:f0:cc:79:e5"): {**OMADA, "index": 0}}
    write = patch.object(dhcp, "write_api", return_value={"code": 200}).start()
    try:
        rc = run(["--apply", "--only", "lan", "12:32:F0:CC:79:E5"], manifest, [DRIFTED, created], write)
    finally:
        patch.stopall()
    assert rc == 0
    assert write.call_count == 1
    method, path, _token, body = write.call_args.args
    assert (method, path) == ("POST", "/services/dhcp_server/static_mapping")
    assert body["ipaddr"] == "192.168.32.40"


def test_unknown_outcome_stops_and_never_resends(manifest):
    write = patch.object(dhcp, "write_api", side_effect=dhcp.OutcomeUnknown("no answer")).start()
    try:
        with pytest.raises(SystemExit, match="Do NOT retry"):
            run(["--apply", "--only", "lan", "12:32:f0:cc:79:e5"], manifest, [DRIFTED], write)
    finally:
        patch.stopall()
    assert write.call_count == 1


def test_answer_without_live_change_is_an_error(manifest):
    write = patch.object(dhcp, "write_api", return_value={"code": 200}).start()
    try:
        with pytest.raises(SystemExit, match="live config does not match"):
            run(["--apply", "--only", "lan", "12:32:f0:cc:79:e5"], manifest, [DRIFTED, DRIFTED], write)
    finally:
        patch.stopall()


def test_api_error_answer_is_an_error(manifest):
    write = patch.object(dhcp, "write_api", return_value={"code": 409, "message": "overlap"}).start()
    try:
        with pytest.raises(SystemExit, match="API returned 409"):
            run(["--apply", "--only", "lan", "12:32:f0:cc:79:e5"], manifest, [DRIFTED], write)
    finally:
        patch.stopall()


def test_only_unknown_mapping_fails_before_live_access(manifest):
    with patch.object(dhcp, "MANIFEST", manifest), patch.object(dhcp, "fetch_live") as fetch, \
         patch.object(sys, "argv", ["sync", "--only", "lan", "00:00:00:00:00:00"]):
        with pytest.raises(SystemExit, match="expected one mapping"):
            dhcp.main()
    fetch.assert_not_called()


def test_activate_runs_alone_and_calls_apply_once():
    with patch.object(dhcp, "keychain_token", return_value="test"), \
         patch.object(dhcp, "write_api", return_value={"code": 200}) as write, \
         patch.object(sys, "argv", ["sync", "--activate"]):
        assert dhcp.main() == 0
    assert write.call_count == 1
    assert write.call_args.args[:2] == ("POST", "/services/dhcp_server/apply")


def test_activate_rejects_mapping_options():
    with patch.object(sys, "argv", ["sync", "--activate", "--apply"]):
        with pytest.raises(SystemExit, match="runs alone"):
            dhcp.main()


def test_curl_config_quoting():
    assert dhcp._cfg('a"b\\c') == '"a\\"b\\\\c"'
