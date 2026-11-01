#!/usr/bin/env python3
"""
Sync repo-declared pfSense DHCP custom (numbered) options to the live
<dhcpd><optN><numberoptions><item> entries in pfSense's config.xml.

Source of truth: pfsense/dhcp-custom-options.yml
Read:  SSH to pfSense, awk the <dhcpd> block out of /cf/conf/config.xml.
Write: SSH to pfSense, config_set_path() + write_config() +
       services_dhcpd_configure() via /usr/local/sbin/pfSsh.php.
Auth:  SSH key (the REST API is not used at all -- see below).

We read via SSH (not REST) because the DHCP list endpoints return 504 through
HAProxy on this build -- the HOME scope alone holds ~256 reservations and
serialising them exceeds the 30 s gateway timeout. Same approach as
sync-pfsense-dhcp-static-mappings.py.

WHY THE WRITE GOES OVER pfSsh.php AND NOT THE REST API (measured 2026-08-21):
    PATCH via HAProxy (https://pfsense.home.lcamaral.com) -> 504 after 30 s.
    PATCH via the nginx backend direct (http://127.0.0.1:56880, plain HTTP --
    HAProxy is what terminates TLS) -> 504 after 180 s, nginx's own ceiling.
    The PHP model layer needs >180 s to service ONE custom_option write on the
    HOME scope; it appears to re-validate all ~256 static mappings per call.
    Four API write attempts were made and none committed (config.xml verified
    unchanged, still exactly one <number>121</number> item), so the API is not
    merely slow -- it is unusable here. We therefore write through pfSense's own
    developer shell, which sets the same config and reloads the same service.

SAVING IS NOT APPLYING -- the bug this script exists to prevent:
    On 2026-08-21 the option was saved via the GUI and config.xml held the new
    value, while /var/dhcpd/etc/dhcpd.conf still held the OLD one. dhcpd kept
    handing out the broken option to every renewing client. write_config() only
    persists; services_dhcpd_configure() is what regenerates dhcpd.conf and
    reloads the daemon. This script always does both, then re-reads to confirm.

pfSense Plus 26.03 NOTE: the global $config array is NULL in pfSsh.php on this
build -- the classic $config['dhcpd'][...] idiom silently yields nothing. Use
config_get_path() / config_set_path().

ENCODING: pfSense stores each option <value> base64-encoded in config.xml, while
the GUI field and this manifest use the PLAIN string. The script decodes what it
reads before diffing and re-encodes on write, so the manifest stays readable and
the diff is meaningful.

Matching strategy: update in place, keyed by (interface, number). Options NOT
listed in the manifest are LEFT UNTOUCHED. Creating a new numbered option is
deliberately NOT supported -- do that once in the GUI and this script will
manage it thereafter (see main()).

Requires a Python with a modern TLS/stdlib -- use the repo venv
(./.venv/bin/python), not /usr/bin/python3, which is 3.9 on LibreSSL 2.8.3.

Workflow:
    ./.venv/bin/python scripts/sync-pfsense-dhcp-options.py          # dry run
    ./.venv/bin/python scripts/sync-pfsense-dhcp-options.py --apply  # write+reload
"""

from __future__ import annotations

import argparse
import base64
import binascii
import re
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "pfsense" / "dhcp-custom-options.yml"

SSH_HOST = "pfsense"
PFSSH = "/usr/local/sbin/pfSsh.php"
CONFIG_XML = "/cf/conf/config.xml"
DHCPD_CONF = "/var/dhcpd/etc/dhcpd.conf"

# Fields we reconcile. `interface` and `number` form the key and are not diffed.
FIELDS = ("type", "value")


def _php_safe(s: str) -> str:
    """Guard against injection into the generated PHP.

    Every field we interpolate is drawn from our own manifest, but a typo or a
    future edit should fail loudly rather than execute. Interface names, option
    numbers and values are all drawn from a deliberately narrow alphabet.
    """
    if not re.fullmatch(r"[A-Za-z0-9_.:/, -]*", s):
        raise ValueError(f"refusing to interpolate unexpected characters: {s!r}")
    return s


def pfssh(php: str, timeout: int = 180) -> str:
    """Run PHP in pfSense's developer shell over SSH and return its output.

    pfSsh.php reads statements from stdin; `exec` runs them and `exit` leaves
    the shell (without `exit` it blocks waiting for more input).
    """
    script = f"{php}\nexec\nexit\n"
    out = subprocess.run(
        ["ssh", SSH_HOST, PFSSH],
        input=script, capture_output=True, text=True, timeout=timeout,
    )
    if out.returncode != 0:
        raise RuntimeError(f"pfSsh.php failed: {out.stderr.strip() or out.stdout.strip()}")
    return out.stdout


def write_option(iface: str, number: str, type_: str, value: str) -> str:
    """Set one custom option and RELOAD the DHCP service.

    The item is located by its option NUMBER, never by a cached index -- pfSense
    array indices shift when neighbouring entries are added or removed, and
    writing to a stale index would silently corrupt an unrelated option.

    services_dhcpd_configure() is not optional: write_config() alone leaves
    dhcpd.conf stale and the daemon serving the previous value (observed
    2026-08-21). See the module docstring.
    """
    iface, number, type_, value = (_php_safe(x) for x in (iface, number, type_, value))
    php = f"""
$iface = '{iface}';
$want_num = '{number}';
$items = config_get_path("dhcpd/$iface/numberoptions/item");
if (!is_array($items)) {{ echo "ERROR: no numberoptions on $iface\\n"; }} else {{
    $found = -1;
    foreach ($items as $i => $it) {{
        if ((string)$it['number'] === $want_num) {{ $found = $i; break; }}
    }}
    if ($found < 0) {{ echo "ERROR: option $want_num not found on $iface\\n"; }} else {{
        config_set_path("dhcpd/$iface/numberoptions/item/$found/type", '{type_}');
        config_set_path("dhcpd/$iface/numberoptions/item/$found/value",
                        base64_encode('{value}'));
        write_config("Set DHCP option $want_num on $iface (sync-pfsense-dhcp-options)");
        services_dhcpd_configure();
        $now = base64_decode(config_get_path(
            "dhcpd/$iface/numberoptions/item/$found/value"));
        echo "RESULT idx=$found value=$now\\n";
    }}
}}"""
    return pfssh(php)


