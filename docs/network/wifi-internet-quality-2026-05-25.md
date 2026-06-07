# 📡 WiFi & Internet Quality Report — 2026-05-25

**Trigger:** investigation into B-hyve irrigation controller reachability
(`192.168.1.8`). Expanded into a broader WiFi + internet health check.

## TL;DR

- 🌐 **Internet / WAN**: HEALTHY. WAN1 (Google Fiber) 15 ms RTT, 0% loss. WAN2
  (backup) 1 ms RTT, 0% loss. Both gateways stable per `dpinger`.
- 🧠 **LAN core (pfSense + wired)**: HEALTHY. Sub-millisecond between any two
  wired hosts. Zero NIC ingress errors. Trivial egress error counters.
- 📶 **WiFi**: **DEGRADED**. Severe bursty loss + huge latency spikes on the
  laptop's 5 GHz association. IoT-VLAN clients (B-hyve etc.) show high
  jitter (60 ms avg, up to 177 ms) even from a wired peer.
- 🌱 **B-hyve controller**: ALIVE, but at `192.168.16.159` on the IoT VLAN —
  not at `192.168.1.8`. The `config.xml` static reservation is stale.

---

## 1. The B-hyve question (root finding)

User believed the Orbit B-hyve sprinkler timer was at `192.168.1.8`. It is not.

| Source | Value |
| --- | --- |
| Static map in `/cf/conf/config.xml` | `192.168.1.8` → `44:67:55:40:39:bd` `orbit-bhyve` (stale) |
| Live ARP on pfSense `ix0.10` (HOME) | no entry for `192.168.1.8` |
| Live ARP on pfSense `ix0.205` (IoT) | `192.168.16.159` at `44:67:55:40:39:bd`, expires 1186 s |
| Ping from IoT GW `192.168.16.1` | 3/3 received, 55-97 ms RTT |
| Ping from wired dockermaster (50 pkts) | 50/50, **RTT 1.9-177 ms, mdev 53.9 ms** |
| MAC OUI `44:67:55` | Espressif (ESP32/8266 — consistent with B-hyve WiFi module) |

The user can't reach it from the laptop because:

1. Laptop is on HOME VLAN (`192.168.0.7`, ix0.10).
2. Controller now lives on IoT VLAN (`192.168.16.159`, ix0.205).
3. Inter-VLAN HOME → IoT is firewalled (per project policy).
4. Orbit B-hyve has no published local API anyway — all 6 probed TCP ports
   (80/443/8080/8443/53/161) returned closed/filtered. Control happens via
   the Orbit cloud over outbound WebSocket.

**Recommendation:** remove the stale `192.168.1.8 / ix0.10` reservation; add a
new one on `ix0.205` for `192.168.16.159` to pin the address.

---

## 2. Measurement matrix

| Path | RTT (avg) | RTT (max) | Loss | Jitter (stddev/mdev) | Verdict |
| --- | ---: | ---: | ---: | ---: | --- |
| **dpinger** HOMELAB → 192.168.7.10 (wired) | 0.43 ms | — | 0% | 0.70 ms | ✅ perfect |
| **dpinger** WAN1 → 8.8.8.8 (Google Fiber) | 15.3 ms | — | 0% | 0.40 ms | ✅ excellent |
| **dpinger** WAN2 → 192.168.12.1 (backup ISP) | 0.96 ms | — | 0% | 1.86 ms | ✅ excellent |
| dockermaster (wired) → pfSense HOME GW | 0.54 ms | 1.52 ms | 0% | 0.49 ms | ✅ |
| dockermaster (wired) → pfSense SRVAN GW | 0.32 ms | 0.40 ms | 0% | 0.05 ms | ✅ |
| dockermaster (wired) → NAS (wired peer) | 0.30 ms | 0.44 ms | 0% | 0.06 ms | ✅ |
| dockermaster → 1.1.1.1 (likely local hijack — see §6) | 0.23 ms | 0.39 ms | 0% | 0.05 ms | ℹ️ anomaly |
| dockermaster → 8.8.8.8 | 0.84 ms | 2.92 ms | 0% | 1.04 ms | ✅ |
| **Laptop (WiFi) → pfSense HOME GW** | **632 ms** (1/5) | 632 ms | **80%** | n/a | 🔴 broken |
| **Laptop (WiFi) → 8.8.8.8** | 627 ms (1/5) | 627 ms | **80%** | n/a | 🔴 broken |
| Laptop (WiFi) → 1.1.1.1 | 101.7 ms | 163.1 ms | 0% | 33.2 ms | 🟡 lossy bursts |
| Laptop (WiFi) → google.com | 108.8 ms | 165.1 ms | 0% | 32.9 ms | 🟡 lossy bursts |
| dockermaster (wired) → laptop (WiFi), 50 pkt | 16.4 ms | 94.8 ms | 0% | 24.3 ms | 🟡 jittery |
| **dockermaster (wired) → B-hyve (WiFi), 50 pkt** | **60.8 ms** | **176.6 ms** | 0% | **53.9 ms** | 🔴 jittery |

The pattern is unambiguous: **wired-only paths are pristine; anything that
crosses the air-link degrades sharply.** This is a WiFi problem, not an
internet or routing problem.

