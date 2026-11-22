import hashlib
import json
import runpy
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/sync-proxmox-storage-monitoring.py"


class SyncStorageMonitoringTest(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SCRIPT))
        self.globals = self.module["plan"].__globals__
        self.manifest = json.loads((self.globals["SOURCE"] / "manifest.json").read_text())

    def fake_remote(self, in_sync):
        source = self.globals["HOSTS"]
        hashes = {i["dest"]: (i["mode"].lstrip("0"), hashlib.sha256((source / i["src"]).read_bytes()).hexdigest())
                  for i in self.manifest["files"]}

        def remote(*args, **kwargs):
            return SimpleNamespace(returncode=0 if in_sync else 1, **vars(answer(*args)))

        def answer(*args):
            if args[0] == "dpkg-query":
                return SimpleNamespace(stdout="install ok installed" if in_sync else "")
            if args[0] == "sh":
                dest = next(d for d in hashes if d in args[2])
                mode, digest = hashes[dest]
                return SimpleNamespace(stdout=f"{mode}\n{digest}  {dest}" if in_sync else "")
            if args[:2] == ("systemctl", "is-enabled"):
                return SimpleNamespace(stdout="enabled" if in_sync else "disabled")
            if args[:2] == ("systemctl", "is-active"):
                return SimpleNamespace(stdout="active" if in_sync else "inactive")
            if args[:2] == ("systemctl", "show"):
                return SimpleNamespace(stdout="success")
            if args[0] == "curl":
                return SimpleNamespace(stdout='homelab_smart_array_physical_drive_ok{bay="1"} 1\n')
            return SimpleNamespace(stdout="")
        return Mock(side_effect=remote)

    def test_plan_in_sync_reports_no_changes(self):
        remote = self.fake_remote(True)
        with patch.dict(self.globals, remote=remote, print=Mock()):
            self.assertEqual(self.module["plan"](self.manifest), ([], [], []))

    def test_apply_installs_without_recommends_and_verifies(self):
        state = {"done": False}
        before, after = self.fake_remote(False), self.fake_remote(True)

        def remote(*args, **kwargs):
            if args[0] == "apt-get" or args[:2] == ("systemctl", "start"):
                state["done"] = True
            return (after if state["done"] else before)(*args, **kwargs)
        mock = Mock(side_effect=remote)
        with patch.dict(self.globals, remote=mock, print=Mock()):
            self.module["apply"](self.manifest)
        calls = [c.args for c in mock.call_args_list]
        self.assertIn(("apt-get", "install", "-y", "--no-install-recommends", "prometheus-node-exporter"), calls)
        self.assertIn(("systemctl", "restart", "prometheus-node-exporter.service"), calls)
        self.assertIn(("/usr/local/sbin/homelab-pve-ui", "apply"), calls)

    def test_remove_keeps_package_and_clears_notes(self):
        mock = Mock(return_value=SimpleNamespace(stdout="", returncode=0))
        with patch.dict(self.globals, remote=mock, print=Mock()):
            self.module["remove"](self.manifest)
        calls = [c.args for c in mock.call_args_list]
        self.assertIn(("/usr/local/sbin/homelab-smart-array-collect", "--remove-notes"), calls)
        self.assertIn(("/usr/local/sbin/homelab-pve-ui", "revert"), calls)
        self.assertIn(("rm", "-f", "/etc/apt/apt.conf.d/99homelab-pve-ui"), calls)
        self.assertLess(calls.index(("/usr/local/sbin/homelab-pve-ui", "revert")),
                        calls.index(("rm", "-f", "/usr/local/sbin/homelab-pve-ui")))
        self.assertNotIn("purge", " ".join(" ".join(c) for c in calls))
        self.assertNotIn(("rm", "-f", "/etc/default/prometheus-node-exporter"), calls)


if __name__ == "__main__":
    unittest.main()
