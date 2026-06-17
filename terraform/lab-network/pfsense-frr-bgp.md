# pfSense FRR BGP — lab cluster peering (applied 2026-06-16)

The pfSense side of the lab-network BGP is **not** Terraform-managed (pfSense isn't in this repo's IaC).
This records what was applied to the production router so it's reproducible + revertible.

## State: LIVE + verified

- `pfSense-pkg-frr-2.1.2_1` installed; BGP **Established** with the lab-router (`192.168.48.2`, AS65010).
- pfSense (AS65000) learned `192.168.30.0/24 via 192.168.48.2` (in the kernel FIB) → the homelab can
  route to the cluster segment.
- **Config backup before changes:** `/tmp/pfsense-config-2026-06-16-pre-frr.xml` (487 KB).

## What was applied (via SSH `php`, using the FRR package's integrated raw config)

Config set in `config.xml`: `installedpackages/frr/config/0/{enable=on,routerid=192.168.48.1,password=zebra}`,
`installedpackages/frrbgp/config/0/{enable=on,asnumber=65000,routerid=192.168.48.1}`, and
`installedpackages/frrglobalraw/config/0/frr` = base64 of:

```text
frr defaults traditional
hostname pfsense-lab
router bgp 65000
 bgp router-id 192.168.48.1
 no bgp ebgp-requires-policy
 neighbor 192.168.48.2 remote-as 65010
 address-family ipv4 unicast
  neighbor 192.168.48.2 activate
  neighbor 192.168.48.2 soft-reconfiguration inbound
  neighbor 192.168.48.2 prefix-list CLUSTER-IN in
 exit-address-family
exit
ip prefix-list CLUSTER-IN seq 5 permit 192.168.30.0/24
ip prefix-list CLUSTER-IN seq 10 permit 10.244.0.0/16
line vty
```

Then `frr_generate_config()` (applies + restarts FRR). pfSense **advertises nothing** and accepts **only**
the cluster prefixes inbound — additive, no overlap with existing routing. FRR is a separate daemon, so a
bad config can't break pfSense's WAN/pf/SSH (verified: WAN `default via 192.168.28.1` stayed up throughout).

## Asymmetric-routing fix (Sprint 1.4)

`config_set_path('filter/bypassstaticroutes', true)` (System → Advanced → Firewall & NAT → "Bypass firewall
rules for traffic on the same interface") + `filter_configure()`. **Note: the config path is `filter/`, not
`system/`** (pfSense reads it via `config_path_enabled('filter','bypassstaticroutes')`). Needed because the
router replies to SVR/HOME hosts directly on-link, bypassing pfSense's state table.

## Rollback

```sh
# restore the pre-change config, or surgically:
ssh pfsense 'php -r "require_once(\"config.inc\"); require_once(\"/usr/local/pkg/frr.inc\");
  config_del_path(\"installedpackages/frrglobalraw\"); config_del_path(\"installedpackages/frrbgp\");
  config_set_path(\"installedpackages/frr/config/0/enable\",\"\"); write_config(\"revert frr\");
  frr_generate_config();"'
ssh pfsense 'pkg delete -y pfSense-pkg-frr'   # full removal
# or restore: cp /tmp/pfsense-config-2026-06-16-pre-frr.xml /conf/config.xml && reboot
```

## LAB network route migration (2026-06-17) — HOMELAB gateway → lab-router

The old pfSense **HOMELAB gateway** (`opt2 → 192.168.7.10`, a static route `192.168.100.0/24 → HOMELAB`
via the Proxmox HOME leg) was the pre-lab-router path to the LAB net. It was replaced by the lab-router:

- **lab-router** now advertises `192.168.100.0/24` too (added `network 192.168.100.0/24` to its `frr.conf`),
  and acts as a symmetric transit: nftables FORWARD allows `HOME/SVR → 192.168.100.0/24` and **masquerades**
  it to the LAB leg (`.100.2`) so LAB hosts reply on-link → reliable return (the lab-router is on the LAB
  segment but is **not** its gateway — Proxmox `.100.1` is — so the masquerade is required).
- **pfSense** CLUSTER-IN prefix-list gained `seq 15 permit 192.168.100.0/24` (via the `frrglobalraw` base64 +
  `frr_generate_config()`). Verified: pfSense installs `192.168.100.0/24 → 192.168.48.2` and reaches
  `.100.1`/`.100.254` at 0% loss.
- **Gotcha — zebra/kernel desync:** after the stale static route's kernel entry was already gone, zebra still
  held a phantom distance-0 "kernel" route that blocked the BGP route. Fix = a **full FRR restart via
  `frr_generate_config()`** (NOT `service frr restart`, which hangs and leaves FRR down — recover with
  `frr_generate_config()`). A fresh start makes zebra re-read the kernel FIB and install the BGP route.

### HOMELAB decommission status: functionally done, config-removal BLOCKED

The HOMELAB gateway + its static route are **disabled and inert** (no kernel route; LAB now rides BGP), so
they are functionally decommissioned. **Removing the disabled entries from `config.xml` is blocked by a
pfSense bug:** `write_config()` throws in `cleanup_backupcache()` → `getConfig(): Return value must be of
type array, int returned` (config.lib.inc:1523). This is the **same bug behind the Status→Services PHP
errors** — `getConfig()`'s L2 cache fallthrough returns an int. **pfSense currently cannot save ANY config
change via the normal path.** Do NOT force `write_config` or hand-edit `config.xml` on the live router; fix
the config-library issue deliberately first (see next steps). Pre-change backup:
`/tmp/pfsense-config-2026-06-17-pre-labroute.xml`.

## TODO (Sprint 2-adjacent)

- Cluster BGP peers (`192.168.30.11-.22`, AS65011) come up when Talos exists; the router already peers them.
- Tighten the lab-router nftables zone matrix (TODO in `cloud-init/lab-router.yaml`) once cluster traffic
  is testable.
