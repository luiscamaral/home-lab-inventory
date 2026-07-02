# ix0 ↔ switch24a Port 27 — 10G SFP+ Optic Flap: Hardware Handoff

**Date:** 2026-06-28 (updated 2026-07-02) · **Status:** diagnosed, awaiting the
replacement optic (material in transit) ·
**Prior RCA:** [`2026-06-18-lan-trunk-ix0-outage-rca.md`](2026-06-18-lan-trunk-ix0-outage-rca.md)

## Verdict

A **marginal/failing optical link** on the `ix0` ↔ `Te1/0/27` 10Gbase-SR run is
corrupting the **pfSense-TX → switch-RX** direction. Switch Port 27 is the **only
errored port on the entire switch**. This is the physical root cause of the
2026-06-28 LAN/NFS cascade (NFS stalls → Vault/keycloak-db/rundeck-db damage).

**Confidence HIGH — and it is NOT the switch's side** (raised from MEDIUM on
2026-07-02 once DDM was obtained from the pfSense end): pfSense's own optic reads
**RX power −2.99 dBm (excellent)**, proving the **switch → pfSense** direction is
optically pristine and clearing the switch's Port-27 transmitter + electronics.
Only the **pfSense → switch** strand is corrupt. The prime suspects are now the
**pfSense-side OEM optic** (generic, not Intel-coded) or the **fiber strand** on
that direction; the switch-side optic is the _least_ likely part.

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

**Component ranking** (revised 2026-07-02 with pfSense-side DDM):

1. **pfSense-side OEM SFP+ optic** — generic module (not Intel-coded), on the TX
   side of the corrupt strand, and its TX power isn't even reportable. Prime suspect.
2. LC **fiber/connector** on the pfSense-TX → switch-RX strand (dirty/bent endface —
   corrupts exactly one direction).
3. switch-side SFP+ RX — **least likely**; its TX is proven perfect (pfSense RX −2.99 dBm).

## DDM (optical power)

**pfSense side — READABLE (this was missed at first): `ifconfig -v ix0`.** The X520
exposes SFF-8472 there. Live 2026-07-02:

| Field | Value | Read |
|---|---|---|
| plugged | `10G Base-SR (LC)`, **vendor OEM** PN `10GBASE-SR` SN `CS101O32050` (2024-03-07) | generic 3rd-party |
| **RX power** | **−2.99 dBm** | **excellent** (switch→pfSense direction is clean) |
| TX power | _not reported by this OEM module_ | — |
| TX bias | 6.86 mA | normal (rising trend would flag a dying laser) |
| module temp / voltage | 52.7 °C / 3.25 V | healthy |

RX power now also trends into Grafana (dashboard **pfSense** → _ix0 Optic — RX Power_
/ _TX Bias & Temp_ panels; metrics `pfsense_sfp_*` from the `ix0_link_metrics.sh`
feeder). A replacement optic's RX/TX power appears there automatically for comparison.

**Switch side — still UNOBTAINABLE remotely** (needed only to fully rule the switch
in/out, which the pfSense-side RX already largely does): Omada `/api/v2` returns
`Unsupported`, the SG3428X controller UI has no per-port DDM, and switch SSH (22) is
firewalled. To read it at the rack: pull the Port-27 optic and read on a light meter,
or console-cable `show interface ethernet 1/0/27 transceiver`.

10G-SR norms: RX ≈ −3…−10 dBm (marginal < ≈ −12…−14, LOS ≈ −17), TX ≈ −3…−8 dBm,
temp < 70 °C.

**Software levers ruled out** (2026-07-02): `advertise_speed` force-10G is **rejected
on an SFP+ port** (`Invalid argument` — the module dictates speed); `flow_control` is
inert (`xon/xoff` counters = 0, no pause frames); the `ix` driver is already the
correct + only Intel driver; the scary `checksum_errs` counter is a benign reporting
change (pfSense bug #12904). No driver/tunable fixes symbol-level CRC — it is hardware.

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
2. **Swap the pfSense-side OEM optic** — the `ix0` X520 transceiver (SN `CS101O32050`).
   **Prime suspect** (generic module on the corrupt TX strand). Prefer an **Intel-coded
   10G-SR** module — the X520 is picky with 3rd-party optics.
3. **Swap the fiber patch cable** (LC-LC OM3/OM4) if 1–2 do not flatten errors.
4. **Swap the switch-side `Te1/0/27` SFP+ optic** — **last resort** (its TX is proven
   clean; only if 1–3 fail).
5. **Confirm fixed:** switch `ifInErrors` flat ≥10 min, `remote_faults` flat, zero flaps
   ≥30 min, and the new optic's RX/TX power healthy on the Grafana panel:

```bash
ssh pfsense 'sysctl dev.ix.0.mac_stats.remote_faults dev.ix.0.mac_stats.crc_errs'
ssh pfsense 'grep -E "flaps_total|sfp_" /var/tmp/node_exporter/ix0_link.prom'
ssh pfsense 'ifconfig -v ix0 | sed -n "/plugged/,\$p"'   # DDM: RX power, TX bias, temp
```

**Step 6 — re-arm the watchdog:**

```bash
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh start && /usr/local/sbin/ix0-watchdog.sh status'
```

## Open follow-ups (IaC / monitoring debt)

- ✅ **`ix0-watchdog` adopted into the repo** — `pfsense/scripts/ix0-watchdog.sh` +
  `ix0watchdog-rcd.sh`, synced via `scripts/sync-pfsense-scripts.py` (deployed).
- ✅ **Optic DDM now trended** — `pfsense_sfp_rx_power_dbm` / `_tx_bias_ma` /
  `_temperature_celsius` / `_voltage_volts` from `ix0_link_metrics.sh`, on the
  **pfSense** Grafana dashboard (RX Power + TX Bias/Temp panels).
- ⬜ **No alert rule fires yet.** Metrics + panels are live, but nobody is paged. Add to
  the Prometheus rules (`terraform/portainer/locals.tf`):
  - `increase(pfsense_link_flaps_total{device="ix0"}[15m]) > 0` (flap)
  - `pfsense_sfp_rx_power_dbm{device="ix0"} < -12` (optic RX degrading)
  - `pfsense_sfp_tx_bias_ma{device="ix0"} > 10` (laser bias climbing — dying laser)
