"""Isolated Ollama embedding smoke benchmark; no Qdrant or production config writes.

Run only against a dedicated evaluation Ollama instance. Pulls and unloads models.
Python 3.10+, standard library only. Each fixture document is one pre-sized chunk.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import math
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DISCLAIMER = (
    "Synthetic smoke corpus, NOT proof of real production gain. Exact in-memory "
    "cosine retrieval only; no production chunking, Qdrant, or generation. "
    "Ollama /api/ps sizes are API metadata, NOT measured RAM; no memory extrapolation. "
    "Cold means unloaded model, not flushed OS/disk caches. Timings include HTTP overhead. "
    "When --rerank-url is supplied, dense retrieval is optionally re-ranked by a neural "
    "cross-encoder; rerank scores come from the reranker, not this harness."
)
DEFAULT_FIXTURE = Path(__file__).resolve().parent.parent / "tests/fixtures/nomad-embedding-eval.json"
# Qwen3 embedding/reranker are instruction-aware. This is the task instruction the
# Qwen3-Embedding card ships for retrieval; it is prepended to the query only.
QWEN_QUERY_INSTRUCTION = "Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery:"
# Cross-encoder rerankers re-score only a candidate window, so this is the dense
# retrieval depth they see (standard two-stage RAG: retrieve top-N, rerank to top-K).
DEFAULT_RERANK_TOP_N = 20


class EvalError(Exception):
    """Invalid input, Ollama response, or benchmark state."""


def canonical_model(model: str) -> str:
    if not isinstance(model, str):
        raise EvalError("Ollama model name must be a string")
    return model if ":" in model.rsplit("/", 1)[-1] else model + ":latest"


class Ollama:
    def __init__(self, url: str, timeout: float = 300):
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme not in {"http", "https"} or not parsed.hostname
                or parsed.username or parsed.password or parsed.query or parsed.fragment):
            raise EvalError("--url must be an HTTP(S) endpoint without credentials/query/fragment")
        self.url = url.rstrip("/")
        self.timeout = timeout

    def request(self, path: str, payload: dict | None = None) -> dict:
        data = None if payload is None else json.dumps(payload, allow_nan=False).encode()
        request = urllib.request.Request(
            self.url + path, data=data, headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                result = json.load(response)
        except urllib.error.HTTPError as exc:
            with exc:
                detail = exc.read(1024).decode(errors="replace")
            raise EvalError(f"{path}: HTTP {exc.code}: {detail}") from exc
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, http.client.HTTPException) as exc:
            raise EvalError(f"{path}: {exc}") from exc
        if not isinstance(result, dict):
            raise EvalError(f"{path}: expected JSON object")
        if "error" in result:
            raise EvalError(f"{path}: Ollama error: {result['error']}")
        return result

    def pull(self, model: str) -> None:
        # Native non-streaming mode still reports failures inside HTTP 200 JSON.
        result = self.request("/api/pull", {"model": model, "stream": False})
        if result.get("status") != "success":
            raise EvalError(f"Pull did not report success for {model}: {result}")

    def loaded(self) -> list:
        models = self.request("/api/ps").get("models")
        if not isinstance(models, list) or any(not isinstance(m, dict) for m in models):
            raise EvalError("/api/ps: invalid models list")
        return models

    def unload(self, model: str) -> None:
        def resident():
            return any(canonical_model(m.get("name") or m.get("model") or "") == canonical_model(model)
                       for m in self.loaded())

        if not resident():
            return
        self.request("/api/embed", {"model": model, "input": [], "keep_alive": 0})
        # Ollama schedules unloading asynchronously after the HTTP response.
        deadline = time.monotonic() + min(self.timeout, 30.0)
        while resident():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise EvalError(f"Model still loaded after unload deadline: {model}")
            time.sleep(min(0.1, remaining))

    def digest(self, model: str) -> str:
        models = self.request("/api/tags").get("models")
        if not isinstance(models, list) or any(not isinstance(m, dict) for m in models):
            raise EvalError("/api/tags: invalid models list")
        for item in models:
            name = item.get("name") or item.get("model") or ""
            if (canonical_model(name) == canonical_model(model)
                    and isinstance(item.get("digest"), str) and item["digest"]):
                return item["digest"]
        raise EvalError(f"No digest found for {model}")

    def embed(self, model: str, texts: list[str], dimensions: int) -> list[list[float]]:
        result = self.request("/api/embed", {
            "model": model, "input": texts, "truncate": False, "keep_alive": "10m",
        })
        return validate_vectors(result.get("embeddings"), len(texts), dimensions)


class Reranker:
    """HTTP client for a cross-encoder reranker (TEI /rerank endpoint)."""

    def __init__(self, url: str, timeout: float = 180):
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme not in {"http", "https"} or not parsed.hostname
                or parsed.username or parsed.password or parsed.query or parsed.fragment):
            raise EvalError("--rerank-url must be an HTTP(S) endpoint without credentials/query/fragment")
        self.url = url.rstrip("/")
        self.timeout = timeout

    def rerank(self, query: str, texts: list[str]) -> list[float]:
        if not texts:
            return []
        data = json.dumps({"query": query, "texts": texts, "truncate": True}, allow_nan=False).encode()
        request = urllib.request.Request(self.url + "/rerank", data=data, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                result = json.load(response)
        except urllib.error.HTTPError as exc:
            with exc:
                detail = exc.read(1024).decode(errors="replace")
            raise EvalError(f"/rerank: HTTP {exc.code}: {detail}") from exc
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, http.client.HTTPException) as exc:
            raise EvalError(f"/rerank: {exc}") from exc
        if not isinstance(result, list) or len(result) != len(texts):
            raise EvalError(f"/rerank: expected {len(texts)} results, got {result!r}")
        scores = [0.0] * len(texts)
        for item in result:
            index = item.get("index")
            score = item.get("score")
            if not isinstance(index, int) or not 0 <= index < len(texts) or not isinstance(score, (int, float)):
                raise EvalError(f"/rerank: malformed result item {item!r}")
            scores[index] = float(score)
        return scores


def validate_vectors(vectors: object, count: int, dimensions: int) -> list[list[float]]:
    if not isinstance(vectors, list) or len(vectors) != count:
        raise EvalError(f"Expected {count} embedding vectors")
    normalized = []
    for vector in vectors:
        if not isinstance(vector, list) or len(vector) != dimensions:
            raise EvalError(f"Expected embedding dimension {dimensions}")
        try:
            valid = all(type(v) in (int, float) and math.isfinite(v) for v in vector)
            norm = math.hypot(*vector) if valid else 0
        except (OverflowError, TypeError):
            norm = 0
        if not norm or not math.isfinite(norm):
            raise EvalError("Embedding must contain finite numbers and have nonzero finite norm")
        normalized.append([v / norm for v in vector])
    return normalized


def load_fixture(path: Path) -> tuple[dict, str]:
    raw = path.read_bytes()
    fixture = json.loads(raw)
    if not isinstance(fixture, dict) or fixture.get("synthetic_smoke_corpus") is not True:
        raise EvalError("Fixture must explicitly declare synthetic_smoke_corpus: true")
    for key in ("documents", "queries"):
        rows = fixture.get(key)
        if not isinstance(rows, list) or not rows:
            raise EvalError(f"Fixture needs nonempty {key}")
        ids = []
        for row in rows:
            if not isinstance(row, dict) or any(
                not isinstance(row.get(field), str) or not row[field].strip() for field in ("id", "text")
            ):
                raise EvalError(f"Each {key} entry needs nonempty string id/text")
            ids.append(row["id"])
        if len(ids) != len(set(ids)):
            raise EvalError(f"Duplicate {key} IDs")
    document_ids = {doc["id"] for doc in fixture["documents"]}
    languages = set()
    for query in fixture["queries"]:
        relevant = query.get("relevant")
        if (query.get("language") not in {"en", "pt"} or not isinstance(relevant, list)
                or not relevant or any(not isinstance(r, str) for r in relevant)
                or len(relevant) != len(set(relevant)) or not set(relevant) <= document_ids):
            raise EvalError("Query needs en/pt language and unique known relevant document IDs")
        languages.add(query["language"])
    if languages != {"en", "pt"}:
        raise EvalError("Fixture must include both English and Portuguese queries")
    return fixture, hashlib.sha256(raw).hexdigest()


def prefixed(text: str, role: str, style: str) -> str:
    """Apply a model family's task prefix. `role` is 'query' or 'document'."""
    if style == "nomic":
        return f"search_{role}: {text}"
    if style == "qwen3":
        # Queries carry the retrieval instruction; documents stay raw (per the card).
        return f"{QWEN_QUERY_INSTRUCTION} {text}" if role == "query" else text
    return text  # raw (bge-m3, mxbai, etc.)


