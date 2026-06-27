# Nginx-exporter health investigation -- 2026-05-27

## Symptom

`nginx-exporter-nginx-exporter-1` is marked `unhealthy` because the Docker healthcheck
shells out to `wget`, but the `nginx/nginx-prometheus-exporter:1.5.1` image is a minimal
Go-binary image with no `wget` (or `curl`) on PATH. The exporter process itself runs fine
and Prometheus scrapes `:9113/metrics` directly, so `up{job="nginx"}=1` despite the
unhealthy label.

## Confirmation

`docker ps` snippet:

```text
nginx-exporter-nginx-exporter-1   Up 2 weeks (unhealthy)   nginx/nginx-prometheus-exporter:1.5.1
```

Last 3 healthcheck log entries (all identical, exit -1):

```text
OCI runtime exec failed: exec failed: unable to start container process: exec: "wget": executable file not found in $PATH
```

Healthcheck definition (from `docker inspect`):

```text
Test: ["CMD","wget","-qO-","http://localhost:9113/metrics"]
Interval: 30s  Timeout: 10s  StartPeriod: 30s  Retries: 3
```

## Root cause

- The compose stack (`terraform/portainer/stacks/nginx-exporter.yml` line 38-43) declares a
  `wget`-based healthcheck.
- The upstream `nginx/nginx-prometheus-exporter:1.5.1` image ships only the Go binary — no
  shell, no `wget`, no `curl`. The healthcheck process fails to exec on every interval,
  Docker counts 3 retries and pins state to `unhealthy`.
- The exporter binary itself is healthy: bound to `0.0.0.0:9113` on 2026-05-12; only runtime
  errors are intermittent `connection refused` / DNS misses against
  `http://rproxy:8080/nginx_status` (transient, self-recovering). Prometheus scrapes the
  exporter directly on macvlan IP `192.168.59.58:9113` — hence `up{job="nginx"}=1` despite
  the unhealthy mark.

## Recommended fix

Replace the healthcheck with one that uses the container's own facilities. Either:

- Use the exporter's own `/-/healthy` endpoint via `CMD` that bypasses needing `wget`/`curl`:

  ```yaml
  healthcheck:
    test: ["CMD", "/usr/bin/nginx-prometheus-exporter", "--version"]
  ```

  Caveat: only proves the binary is on disk, not that it's serving.

- Or drop the healthcheck entirely (`healthcheck: { disable: true }`) and rely on
  `up{job="nginx"}` in Prometheus, which is already the source of truth.

- Or switch the image to a variant with a shell (none published upstream) — not recommended.

Best option: disable the healthcheck in `terraform/portainer/stacks/nginx-exporter.yml` and
let Prom's `up{}` be authoritative. Then `terraform apply` + Portainer stack stop/start.

## Severity

**Low.** Pure cosmetic / monitoring-signal noise. Metrics flow uninterrupted; no scrape gap;
no functional impact on `rproxy` or any consumer. Only effect is `docker ps` showing red and
any container-health alerting firing on it.

## How urgent

Not urgent — batch with the next IaC change to the stack; no SLA impact.
