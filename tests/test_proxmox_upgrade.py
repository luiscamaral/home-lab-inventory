import runpy
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/proxmox-upgrade.py"
PACKAGES = {"pve-manager": "9.2.32", "proxmox-kernel-7.0.14-30-pve-signed": "7.0.14-30"}
GOOD = """287 upgraded, 8 newly installed, 0 to remove and 0 not upgraded.
Inst pve-manager [9.1.7] (9.2.32 Proxmox Debian Repository:stable [all]) []
Inst proxmox-kernel-7.0.14-30-pve-signed (7.0.14-30 Proxmox Debian Repository:stable [amd64])
"""


class UpgradeTest(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SCRIPT))
        self.problems = self.module["simulation_problems"]

    def test_reviewed_simulation_passes(self):
        self.assertEqual(self.problems(GOOD, PACKAGES), [])

    def test_removal_blocks(self):
        self.assertIn("remove", self.problems(GOOD + "Remv pve-firewall [5.0]\n", PACKAGES)[0])

    def test_new_target_version_blocks(self):
        output = GOOD.replace("(9.2.32", "(9.2.40")
        self.assertIn("9.2.40", self.problems(output, PACKAGES)[0])

    def test_missing_package_blocks(self):
        output = GOOD.replace("Inst pve-manager", "Inst other")
        self.assertIn("not in the upgrade set", self.problems(output, PACKAGES)[0])

    def test_apply_backs_up_before_upgrade_and_never_reboots(self):
        remote = Mock(return_value="")
        with patch.dict(self.module["start_upgrade"].__globals__, remote=remote, print=Mock()):
            self.module["start_upgrade"]({"unit": "u"})
        calls = [c.args for c in remote.call_args_list]
        self.assertEqual(calls[1][0], "tar")
        self.assertEqual(calls[2][0], "/usr/bin/systemd-run")
        self.assertNotIn("reboot", " ".join(" ".join(c) for c in calls))


if __name__ == "__main__":
    unittest.main()
