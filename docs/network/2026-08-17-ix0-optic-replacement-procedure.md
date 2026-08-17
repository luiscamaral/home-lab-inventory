# 🔧 ix0 Optic Replacement — Rack Procedure

**Date:** 2026-08-17 · **Status:** ready to execute, hardware swap outstanding since 2026-06-28
**Diagnosis:** [`2026-06-28-ix0-optic-flap-handoff.md`](2026-06-28-ix0-optic-flap-handoff.md) — still valid,
re-confirmed today. This page is the _execution_ checklist; that page is the _why_.

## 🎯 What you are replacing and why

| Item | Value |
|---|---|
| Part | pfSense-side SFP+ on `ix0` |
| Module | OEM (not Intel-coded) `10GBASE-SR`, **SN `CS101O32050`**, dated 2024-03-07 |
| Link | `ix0` ↔ switch24a **`Te1/0/27`**, 10Gbase-SR, LC duplex |
| Faulty direction | **pfSense TX → switch RX** (one direction only) |
| Replacement | **Intel-coded 10G-SR** preferred — the X520 is picky with third-party optics |

**The switch end is not suspect.** pfSense RX power reads −3.04 dBm (excellent), switch `ifOutErrors` = 0,
and Port 27 is the only errored port on the entire switch. Swap the pfSense side first.

## 📊 Baseline before you touch anything (2026-08-17 15:50)

| Metric | Value | Healthy |
|---|---|---|
| Loss @1400 B | **46–55 %** | < 0.5 % |
| Loss @56 B | **6.7 %** | 0 % |
| `remote_faults` | **51–55 /s** | 0 /s |
| `local_faults`, `crc_errs` | 0 delta | 0 |
| DDM RX power / TX bias / temp | −3.04 dBm / 6.61 mA / 50.8 °C | unchanged is fine |

A bounce currently recovers to ~6 % for a while, then decays back over roughly two hours.

## ⚠️ Blast radius

Every unplug, reseat or swap drops Port 27, which is the **whole LAN trunk** — HOME, IoT, SVR and all
tagged VLANs blip for ~30–50 s (link re-init + STP reconverge) and NFS stalls briefly.
**WAN2 failover does not help**: this is the LAN trunk, not a WAN link, so both WANs are irrelevant to
the outage. Do this in a maintenance window.

## ✅ Step 0 — disarm the watchdog (do not skip)

Otherwise it will bounce the link while your hands are in the rack.

```bash
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh stop && /usr/local/sbin/ix0-watchdog.sh status'
```

Alternative that keeps metrics flowing but never bounces:

```bash
ssh pfsense 'touch /var/db/ix0-watchdog.nobounce'      # remove the file to re-enable
```

## 👀 Live error watch — leave this running through every step

Success = the counter **stops climbing**. Run on the Mac:

```bash
while true; do
  ssh pfsense 'printf "%s remote_faults=%s crc=%s local=%s\n" \
    "$(date +%T)" \
    "$(sysctl -n dev.ix.0.mac_stats.remote_faults)" \
    "$(sysctl -n dev.ix.0.mac_stats.crc_errs)" \
    "$(sysctl -n dev.ix.0.mac_stats.local_faults)"'
  sleep 5
done
```

Second terminal, the metric that actually matters to users:

```bash
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh check'    # mean large-frame loss across 2 targets
```

## 🔩 Swap order — stop as soon as `remote_faults` goes flat

1. **Clean + reseat both LC connectors** — pfSense `ix0` and switch `Te1/0/27`. Fibre cleaner or
   lint-free wipe + IPA on all four endfaces. Cheapest fix and it resolves most single-strand errors.
   Watch ~5 min before concluding.
2. **Swap the pfSense-side optic** (SN `CS101O32050`) — **prime suspect**. Prefer an Intel-coded module.
3. **Swap the LC patch cable** (OM3/OM4) if 1–2 did not flatten the counter.
4. **Swap the switch-side `Te1/0/27` optic** — last resort; its transmitter is proven clean.

