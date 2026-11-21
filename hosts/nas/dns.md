# nas (Synology) DNS — desired state + apply (manual, DSM UI)

Unlike the Linux hosts (see `hosts/proxmox/dns.yml` and each
`hosts/<host>/etc/systemd/network/10-ens19.network`), **Synology DNS has no
clean IaC/CLI path.** DSM renders `/etc/resolv.conf` from its network-settings
database; `resolv.conf.static` is empty and the nameservers live only in the
rendered file, so any hand-edit is overwritten on the next network event or
reboot. Do not hand-edit resolv.conf on the NAS (operating rule #1 — and it is
a storage appliance).

## Problem

`/etc/resolv.conf` currently lists both nameservers as pfSense
(`192.168.4.1` + `192.168.32.33`), and `.32.33` does not answer on :53 — the
same single-resolver DNS SPOF fixed on the other hosts (incident 2026-06-28).
Low urgency here: NFS mounts are by IP (DNS-independent) and `.4.1` works; the
dead `.32.33` is just a failed fallback.

## Desired state

```text
nameserver 192.168.4.1     # pfSense Unbound — unfiltered recursive primary
nameserver 192.168.4.236   # pihole-3 — independent backup (runs ON this NAS,
                           #   home-net; the only pihole reachable from nas)
domain     home.lcamaral.com
```

## Apply (manual — DSM UI)

DSM → **Control Panel → Network → General → Manually configure DNS server**:

- Preferred DNS: `192.168.4.1`
- Alternative DNS: `192.168.4.236`

Then verify: `ssh nas 'cat /etc/resolv.conf'` shows `.4.236` in place of
`.32.33`, and `nslookup google.com 192.168.4.236` answers.

> Note: `dig` on DSM is unreliable/absent — use `nslookup` to test.
