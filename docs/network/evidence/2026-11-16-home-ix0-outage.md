# HOME and ix0 outage evidence

## Scope

Collected on 2026-11-16 from 15:56 to 15:58 MST. The Mac used ADMIN
address `192.168.32.59`. The checks used ping, TCP connections, DNS queries,
and read-only SSH to pfSense at `192.168.32.33`. No network settings changed.
The switch port was not checked in this collection.

## Link and VLAN status

Source: pfSense. Command: `ifconfig` for each interface. At 15:57:46 MST:

```text
ix0      status: no carrier
ix0.10   192.168.4.1/20     parent ix0   status: no carrier
ix0.28   192.168.48.1/20    parent ix0   status: no carrier
ix0.105  192.168.128.1/24   parent ix0   status: no carrier
ix0.205  192.168.16.1/24    parent ix0   status: no carrier
igc3     192.168.32.33/27                status: active
```

The pfSense system log recorded all five ix0 interfaces changing to DOWN at
15:47:14 MST. That entry does not establish the cause of the link loss.

## Reachability

From ADMIN, pfSense SSH, the switch HTTPS port, and the Omada HTTPS port
accepted TCP connections. A direct HTTPS request to `1.1.1.1` returned 301.
The Mac received ping replies from `192.168.4.1`, a pfSense interface address.
That reply does not prove that pfSense can reach HOME clients on ix0.10.
HOME clients and the Vault service did not respond to the selected probes.

## Watchdog

Source: `/var/log/ix0-watchdog.log` on pfSense. The log reported degraded
probes at 15:42:48, 15:43:54, and 15:45:01 MST. It recorded a disarmed
state and no bounce at 15:45:01. From 15:47:47 through 15:57:41 it reported
all targets unreachable and `link=down`. It reported that the nobounce flag
prevented automatic recovery. The log does not identify the failed component.

## Prior context

`docs/network/2026-11-16-ix0-live-evidence.md` records a prior live link and
rising remote fault counters. It did not establish the faulty component.
The Omada API reservation attempt ended in HTTP timeouts before this outage.
The available evidence does not establish whether it caused the outage.

## API request correlation

Collected on 2026-11-16 at 16:00 MST from the pfSense system and nginx logs.
The first tunnel command stopped at a `printf` error before it sent a GET.
The next tunnel command sent a GET to the DHCP static mapping endpoint.

```text
15:46:08 watchdog: degraded, mean loss 34%
15:47:14 kernel: ix0 and its four VLANs changed to DOWN
15:47:16 nginx: GET /api/v2/services/dhcp_server/static_mapping 200
15:47:47 watchdog: all LAN targets unreachable, link=down
```

The nginx time is the access log time, not a verified request start time.
The GET overlapped the outage. The logs do not establish whether it caused it.
The previous POST requests returned 504 through HAProxy. The GET used the
local nginx listener through an SSH tunnel.

## User-approved recovery attempt

At 16:02:23 MST, the user approved one ix0 restart. The operator used the
procedure in `docs/network/2026-06-18-lan-trunk-ix0-outage-rca.md` over the
ADMIN SSH path. The command set ix0 down, waited four seconds, then set it up.
If the command ended early, a shell exit trap also requested `ix0 up`.

At 16:02:30, ix0 was administratively UP but showed no carrier. At 16:03:00,
`ifconfig` still showed no carrier on ix0 and all four VLANs. ADMIN igc3
remained active. The no-bounce flag remained present.

At 16:03:05, the controller returned HTTP 200 and ADMIN DNS answered. A ping
to HOME host `192.168.2.50` received no replies. No second bounce was attempted.

## Apply investigation

Collected at 16:05 MST through read-only SSH to pfSense. `ix0` and all four
VLANs still reported no carrier. ADMIN remained active.

The command `stat` reported `/cf/conf/config.xml` last modified on
2026-11-11 at 09:41:19 MST. The live configuration read after the timed-out
POSTs did not contain the ADMIN reservation. These observations do not prove
that no background process or non-persistent action occurred.

The pfSense API source shows that a DHCP static-mapping model can invoke
`dhcp_apply_changes()` when an apply is requested. The core model defaults
`always_apply` to false. The sync script did not send an `apply` field. This
review did not prove all endpoint defaults or paths used by those requests.

