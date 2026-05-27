# 📊 snmp-exporter — pfSense module regen

The `snmp-exporter` stack scrapes pfSense (and one day, the managed
switch) via the SNMP v2c protocol. This directory holds the inputs
needed to **regenerate** the exporter's `snmp.yml` config file from
scratch, plus the generator output itself.

## What lives here

| File | Purpose |
| --- | --- |
| `generator.yml` | Walk list + lookups + auths for the snmp_exporter generator. Source of truth for which OIDs we collect. |
| `mibs/*.txt` | pfSense-specific BEGEMOT MIB files (pulled from `/usr/share/snmp/mibs/` on pfSense). Non-IETF, not bundled with snmp_exporter. |
| `Dockerfile.generator` | Builds a generator image preloaded with the IETF/IANA standard MIB tree (via Debian's `snmp-mibs-downloader`) plus the BEGEMOT MIBs. |
| `regen.sh` | One-shot regen: build the helper image, run the generator, produce `snmp.yml`. |
| `snmp.yml` | Generator output. Committed to git so we can audit changes. **Community string is the placeholder `public`** — real value is injected at deploy. |

## Module: `pfsense`

Walks what FreeBSD `bsnmpd` on pfSense actually exposes. Only the
`mibII` and `pf` modules are loaded in `<snmpd><modules>` on
`pfsense.home.lcamaral.com`. The `hostres` module is **not** loaded
(confirmed 2026-05-26: walks of `1.3.6.1.2.1.25.*` hung every scrape
until those OIDs were removed from `generator.yml`).

| MIB / subtree | What we get |
| --- | --- |
| **`SNMPv2-MIB`** sys{UpTime,Name,Descr,Contact,Location} | basic identity |
| **`IF-MIB`** ifTable + ifXTable | per-interface counters (incl. 64-bit HC variants) with `ifName` / `ifAlias` lookups |
| **`BEGEMOT-PF-MIB`** pfStatus, pfCounter, pfStateTable, pfLimits, pfTimeouts, pfLogInterface, pfInterfaces, pfTablesTbl{Number,Table} | PF firewall daemon health, packet counters, state-table churn, capacity limits, timeouts, per-iface block/pass counters, per-pf-table summaries |

**Host-level metrics on pfSense come from the `node` Prometheus job,
not SNMP.** `node_exporter` runs on pfSense at `192.168.4.1:9100`
(installed via `pfSense-pkg-node_exporter`) and exposes
`node_cpu_seconds_total`, `node_memory_*`, `node_filesystem_*`,
`node_network_*` (per VLAN sub-interface, including `ix0.10`,
`ix0.205`, etc.), `node_nf_conntrack_entries`, and the textfile
collectors at `/var/tmp/node_exporter/` — richer FreeBSD-native
data than `HOST-RESOURCES-MIB` could give us through bsnmpd anyway.

If you ever need to re-enable the `hostres` module on pfSense (e.g.
to dual-source storage metrics): Services → SNMP → Modules →
HostRes ☑ → save. Then add the hr* names back to `generator.yml`,
re-run `regen.sh`, and the runtime walk will start including them.

**Deliberately skipped** (would explode scrape size or are noise):

- `pfTablesAddrTable` — per-IP entries inside each PF table (~3000 IPs ×
  12 columns = 36k metric lines from bogon/abusers/RFC1918 lists)
- `pfSrcNodes` — per-source-IP, can also explode under load
- `pfAltq` — Altq queues (deprecated on pfSense, all 0)
- `pfLabels` — per-PF-rule label counters (niche)
- `UCD-SNMP-MIB` (laTable / systemStats / memory / dskTable) — not in
  `bsnmpd`, only in `net-snmp`

Result: walk completes in ~70 ms (was timing out at 10 s when the
hr* OIDs were in the walk list against a bsnmpd without `hostres`).

## Regenerating

```bash
cd dockermaster/docker/snmp-exporter
./regen.sh
```

The script builds `local/snmp-generator-with-mibs` (helper image bundling
the IETF MIB tree from Debian's `snmp-mibs-downloader` + the BEGEMOT MIBs
from `mibs/`), then runs `snmp_exporter generator generate` against
`generator.yml` and writes `snmp.yml`.

If you change the walk list, edit `generator.yml` and re-run `regen.sh`.

> ℹ️ **Note on the current committed `snmp.yml`:** the walk/get OID
> lists are in sync with `generator.yml` (hand-edited 2026-05-26 to
> match the live slim on ds-1 after the hostres incident). Orphaned
> metric definitions for the dropped `hr*` names remain in the file
> — they are harmless (no OID walks them) and will be cleaned up
> when `regen.sh` is next run.

## Deploying (current state)

> ⚠️ This is the IaC-anti-pattern part. The runtime `snmp.yml` is
> bind-mounted from `/nfs/dockermaster/docker/snmp-exporter/snmp.yml`
> (see `terraform/portainer/stacks/snmp-exporter.yml` line 37). Until we
> migrate to a baked-image deploy (see _Phase E_ below), the deploy is a
> manual scp + container restart.

```bash
# 1. Pull the live community string from Vault (NOT committed to git).
COMMUNITY=$(vault kv get -field=community secret/homelab/pfsense/snmp)

# 2. Render snmp.yml with the real community substituted in.
sed "s/community: public/community: $COMMUNITY/" snmp.yml > /tmp/snmp.yml.deploy

# 3. Drop on dockermaster's NFS share, restart exporter.
scp /tmp/snmp.yml.deploy 192.168.48.45:/nfs/dockermaster/docker/snmp-exporter/snmp.yml
ssh 192.168.48.45 'docker restart snmp-exporter-snmp-exporter-1'

# 4. Verify Prometheus snmp-pfsense target stays UP and new metrics flow.
ssh 192.168.48.45 'docker exec prometheus-prometheus-1-1 wget -qO- "http://localhost:9090/api/v1/query?query=pfStateTableCount" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[\"data\"][\"result\"][0])"'

# 5. Clean up.
rm /tmp/snmp.yml.deploy
```

## Phase E: bake into a custom image (the IaC-correct fix)

The bind-mount above is tracked as an IaC-first violation
(memory: `feedback_iac_first_principle.md`). Migration plan:

1. Build a Dockerfile in this directory that `FROM`s the upstream
   snmp-exporter image and `COPY`s `snmp.yml` to `/etc/snmp_exporter/snmp.yml`.
2. Wire the build into the existing `build-multi-type-images.yml` GitHub
   workflow → push to `registry.cf.lcamaral.com/snmp-exporter:<tag>`.
3. Inject the community at runtime via env var instead of file
   substitution (`SNMP_AUTH_PFSENSE_V2_COMMUNITY` → injected via
   compose `env_file:` from a Vault-rendered `.env`).
4. Update `terraform/portainer/stacks/snmp-exporter.yml` to use the
   custom image, drop the bind-mount.
5. `terraform apply`; trigger Portainer stack stop+start (per
   `feedback_portainer_stack_redeploy.md`).

Out of scope for the initial regen PR; tracked as a follow-up.

## Troubleshooting

- _"cannot find oid 'X' to walk"_ — generator can't find the OID in its
  loaded MIBs. Either provide the missing MIB file in `mibs/` or use a
  numeric OID instead of a name in `generator.yml`'s `walk:` list.
- _"Missing MIB"_ during build — a referenced IMPORTS module isn't in
  `/var/lib/mibs/{ietf,iana,site}/`. Add the MIB file to `mibs/` and
  rebuild.
- _Empty scrape response_ — pfSense's bsnmpd doesn't load that module by
  default. Check `/var/etc/snmpd.conf` on pfSense for
  `begemotSnmpdModulePath."<name>"` entries; add the missing one via
  Services → SNMP → Modules in the pfSense UI.
