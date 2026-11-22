import glob
import json
import os
import runpy
import unittest
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = runpy.run_path(str(ROOT / "scripts/build-glass-panel.py"))
DASHBOARDS = ROOT / "terraform/portainer/stacks"


def targets(board):
    for panel in board["panels"]:
        for target in panel.get("targets", []):
            yield panel["title"], target


class GlassPanelTest(unittest.TestCase):
    def setUp(self):
        self.board = json.loads(BUILDER["OUT"].read_text())

    def test_json_matches_the_builder(self):
        built = json.loads(json.dumps(BUILDER["build"]()))
        self.assertEqual(self.board, built, "run scripts/build-glass-panel.py and commit the JSON")

    def test_every_link_points_to_a_repo_dashboard(self):
        uids = set()
        for path in glob.glob(str(DASHBOARDS / "grafana-dashboards*/*.json")):
            uid = json.loads(Path(path).read_text()).get("uid")
            self.assertTrue(uid, f"{path} has no fixed uid")
            self.assertNotIn(uid, uids, f"duplicate uid {uid}")
            uids.add(uid)
        links = [link["url"] for panel in self.board["panels"] for link in panel.get("links", [])]
        self.assertGreater(len(links), 15)
        for url in links:
            self.assertIn(url.removeprefix("/d/"), uids, url)

    def test_layout_fits_the_grid(self):
        for panel in self.board["panels"]:
            grid = panel["gridPos"]
            self.assertLessEqual(grid["x"] + grid["w"], 24, panel["title"])
        self.assertEqual(len({p["id"] for p in self.board["panels"]}), len(self.board["panels"]))

    @unittest.skipUnless(os.environ.get("HOMELAB_THANOS_URL"), "set HOMELAB_THANOS_URL to query live data")
    def test_every_query_returns_data(self):
        base = os.environ["HOMELAB_THANOS_URL"].rstrip("/") + "/api/v1/query?dedup=true&query="
        empty = []
        for title, target in targets(self.board):
            url = base + urllib.parse.quote(target["expr"])
            result = json.load(urllib.request.urlopen(url, timeout=30))["data"]["result"]
            if not result and (title, target["refId"]) not in BUILDER["MAY_BE_EMPTY"]:
                empty.append(f"{title}/{target['refId']}: {target['expr']}")
        self.assertEqual(empty, [])


if __name__ == "__main__":
    unittest.main()
