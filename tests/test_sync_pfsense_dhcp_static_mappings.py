import importlib.util
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/sync-pfsense-dhcp-static-mappings.py"
spec = importlib.util.spec_from_file_location("dhcp_static_mappings", SCRIPT)
dhcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dhcp)


def test_only_applies_selected_mapping(tmp_path):
    manifest = tmp_path / "mappings.yml"
    manifest.write_text(
        "mappings:\n"
        "  - {interface: lan, mac: '12:32:f0:cc:79:e5', ipaddr: 192.168.32.40}\n"
        "  - {interface: opt2, mac: 'aa:bb:cc:dd:ee:ff', ipaddr: 192.168.0.23}\n"
    )
    live = {("opt2", "aa:bb:cc:dd:ee:ff"): {
        "ipaddr": "192.168.0.23", "hostname": "", "descr": "drift", "index": 0,
    }}
    argv = ["sync", "--apply", "--only", "lan", "12:32:F0:CC:79:E5"]
    with patch.object(dhcp, "MANIFEST", manifest), patch.object(dhcp, "fetch_live", return_value=live), \
         patch.object(dhcp, "keychain_token", return_value="test"), \
         patch.object(dhcp, "api", return_value={"data": {"id": 1}}) as api, \
         patch.object(sys, "argv", argv):
        assert dhcp.main() == 0
    assert api.call_count == 1
    assert api.call_args.args[0:2] == ("POST", "/services/dhcp_server/static_mapping")
    assert api.call_args.args[3]["ipaddr"] == "192.168.32.40"


def test_only_unknown_mapping_fails_before_live_access(tmp_path):
    manifest = tmp_path / "mappings.yml"
    manifest.write_text("mappings: []\n")
    with patch.object(dhcp, "MANIFEST", manifest), patch.object(dhcp, "fetch_live") as fetch, \
         patch.object(sys, "argv", ["sync", "--only", "lan", "00:00:00:00:00:00"]):
        with pytest.raises(SystemExit, match="expected one mapping"):
            dhcp.main()
    fetch.assert_not_called()
