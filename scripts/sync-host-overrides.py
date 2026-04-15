#!/usr/bin/env python3
"""
Sync DNS host overrides from `pfsense/host-overrides.yml` (single source
of truth) to BOTH pihole (via a generated dnsmasq.d file) AND pfSense
(via the REST API).

Workflow:
    1. Edit `pfsense/host-overrides.yml`
    2. Run this script:
         scripts/sync-host-overrides.py            # dry run, show diff
         scripts/sync-host-overrides.py --apply    # write file + push to pfSense
    3. Run terraform to roll the dnsmasq.d file to pihole-2/-3:
         terraform -chdir=terraform/portainer apply
    4. Manually push to pihole-1 LXC (see pihole/README.md)

Architecture:
    - YAML is canonical
    - This script generates `pihole/dnsmasq.d/06-host-overrides.conf` for piholes
    - This script reconciles pfSense Unbound host_overrides via the REST API
    - pfSense API access is via `ssh pfsense 'curl ... 127.0.0.1:56880'`
      because the API is only bound to localhost on the admin subnet
    - Auth token is pulled from macOS Keychain (`pfsense-api-token`)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
YAML_PATH = REPO_ROOT / "pfsense" / "host-overrides.yml"
DNSMASQ_OUT_PATH = REPO_ROOT / "pihole" / "dnsmasq.d" / "06-host-overrides.conf"

PFSENSE_API_BASE = "http://127.0.0.1:56880/api/v2"
PFSENSE_OVERRIDES_PATH = "/services/dns_resolver/host_overrides"
PFSENSE_OVERRIDE_PATH = "/services/dns_resolver/host_override"
PFSENSE_APPLY_PATH = "/services/dns_resolver/apply"


@dataclass(frozen=True)
class Alias:
    host: str
    domain: str

    @property
    def fqdn(self) -> str:
        return f"{self.host}.{self.domain}"


@dataclass
class Override:
    host: str
    domain: str
    ip: list[str]
    description: str = ""
    aliases: list[Alias] = field(default_factory=list)

    @property
    def fqdn(self) -> str:
        return f"{self.host}.{self.domain}"

    @classmethod
    def from_yaml(cls, d: dict) -> "Override":
        ip = d["ip"]
        if isinstance(ip, str):
            # Accept comma-separated form for compatibility with the pfSense GUI.
            ip = [s.strip() for s in ip.split(",") if s.strip()]
        return cls(
            host=d["host"],
            domain=d["domain"],
            ip=list(ip),
            description=d.get("description", ""),
            aliases=[Alias(host=a["host"], domain=a["domain"]) for a in d.get("aliases", [])],
        )

    @classmethod
    def from_pfsense(cls, d: dict) -> "Override":
        ip = d.get("ip") or []
        if isinstance(ip, str):
            ip = [s.strip() for s in ip.split(",") if s.strip()]
        aliases = []
        for a in d.get("aliases") or []:
            aliases.append(Alias(host=a["host"], domain=a["domain"]))
        return cls(
            host=d["host"],
            domain=d["domain"],
            ip=list(ip),
            description=d.get("descr") or "",
            aliases=aliases,
        )

    def to_pfsense_payload(self) -> dict:
        payload = {
            "host": self.host,
            "domain": self.domain,
            "ip": self.ip,
            "descr": self.description,
        }
        if self.aliases:
            payload["aliases"] = [{"host": a.host, "domain": a.domain, "description": ""} for a in self.aliases]
        return payload

    def normalized(self) -> tuple:
        """Comparison key — order of IPs and aliases doesn't matter for equality."""
        return (
            self.host,
            self.domain,
            tuple(sorted(self.ip)),
            self.description,
            tuple(sorted((a.host, a.domain) for a in self.aliases)),
        )


def load_yaml() -> list[Override]:
    if not YAML_PATH.exists():
        sys.exit(f"error: {YAML_PATH} not found")
    with YAML_PATH.open() as f:
        raw = yaml.safe_load(f)
    if not isinstance(raw, list):
        sys.exit(f"error: {YAML_PATH} must be a YAML list")
    return [Override.from_yaml(d) for d in raw]


def get_pfsense_token() -> str:
    try:
        out = subprocess.check_output(
            ["security", "find-generic-password", "-w", "-s", "pfsense-api-token", "-a", subprocess.check_output(["whoami"]).decode().strip()],
            text=True,
        )
    except subprocess.CalledProcessError as e:
        sys.exit(f"error: pfSense API token not in Keychain (security find-generic-password -s pfsense-api-token): {e}")
    return out.strip()