The nginx log recorded three POST requests ending with status 499 at
15:41:54, 15:42:26, and 15:43:00. The client saw 504 responses. The same
endpoint logged a GET response at 15:47:16. The kernel logged ix0 down at
15:47:14. Those timestamps do not establish the cause of the link loss.

## Power capability check

Collected on 2026-11-16 at 16:12:47 MST over read-only ADMIN SSH.
`kenv` reported maker `CWWK` and product `CW-ADLN-PCIE-4L`. The BIOS
vendor was American Megatrends International, LLC, with version `5.27`.
`sysctl hw.acpi.supported_sleep_state` returned `S5`. A read-only search
of sysctl names found no RTC wake or alarm entry. `/dev/ipmi*` did not exist.

These checks do not establish whether the BIOS supports timed power-on or
Wake-on-LAN. They do not prove whether standby power reaches the NIC.

At 16:14:36 MST, `ifconfig -v igc3` showed `WOL_MAGIC` in the active options
and reported MAC `a8:b8:e0:00:bc:50`. The same command showed `ix0` with
`WOL_MAGIC` and no carrier. The Mac used ADMIN on the igc3 network. The
firmware wake behavior after shutdown was not tested at that time.

The FreeBSD `acpiconf(8)` manual lists no command to schedule an RTC wake.
This does not prove that the board firmware lacks an RTC wake setting.
Source: https://man.freebsd.org/cgi/man.cgi?query=acpiconf&sektion=8

## Power-off and wake attempt

At 16:17:29 MST, the user approved `shutdown -p now`. Before shutdown, the
Mac started a standalone Wake-on-LAN sender on the ADMIN subnet. Its log is
`docs/network/evidence/2026-11-16-pfsense-wake.log`. The sender recorded
broadcast packets beginning at 16:17:35. ADMIN SSH did not return during
the check through 16:21:27.

At 16:32:28, ADMIN SSH worked and pfSense uptime was about four minutes.
The logs reviewed here do not establish how the router powered on again.

## Enable ix0

At 16:32:37 MST, the user requested ix0 enabled. `ifconfig ix0` showed UP
and no carrier before the command. The operator ran `ifconfig ix0 up` once.
At 16:32:41, ix0 and all four VLANs still showed no carrier. ADMIN igc3 was
active and the watchdog no-bounce flag remained present.

No down command ran. The separate link and HOME-internet monitor continued to run.

## Dummy interface and driver check

Collected at 16:38 MST over read-only ADMIN SSH. The pfSense configuration
listed `opt6` as enabled on `ix0`, with description `carrier_ix0_10g` and
no IPv4 address. HOME, SERVER, GUEST, and IoT remained enabled on their VLANs.
The system log recorded the new interface assignment at 16:33:26.

`ifconfig -v ix0` showed UP and no carrier. It detected an Intel X520 NIC and
a Cable Matters copper pigtail. The driver listed autoselect, `1000Base-KX`,
and `10Gbase-Twinax` as supported media. The kernel log showed driver attach
and queue setup after boot. The selected ix0 kernel lines contained no
unsupported-module or driver-failure message.

`netstat -I ix0 -n -b -d` showed zero received packets and zero input errors
since the latest boot. The device counters read 15 remote faults, 92 local
faults, and zero CRC errors. A second reading five seconds later was unchanged.
Those counters alone do not identify the cause. The switch port was not checked.

## Switch port reset attempt

At 16:39 MST, the user asked for a reset of the switch port. The plan was an
Omada API disable and enable of port 27, the port LLDP linked to `ix0`.
Vault on ports 8200 of `192.168.59.25`, `192.168.4.233`, and `192.168.59.2`
refused connections. The Mac Keychain had no `omada`, `omada-controller`,
`switch24a`, or `tplink` item. The Omada API answered `/api/info` without a
login. No login ran and no switch change was made.

## Recovery after user reboot in Omada

The user said they used the Omada web UI to reboot. The statement did not say
which device they rebooted. The switch uptime was not read.

