#!/usr/bin/env python3
"""
Force-redeploy one or more Portainer stacks via the Portainer API.

Workaround for the portainer/portainer Terraform provider's known
limitation (issue #18): when `stack_file_content` changes only touch
Compose `configs:` blocks, `terraform apply` succeeds and Portainer's
stored definition is updated, but the running container is NOT
recreated — the Compose `configs:` mount keeps yesterday's content
until the stack is stop+start'd via the API.

Usage:
    scripts/portainer-redeploy.py STACK_NAME [STACK_NAME ...]
    scripts/portainer-redeploy.py --from-tfplan PLAN_FILE
    scripts/portainer-redeploy.py --all-stack-changes  # parses last
                                                       # `terraform plan`
                                                       # in the cwd

Examples:
    scripts/portainer-redeploy.py prometheus reverse-proxy
    cd terraform/portainer && terraform plan -out tf.plan && \\
        ../../scripts/portainer-redeploy.py --from-tfplan tf.plan

Auth: Portainer admin password from Vault (`secret/homelab/portainer`,
field `admin_password`). Vault token from macOS Keychain
(`vault-root-token`).

The Portainer API is reached at https://192.168.59.2:9443 — that IP
is on the docker-servers-net macvlan, only host-routable from the LAN
(or via twingate when off-LAN).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

PORTAINER_URL = "https://192.168.59.2:9443"
VAULT_ADDR = "http://vault.d.lcamaral.com"
VAULT_PORTAINER_PATH = "secret/homelab/portainer"
VAULT_PORTAINER_FIELD = "admin_password"
KEYCHAIN_VAULT_TOKEN_SERVICE = "vault-root-token"


def _get_vault_token() -> str:
    user = subprocess.check_output(["whoami"], text=True).strip()
    return subprocess.check_output(
        ["security", "find-generic-password", "-w", "-s", KEYCHAIN_VAULT_TOKEN_SERVICE, "-a", user],
        text=True,
    ).strip()


def _get_portainer_password(vault_token: str) -> str:
    return subprocess.check_output(
        ["env", f"VAULT_ADDR={VAULT_ADDR}", f"VAULT_TOKEN={vault_token}",
         "vault", "kv", "get", "-field=" + VAULT_PORTAINER_FIELD, VAULT_PORTAINER_PATH],
        text=True,
    ).strip()


def _portainer_request(method: str, path: str, jwt: str | None = None, body: dict | None = None) -> tuple[int, bytes]:
    """Issue an HTTP request to Portainer; returns (status_code, body)."""
    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(f"{PORTAINER_URL}{path}", method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(body).encode()
    if jwt:
        req.add_header("Authorization", f"Bearer {jwt}")
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def _portainer_jwt(password: str) -> str:
    code, body = _portainer_request("POST", "/api/auth", body={"username": "admin", "password": password})
    if code != 200:
        sys.exit(f"error: portainer auth failed ({code}): {body[:200].decode(errors='replace')}")
    return json.loads(body)["jwt"]


def list_stacks(jwt: str) -> list[dict]:
    code, body = _portainer_request("GET", "/api/stacks", jwt=jwt)
    if code != 200:
        sys.exit(f"error: GET /api/stacks failed ({code})")
    return json.loads(body)


def stop_stack(jwt: str, sid: int, endpoint_id: int) -> bool:
    code, body = _portainer_request("POST", f"/api/stacks/{sid}/stop?endpointId={endpoint_id}", jwt=jwt)
    if code not in (200, 204):
        print(f"  WARN: stop {sid} returned {code}: {body[:200].decode(errors='replace')}", file=sys.stderr)
        return False
    return True


def start_stack(jwt: str, sid: int, endpoint_id: int) -> bool:
    code, body = _portainer_request("POST", f"/api/stacks/{sid}/start?endpointId={endpoint_id}", jwt=jwt)
    if code not in (200, 204):
        print(f"  WARN: start {sid} returned {code}: {body[:200].decode(errors='replace')}", file=sys.stderr)
        return False
    return True


def names_from_tfplan(plan_path: Path, state_dir: Path) -> list[str]:
    """Extract stack names from a `terraform plan -out` binary plan.

    `terraform show -json` requires provider plugins, so we run it
    from inside `state_dir` (where `terraform init` has been run).
    `plan_path` is resolved relative to state_dir if not absolute.
    """
    if not plan_path.is_absolute():
        plan_path = (state_dir / plan_path).resolve()
    show = subprocess.run(
        ["terraform", "-chdir=" + str(state_dir), "show", "-json", str(plan_path)],
        capture_output=True, text=True, check=False,
    )
    if show.returncode != 0:
        sys.exit(f"error: `terraform -chdir={state_dir} show -json {plan_path}` failed: {show.stderr}")
    plan = json.loads(show.stdout)
    names: list[str] = []
    for change in plan.get("resource_changes", []):
        if change.get("type") != "portainer_stack":
            continue
        actions = change.get("change", {}).get("actions") or []
        if "update" not in actions and "create" not in actions:
            continue
        # The `name` attribute carries the Portainer stack name.
        name = change.get("change", {}).get("after", {}).get("name")
        if name:
            names.append(name)
    return names


def names_from_state(state_dir: Path) -> list[str]:
    """List all portainer_stack names from the terraform state in state_dir."""
    pull = subprocess.run(
        ["terraform", "-chdir=" + str(state_dir), "state", "pull"],
        capture_output=True, text=True, check=False,
    )
    if pull.returncode != 0:
        sys.exit(f"error: terraform state pull failed: {pull.stderr}")
    state = json.loads(pull.stdout)
    names: list[str] = []
    for r in state.get("resources", []):
        if r.get("type") != "portainer_stack":
            continue
        for inst in r.get("instances", []):
            n = inst.get("attributes", {}).get("name")
            if n:
                names.append(n)
    return names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stacks", nargs="*", help="Stack names to redeploy (e.g. `grafana prometheus`).")
    parser.add_argument("--from-tfplan", metavar="PLAN_FILE", help="Read stack names from a `terraform plan -out` binary.")
    parser.add_argument("--state-dir", default="terraform/portainer", help="Path to the TF root for --from-tfplan + name lookups.")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be redeployed; don't touch Portainer.")
    parser.add_argument("--sleep", type=float, default=4.0, help="Seconds to sleep between stop and start (default: 4).")
    args = parser.parse_args()

    targets: list[str] = list(args.stacks)
    if args.from_tfplan:
        targets += names_from_tfplan(Path(args.from_tfplan), Path(args.state_dir))
    if not targets:
        sys.exit("error: no stack names provided. Pass names as args or use --from-tfplan.")

    targets = sorted(set(targets))
    print(f"Will redeploy: {', '.join(targets)}")

    if args.dry_run:
        print("(dry-run; skipping API calls)")
        return 0

    vault_token = _get_vault_token()
    portainer_pw = _get_portainer_password(vault_token)
    jwt = _portainer_jwt(portainer_pw)

    stacks = list_stacks(jwt)
    by_name = {s["Name"]: s for s in stacks}

    fails: list[str] = []
    for name in targets:
        s = by_name.get(name)
        if s is None:
            print(f"  SKIP {name}: not found in Portainer")
            fails.append(name)
            continue
        sid = s["Id"]
        ep = s["EndpointId"]
        print(f"  [{name}] stop (id={sid} endpoint={ep})...", end=" ", flush=True)
        ok = stop_stack(jwt, sid, ep)
        print("ok" if ok else "FAIL")
        if not ok:
            fails.append(name)
            continue
        time.sleep(args.sleep)
        print(f"  [{name}] start...", end=" ", flush=True)
        ok = start_stack(jwt, sid, ep)
        print("ok" if ok else "FAIL")
        if not ok:
            fails.append(name)

    if fails:
        print(f"\nFAILED: {', '.join(fails)}", file=sys.stderr)
        return 1
    print(f"\nRedeployed {len(targets)} stack(s) cleanly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