def pfsense_curl(method: str, path: str, token: str, body: dict | None = None) -> dict:
    """Execute curl against pfSense API via ssh tunnel-equivalent."""
    cmd_parts = [
        "curl", "-s", "-X", method,
        "-H", f"'X-API-Key: {token}'",
        "-H", "'Content-Type: application/json'",
    ]
    if body is not None:
        # Single-quote escape for the JSON payload
        body_json = json.dumps(body)
        cmd_parts += ["-d", f"'{body_json}'"]
    cmd_parts.append(f"'{PFSENSE_API_BASE}{path}'")
    remote_cmd = " ".join(cmd_parts)
    result = subprocess.run(
        ["ssh", "pfsense", remote_cmd],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        sys.exit(f"error: ssh pfsense failed (rc={result.returncode}): {result.stderr}")
    if not result.stdout.strip():
        sys.exit(f"error: empty response from {method} {path}")
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        sys.exit(f"error: invalid JSON from {method} {path}: {e}\n{result.stdout[:500]}")
    if data.get("code", 0) >= 400:
        sys.exit(f"error: API {method} {path} returned {data.get('code')}: {data.get('message')}")
    return data


def fetch_pfsense_overrides(token: str) -> list[Override]:
    data = pfsense_curl("GET", PFSENSE_OVERRIDES_PATH, token)
    return [Override.from_pfsense(d) for d in data.get("data", [])]


def render_dnsmasq(overrides: list[Override]) -> str:
    """Generate the dnsmasq.d file content from the YAML overrides."""
    lines = [
        "# pfSense host overrides — GENERATED, do not edit by hand",
        "#",
        "# Source: pfsense/host-overrides.yml",
        "# Generator: scripts/sync-host-overrides.py",
        "#",
        "# Synced to pihole-1 (LXC, manual), pihole-2 (ds-1, terraform), and",
        "# pihole-3 (NAS, terraform). Same content also pushed to pfSense",
        "# Unbound via the REST API by the same script for clients that resolve",
        "# directly via pfSense (ADMIN VLAN, twingate connectors, etc.).",
        "#",
        "# DO NOT add `local=` markers here — these zones (home.lcamaral.com,",
        "# admin.lcamaral.com, lab.home) are intentionally NOT made authoritative",
        "# on pihole because pfSense Unbound also hosts dynamic DHCP-derived",
        "# entries in the same namespaces, and those need to remain reachable",
        "# via the upstream pihole→pfSense forward chain.",
        "",
    ]
    # Group by domain for readability
    by_domain: dict[str, list[Override]] = {}
    for o in overrides:
        by_domain.setdefault(o.domain, []).append(o)
    for domain in sorted(by_domain):
        lines.append(f"# --- {domain} ---")
        for o in sorted(by_domain[domain], key=lambda x: x.host):
            if o.description:
                lines.append(f"# {o.description}")
            for ip in o.ip:
                lines.append(f"address=/{o.fqdn}/{ip}")
            for a in o.aliases:
                for ip in o.ip:
                    lines.append(f"address=/{a.fqdn}/{ip}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def diff_overrides(yaml_list: list[Override], pf_list: list[Override]) -> tuple[list[Override], list[tuple[Override, Override]], list[Override]]:
    """Compute create/update/delete diffs (yaml is target, pfsense is current).

    Returns (to_create, to_update_pairs, to_delete).
    Identity = (host, domain).
    """
    yaml_index = {(o.host, o.domain): o for o in yaml_list}
    pf_index = {(o.host, o.domain): o for o in pf_list}
    to_create = [o for k, o in yaml_index.items() if k not in pf_index]
    to_delete = [o for k, o in pf_index.items() if k not in yaml_index]
    to_update = []
    for k, target in yaml_index.items():
        current = pf_index.get(k)
        if current and target.normalized() != current.normalized():
            to_update.append((current, target))
    return to_create, to_update, to_delete


def print_diff(to_create, to_update, to_delete) -> bool:
    """Returns True if there's any change."""
    n = len(to_create) + len(to_update) + len(to_delete)
    if n == 0:
        print("pfSense is in sync with YAML — nothing to do.")
        return False
    print(f"Diff vs pfSense: +{len(to_create)} create, ~{len(to_update)} update, -{len(to_delete)} delete")
    for o in to_create:
        print(f"  + {o.fqdn} -> {','.join(o.ip)}")
    for cur, tgt in to_update:
        print(f"  ~ {tgt.fqdn}: {cur.normalized()[2:]} → {tgt.normalized()[2:]}")
    for o in to_delete:
        print(f"  - {o.fqdn} -> {','.join(o.ip)}")
    return True


def find_pfsense_id(host: str, domain: str, token: str) -> int:
    """Look up the numeric ID of an entry by (host, domain). pfSense IDs are ordinals."""
    data = pfsense_curl("GET", PFSENSE_OVERRIDES_PATH, token)
    for d in data.get("data", []):
        if d["host"] == host and d["domain"] == domain:
            return d["id"]
    raise KeyError(f"({host}, {domain}) not found in pfSense host_overrides")


def apply_diff(to_create, to_update, to_delete, token: str) -> None:
    # Process deletes in reverse-id order so earlier indexes don't shift
    if to_delete:
        # Re-fetch the live list once and resolve each id at delete time
        live = pfsense_curl("GET", PFSENSE_OVERRIDES_PATH, token).get("data", [])
        targets = []
        for o in to_delete:
            for d in live:
                if d["host"] == o.host and d["domain"] == o.domain:
                    targets.append((d["id"], o))
                    break
        # Delete highest id first (so lower ids stay stable)
        for the_id, o in sorted(targets, key=lambda t: -t[0]):
            print(f"  DELETE id={the_id} {o.fqdn}")
            pfsense_curl("DELETE", f"{PFSENSE_OVERRIDE_PATH}?id={the_id}", token)

    for cur, tgt in to_update:
        the_id = find_pfsense_id(cur.host, cur.domain, token)
        payload = tgt.to_pfsense_payload()
        payload["id"] = the_id
        print(f"  UPDATE id={the_id} {tgt.fqdn}")
        pfsense_curl("PATCH", PFSENSE_OVERRIDE_PATH, token, body=payload)

    for o in to_create:
        print(f"  CREATE {o.fqdn}")
        pfsense_curl("POST", PFSENSE_OVERRIDE_PATH, token, body=o.to_pfsense_payload())

    # Apply all pending changes (writes config.xml and reloads Unbound)
    print("  APPLY (reloading Unbound)")
    pfsense_curl("POST", PFSENSE_APPLY_PATH, token)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="Actually write files and call pfSense API (default: dry-run)")
    parser.add_argument("--no-pfsense", action="store_true", help="Skip pfSense sync, only generate dnsmasq.d file")
    args = parser.parse_args()

    overrides = load_yaml()
    print(f"Loaded {len(overrides)} entries from {YAML_PATH.relative_to(REPO_ROOT)}")

    # Render the dnsmasq.d file
    rendered = render_dnsmasq(overrides)
    if DNSMASQ_OUT_PATH.exists():
        existing = DNSMASQ_OUT_PATH.read_text()
        if existing == rendered:
            print(f"  {DNSMASQ_OUT_PATH.relative_to(REPO_ROOT)}: up to date ({len(rendered.splitlines())} lines)")
        else:
            if args.apply:
                DNSMASQ_OUT_PATH.write_text(rendered)
                print(f"  {DNSMASQ_OUT_PATH.relative_to(REPO_ROOT)}: WROTE ({len(rendered.splitlines())} lines)")
            else:
                print(f"  {DNSMASQ_OUT_PATH.relative_to(REPO_ROOT)}: would update ({len(rendered.splitlines())} lines, --apply to write)")
    else:
        if args.apply:
            DNSMASQ_OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
            DNSMASQ_OUT_PATH.write_text(rendered)
            print(f"  {DNSMASQ_OUT_PATH.relative_to(REPO_ROOT)}: CREATED ({len(rendered.splitlines())} lines)")
        else:
            print(f"  {DNSMASQ_OUT_PATH.relative_to(REPO_ROOT)}: would create ({len(rendered.splitlines())} lines, --apply to write)")

    if args.no_pfsense:
        return 0

    # pfSense diff
    token = get_pfsense_token()
    pf = fetch_pfsense_overrides(token)
    print(f"Loaded {len(pf)} entries from pfSense")
    to_create, to_update, to_delete = diff_overrides(overrides, pf)
    has_diff = print_diff(to_create, to_update, to_delete)

    if has_diff and args.apply:
        apply_diff(to_create, to_update, to_delete, token)
        print("pfSense sync complete.")
    elif has_diff:
        print("(--apply to push changes to pfSense)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