The pfSense kernel log recorded `ix0` UP at 16:46:26 MST. At 16:47:44,
`ifconfig ix0` showed `10Gbase-Twinax <full-duplex,rxpause,txpause>` and active.
The device counters read 15 remote faults, 2824 local faults, and zero CRC
errors, unchanged over five seconds. The watchdog logged recovery at 16:46:36.

At 16:48:11, pfSense pinged `192.168.7.11`, `192.168.7.10`, `192.168.2.50`,
`192.168.48.44`, `192.168.59.25`, and `192.168.16.1` with no loss. `192.168.4.70`
did not reply. pfSense logged 196 HOME DHCP lines after 16:46.

Vault accepted a TCP connection. From the Mac on ADMIN, `192.168.2.50`
answered ping. The Proxmox SSH check at `192.168.7.11` timed out. This review
did not test whether the firewall blocks that ADMIN path.

The standalone monitor kept reporting `home_https=unreachable`. It tests HTTPS
through SSH to Proxmox, so the Mac must reach Proxmox for the test to pass.

## Retest from HOME

Collected from 16:49 to 16:52 MST, with the Mac on `192.168.0.7`.

- Gateways `192.168.4.1`, `.32.33`, `.48.1`, `.16.1`, and `.128.1` answered ping.
- DNS on `192.168.4.1`, `192.168.100.254`, `192.168.59.50`, and `192.168.4.236`
  resolved `google.com`. A first query to `192.168.4.236` timed out. Later UDP
  and TCP queries worked.
- TCP connections worked to Proxmox, Vault, Portainer, the switch web UI,
  Omada, and pfSense. SSH worked to `dockermaster` and `nas`.
- `https://www.google.com` returned 200. pfSense, Grafana, Keycloak, Home
  Assistant, the registry, and Vault answered over HTTPS.
- The three reverse-proxy addresses `192.168.59.28`, `.48`, and `.49` served
  Vault on port 443 with the `*.d.lcamaral.com` certificate.
- `docker ps` on `dockermaster` showed 24 running containers and none
  unhealthy or restarting.
- `https://rustdesk.home.lcamaral.com` returned 502. `192.168.4.70` refused
  ports 80 and 443. Neither was investigated.

Prometheus listed nine firing alerts at 16:51. Three were `ix0` alerts. Four
were certificate probes and two were RustDesk endpoint probes. The probes were
not re-evaluated after the outage ended.

## Reservation apply from merged main

PR 146 merged as `5608742`. It changed the sync tool to send each write once,
through pfSense's local listener over the ADMIN path, and to read the result back.
At 17:08:37 MST, the tool sent one POST for the Omada reservation. At 17:11:38,
pfSense returned a 504 page after 180 seconds. The tool reported an unknown
outcome and stopped. A read of `/cf/conf/config.xml` showed no ADMIN mapping.

A separate watcher sampled every three seconds from 17:08:30 to 17:12:31. The
file is `docs/network/evidence/2026-11-16-apply-watch.log`. `ix0` stayed active
and the 1400-byte probe loss stayed at 0.0%. The load average rose from 0.20 to
about 1.5. It fell to 1.17 at the last sample.

The config revision at 17:05:57 reads "lamaral ... Interfaces settings changed".
It came from the web UI at `192.168.0.7`, so it predates the apply.

The pre-apply copy of the configuration is
`/root/config.xml.pre-omada-reservation-20261116` on pfSense.

## Reservation applied through PHP

PR 147 merged as `18786b5`. It replaced the REST write with PHP run on pfSense
over the ADMIN path. The PHP uses the same calls as the GUI edit page.

The PHP first validates the entry. A live dry run accepted the Omada reservation
in 0.5 seconds. It refused six bad entries. These were an address inside the
dynamic range, one reserved to another MAC, and one outside the subnet. The
others were the interface's own address, a bad MAC, and an unknown interface.

At 17:20:50 MST the tool wrote the mapping in 1.4 seconds and read it back from
the live config. A diff against the pre-apply copy showed one added staticmap and
the revision note. At 17:21:03 `--activate` reloaded only dhcpd in 2.6 seconds.
The running `/var/dhcpd/etc/dhcpd.conf` held `fixed-address 192.168.32.40` for
the MAC. Unbound kept running and `ix0` stayed active throughout.

