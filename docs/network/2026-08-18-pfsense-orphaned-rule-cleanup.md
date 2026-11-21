# 🧹 pfSense Cleanup — Orphaned Firewall Rules Removed

**Date:** 2026-08-18 · **Applied via:** pfSense REST API `DELETE /api/v2/firewall/rule`
**Result:** 126 → 108 filter rules · running ruleset unchanged · no functional change

## What was wrong

18 filter rules were bound to interfaces or interface groups that **no longer exist**.
`<ifgroups>` is absent from `config.xml` entirely, yet rules still referenced
`LocalNetworks`, `Internet`, `PrivateNetwork` and `opt6`, while `<interfaces>` defines
only `wan, lan, opt1–opt5`. 10 of the 18 were enabled.

The five `opt6` rules are the auto-generated **HA/CARP sync** rules ("Allow configuration
synchronization", "Allow state synchronization"). They are leftovers from a sync interface
that was removed — related to the known `hasync` remnant (see Not Done below).

## Proof they were inert — this is the key evidence

pfSense's rule generator skips rules whose interface cannot be resolved, so these never
reached the packet filter. Verified by tracker lookup against the **running** ruleset:

```text
tracker 1671644519  live_rules=0   <- INERT     (x10 enabled orphans, all 0)
control tracker from a live opt2 rule: live_rules=1   <- method proven to work
```

The control is what makes this trustworthy: the same lookup finds a real rule, so a
zero result means genuinely absent, not a broken test.

Confirmed after the change:

| Check | Before | After |
|---|---|---|
| filter rules in config | 126 | **108** |
| orphaned rules | 18 | **0** |
| running ruleset (`pfctl -sr`) | 266 lines | **266 lines** |
| `pfctl -si` status | Enabled | Enabled |

The running ruleset being byte-for-byte unchanged is the proof that nothing functional
was removed. No `/firewall/apply` was needed for the same reason.

## Rules removed

| Interface | Count | Enabled | Notes |
|---|---|---|---|
| `LocalNetworks` | 7 | 3 | incl. "Reject all DNS requests (53 & 853)" — inert, which is why DoT leaks out of HOME |
| `Internet` | 6 | 0 | all disabled |
| `opt6` | 5 | 5 | HA/CARP sync rules from a removed sync interface |
| `PrivateNetwork` | 2 | 1 | "Allow 239.255.255.250" (SSDP) |

Deleted in **descending index order**, verifying each rule's `tracker` immediately before
its `DELETE`. The API addresses rules by array index and reorders after every mutation
(`memory/feedback_pfsense_api_id_shift.md`), so ascending order or a blind index would
risk deleting a live rule. 18 deleted, 0 skipped — every tracker matched.

Pre-change `config.xml` snapshot left on the router at `/tmp/pre-cleanup.xml`; pfSense
also auto-snapshots to `/cf/conf/backup/` before each change.

## ⚠️ Not done — no sanctioned IaC path exists

`.claude/operating-rules.md` forbids SSH-editing `config.xml` or running `write_config`.
These have **zero REST API coverage** (verified against the live 264-path OpenAPI schema),
so they cannot be cleaned without breaking that rule. They are inert and cosmetic —
**except the `hasync` remnant, which has real operational history.**

| Item | Size | API? | Impact |
|---|---|---|---|
| `hasync` — `pfsyncpeerip=192.168.32.34`, `pfsyncinterface=lan`, empty `synchronizetoip`/`username` | — | **none** | Half-configured HA pointing at a dead peer. Per `memory/feedback_pfsense_package_xmlrpc_sync.md` this class of remnant caused packages to call a dead `pfsense2` on every restart, contributing to WAN/link flaps |
| `ntopng`, `miniupnpd`, `zeek`, `zeekcontrol` | ~1.6 KB | **none** | cosmetic |
| `freeradius`, `freeradiusclients`, `freeradiusinterfaces`, `freeradiuseapconf` | ~2.3 KB | entity-level only, package not installed | cosmetic |

Recommended: remove `hasync` via the GUI (System → High Availability) — it is the only
one with a functional argument. The other 8 sections are safe to leave indefinitely.

## Also noted

`docs/network/pfsense.md` claims pfBlockerNG is installed and active. The live config shows
**it is not installed** (15 packages, none pfBlockerNG). That doc is stale.