def prefix_label(style: str) -> str:
    return {
        "nomic": "search_document: / search_query:",
        "qwen3": "query: 'Instruct: ...\\nQuery:' (documents raw)",
        "raw": "none (raw text)",
    }.get(style, style)


def rank(documents: list[dict], vectors: list[list[float]], query: list[float]) -> list[dict]:
    scored = [
        {"id": doc["id"], "score": sum(a * b for a, b in zip(vector, query))}
        for doc, vector in zip(documents, vectors)
    ]
    return sorted(scored, key=lambda item: (-item["score"], item["id"]))


def retrieval_metrics(ranking: list[dict], relevant: list[str]) -> dict:
    relevant_ids = set(relevant)
    positions = [i for i, row in enumerate(ranking, 1) if row["id"] in relevant_ids]
    return {
        "recall_at_1": sum(p <= 1 for p in positions) / len(relevant_ids),
        "recall_at_5": sum(p <= 5 for p in positions) / len(relevant_ids),
        "mrr": 1 / positions[0] if positions else 0.0,
    }


def summarize_metrics(rows: list[dict]) -> dict:
    def mean_metrics(group):
        return {"queries": len(group), **{
            key: statistics.mean(row["metrics"][key] for row in group)
            for key in ("recall_at_1", "recall_at_5", "mrr")
        }}

    return {
        "overall": mean_metrics(rows),
        "by_language": {
            language: mean_metrics([row for row in rows if row["language"] == language])
            for language in sorted({row["language"] for row in rows})
        },
    }