The VM still held a `.55` lease ending 2026-11-17 01:14:35 UTC. It renewed at
16:06:35, 16:38:35, and 17:10:35 MST, so the next renewal is about 17:42:35. At
that renewal dhcpd can refuse `.55` and offer `.40`. A separate watcher logs the
move in `docs/network/evidence/2026-11-16-omada-ip-flip-watch.log`.

A retest from HOME at 17:22 reached all gateways and four DNS servers. It also
reached Vault, Portainer, Proxmox, the switch UI, Omada, Google, Home Assistant,
Grafana, and Keycloak.

Five alerts were firing, down from nine. The four certificate probe alerts
cleared. `Ix0OpticFaultStorm`, `Ix0AutoBounceFailed`, `Ix0WatchdogDisarmed`,
and two RustDesk alerts remained.

## Static address for the Omada VM

PR 148 merged as `e47227c`. It adds `hosts/omada-controller/etc/netplan/01-netcfg.yaml`
and `scripts/sync-guest-netplan.py`. The script works through the Proxmox guest agent.
Sudo on the guest needs a password, and the agent does not.

At 17:35:15 MST the apply ran. The guest backed up the live file as
`/etc/netplan/01-netcfg.yaml.bak-20261116-173518`, wrote the new file, and
`netplan generate` accepted it. The script armed a 180-second revert guard first.

It applied three seconds later, detached. The guest agent then reported `192.168.32.40/27` on `ens18`, a
default route via `192.168.32.33`, DNS `192.168.32.33`, and search domain `admin.lcamaral.com`.
The script cancelled the guard at 17:35:33. A second dry run reported the file in sync.

At 17:35:42, ports 8043, 8088, 22, and 29811 on `.40` accepted connections from the Mac on HOME.
Port 8043 on `.55` was closed. `https://192.168.32.40:8043` and the name-based URL returned 200.

The Omada API on `.40` showed the switch with status 14 (connected) at 17:36:18. Its `lastSeen`
stopped at 17:35:18. It showed status 30 (disconnected) at 17:36:49 and 17:37:04.

It showed 22 at 17:37:19 and 14 again at 17:37:34, with `lastSeen` advancing. The switch
reconnected by itself. The management gap was about 2 minutes. No `ix0` change appeared in that
window.

At 17:39 MST, pfSense Unbound and Pi-hole-2 still returned `192.168.32.55` and `.40` for the
controller name. Unbound held `.55` from `/var/unbound/dhcpleases_entries.conf`. The DHCP lease
for `.55` showed `binding state free`, ended 17:35:30 MST. The cause of the stale entry was not
found. Pi-hole-1 and Pi-hole-3 returned only `.40`.

The retest from HOME at 17:39 found all gateways, Vault, Portainer, Proxmox, the switch UI, and
Omada reachable. Five alerts were firing: two RustDesk probes, `Ix0OpticDegrading`,
`Ix0AutoBounceFailed`, and `Ix0WatchdogDisarmed`.

## Switch and controller state

Collected at 17:12 MST from the Omada API with the Keychain backup login.
The controller reported version 6.2.10.17. The switch SG3428X v1.30 reported
firmware `1.30.24 Build 20260509 Rel.25087`, uptime 26m42s, `needUpgrade` false,
and `fwDownload` false. The uptime puts its restart at about 16:45:47, which is
40 seconds before `ix0` came up. The tested firmware paths returned unsupported
request errors. The check does not query TP-Link's own firmware list.

The TP-Link download page showed Linux packages 6.2.14.11 (2026-07-17) and
6.3.0.45 (2026-09-04). For 6.3.0.111 it showed a Windows zip and a release
note link, and no Linux package. The 6.3.0 release note lists no operating
system requirement. It says some features need Managed Switch firmware 6.4 or
newer. The guest ran Ubuntu 20.04.6, Java 17.0.15, MongoDB 7.0.37, and package
`omadac` 6.2.10.17, with 19 GB free. The controller was not changed.

The monitor logged SUCCESS at 16:49:26 on an HTTP 503 from `1.1.1.1`. A pfSense
redirect rule on `ix0.10` sends traffic to the `OutboundDNSServers_old` alias
to pfSense. HAProxy answered with its own certificate, so that SUCCESS does not
prove internet access.