def live_dhcpd_conf_value(number: str) -> str:
    """Read the value actually present in the GENERATED dhcpd.conf.

    config.xml and dhcpd.conf can disagree -- that divergence is the whole
    reason this script reloads the service. Verifying against the generated
    file is what proves the change reached the running daemon.
    """
    out = subprocess.run(
        ["ssh", SSH_HOST,
         f"grep -oE 'option custom-[a-z0-9-]+ [0-9a-fA-F:.]+;' {DHCPD_CONF} | tail -5"],
        capture_output=True, text=True, check=False,
    )
    return out.stdout.strip()


def _text(el, tag: str) -> str:
    child = el.find(tag)
    return (child.text or "").strip() if child is not None and child.text else ""


def _decode(value: str) -> str:
    """config.xml stores option values base64-encoded. Fall back to the raw
    string if it is not valid base64 -- older hand-made entries may be plain."""
    if not value:
        return ""
    try:
        return base64.b64decode(value, validate=True).decode("utf-8", "replace")
    except (binascii.Error, ValueError):
        return value


def fetch_live() -> dict[tuple[str, str], dict]:
    """Read <dhcpd> from config.xml via SSH.

    Returns {(interface, number): {type, value, index}} where `index` is the
    item's position within its scope's <numberoptions> (the API's `id`).

    Only SCOPE-level <numberoptions> are read. ElementTree's findall() matches
    direct children only, so the empty per-<staticmap> <numberoptions> elements
    are correctly skipped.
    """
    out = subprocess.run(
        ["ssh", "pfsense", f"awk '/<dhcpd>/,/<\\/dhcpd>/' {CONFIG_XML}"],
        capture_output=True, text=True, check=True,
    )
    # stdlib ElementTree, matching the sibling sync scripts. The input is our
    # own /cf/conf/config.xml pulled over authenticated SSH, not untrusted
    # input, and ElementTree does not resolve external entities.
    import xml.etree.ElementTree as ET  # noqa: PLC0415
    tree = ET.fromstring("<root>" + out.stdout + "</root>")
    dhcpd = tree.find("dhcpd")
    live: dict[tuple[str, str], dict] = {}
    if dhcpd is None:
        return live
    for scope in dhcpd:
        iface = scope.tag
        index = 0
        for numopts in scope.findall("numberoptions"):
            for item in numopts.findall("item"):
                number = _text(item, "number")
                if not number:
                    continue
                live[(iface, number)] = {
                    "type": _text(item, "type"),
                    "value": _decode(_text(item, "value")),
                    "index": index,
                }
                index += 1
    return live


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true",
                        help="Create/update options and apply (default: dry-run)")
    args = parser.parse_args()

    if not MANIFEST.is_file():
        sys.exit(f"error: {MANIFEST} not found")
    with MANIFEST.open() as f:
        data = yaml.safe_load(f) or {}
    declared = data.get("options", [])
    if not declared:
        print("no custom options declared in manifest")
        return 0

    live = fetch_live()
    print(f"live custom options across all scopes: {len(live)}")

    pending = 0

    for d in declared:
        iface = d["interface"]
        number = str(d["number"])
        label = f"{iface} option {number}"
        cur = live.get((iface, number))

        if cur is None:
            # Creating a brand-new numbered option means appending to an array
            # that may not exist yet. That is a different (and riskier) PHP
            # operation than updating one in place, and nothing in this repo
            # needs it yet -- so refuse loudly rather than guess.
            print(f"  ! {label} does not exist on pfSense -- create it once in the "
                  f"GUI (Services > DHCP Server), then this script will manage it")
            pending += 1
            continue

        diffs = {k: (cur[k], str(d.get(k, ""))) for k in FIELDS
                 if cur[k] != str(d.get(k, ""))}
        if not diffs:
            print(f"  = {label}: in sync")
            continue

        print(f"  ~ UPDATE {label}")
        for k, (was, want) in diffs.items():
            print(f"      {k}: {was!r} -> {want!r}")
        pending += 1
        if args.apply:
            # write_option() both persists AND reloads dhcpd -- see docstring.
            out = write_option(iface, number, d.get("type", "string"), d["value"])
            result = [ln for ln in out.splitlines()
                      if ln.startswith(("RESULT", "ERROR"))]
            for ln in result:
                print(f"    -> {ln}")
            if not result or any(ln.startswith("ERROR") for ln in result):
                sys.exit(f"error: write failed for {label}\n{out}")

    if pending == 0:
        print("DHCP custom options in sync.")
        return 0

    if not args.apply:
        print(f"\n{pending} change(s) pending -- re-run with --apply.")
        return 0

    # Verify against the GENERATED dhcpd.conf, not just config.xml. Those two
    # diverged on 2026-08-21 and the daemon kept serving the stale value.
    print("\nverifying the running dhcpd.conf:")
    for line in live_dhcpd_conf_value("").splitlines():
        print(f"  {line}")
    print("\nre-reading config to confirm:")
    for (iface, number), v in sorted(fetch_live().items()):
        print(f"  {iface} option {number} = {v['value']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
