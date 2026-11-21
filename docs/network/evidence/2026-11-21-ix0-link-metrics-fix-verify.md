# ix0_link_metrics fix: apply and verification, 2026-11-21

Applied 2026-11-21T06:38:11Z from merged main 445cd46 (PR #166) with `scripts/sync-pfsense-scripts.py --apply`.
Dry run before apply showed only `ix0_link_metrics.sh` would update. One script pushed (125 lines). No link bounce.

Observed after apply (pfSense, 06:37Z): ix0_link.prom has no bare "0" line; node_exporter `node_textfile_scrape_error 0`;
ix0_link.prom is listed in `node_textfile_mtime_seconds`; `pfsense_ix0_remote_faults_total` and `pfsense_link_up` are on :9100.
Thanos values: see the PR #166 comment.
Not checked: the Grafana UI itself.
