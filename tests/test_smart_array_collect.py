import importlib.machinery
import importlib.util
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "hosts/proxmox/storage-monitoring/homelab-smart-array-collect"
FIXTURES = ROOT / "tests/fixtures/smart_array"


def load():
    loader = importlib.machinery.SourceFileLoader("collect", str(SCRIPT))
    spec = importlib.util.spec_from_loader("collect", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class SmartArrayCollectTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = load()
        text = {p.name: p.read_text() for p in FIXTURES.iterdir()}
        smart = {}
        for name, body in text.items():
            if name.startswith("smartctl-"):
                summary = cls.c.summarize_smart(json.loads(body))
                smart[summary["serial"]] = summary
        cls.controller = cls.c.parse_controller(text["ctrl-detail.txt"])
        volumes, drives = cls.c.parse_config(text["show-config.txt"])
        details = cls.c.parse_drive_details(text["pd-detail.txt"])
        drives = cls.c.merge(drives, details, smart)
        cls.state = {"slot": "0", "time": 1795400000, "controller": cls.controller,
                     "volumes": volumes, "drives": drives}

    def drive(self, bay):
        return next(d for d in self.state["drives"] if d["bay"] == bay)

    def test_controller_reports_failed_capacitor_with_write_cache_on(self):
        self.assertEqual(self.controller["controller"], "OK")
        self.assertTrue(self.controller["capacitor"].startswith("Failed"))
        self.assertTrue(self.controller["nbwc"])
        self.assertEqual(self.controller["model"], "Smart Array P420i")

    def test_volumes_and_drive_roles(self):
        self.assertEqual([(v["id"], v["raid"], v["status"]) for v in self.state["volumes"]],
                         [("1", "5", "OK"), ("2", "5", "OK")])
        self.assertEqual(len(self.state["drives"]), 8)
        self.assertEqual(self.drive("1I:1:1")["volume"], "1")
        self.assertEqual(self.drive("2I:1:8")["role"], "spare")
        self.assertIsNone(self.drive("2I:1:8")["volume"])
        self.assertEqual(self.drive("1I:1:4")["role"], "unassigned")

    def test_smart_is_matched_to_every_bay(self):
        for d in self.state["drives"]:
            self.assertTrue(d["smart_passed"], d["bay"])
            self.assertIsNotNone(d["temp"], d["bay"])
        self.assertEqual(self.drive("1I:1:2")["temp"], 33)
        self.assertEqual(self.drive("1I:1:2")["ssd_life_left"], 100)
        self.assertIsNone(self.drive("2I:1:5")["ssd_life_left"])

    def test_metrics_values_and_format(self):
        text = self.c.metrics(self.state)
        self.assertIn('homelab_smart_array_capacitor_ok{slot="0",model="Smart Array P420i"} 0', text)
        self.assertIn('homelab_smart_array_no_battery_write_cache_enabled{slot="0",model="Smart Array P420i"} 1',
                      text)
        self.assertEqual(len(re.findall(r"^homelab_smart_array_physical_drive_ok\{", text, re.MULTILINE)), 8)
        self.assertEqual(len(re.findall(r"^homelab_smart_array_ssd_life_left_percent\{", text, re.MULTILINE)), 3)
        for line in text.splitlines():
            if not line.startswith("#"):
                self.assertRegex(line, r'^[a-z_]+(\{[^}]*\})? -?\d+(\.\d+)?$')

    def test_notes_block_has_no_serials_and_round_trips_json(self):
        block = self.c.notes_block(self.state)
        self.assertNotIn("SERIAL-", block)
        self.assertIn("Capacitor: **Problem**", block)
        payload = re.search(r"<!-- homelab-smart-array-json (.*) -->", block)[1]
        self.assertEqual(len(json.loads(payload)["drives"]), 8)

    def test_replace_block_keeps_other_notes(self):
        block = self.c.notes_block(self.state)
        notes = "My notes\n"
        once = self.c.replace_block(notes, block)
        self.assertTrue(once.startswith("My notes\n\n"))
        self.assertEqual(self.c.replace_block(once, block), once)
        self.assertEqual(self.c.replace_block("", block), block)


if __name__ == "__main__":
    unittest.main()
