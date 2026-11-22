import runpy
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/sync-proxmox-pve-mods.py"


def result(stdout="", returncode=0):
    return SimpleNamespace(stdout=stdout, returncode=returncode)


class PveModsTest(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SCRIPT))
        self.globals = self.module["apply"].__globals__
        self.manifest = {"min_pve_manager": "9.2", "version": "2.2.3", "apt_packages": ["lm-sensors"],
                         "deb_url": "https://example.invalid/p.deb", "deb_sha256": "ab"}

    def run_apply(self, pve, conf_state="node_info=1"):
        source = self.globals["SOURCE"]
        files = {target: (source / name).read_text() for name, target in self.globals["CONFIGS"].items()}

        def fake(*args, **kwargs):
            if args[0] == "pveversion":
                return result(f"pve-manager/{pve}/abc (running kernel: 7.0)")
            if args[0] == "dpkg-query":
                return result("", 1)
            if args[0] == "cat":
                return result(files[args[1]])
            if args[0] == "grep":
                return result(conf_state)
            return result()

        remote = Mock(side_effect=fake)
        with patch.dict(self.globals, remote=remote, print=Mock()):
            self.module["apply"](self.manifest)
        return [call.args[0] for call in remote.call_args_list]

    def test_blocks_before_pve_9_2_without_writes(self):
        with self.assertRaisesRegex(ValueError, "Upgrade Proxmox VE first"):
            self.run_apply("9.1.7")

    def test_apply_order_checks_hash_before_install(self):
        commands = self.run_apply("9.2.32")
        self.assertLess(commands.index("sha256sum"), commands.index("apt-get"))
        self.assertLess(commands.index("apt-get"), commands.index("install"))
        self.assertLess(commands.index("install"), commands.index(self.globals["APPLY"]))

    def test_incompatible_patch_is_reported(self):
        with self.assertRaisesRegex(ValueError, "node_info=2"):
            self.run_apply("9.2.32", conf_state="node_info=2")

    def test_repo_config_enables_only_node_info_without_smart_service(self):
        source = self.globals["SOURCE"]
        main = (source / "pve-mods.conf").read_text()
        node = (source / "conf.d/node_info.conf").read_text()
        self.assertIn("node_info=1", main)
        for other in ("nag_screen", "oidc_console_access", "guest_summary", "node_search"):
            self.assertIn(f"{other}=0", main)
        storage = node[node.index("[storage_health]"):]
        self.assertIn("enabled=0", storage.split("\n[")[0])


if __name__ == "__main__":
    unittest.main()
