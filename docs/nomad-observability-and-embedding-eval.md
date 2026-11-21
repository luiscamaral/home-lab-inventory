# NOMAD logs, metrics, and isolated embedding evaluation

## Service Logs & Metrics

NOMAD v1.35.1's Settings sidebar calls `getServiceLink('9999')`, producing
`http://nomad.d.lcamaral.com:9999`. This launches optional **Dozzle**, not NOMAD's per-app
`/api/system/services/:name/logs` endpoints. The initial IaC deliberately omitted Dozzle,
so the sidebar link could not work. There is no configurable URL override for this link.

The declarative fix consists of:

- `nomad_dozzle` (`amir20/dozzle:v10.0`) on `192.168.59.61:8080`, using base path `/logs`.
- A listener on port 9999 in the shared NOMAD Nginx vhost. It redirects to
  **<https://nomad.d.lcamaral.com/logs/>**, preserving the upstream UI without patching assets.
- HTTPS `/logs/` proxying, with buffering disabled for live log/metric streams.
- `nomad_docker_readonly`: a private socket proxy allowing Docker reads but denying mutations.
  It has no published ports and is reachable only on the internal `logs` network.
  `DISABLE_IPV6=1` selects an IPv4 listener because ds-2 disables IPv6; the image's default
  `[::]:2375` listener otherwise prevents HAProxy (and therefore Dozzle) from starting.
- Dozzle's `name=^/nomad_` filter, with actions, shell, and analytics disabled. Dozzle itself
  has no Docker socket mount. This remains LAN/Twingate-only, like NOMAD; do not add a public
  Cloudflare route without authentication. Logs can contain sensitive application data.

The Nginx vhost is shared by all three reverse proxies (`.28`, `.48`, `.49`). Verify the port
9999 redirect, HTTPS page, container list, log stream, and metrics through every replica.
Verify that the socket proxy rejects a Docker mutation request; do not use a real container
as a destructive test target.

The separate AI Assistant per-app log API still looks for `nomad_ollama`, which intentionally
does not exist in this remote-chat deployment. View the actual `nomad_embed_ollama`,
`nomad_litellm`, and `nomad_cli_proxy_api` components through Dozzle instead. Renaming the
embedding container would allow NOMAD's native installer to manage it, violating IaC ownership.

## Independent embedding + reranker experiment

`portainer_stack.nomad_embedding_eval` deploys a separate, one-shot Compose stack on ds-2.
This is a bounded evaluation on a resized ds-2 (48 GiB, 2026-11-14).

| Component | Limit / isolation |
| --- | --- |
| `nomad_eval_ollama` | 4 CPUs, 24 GiB ceiling, one loaded model and one parallel request |
| `nomad_eval_reranker` | 4 CPUs, 8 GiB; TEI serving `bge-reranker-v2-m3` (`/rerank`) |
| `nomad_embedding_eval` | 0.5 CPU, 128 MiB, standard-library Python runner |
| Models/results | Separate local named volumes, never production `/opt/project-nomad/ollama` |
| Network | Separate bridge; no published ports, production networks, or Docker socket |
| Vector index | Exact in-memory cosine search; never production Qdrant |

The runner's root filesystem must remain writable: Portainer materializes inline `configs.content`
there and rejects this configuration on a read-only service. It still has no capabilities,
privilege escalation, Docker socket, production mounts, or production network membership.

The runner pulls `nomic-embed-text:v1.5`, `bge-m3`, and `qwen3-embedding:8b` (4096-dim), then
evaluates them sequentially. It applies Nomic's `search_*` prefixes, Qwen3's retrieval instruction
(`Instruct: ...\nQuery:` on the query only, raw documents), and raw text for BGE-M3. When the
reranker is reachable, each model's dense top-N candidates are re-scored by the cross-encoder to
produce a two-stage (`reranked_metrics`) view alongside the dense-only `metrics`. Each model is
unloaded after its measurements. Digests, returned dimensions, corpus identity, retrieval metrics,
reranked metrics, and latency observations are saved in `/results/embedding-eval.json`.

The TEI reranker is pulled from Hugging Face on first start. TEI's CPU image targets AVX2; on an
older CPU (this host is an Ivy Bridge Xeon without AVX2) the reranker container may fail to start
with SIGILL — if so the embedding-only results still stand and the reranker is reported as blocked.
TEI does not yet ship Qwen3-Reranker support (the upstream PRs are still open), so the reranker uses
`bge-reranker-v2-m3` (XLM-RoBERTa cross-encoder, MIT) — a model-agnostic two-stage re-score that is
comparable in intent but not the Qwen3 reranker originally requested.

The fixture is **synthetic smoke-test data**, with English technical/reference passages and
English/Portuguese questions. It tests plumbing and provides a small controlled comparison,
not evidence of a production quality improvement. It does not reproduce NOMAD's keyword
bonuses, relevance threshold, query rewriting, or source-diversity scoring.

Before promoting any model, repeat with representative original documents and independently
labelled questions. Compare recall/MRR, warmed query latency, indexing throughput, memory peaks,
and relevance thresholds. Do not interpret `/api/ps` model size as actual peak process RAM.

### Deploy and inspect

Use the repository's normal PR → merge → apply-from-clean-main workflow. Planned targets:

```sh
terraform -chdir=terraform/portainer plan \
  -target=portainer_stack.nomad \
  -target=portainer_stack.reverse_proxy \
  -target=portainer_stack.reverse_proxy_2 \
  -target=portainer_stack.reverse_proxy_3 \
  -target=portainer_stack.nomad_embedding_eval
```

Check host headroom and that no user-run NOMAD benchmark is active before starting the experiment.
Keep ample available RAM; the 6-GiB container limit is a ceiling, not a reservation. Both models
run on the same CPU allowance, but timings on a shared host remain workload-dependent.

```sh
ssh 192.168.48.46 'docker logs nomad_embedding_eval'
ssh 192.168.48.46 'docker inspect -f "{{.State.ExitCode}}" nomad_embedding_eval'
ssh 192.168.48.46 'docker exec nomad_eval_ollama ollama ps'
```

The successful outcome is a non-empty report containing both models and real document/query
counts, not merely an exit code of zero. The runner is not restarted automatically. A deliberate
repeat should go through an approved deployment/task mechanism, not production-model changes.

### Local regression checks

```sh
uv run --no-project --with PyYAML python -m unittest discover -s tests -p 'test_nomad*.py'
```

The same tests run as a pre-commit hook for affected files.

## Rollback and production boundaries

Revert the change through a PR and apply only its targets from merged `main`. Preserve evaluation
volumes/results unless deletion is explicitly approved. This change does **not** switch NOMAD's
embedding model, change its 768-dimensional index, alter Gemini subscription routing, or reset
documents. A BGE-M3 migration still requires application support for its model/prefixes and
1,024-dimensional vectors, plus a separate index rebuild and validation.
