#!/bin/sh
# pfsync-dest: /usr/local/bin/dpinger_textfile_30s.sh
#
# Cron wrapper: run dpinger_textfile.sh twice per minute for ~30 s
# effective cadence. Cron's minimum interval is 1 minute, so two
# back-to-back invocations with a 30 s gap between them get us the
# resolution we want without spawning a daemon.

/usr/local/bin/dpinger_textfile.sh
sleep 30
/usr/local/bin/dpinger_textfile.sh
