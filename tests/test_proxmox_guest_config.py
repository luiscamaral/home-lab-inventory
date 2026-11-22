import json
import runpy
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/sync-proxmox-guest-config.py"


class GuestConfigTest(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SCRIPT))
        self.globals = self.module["plan"].__globals__
        self.manifest = json.loads(self.globals["MANIFEST"].read_text())
        self.live = {}
        for vmid, want in self.manifest["guests"].items():
            key = "name" if want["type"] == "qemu" else "hostname"
            self.live[vmid] = {key: want["name"], "startup": "order=9"}
        self.live["121"]["bios"] = "ovmf"

    def fake_config(self, node, kind, vmid):
        return dict(self.live[vmid])

    def run_with(self, func, *args, remote=None):
        remote = remote or Mock(return_value="status: stopped")
        with patch.dict(self.globals, guest_config=self.fake_config, remote=remote,
                        wait_for_agent=Mock(), print=Mock()):
            return func(*args), remote

    def test_plan_lists_startup_and_efidisk(self):
        (startup, efidisks), _ = self.run_with(self.module["plan"], self.manifest)
        self.assertEqual(len(startup), 7)
        self.assertEqual(efidisks, [("121", self.manifest["efidisks"]["121"])])

    def test_wrong_guest_name_blocks(self):
        self.live["120"]["name"] = "other"
        with self.assertRaisesRegex(ValueError, "expected 'dockermaster'"):
            self.run_with(self.module["plan"], self.manifest)

    def test_non_ovmf_blocks_efidisk(self):
        self.live["121"]["bios"] = "seabios"
        with self.assertRaisesRegex(ValueError, "does not use OVMF"):
            self.run_with(self.module["plan"], self.manifest)

    def test_efidisk_shuts_down_before_set_and_starts_after(self):
        self.live["121"]["efidisk0"] = "thin-pool-ssd:vm-121-disk-1,size=4M"
        _, remote = self.run_with(self.module["apply_efidisk"], self.manifest, "121", "spec")
        verbs = [c.args[:2] for c in remote.call_args_list]
        self.assertEqual(verbs, [("qm", "shutdown"), ("qm", "status"), ("qm", "set"), ("qm", "start")])

    def test_efidisk_not_added_if_vm_still_running(self):
        remote = Mock(return_value="status: running")
        with self.assertRaisesRegex(ValueError, "did not stop"):
            self.run_with(self.module["apply_efidisk"], self.manifest, "121", "spec", remote=remote)
        self.assertNotIn(("qm", "set"), [c.args[:2] for c in remote.call_args_list])


if __name__ == "__main__":
    unittest.main()