def latency_summary(samples: list[float]) -> dict:
    ordered = sorted(samples)
    return {
        "samples": len(samples), "median_ms": statistics.median(samples),
        "p95_ms": ordered[math.ceil(0.95 * len(ordered)) - 1],
    }


def timed_embed(client: Ollama, model: str, texts: list[str], dimensions: int) -> tuple[list, float]:
    start = time.perf_counter()
    vectors = client.embed(model, texts, dimensions)
    return vectors, (time.perf_counter() - start) * 1000


def measure_model(client: Ollama, fixture: dict, spec: tuple, repeats: int, batch_size: int,
                  reranker: Reranker | None = None, rerank_top_n: int = DEFAULT_RERANK_TOP_N) -> dict:
    model, dimensions, style = spec
    print(f"[{model}] pulling model; expected dimensions={dimensions}", flush=True)
    client.pull(model)
    digest = client.digest(model)
    try:
        client.unload(model)
        first_query = prefixed(fixture["queries"][0]["text"], "query", style)
        _, cold_ms = timed_embed(client, model, [first_query], dimensions)
        print(f"[{model}] digest={digest}; validated model-load-cold query in {cold_ms:.1f} ms", flush=True)
        documents = fixture["documents"]
        index_start = time.perf_counter()
        vectors = []
        for offset in range(0, len(documents), batch_size):
            texts = [prefixed(d["text"], "document", style) for d in documents[offset:offset + batch_size]]
            vectors.extend(client.embed(model, texts, dimensions))
        index_seconds = time.perf_counter() - index_start
        print(f"[{model}] indexed {len(vectors)} chunks x {dimensions} dimensions "
              f"in {index_seconds:.3f}s ({len(vectors) / index_seconds:.2f} chunks/s)", flush=True)
        # A separate warmup is excluded from query latency statistics.
        client.embed(model, [first_query], dimensions)
        rows = []
        for query in fixture["queries"]:
            samples = []
            for _ in range(repeats):
                query_vectors, elapsed = timed_embed(
                    client, model, [prefixed(query["text"], "query", style)], dimensions
                )
                samples.append(elapsed)
            ranking = rank(documents, vectors, query_vectors[0])
            rows.append({
                "id": query["id"], "language": query["language"], "relevant": query["relevant"],
                "query_text": query["text"], "ranking": ranking,
                "metrics": retrieval_metrics(ranking, query["relevant"]),
                "warm_embedding_ms": samples,
            })
        rerank_status = None
        if reranker is not None:
            try:
                text_by_id = {doc["id"]: doc["text"] for doc in documents}
                for row in rows:
                    window = row["ranking"][:rerank_top_n]
                    candidates = [text_by_id[item["id"]] for item in window]
                    scores = reranker.rerank(row["query_text"], candidates)
                    order = sorted(range(len(candidates)), key=lambda i: (-scores[i], window[i]["id"]))
                    reranked = [{"id": window[i]["id"]} for i in order] + \
                               [{"id": item["id"]} for item in row["ranking"][rerank_top_n:]]
                    row["reranked_metrics"] = retrieval_metrics(reranked, row["relevant"])
                rerank_status = "ok"
            except EvalError as exc:
                print(f"[{model}] reranker unavailable; skipping two-stage rerank: {exc}", flush=True)
                rerank_status = f"skipped: {exc}"
        loaded = client.loaded()
        metrics = summarize_metrics(rows)
        latency = latency_summary([ms for row in rows for ms in row["warm_embedding_ms"]])
        overall = metrics["overall"]
        print(f"[{model}] evaluated {len(rows)} queries ({latency['samples']} warm samples); "
              f"recall@1={overall['recall_at_1']:.4f} recall@5={overall['recall_at_5']:.4f} "
              f"MRR={overall['mrr']:.4f}; warm median/p95="
              f"{latency['median_ms']:.1f}/{latency['p95_ms']:.1f} ms", flush=True)
        result = {
            "model": model, "digest": digest, "expected_dimensions": dimensions,
            "verified_dimensions": len(vectors[0]), "document_count": len(vectors),
            "prefixes": prefix_label(style),
            "cold_query": {"id": fixture["queries"][0]["id"], "embedding_ms": cold_ms},
            "indexing": {"seconds": index_seconds, "chunks_per_second": len(vectors) / index_seconds,
                         "batch_size": batch_size, "model_already_loaded": True},
            "warm_query_latency": latency,
            "warm_query_latency_by_language": {
                language: latency_summary([ms for row in rows if row["language"] == language
                                           for ms in row["warm_embedding_ms"]])
                for language in sorted({row["language"] for row in rows})
            },
            "metrics": metrics, "queries": rows,
            "ollama_ps_metadata": loaded,
            "ollama_ps_note": "API-reported metadata only; size/size_vram are NOT measured process RAM",
        }
        if rerank_status == "ok":
            result["reranked_metrics"] = summarize_metrics([
                {"language": row["language"], "metrics": row["reranked_metrics"]} for row in rows
            ])
            result["rerank"] = {
                "note": "Dense top-N candidates re-scored by the cross-encoder at --rerank-url; "
                        "reranked_metrics are comparable to metrics but reflect the two-stage pipeline.",
                "top_n": rerank_top_n,
            }
        elif reranker is not None:
            result["rerank"] = {"status": rerank_status}
        return result
    finally:
        # Do not silently continue with overlapping resident benchmark models.
        client.unload(model)
        print(f"[{model}] unloaded; no longer resident according to /api/ps", flush=True)


