#!/usr/bin/env python3
"""
Sync DNS state to ALL pihole instances + pfSense Unbound from the
authoritative repo files:
  * pihole-1 (LXC 10000 on proxmox) — `pct push` of every file in
    `pihole/dnsmasq.d/` listed in `PIHOLE_LXC_FILES`, then pihole-FTL
    reload (covers 04-d-lcamaral-com.conf, 05-home.conf, and the
    generated 06-host-overrides.conf).
  * pihole-2 / pihole-3 (Docker on ds-1 / nas) — same files picked up
    via `terraform -chdir=terraform/portainer apply` (Compose configs:).
  * pfSense Unbound — host overrides reconciled via the pfSense REST API.

Source of truth for host overrides: `pfsense/host-overrides.yml`.
04 / 05 are hand-curated zone files in `pihole/dnsmasq.d/`.

Workflow:
    1. Edit either the YAML (host overrides) or the static .conf files
    2. Run this script:
         scripts/sync-host-overrides.py            # dry run, show diff
         scripts/sync-host-overrides.py --apply    # push everywhere
    3. For pihole-2/-3 (Docker), run terraform afterwards:
         terraform -chdir=terraform/portainer apply

Auth: macOS Keychain (`pfsense-api-token`).
LXC access: `ssh proxmox 'sudo pct push 10000 ...'`.
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

PIHOLE_LXC_VMID = 10000
PIHOLE_DNSMASQ_DIR = REPO_ROOT / "pihole" / "dnsmasq.d"
PIHOLE_LXC_DNSMASQ_DIR = "/etc/dnsmasq.d"
# Files that the script keeps in lockstep on the LXC. 06 is generated
# by render_dnsmasq() (host overrides); 04 and 05 are hand-curated zone
# files but pushed by the same flow so the LXC mirrors what the
# Compose `configs:` mechanism injects into pihole-2/-3.
PIHOLE_LXC_FILES = ["04-d-lcamaral-com.conf", "05-home.conf", "06-host-overrides.conf"]
PROXMOX_SUDO = "SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A"


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


def fetch_pihole_lxc_file(filename: str) -> str | None:
    """Read one dnsmasq.d file from the pihole-1 LXC. Returns None on miss."""
    target = f"{PIHOLE_LXC_DNSMASQ_DIR}/{filename}"
    cmd = f"{PROXMOX_SUDO} pct exec {PIHOLE_LXC_VMID} -- cat {target}"
    result = subprocess.run(["ssh", "proxmox", cmd], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return None
    return result.stdout


def push_pihole_lxc_file(filename: str, content: str) -> None:
    """Stage content on proxmox, pct push it into the LXC. Caller reloads FTL once at the end."""
    tmp_path = f"/tmp/{filename}"
    target = f"{PIHOLE_LXC_DNSMASQ_DIR}/{filename}"
    # Step 1: write content to a tempfile on proxmox (lamaral-writable)
    result = subprocess.run(
        ["ssh", "proxmox", f"cat > {tmp_path}"],
        input=content, capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        sys.exit(f"error: stage to proxmox /tmp/{filename} failed: {result.stderr}")

    # Step 2: pct push into the LXC filesystem
    push_cmd = f"{PROXMOX_SUDO} pct push {PIHOLE_LXC_VMID} {tmp_path} {target} --perms 0644"
    result = subprocess.run(["ssh", "proxmox", push_cmd], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        sys.exit(f"error: pct push {filename} failed: {result.stderr or result.stdout}")


def reload_pihole_ftl_lxc() -> None:
    """Reload pihole-FTL inside the LXC; falls back to restart if reload fails."""
    reload_cmd = f"{PROXMOX_SUDO} pct exec {PIHOLE_LXC_VMID} -- systemctl reload pihole-FTL"
    result = subprocess.run(["ssh", "proxmox", reload_cmd], capture_output=True, text=True, check=False)
    if result.returncode == 0:
        return
    restart_cmd = f"{PROXMOX_SUDO} pct exec {PIHOLE_LXC_VMID} -- systemctl restart pihole-FTL"
    result = subprocess.run(["ssh", "proxmox", restart_cmd], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        sys.exit(f"error: pihole-FTL reload+restart both failed: {result.stderr or result.stdout}")


def sync_pihole_lxc(rendered_06: str, apply: bool) -> None:
    """Compare each PIHOLE_LXC_FILES entry on the LXC vs the repo and push diffs."""
    print(f"pihole-1 LXC ({PIHOLE_LXC_VMID}):")
    pushed = []
    for filename in PIHOLE_LXC_FILES:
        if filename == "06-host-overrides.conf":
            target_content = rendered_06
        else:
            repo_path = PIHOLE_DNSMASQ_DIR / filename
            if not repo_path.exists():
                print(f"  {filename}: SKIP (not in repo)")
                continue
            target_content = repo_path.read_text()

        current = fetch_pihole_lxc_file(filename)
        if current == target_content:
            print(f"  {filename}: up to date")
            continue

        verb = "create" if current is None else "update"
        if not apply:
            print(f"  {filename}: would {verb} ({len(target_content.splitlines())} lines, --apply to push)")
            continue

        push_pihole_lxc_file(filename, target_content)
        pushed.append(filename)
        print(f"  {filename}: PUSHED ({len(target_content.splitlines())} lines)")

    if pushed and apply:
        reload_pihole_ftl_lxc()
        print(f"  pihole-FTL reloaded after pushing {len(pushed)} file(s)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="Actually write files and call APIs (default: dry-run)")
    parser.add_argument("--no-pfsense", action="store_true", help="Skip pfSense sync")
    parser.add_argument("--no-lxc", action="store_true", help="Skip pihole-1 LXC sync")
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

    # pihole-1 LXC sync (independent of pfSense)
    if not args.no_lxc:
        sync_pihole_lxc(rendered, args.apply)

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
