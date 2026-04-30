#!/bin/sh
#

echo "Installing wget to verify container healthy state"
apt update
apt install wget -y

CMD="/usr/bin/promtail -config.file=/etc/promtail/config.yml"
printf 'Starting promtail with command:\n$ %s\n' "${CMD}"
$CMD
