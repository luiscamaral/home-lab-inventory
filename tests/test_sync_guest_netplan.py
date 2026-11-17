import base64
import importlib.util
import re
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("guest_netplan", ROOT / "scripts/sync-guest-netplan.py")
gn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gn)

GUEST = gn.GUESTS["omada-controller"]
REPO_FILE = (ROOT / "hosts/omada-controller/etc/netplan/01-netcfg.yaml").read_text()
LIVE_DHCP = "network:\n  version: 2\n  ethernets:\n    ens18:\n      dhcp4: yes\n"
GOOD_STATE = ("2: ens18    inet 192.168.32.40/27 brd 192.168.32.63 scope global ens18\n"
              "default via 192.168.32.33 dev ens18 proto static\n")
OLD_STATE = "2: ens18    inet 192.168.32.55/27 scope global dynamic ens18\ndefault via 192.168.32.33 dev ens18 proto dhcp\n"


def variant(old, new):
    assert old in REPO_FILE
    return REPO_FILE.replace(old, new)


def test_repo_file_passes_its_own_checks():
    gn.check_repo_file(GUEST, REPO_FILE)


@pytest.mark.parametrize("text, why", [
    (variant("dhcp4: false", "dhcp4: true"), "dhcp4"),
    (variant("192.168.32.40/27", "192.168.32.41/27"), "does not carry"),
    (variant("via: 192.168.32.33", "via: 192.168.32.1"), "no route via"),
    (variant("nameservers:\n        addresses:\n          - 192.168.32.33\n        search:\n          - admin.lcamaral.com\n", ""), "no DNS"),
])
def test_bad_repo_file_is_refused(text, why):
    with pytest.raises(SystemExit, match=why):
        gn.check_repo_file(GUEST, text)


def test_apply_script_order_and_payload():
    s = gn.apply_script("01-netcfg.yaml", REPO_FILE, "20261116-170000")
    assert s.index("cp -p /etc/netplan/01-netcfg.yaml /etc/netplan/01-netcfg.yaml.bak-") < s.index("netplan generate")
    assert s.index("netplan generate") < s.index("--unit=netplan-revert-guard") < s.index("--unit=netplan-apply-now")
    assert "GENERATE_FAILED" in s and "set -e" in s
    b64 = re.search(r"printf %s (\S+) \| base64 -d", s).group(1)
    assert base64.b64decode(b64).decode() == REPO_FILE


class Agent:
    """Fake guest agent. Records every script it is asked to run."""

    def __init__(self, live, states, apply_code=0):
        self.live, self.states, self.apply_code, self.calls = live, list(states), apply_code, []

    def __call__(self, vmid, script, timeout=40):
        self.calls.append(script)
        if script.startswith("cat /etc/netplan"):
            return 0, self.live
        if "netplan generate" in script:
            return self.apply_code, "SCHEDULED" if self.apply_code == 0 else "GENERATE_FAILED"
        if script.startswith("ip -4 -o addr"):
            return 0, self.states.pop(0) if len(self.states) > 1 else self.states[0]
        if "is-active" in script:
            return 0, "guard-cancelled"
        raise AssertionError(script)

    def ran(self, needle):
        return [c for c in self.calls if needle in c]


def run_sync(agent, apply=True, verify_secs=0.05):
    clock = iter(range(0, 10_000))  # each time.time() call advances one second
    with patch.object(gn, "REPO_ROOT", ROOT), patch.object(gn, "agent_exec", agent), \
         patch.object(gn.time, "sleep", lambda s: None), patch.object(gn.time, "time", lambda: next(clock)), \
         patch.object(gn, "VERIFY_SECS", verify_secs):
        return gn.sync_one("omada-controller", GUEST, apply)


def test_in_sync_does_nothing():
    agent = Agent(REPO_FILE, [GOOD_STATE])
    assert run_sync(agent) == 0
    assert not agent.ran("netplan generate") and not agent.ran("is-active")


def test_dry_run_never_writes():
    agent = Agent(LIVE_DHCP, [GOOD_STATE])
    assert run_sync(agent, apply=False) == 0
    assert not agent.ran("netplan generate")


def test_guard_is_cancelled_only_after_the_new_address_is_verified():
    agent = Agent(LIVE_DHCP, [OLD_STATE, OLD_STATE, GOOD_STATE])
    assert run_sync(agent, verify_secs=100) == 0
    order = [("apply" if "netplan generate" in c else "state" if c.startswith("ip -4") else "cancel")
             for c in agent.calls if not c.startswith("cat ")]
    assert order[0] == "apply" and order[-1] == "cancel"
    assert order.count("state") == 3 and order.index("cancel") > max(i for i, o in enumerate(order) if o == "state")


def test_unverified_change_leaves_the_guard_armed():
    agent = Agent(LIVE_DHCP, [OLD_STATE])
    assert run_sync(agent) == 1
    assert not agent.ran("is-active")


def test_failed_generate_aborts_without_waiting():
    agent = Agent(LIVE_DHCP, [GOOD_STATE], apply_code=1)
    with pytest.raises(SystemExit, match="Nothing was applied"):
        run_sync(agent)
    assert not agent.ran("is-active") and not agent.ran("ip -4 -o addr")


def test_apply_requires_a_guest():
    with patch.object(sys, "argv", ["sync", "--apply"]):
        with pytest.raises(SystemExit, match="--apply needs --guest"):
            gn.main()