**Mitigation:** a synthetic WiFi client now measures this from the client side —
see [esp32-c5-wifi-probe.md](esp32-c5-wifi-probe.md).

---

## 3. WiFi link details (laptop)

From `system_profiler SPAirPortDataType`:

| Field | Value |
| --- | --- |
| PHY mode | 802.11ax (WiFi 6) |
| Channel | **120 (5 GHz, 160 MHz) — DFS** |
| Country | US |
| Security | WPA2/WPA3 Personal |
| Signal / Noise | -54 dBm / -93 dBm (SNR ≈ 39 dB, nominally excellent) |
| Transmit Rate | 864 Mbps |
| MCS Index | 4 (low for the available SNR) |

**Anomaly:** with -54 dBm of RSSI the link _should_ be running MCS 9-11 at
gigabit-plus rates. MCS 4 + 864 Mbps suggests the radio is rate-capping
after retries, **not** signal-limited. That is the classic signature of
**interference** or **DFS radar events** on the channel.

---

## 4. Why this is happening — likely root causes

### 4.1 Channel 120 is a DFS (Dynamic Frequency Selection) channel

5 GHz channels 52-64 and 100-144 require radar avoidance. When the AP
detects a radar pulse — real or false-positive — it MUST:

1. Vacate the channel within 200 ms (no transmit).
2. Pick a new channel.
3. Wait 60 s of "channel availability check" before re-using channel 120.

During that gap, the AP either kicks all clients to a fallback channel or
stays silent. Clients see this as **massive bursty loss + reassociation
delays**, exactly matching what the laptop reports.

160 MHz width makes this worse: it spans four times the DFS spectrum, so any
radar source in the area trips the AP more often.

### 4.2 Multiple AP hardware on the same VLAN

ARP enumeration on `ix0.10` shows mixed vendors:

| Likely role | MAC prefix | Vendor |
| --- | --- | --- |
| Secondary AP/router @ 192.168.1.1 | `34:e1:d1` | TP-Link |
| Asus-family clients/APs (.15.x range) | `98:17:3c`, `1c:98:c1`, `80:07:94`, `60:e8:5b`, `18:ce:94` | ASUSTek |
| Synology NAS (.1.50) | `90:09:d0` | Synology |

If TP-Link and ASUS units are both broadcasting on overlapping 5 GHz
channels, co-channel interference can produce exactly this latency
profile, with no help from DFS.

### 4.3 IoT VLAN load

`ix0.205` has 25 active ARP entries (lots of small-radio IoT devices); its
egress error counter is 14,774 / 2.7M = **~0.55%** — notable. Pings to the
B-hyve from the IoT gateway showed 75 ms RTT with high stddev; from a
wired peer through pfSense it was 60.8 ms avg, 176 ms max, mdev 53.9 ms.
Both metrics point to **the AP's IoT SSID being saturated or
interference-limited**, not the device.

---

## 5. Recommendations (in priority order)

1. **Move off DFS.** Force the 5 GHz radio to a non-DFS channel:
   - US lower band: 36 / 40 / 44 / 48
   - US upper band: 149 / 153 / 157 / 161
   - 165 if available
2. **Drop to 80 MHz width** until stable, then test 160 MHz again only after
   verifying no DFS events.
3. **Audit AP topology.** Identify exactly which APs are on the HOME and
   IoT SSIDs (TP-Link unit at `192.168.1.1` + any Asus unit). Confirm
   they are not transmitting on the same channel. Disable any AP that
   shouldn't be active.
4. **Update AP firmware.** TP-Link and Asus consumer APs ship with stale
   DFS detection logic; firmware updates routinely fix flapping.
5. **Pin the B-hyve.** Replace the stale `ix0.10 / 192.168.1.8` reservation
   with `ix0.205 / 192.168.16.159` in `/cf/conf/config.xml`. Document the
   B-hyve in `inventory/` (it currently isn't in any inventory file).
6. **Re-test.** After the radio changes, re-run §2's matrix from both the
   laptop and dockermaster. Expect laptop → HOME GW to drop to ≤ 5 ms
   with 0% loss; expect B-hyve RTT < 30 ms with mdev < 10 ms.

---

## 6. Notes & loose ends

- **`1.1.1.1` from dockermaster answers in 0.2 ms.** This isn't real
  Cloudflare; something on the homelab is intercepting/answering for
  that IP. Likely a Pi-hole, Twingate connector, or Docker overlay route.
  Out of scope for this report — flagged for follow-up.
- **pfSense ix0.10 has 72,855 egress errors over 277 M packets** (0.026%) —
  not a current cause for concern but worth re-checking after the radio
  changes; if egress errors keep climbing, look at NIC pause-frame /
  flow-control settings (currently `rxpause,txpause` enabled on `ix0`).
- **MTR through dockermaster collapsed to 1 hop** (because of the 1.1.1.1
  hijack above). Real WAN1 path quality is best read from `dpinger`
  (`/var/run/dpinger_WAN1GW~...sock`), which shows 15 ms / 0% / 0.4 ms
  stddev — clean.
- The SSH session from the laptop to pfSense dropped mid-test, which is
  itself confirmation of the WiFi instability documented here.

---

_Report generated 2026-05-25 from pfSense REST API + SSH on `pfsense`,
`dockermaster`, and laptop (`192.168.0.7`). No state-changing commands
were executed._
