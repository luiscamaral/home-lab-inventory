import json
import runpy
import unittest
from pathlib import Path
from unittest.mock import Mock, call, patch


class BackupJobTest(unittest.TestCase):
    def setUp(self):
        script = Path(__file__).resolve().parents[1] / "scripts/sync-proxmox-backup-job.py"
        module = runpy.run_path(str(script))
        self.sync = module["sync"]
        self.manifest = json.loads(module["MANIFEST"].read_text())
        self.job = self.manifest["job"]
        self.endpoint = f"/cluster/backup/{self.job['id']}"
        self.api = Mock()
        patcher = patch.dict(self.sync.__globals__, api=self.api)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_plan_does_not_write(self):
        self.api.return_value = {**self.job, "next-run": 42}
        self.sync(self.manifest)
        self.api.assert_called_once_with("get", self.endpoint)

    def test_apply_changes_only_scratch_and_reads_back(self):
        self.api.side_effect = [self.job.copy(), None, {**self.job, "tmpdir": "/var/tmp"}]
        self.sync(self.manifest, apply=True)
        self.assertEqual(self.api.call_args_list, [
            call("get", self.endpoint), call("set", self.endpoint, "--tmpdir", "/var/tmp"),
            call("get", self.endpoint),
        ])

    def test_apply_refuses_storage_drift(self):
        self.api.return_value = {**self.job, "storage": "local"}
        with self.assertRaisesRegex(ValueError, "differs from the reviewed job"):
            self.sync(self.manifest, apply=True)
        self.api.assert_called_once_with("get", self.endpoint)

    def test_apply_stops_if_readback_is_wrong(self):
        self.api.side_effect = [self.job.copy(), None, self.job.copy()]
        with self.assertRaisesRegex(ValueError, "readback differs"):
            self.sync(self.manifest, apply=True)
        self.assertEqual(self.api.call_count, 3)

    def test_null_setting_removes_only_scratch(self):
        self.api.side_effect = [{**self.job, "tmpdir": "/var/tmp"}, None, self.job.copy()]
        self.sync({**self.manifest, "tmpdir": None}, apply=True)
        self.api.assert_has_calls([call("set", self.endpoint, "--delete", "tmpdir")])

    def test_backup_uses_nas_without_pruning(self):
        self.api.side_effect = [{**self.job, "tmpdir": "/var/tmp"}, "UPID:test"]
        self.sync(self.manifest, test_backup=True)
        self.api.assert_has_calls([call(
            "create", "/nodes/proxmox/vzdump", "--vmid", "10000", "--storage", "pve-backups",
            "--mode", "snapshot", "--compress", "zstd", "--tmpdir", "/var/tmp",
            "--remove", "0", "--notification-mode", "notification-system",
        )])


if __name__ == "__main__":
    unittest.main()
