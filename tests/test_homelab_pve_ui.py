import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "hosts/proxmox/pve-ui/homelab-pve-ui"
JS = ROOT / "hosts/proxmox/pve-ui/homelab-storage.js"
TEMPLATE = ROOT / "tests/fixtures/pve_ui/index.html.tpl"
MARK = 'data-homelab="storage"'


class HomelabPveUiTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.template = self.dir / "index.html.tpl"
        self.js = self.dir / "homelab-storage.js"
        self.reloads = self.dir / "reloads"
        shutil.copy(TEMPLATE, self.template)
        shutil.copy(JS, self.js)
        gnubin = "/opt/homebrew/opt/coreutils/libexec/gnubin"  # GNU chmod on macOS; Linux already has it
        path = f"{gnubin}:{os.environ['PATH']}" if os.path.isdir(gnubin) else os.environ["PATH"]
        self.env = dict(os.environ, PATH=path, HOMELAB_PVE_UI_TEMPLATE=str(self.template), HOMELAB_PVE_UI_JS=str(self.js),
                        HOMELAB_PVE_UI_RELOAD=f"touch {self.reloads}")

    def run_ui(self, action):
        return subprocess.run(["bash", str(SCRIPT), action], env=self.env, capture_output=True, text=True,
                              check=False)

    def test_apply_adds_one_tag_after_pvemanagerlib_and_reloads(self):
        self.assertEqual(self.run_ui("apply").returncode, 0)
        lines = self.template.read_text().splitlines()
        tags = [i for i, line in enumerate(lines) if MARK in line]
        self.assertEqual(len(tags), 1)
        self.assertIn("pvemanagerlib.js", lines[tags[0] - 1])
        self.assertTrue(self.reloads.exists())
        self.assertEqual(self.run_ui("check").returncode, 0)

    def test_apply_is_idempotent_without_reload(self):
        self.run_ui("apply")
        first = self.template.read_text()
        self.reloads.unlink()
        self.assertEqual(self.run_ui("apply").returncode, 0)
        self.assertEqual(self.template.read_text(), first)
        self.assertFalse(self.reloads.exists())

    def test_js_change_updates_the_version_in_place(self):
        self.run_ui("apply")
        old = [line for line in self.template.read_text().splitlines() if MARK in line][0]
        self.js.write_text(self.js.read_text() + "// change\n")
        self.assertEqual(self.run_ui("check").returncode, 1)
        self.run_ui("apply")
        tags = [line for line in self.template.read_text().splitlines() if MARK in line]
        self.assertEqual(len(tags), 1)
        self.assertNotEqual(tags[0], old)

    def test_revert_restores_the_original_template(self):
        original = self.template.read_text()
        self.run_ui("apply")
        self.assertEqual(self.run_ui("revert").returncode, 0)
        self.assertEqual(self.template.read_text(), original)
        self.assertEqual(self.run_ui("check").returncode, 1)

    def test_missing_anchor_changes_nothing(self):
        text = self.template.read_text().replace("pvemanagerlib.js", "otherlib.js")
        self.template.write_text(text)
        result = self.run_ui("apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("anchor line not found", result.stdout)
        self.assertEqual(self.template.read_text(), text)


if __name__ == "__main__":
    unittest.main()
