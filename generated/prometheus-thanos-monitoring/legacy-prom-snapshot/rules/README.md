# Rule files

`prometheus.yml` references `alert.rules` in `rule_files:`, but **no rule file
exists** inside the running container:

```
$ docker exec prometheus-prometheus-1 ls -la /etc/prometheus/
total 12
-rw-rw-r--    1 1027     1000          1869 Mar 26  2023 prometheus.yml
$ docker exec prometheus-prometheus-1 find /etc/prometheus -type f
/etc/prometheus/prometheus.yml
```

The host bind mount `/nfs/dockermaster/docker/prometheus/` only contains
`prometheus.yml`, `snmp.yml`, `snmp.bkp.yml`, `prometheus.yml.example.zero`,
`docker-compose.yaml`, `alertmanager/`, `hosts/` — no `alert.rules` and no
`rules/` directory.

**Effective state**: Prometheus is logging a load error for the missing rule
file at every reload, and **no alert rules are evaluated**. Alertmanager is
running but its `config.yml` has only a placeholder receiver (`slack` with all
fields commented out), so even if rules fired, alerts would go nowhere.

→ Nothing to migrate from `rule_files`.