def run(args: argparse.Namespace) -> dict:
    fixture, fixture_hash = load_fixture(args.fixture)
    client = Ollama(args.url, args.timeout)
    models = [
        (args.nomic_model, 768, "nomic"),
        (args.bge_model, 1024, "raw"),
        (args.qwen_model, args.qwen_dims, "qwen3"),
    ]
    names = [model[0] for model in models]
    if len(set(names)) != len(names):
        raise EvalError("Model names must be distinct")
    reranker = Reranker(args.rerank_url, args.timeout) if args.rerank_url else None
    initial_models = client.loaded()
    if initial_models:
        raise EvalError("Evaluation endpoint must start with no loaded models; use a dedicated instance")
    return {
        "schema_version": 1, "created_at": datetime.now(timezone.utc).isoformat(),
        "disclaimer": DISCLAIMER, "synthetic_smoke_corpus": True,
        "fixture": {"path": str(args.fixture), "sha256": fixture_hash,
                    "description": fixture.get("description", "Synthetic handcrafted smoke fixture"),
                    "documents": len(fixture["documents"]), "queries": len(fixture["queries"])},
        "method": {"index": "exact cosine, in memory", "document_unit": "one document = one chunk",
                   "warm_repeats_per_query": args.repeats, "p95": "nearest rank",
                   "query_latency": "embedding HTTP round trip + validation; excludes cosine ranking",
                   "recall": "fraction of relevant documents retrieved; macro average over queries",
                   "preprocessing": "Identical fixture text, no splitting/overlap/filtering; "
                                    "Nomic search_* prefixes, Qwen3 query instruction, bge raw text",
                   "normalization": "L2 normalize finite nonzero vectors; exact dot product = cosine",
                   "rerank": (f"cross-encoder re-score of dense top-{args.rerank_top_n} candidates"
                              if reranker else "disabled"),
                   "limitations": [
                       "Short English documents with paired English/Portuguese queries; not independent production samples",
                       "Handcrafted relevance labels, not independently adjudicated; no statistical significance claim",
                       "Dense vectors only; no BGE sparse/ColBERT retrieval; reranker (when enabled) is a single cross-encoder",
                       "Fixed model/query order; one model-load-cold sample; OS caches not flushed",
                       "Warm indexing follows the cold query; query warmup excluded; server inference settings unchanged",
                       "Hardware contention/server defaults affect timings; process RAM and peak memory not measured",
                   ],
                   "order": names, "initial_ollama_ps_metadata": initial_models},
        "models": [measure_model(client, fixture, model, args.repeats, args.batch_size, reranker, args.rerank_top_n)
                   for model in models],
    }


