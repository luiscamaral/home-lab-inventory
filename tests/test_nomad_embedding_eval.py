"""Deterministic stdlib-only benchmark tests: no real model downloads or services."""

import argparse
import copy
import importlib.util
import io
import json
import math
import tempfile
import threading
import unittest
import urllib.error
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("nomad_embedding_eval", ROOT / "scripts/nomad-embedding-eval.py")
eval_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(eval_module)
FIXTURE = ROOT / "tests/fixtures/nomad-embedding-eval.json"


def tiny_fixture():
    return {
        "synthetic_smoke_corpus": True,
        "documents": [{"id": "a", "text": "alpha"}, {"id": "b", "text": "beta"}],
        "queries": [
            {"id": "en", "text": "alpha?", "language": "en", "relevant": ["a"]},
            {"id": "pt", "text": "beta?", "language": "pt", "relevant": ["b"]},
        ],
    }


class FakeOllama(eval_module.Ollama):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.calls = []
        self.resident = []
        self.bad_vectors = False

    def request(self, path, payload=None):
        self.calls.append((path, copy.deepcopy(payload)))
        if path == "/api/pull":
            return {"status": "success"}
        if path == "/api/tags":
            return {"models": [{"name": m, "digest": "sha256:" + m}
                               for m in ("nomic-embed-text:v1.5", "bge-m3:latest")]}
        if path == "/api/ps":
            return {"models": self.resident.copy()}
        if path == "/api/embed":
            if not payload["input"]:
                self.resident = []
                return {"embeddings": []}
            model = payload["model"]
            self.resident = [{"name": eval_module.canonical_model(model), "size": 1234, "size_vram": 0}]
            dimensions = 768 if model.startswith("nomic") else 1024
            vectors = []
            for text in payload["input"]:
                vector = [0.0] * dimensions
                vector[0 if "alpha" in text else 1] = 1.0
                vectors.append(vector)
            return {"embeddings": [[]] if self.bad_vectors else vectors}
        raise AssertionError(path)


@contextmanager
def fake_server(response, status=200):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            self.send_response(status)
            self.end_headers()
            self.wfile.write(response)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield eval_module.Ollama(f"http://127.0.0.1:{server.server_port}", timeout=1)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class RetrievalTests(unittest.TestCase):
    def test_exact_cosine_order_and_stable_tie_break(self):
        vectors = eval_module.validate_vectors([[3, 0], [1, 1], [0, 2]], 3, 2)
        ranking = eval_module.rank([{"id": x} for x in ("a", "b", "c")], vectors, [1, 0])
        self.assertEqual([r["id"] for r in ranking], ["a", "b", "c"])
        self.assertAlmostEqual(ranking[1]["score"], 1 / math.sqrt(2))
        tie = eval_module.rank([{"id": "z"}, {"id": "a"}], [[1, 0], [1, 0]], [1, 0])
        self.assertEqual([r["id"] for r in tie], ["a", "z"])

    def test_recall_is_fraction_not_hit_rate_and_mrr_uses_first(self):
        ranking = [{"id": str(i)} for i in range(1, 8)]
        self.assertEqual(eval_module.retrieval_metrics(ranking, ["1", "6"]),
                         {"recall_at_1": 0.5, "recall_at_5": 0.5, "mrr": 1.0})
        self.assertEqual(eval_module.retrieval_metrics(ranking, ["2"])["mrr"], 0.5)
        self.assertEqual(eval_module.retrieval_metrics(ranking, ["missing"])["mrr"], 0)

    def test_macro_metrics_grouped_by_language(self):
        rows = [{"language": language, "metrics": dict.fromkeys(
            ("recall_at_1", "recall_at_5", "mrr"), score)}
            for language, score in (("en", 1.0), ("pt", 0.0), ("pt", 0.5))]
        summary = eval_module.summarize_metrics(rows)
        self.assertEqual(summary["overall"]["mrr"], 0.5)
        self.assertEqual(summary["by_language"]["en"]["mrr"], 1)
        self.assertEqual(summary["by_language"]["pt"], {
            "queries": 2, "recall_at_1": 0.25, "recall_at_5": 0.25, "mrr": 0.25})

    def test_latency_median_and_nearest_rank_p95(self):
        self.assertEqual(eval_module.latency_summary(list(range(1, 21))),
                         {"samples": 20, "median_ms": 10.5, "p95_ms": 19})

    def test_invalid_vectors(self):
        cases = [None, [], [[1]], [[1, 0], [0, 1]], [[float("nan"), 1]],
                 [[float("inf"), 1]], [[0, 0]], [[True, 1]], [["1", 0]], [[{}, 0]]]
        for vectors in cases:
            with self.subTest(vectors=vectors), self.assertRaises(eval_module.EvalError):
                eval_module.validate_vectors(vectors, 1, 2)


