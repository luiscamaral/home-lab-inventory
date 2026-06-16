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

## TODO (Sprint 2-adjacent)

- Cluster BGP peers (`192.168.30.11-.22`, AS65011) come up when Talos exists; the router already peers them.
- Tighten the lab-router nftables zone matrix (TODO in `cloud-init/lab-router.yaml`) once cluster traffic
  is testable.