def positive_int(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def positive_timeout(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be finite and positive")
    return number


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Dedicated evaluation Ollama endpoint (no default)")
    parser.add_argument("--allow-model-changes", action="store_true", required=True,
                        help="Acknowledge model downloads and load/unload on this isolated endpoint")
    parser.add_argument("--fixture", type=Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--nomic-model", default="nomic-embed-text:v1.5")
    parser.add_argument("--bge-model", default="bge-m3")
    parser.add_argument("--qwen-model", default="qwen3-embedding:8b")
    parser.add_argument("--qwen-dims", type=positive_int, default=4096,
                        help="Expected embedding dimension for the qwen model (8b=4096, 4b=2560, 0.6b=1024)")
    parser.add_argument("--rerank-url", default=None,
                        help="Optional TEI cross-encoder endpoint (e.g. http://reranker:80); "
                             "when set, dense top-N candidates are re-scored by the reranker")
    parser.add_argument("--rerank-top-n", type=positive_int, default=DEFAULT_RERANK_TOP_N,
                        help="Dense candidate window the reranker re-scores")
    parser.add_argument("--timeout", type=positive_timeout, default=300.0, help="Per HTTP request seconds")
    parser.add_argument("--repeats", type=positive_int, default=3)
    parser.add_argument("--batch-size", type=positive_int, default=16)
    args = parser.parse_args(argv)
    try:
        if args.output.resolve() == args.fixture.resolve():
            raise EvalError("Output must not overwrite the fixture")
        result = run(args)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    except (EvalError, OSError, ValueError) as exc:
        print(f"Embedding evaluation failed: {exc}", file=sys.stderr)
        return 1
    print(f"Completed {len(result['models'])} models, {result['fixture']['documents']} documents and "
          f"{result['fixture']['queries']} queries per model; wrote {args.output}. "
          "Synthetic smoke results only, NOT production evidence.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