class HTTPTests(unittest.TestCase):
    def test_native_pull_success_and_in_band_failure(self):
        with fake_server(b'{"status":"success"}') as client:
            client.pull("bge-m3")
        with (fake_server(b'{"error":"download failed"}') as client,
              self.assertRaisesRegex(eval_module.EvalError, "download failed")):
            client.pull("bge-m3")

    def test_incomplete_pull_and_bad_json_fail(self):
        for response in (b'{"status":"pulling manifest"}', b'not JSON', b'[]'):
            with (self.subTest(response=response), fake_server(response) as client,
                  self.assertRaises(eval_module.EvalError)):
                client.pull("bge-m3")

    def test_http_error(self):
        with (fake_server(b'model missing', status=404) as client,
              self.assertRaisesRegex(eval_module.EvalError, "HTTP 404.*model missing")):
            client.pull("bge-m3")

    def test_timeout_and_connection_failure(self):
        client = eval_module.Ollama("http://localhost:1234")
        for error in (TimeoutError("timed out"), urllib.error.URLError("refused")):
            with (patch.object(eval_module.urllib.request, "urlopen", side_effect=error),
                  self.assertRaises(eval_module.EvalError)):
                client.pull("bge-m3")

    def test_url_rejects_credentials_and_non_http(self):
        for url in ("file:///etc/passwd", "http://user:pass@localhost", "http://localhost?key=x"):
            with self.subTest(url=url), self.assertRaises(eval_module.EvalError):
                eval_module.Ollama(url)

    def test_malformed_model_metadata_is_rejected(self):
        client = eval_module.Ollama("http://evaluation")
        for metadata in ({"models": None}, {"models": [None]},
                         {"models": [{"name": 7, "digest": "digest"}]},
                         {"models": [{"name": "bge-m3:latest", "digest": 7}]}):
            with (self.subTest(metadata=metadata), patch.object(client, "request", return_value=metadata),
                  self.assertRaises(eval_module.EvalError)):
                client.digest("bge-m3")


