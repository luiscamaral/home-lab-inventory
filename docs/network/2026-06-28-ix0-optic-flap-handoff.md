# ix0 ↔ switch24a Port 27 — 10G SFP+ Optic Flap: Hardware Handoff

**Date:** 2026-06-28 · **Status:** diagnosed, awaiting hardware action ·
**Prior RCA:** [`2026-06-18-lan-trunk-ix0-outage-rca.md`](2026-06-18-lan-trunk-ix0-outage-rca.md)

## Verdict

A **marginal/failing optical link** on the `ix0` ↔ `Te1/0/27` 10Gbase-SR run is
corrupting the **pfSense-TX → switch-RX** direction. Switch Port 27 is taking
~12 CRC errors/sec **and it is the only errored port on the entire switch**. This
is the physical root cause of the 2026-06-28 LAN/NFS cascade (NFS stalls →
Vault/keycloak-db/rundeck-db damage). Confidence **HIGH** on the link + direction;
**MEDIUM** on which component (optic vs fiber) because DDM is unreadable remotely.

## Evidence (read-only, both ends agree)

| Counter | Baseline | Now | Note |
|---|---|---|---|
| pfSense `dev.ix.0.mac_stats.remote_faults` | 26,996,405 | 59,845,545 | climbing (+32.8M) |
| pfSense `mac_stats.local_faults` | 3,169 | 7,190 | low |
| pfSense `mac_stats.crc_errs` / `netstat Ierrs` | 2 / — | 2 / 2 | pfSense RX clean |
| switch `Te1/0/27 ifInErrors` | — | 55.38M | **+148 in 12s ≈ 12/sec, climbing** |
| switch `Te1/0/27 ifOutErrors` | — | 0 | switch→pfSense clean |
| switch `ifInErrors` on every other port | — | 0 | **only Port 27 errors** |
| `pfsense_link_flaps_total{ix0}` | 20 | 21 | ~4 events/24h |

`remote_faults (59.8M) ≈ ifInErrors (55.4M)` — the same fault counted at both ends.
The link is **UP right now** (STP Forwarding, not blocking) but actively corrupting.
The most recent "flap" was the `ix0-watchdog` deliberately bouncing the trunk at
22:22 (46s outage) after the optic made all LAN hosts unreachable for ~3 min.

## Localization — pfSense-TX → switch-RX strand

- switch RX dirty (`ifInErrors` climbing), switch TX clean (`ifOutErrors 0`).
- pfSense RX clean (`crc_errs 2`), pfSense sees partner faulting (`remote_faults` climbing).
- Only Port 27 errors on the switch → localized to this one optical run, not the switch.

**Component ranking** (DDM would separate these; unavailable remotely):

1. pfSense-side SFP+ **TX laser** degrading — feeds the corrupt strand (most likely).
2. LC **fiber/connector** on the pfSense-TX → switch-RX strand (dirty/bent endface).
3. switch-side SFP+ RX — possible but lower (its TX is perfectly clean).

## DDM (optical power) — get it at the rack

Unreadable remotely: pfSense ixgbe exposes no DDM OID; Omada `/api/v2` returns
`Unsupported`; SNMP ENTITY-SENSOR/private MIBs empty; switch SSH (22) refused. To read it:

- **Omada web UI** `http://192.168.32.55:8088` → switch24a → Port 27 → SFP/DDM panel.
- Console-cable CLI: `show interface transceiver`.
- Or pull each optic and read on an SFP/light meter.

10G-SR norms: RX ≈ −3…−10 dBm (marginal < ≈ −12…−14, LOS ≈ −17), TX ≈ −3…−8 dBm,
temp < 70 °C.

## Hardware action list (do in order; stop when `ifInErrors` flattens)

> ⚠️ Every unplug/reseat/swap drops Port 27 → the **entire LAN trunk**
> (HOME/IoT/SVR and all tagged VLANs) blips for ~30–50s (link re-init + STP
> reconverge) and NFS stalls briefly. Do this in a maintenance window.

**Step 0 — disarm the auto-bouncer** so it does not fight you mid-work:

```bash
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh stop'      # re-arm later with: start
```

**Live error watch** (run on the Mac; leave it running through every step — success =
`ifInErrors` stops climbing):

```bash
export VAULT_ADDR=http://192.168.59.25:8200
export VAULT_TOKEN=$(security find-generic-password -w -a "$USER" -s vault-root-token)
COMM=$(vault kv get -field=snmp_community secret/homelab/switch24a)
while true; do printf '%s Te1/0/27 ifInErrors=' "$(date +%T)"; \
  snmpget -v2c -c "$COMM" -Oqv 192.168.32.39 1.3.6.1.2.1.2.2.1.14.49179; sleep 5; done
```

1. **Clean + reseat BOTH LC connectors** — pfSense `ix0` optic and switch `Te1/0/27`
   optic. Fiber cleaner / lint-free + IPA on all four endfaces. Cheapest, fixes most
   single-strand CRC. Watch the counter ~5 min.
2. **Swap the fiber patch cable** (LC-LC OM3/OM4) if cleaning does not flatten errors.
3. **Swap the pfSense-side SFP+ optic** (the `ix0` X520 transceiver) — most-likely part.
4. **Swap the switch-side `Te1/0/27` SFP+ optic** if errors persist.
5. **Confirm fixed:** `ifInErrors` flat ≥10 min, `remote_faults` flat, zero flaps ≥30 min:

```bash
ssh pfsense 'sysctl dev.ix.0.mac_stats.remote_faults dev.ix.0.mac_stats.crc_errs'
ssh pfsense 'grep flaps_total /var/tmp/node_exporter/ix0_link.prom'
```

**Step 6 — re-arm the watchdog:**

```bash
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh start && /usr/local/sbin/ix0-watchdog.sh status'
```

## Open follow-ups (IaC / monitoring debt)

- **`ix0-watchdog` is hand-placed, NOT in the repo** — `/usr/local/sbin/ix0-watchdog.sh`,
  a boot hook, and `/etc/cron.d/ix0-watchdog`. Adopt into `pfsense/scripts/` +
  `scripts/sync-pfsense-scripts.py` (no behavior change); violates IaC-first until then.
- **No alert rule fires on ix0 flaps.** Metric + Grafana panel are live, but nobody is
  paged. Add `increase(pfsense_link_flaps_total{device="ix0"}[15m]) > 0` to the
  Prometheus rules (`terraform/portainer/locals.tf`).
