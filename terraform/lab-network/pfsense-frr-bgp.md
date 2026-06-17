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
ip route 192.168.100.0/24 192.168.7.10
line vty
```

> The `ip route 192.168.100.0/24 192.168.7.10` line is the **LAB direct route** added 2026-06-17 (see "LAB
> network routing" below). Everything above it is the original cluster-BGP bring-up.

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

## LAB network routing (2026-06-17, final) — DIRECT via Proxmox; lab-router is cluster-only

The old pfSense **HOMELAB gateway** (`opt2 → 192.168.7.10`, static route `192.168.100.0/24 → HOMELAB` via the
Proxmox HOME leg) routed the LAB net. **Final design: LAB stays on the direct Proxmox path; the lab-router
routes only the cluster.**

- **Why not via the lab-router:** an interim attempt advertised `192.168.100.0/24` from the lab-router + a
  `HOME/SVR → LAB` masquerade. It made pfSense→LAB work but **broke LAB-originated egress** — the masquerade
  mangled the reply source, so the LAB Pi-hole (`.100.254`) couldn't reach its upstream (`.4.1`) or the
  internet (DNS dead). Root cause: the lab-router is _on_ the LAB segment but is **not** its gateway
  (Proxmox `.100.1` is). So it's the wrong router for LAB. **That advertisement + masquerade were reverted**
  (lab-router `frr.conf` / nftables in `cloud-init/lab-router.yaml`); the lab-router now advertises only
  `192.168.30.0/24`.
- **LAB route on pfSense (current):** a persistent **FRR static route** in `frrglobalraw`:
  `ip route 192.168.100.0/24 192.168.7.10` (distance 1, beats any BGP). Symmetric egress via Proxmox
  (Proxmox is the LAB gateway). CLUSTER-IN prefix-list = `seq 5 192.168.30.0/24` + `seq 10 10.244.0.0/16`
  only (the interim `seq 15` for LAB was removed). Verified: pfSense installs
  `S>* 192.168.100.0/24 via 192.168.7.10`, reaches `.100.1`/`.100.254` at 0% loss, and `.100.254` resolves
  public names again. No automatic backup (LAB depends on Proxmox `.7.10`); add a floating route later if
  redundancy is wanted.
- **FRR restart caveat:** `service frr restart` hangs/leaves FRR down on this box; restart via
  `frr_generate_config()`. A fresh start also clears any zebra/kernel route desync.

### HOMELAB decommission status: DONE (config entries removed)

The HOMELAB gateway + its `192.168.100.0/24` static route are **removed from `config.xml`** (verified:
`config_get_path('gateways/gateway_item')` = WAN1GW + WAN2_DHCP only; no LAB static route). LAB rides BGP;
production (DHCP/WAN/cluster route) unaffected.

**How (important caveat):** the normal `write_config()` path is **broken** on this box — it throws in
`cleanup_backupcache()` → `getConfig(): Return value must be of type array, int returned`
(config.lib.inc:1523; `syncBackupCache` line ~1372 opens a config root whose XML+cache are absent, so
`getConfig` returns its non-array default). This is the **same fault behind the Status→Services PHP errors**,
and it means **pfSense currently cannot save config via the GUI / normal path.** The two entries were removed
with a **one-time `DOMDocument` bypass** (load `config.xml` → remove the 2 nodes by XPath → validate with
`parse_xml_config` + structural checks → atomic `rename` → clear `/tmp/config.cache`). `config_write_file()`
alone did NOT work (a legacy-`$config` vs `config_set_path` API disconnect in CLI). **The underlying
`write_config` bug is still present** — fix it deliberately before relying on GUI saves (see next steps).
Pre-change backups: `/tmp/pfsense-config-2026-06-17-pre-labroute.xml`, `/tmp/config-pre-rmhomelab-*.xml`.

## TODO (Sprint 2-adjacent)

- Cluster BGP peers (`192.168.30.11-.22`, AS65011) come up when Talos exists; the router already peers them.
- Tighten the lab-router nftables zone matrix (TODO in `cloud-init/lab-router.yaml`) once cluster traffic
  is testable.