class HarnessTests(unittest.TestCase):
    def test_fixed_fixture_is_synthetic_bilingual_and_multi_topic(self):
        fixture, digest = eval_module.load_fixture(FIXTURE)
        self.assertGreaterEqual(len(fixture["documents"]), 10)
        self.assertEqual({q["language"] for q in fixture["queries"]}, {"en", "pt"})
        self.assertEqual(len(digest), 64)
        self.assertIn("NOT proof", fixture["description"])

    def test_fixture_rejects_unknown_labels_duplicates_and_missing_language(self):
        for mutation in (lambda f: f.update(synthetic_smoke_corpus=False),
                         lambda f: f["queries"][0].update(relevant=["unknown"]),
                         lambda f: f["queries"][0].update(relevant=["a", "a"]),
                         lambda f: f["queries"][0].update(language="pt"),
                         lambda f: f["documents"].append(f["documents"][0])):
            fixture = tiny_fixture()
            mutation(fixture)
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "fixture.json"
                path.write_text(json.dumps(fixture))
                with self.assertRaises(eval_module.EvalError):
                    eval_module.load_fixture(path)

    def test_model_measurement_prefixes_timing_metadata_and_unload(self):
        for model, dimensions, nomic in (("nomic-embed-text:v1.5", 768, True), ("bge-m3", 1024, False)):
            client = FakeOllama("http://evaluation")
            result = eval_module.measure_model(client, tiny_fixture(), (model, dimensions, nomic), 2, 1)
            self.assertEqual(result["verified_dimensions"], dimensions)
            self.assertEqual(result["metrics"]["overall"]["mrr"], 1)
            self.assertEqual(result["warm_query_latency"]["samples"], 4)
            self.assertGreaterEqual(result["cold_query"]["embedding_ms"], 0)
            self.assertGreater(result["indexing"]["chunks_per_second"], 0)
            self.assertIn("NOT measured", result["ollama_ps_note"])
            texts = [text for path, payload in client.calls if path == "/api/embed"
                     for text in payload["input"]]
            self.assertIn("search_document: alpha" if nomic else "alpha", texts)
            self.assertIn("search_query: beta?" if nomic else "beta?", texts)
            if not nomic:
                self.assertFalse(any(text.startswith("search_") for text in texts))
            self.assertEqual(client.resident, [])

    def test_unloads_even_on_invalid_dimensions(self):
        client = FakeOllama("http://evaluation")
        client.bad_vectors = True
        with self.assertRaisesRegex(eval_module.EvalError, "dimension 768"):
            eval_module.measure_model(client, tiny_fixture(), ("nomic-embed-text:v1.5", 768, True), 1, 16)
        self.assertEqual(client.resident, [])

    def test_default_bge_digest_accepts_ollama_latest_alias(self):
        client = FakeOllama("http://evaluation")
        self.assertEqual(client.digest("bge-m3"), "sha256:bge-m3:latest")

    def test_unload_detects_still_resident_latest_alias(self):
        client = FakeOllama("http://evaluation")
        with (patch.object(client, "loaded", return_value=[{"name": "bge-m3:latest"}]),
              self.assertRaisesRegex(eval_module.EvalError, "still loaded")):
            client.unload("bge-m3")

    def test_cli_result_json_and_sequential_model_order(self):
        clients = []

        def create_client(*args):
            client = FakeOllama(*args)
            clients.append(client)
            return client

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            fixture = Path(directory) / "fixture.json"
            fixture.write_text(json.dumps(tiny_fixture()))
            with patch.object(eval_module, "Ollama", side_effect=create_client), \
                    redirect_stdout(io.StringIO()) as logs:
                code = eval_module.main(["--url", "http://evaluation", "--allow-model-changes",
                                         "--fixture", str(fixture), "--output", str(output), "--repeats", "1"])
            self.assertEqual(code, 0)
            result = json.loads(output.read_text())
            self.assertEqual(result["schema_version"], 1)
            self.assertTrue(result["synthetic_smoke_corpus"])
            self.assertIn("NOT proof", result["disclaimer"])
            self.assertEqual([m["verified_dimensions"] for m in result["models"]], [768, 1024])
            self.assertEqual([len(m["queries"]) for m in result["models"]], [2, 2])
            self.assertEqual([m["document_count"] for m in result["models"]], [2, 2])
            self.assertIn("indexed 2 chunks x 768 dimensions", logs.getvalue())
            self.assertIn("evaluated 2 queries (2 warm samples)", logs.getvalue())
            self.assertIn("Completed 2 models, 2 documents and 2 queries", logs.getvalue())
            self.assertIn("no splitting", result["method"]["preprocessing"])
            self.assertGreaterEqual(len(result["method"]["limitations"]), 5)
            calls = clients[0].calls
            bge_pull = next(i for i, call in enumerate(calls)
                            if call[0] == "/api/pull" and call[1]["model"] == "bge-m3")
            self.assertEqual(calls[bge_pull - 2], ("/api/embed", {
                "model": "nomic-embed-text:v1.5", "input": [], "keep_alive": 0}))

    def test_cli_failure_has_no_success_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            with patch.object(eval_module, "run", side_effect=eval_module.EvalError("bad vectors")), \
                    redirect_stderr(io.StringIO()) as errors:
                code = eval_module.main(["--url", "http://evaluation", "--allow-model-changes",
                                         "--output", str(output)])
            self.assertEqual(code, 1)
            self.assertIn("bad vectors", errors.getvalue())
            self.assertFalse(output.exists())

    def test_refuses_nonempty_endpoint_before_pulling(self):
        client = FakeOllama("http://evaluation")
        client.resident = [{"name": "production-model"}]
        args = argparse.Namespace(fixture=FIXTURE, url="http://evaluation", timeout=1,
                                  nomic_model="nomic-embed-text:v1.5", bge_model="bge-m3")
        with (patch.object(eval_module, "Ollama", return_value=client),
              self.assertRaisesRegex(eval_module.EvalError, "dedicated instance")):
            eval_module.run(args)
        self.assertFalse(any(path == "/api/pull" for path, _ in client.calls))

    def test_cli_requires_url_and_acknowledgement_and_positive_parameters(self):
        for arguments in (["--output", "unused"],
                          ["--url", "http://evaluation", "--output", "unused"],
                          ["--url", "http://evaluation", "--allow-model-changes", "--output", "unused",
                           "--timeout", "nan"]):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                eval_module.main(arguments)
            self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