### 🧪 Optional 30-second discriminator: fibre vs optic

If after step 1 you want to know whether the strand or the module is at fault, **swap the two LC strands
at one end only** (A↔B). This reverses which physical fibre carries pfSense's transmit.

- Fault **follows the strand** → the fibre is bad; `local_faults` / `crc_errs` start climbing and
  `remote_faults` goes quiet (the damage moves to _our_ receive side).
- Fault **stays on transmit** (`remote_faults` still climbing, `crc_errs` still 0) → the **optic** is bad.

Remember to swap them back if it changes nothing.

## ✔️ Verification — all five must hold

```bash
# 1. fault counters flat over 60s (the definitive test)
ssh pfsense 'a=$(sysctl -n dev.ix.0.mac_stats.remote_faults); sleep 60; \
  b=$(sysctl -n dev.ix.0.mac_stats.remote_faults); echo "remote_faults delta=$((b-a)) (want 0)"'

# 2. loss gone at the size that matters, and at small sizes
ssh pfsense 'for s in 56 1400; do printf "  %sB: " "$s"; \
  ping -c 300 -i 0.04 -s $s -q -t 5 192.168.48.45 | grep -o "[0-9.]*% packet loss"; done'

# 3. still one-directional-clean (both must stay 0)
ssh pfsense 'sysctl dev.ix.0.mac_stats.crc_errs dev.ix.0.mac_stats.local_faults'

# 4. new optic DDM — record these for the next comparison
ssh pfsense 'ifconfig -v ix0 | sed -n "/plugged/,\$p"'

# 5. end-to-end throughput from a LAN client (crosses ix0)
ssh dockermaster 'curl -sk -o /dev/null --max-time 12 \
  -w "%{speed_download} B/s\n" \
  https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
```

Targets: `remote_faults` delta **0**, loss **< 0.5 %** at 1400 B and **0 %** at 56 B, `crc_errs` and
`local_faults` **0**, RX power **−3…−10 dBm**, TX bias near **6–7 mA**, throughput **≫ 100 Mbps**.

10G-SR norms: RX −3…−10 dBm (marginal below ≈ −12, loss of signal ≈ −17), TX −3…−8 dBm, temp < 70 °C.

## 🔁 Step 6 — re-arm

```bash
ssh pfsense 'rm -f /var/db/ix0-watchdog.nobounce'          # if you used the flag
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh reset'        # clears disarm + failure counter
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh start && /usr/local/sbin/ix0-watchdog.sh status'
```

Optional confidence check — deliberately exercises bounce → settle → verify, and costs one ~30–50 s blip:

```bash
ssh pfsense '/usr/local/sbin/ix0-watchdog.sh testbounce'
```

On a healthy link this should report `VERDICT: SUCCEEDED`.

## 🚨 If it goes wrong

| Symptom | Action |
|---|---|
| Link will not come up after reseat | `ssh pfsense 'ifconfig ix0 down; sleep 5; ifconfig ix0 up'` |
| Locked out of pfSense over LAN | Admin VLAN on `igc3` (192.168.32.32/27) is a separate physical port |
| New optic not recognised | X520 rejects some third-party modules — this is why Intel-coded is preferred |
| Errors unchanged after all four steps | Fault is upstream of the optics; escalate to the switch port / SFP cage itself |

## 📡 Monitoring that now covers this

Deployed 2026-08-17 (branch `feat/ix0-degraded-autobounce`):

- `pfsense_ix0_remote_faults_total` — the earliest signal; climbs for days before users notice
- `pfsense_ix0_large_frame_loss_percent` / `_mean_percent` — user-visible impact at 1400 B
- Auto-bounce with self-verification, exponential backoff and self-disarm when bouncing stops helping
- Alerts: `Ix0OpticDegrading`, `Ix0LargeFrameLoss{,Critical}`, `Ix0AutoBounceFailed`,
  `Ix0WatchdogDisarmed`, plus staleness alerts

After the swap, `Ix0OpticDegrading` going quiet is the durable proof that the fix held.
