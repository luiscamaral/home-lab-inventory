#!/bin/sh
# pfsync-dest: /usr/local/etc/rc.d/ix0watchdog.sh
# pfSense runs /usr/local/etc/rc.d/*.sh at boot. Start the ix0 LAN-trunk
# watchdog immediately (the config.xml keepalive cron in pfsense/cron-jobs.yml
# would otherwise take up to 60s to start it). Idempotent: `start` is a no-op
# if the watchdog is already running.
/usr/local/sbin/ix0-watchdog.sh start
