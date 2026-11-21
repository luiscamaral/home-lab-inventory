# Is switch24a syslog reaching the NAS Log Center? 2026-11-21

Collected 2026-11-21 ~07:05-07:25Z (00:05-00:25 MST). Read-only. User approved use of the NAS sudo password for this check
(password read from Keychain, not recorded here). Sources: `ssh nas` (+sudo: file listing, config read, sqlite `-readonly` on COPIES in /tmp, removed after),
`ssh pfsense` (pfctl rules and states). Not checked: the live syslog setting on the switch or in Omada, packet capture, the switch's own log buffer.

## Observed: NAS receiver
- `syslog-ng` from the LogCenter package listens on UDP `0.0.0.0:514` (`s_syno_bsd_external_BSD_UDP`). UDP socket: no drops, empty queue.
- Received logs are written per host under `/volume2/Backups/LogsArchive/<host>/SYNOSYSLOGDB_<host>.DB` (sqlite).
- The receiver works for other senders. Latest row per host dir:
  - KitchenSinkLight.iot.lcamaral.com: 119,682 rows, last 2026-11-21 00:02:10 MST
  - house-switch-basement-bedroom.iot.lcamaral.com: 118,367 rows, last 2026-11-21 00:02:22
  - omada-controller.admin.lcamaral.com: 28 rows, last 2026-11-20 06:49:06
  - 192.168.16.115: last 2026-11-11 15:41:21; 192.168.16.16: last 2026-08-18; pfSense host dirs: last 2024-2025 (not received now)

## Observed: the switch
- Host dir `TL-SG3428X`: 1,073 rows, 2026-04-28 15:13:41 to **2026-06-18 23:07:50**. By month: Apr 102, May 494, Jun 477. Nothing after.
- Last rows: "Send topology change on CIST Te1/0/27 and Te1/0/28" (20:29:47), "Deleted user admin / lamaral OK", "Logout the web", "Disable IPv6 dual netstack OK" (23:07:44-50).
  These match the Omada adoption on 2026-06-18/19.
- `switch24a.admin.lcamaral.com` dir holds only a 2024 archive ZIP.
- No file under LogsArchive mentions `Te1/0/27`, `Port27` or `192.168.32.39` except the old TL-SG3428X DB.
- pfSense: rule "Admin access to the world" passes ADMIN net to any. No pf state switch -> NAS:514 at 07:05Z (UDP states last about 1 min; not conclusive).

## Conclusion (supported)
- Since 2026-06-18 23:07 MST the NAS has received no syslog from the switch. This covers 2026-11-16 15:47-16:46 MST, the ix0 outage.
- The NAS receiver itself works, so the gap is on the sending side or its path.
- `docs/network/switch24a-omada-integration-plan.md` lists "Syslog -> 192.168.1.50:514" as applied and verified. The NAS data does not support that.

## Unknown
- Whether the switch has remote logging enabled now, its source IP and its hostname; whether Omada pushes the setting.
- Whether the path ADMIN -> HOME was ever the path used before 2026-06-18, and whether ix0 down on 2026-11-16 would have blocked it anyway.

## Addendum: Omada controller settings (read-only API, 2026-11-21 ~07:35Z)
Source: Omada 6.3.0.111 internal API at `https://192.168.32.40:8043` (login with the Keychain backup login, then GET only). Site `LAHome`.
- Site setting `remoteLog`: enable = true, host = 192.168.1.50, port = 514, moreClientLog = false.
- The site has one Omada device: switch `SG3428X` (mac 54-AF-97-A6-99-71), ip 192.168.32.39, firmware 1.30.24 Build 20260509 Rel.25087, status 14 (connected), uptime 4 d 7 h 25 m.
- The switch object (`/switches/{mac}`) exposes SNMP fields (`snmp`, `devCap.snmpSupport`) and no log, syslog or remote-log field.
- Result: Omada says remote logging to the NAS is on. The NAS has received nothing from the switch since 2026-06-18 23:07.

Unknown: whether the Omada site-level Remote Logging setting applies to switches at all, and what the switch's own Log settings show. Not checked: the switch web UI.

## Addendum 2: switch web UI (2026-11-21 ~07:12Z)
- `https://192.168.32.39/data/status.json` (no login): `{"auth":false,"mByCtrl":true}`. The switch reports it is managed by the controller.
- One login POST to `data/login.json` with the `switch24a-backup` Keychain login: `success: true`, `errorcode: 0`, but the response had no session token and no cookie.
  `data/remoteLog.json`, `data/localLog.json` and `data/lan.json` then still returned `auth:false`.
- The UI source shows that when the device is controller-managed (`getCtrlAuth`), login only shows the "controlled by Omada" panel (`showControlStatus`). It gives no configuration session.
- Result: the switch's own Log settings and log buffer could not be read through the web UI while it is adopted. Nothing was changed. One login attempt may appear in the switch's log.
- Still not checked: the switch's live remote-log setting.

## Addendum 3: vendor documentation and Omada event store (2026-11-21 ~07:45Z)
- TP-Link, "How to Export System Logs from Omada Devices" (https://support.omadanetworks.com/us/document/135217/, published 2026-09-29), table of log methods:
  Controller-Managed Devices: local log export Yes, **Syslog Server N/A**, debug log Yes. Standalone Switch: Yes / Yes / No.
  Syslog steps are given only for a standalone switch (its own web UI, Maintenance > Logs > Remote Logs).
- TP-Link community post (2024-06-17, https://community.tp-link.com/en/business/forum/topic/671998): a user states the controller's remote syslog sends controller messages only, not device-level syslog. This is a user statement, not a vendor statement.
- Omada API (read-only GET, 2026-11-21): `/sites/{site}/events` and `/sites/{site}/alerts` return `totalRows: 0` with no time filter. The 2026-11-16 21:00Z-00:30Z window also returns 0.
- Reading: this matches the observation that the switch sent nothing to the NAS after adoption. It is consistent with, not proof of, "controller-managed switches do not send syslog".
