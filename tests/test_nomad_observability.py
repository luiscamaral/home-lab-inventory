"""Regression checks for NOMAD's Dozzle launcher and experiment isolation."""

import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "dockermaster/docker/compose/nomad"
VHOST = ROOT / "dockermaster/docker/compose/nginx-rproxy/vhost.d/nomad.d.lcamaral.com.conf"


class NomadObservabilityTests(unittest.TestCase):
    def setUp(self):
        self.stack = yaml.safe_load((COMPOSE / "docker-compose.yml.tftpl").read_text())
        self.experiment = yaml.safe_load((COMPOSE / "embedding-eval.yml.tftpl").read_text())

    def test_dozzle_has_https_base_and_filters(self):
        service = self.stack["services"]["dozzle"]
        env = dict(item.split("=", 1) for item in service["environment"])
        self.assertEqual(env["DOZZLE_BASE"], "/logs")
        self.assertEqual(env["DOZZLE_FILTER"], "name=^/nomad_")
        self.assertEqual(env["DOZZLE_ENABLE_ACTIONS"], "false")
        self.assertEqual(env["DOZZLE_ENABLE_SHELL"], "false")
        self.assertNotIn("ports", service)
        self.assertFalse(any("docker.sock" in mount for mount in service.get("volumes", [])))

    def test_socket_proxy_is_private_and_read_only(self):
        service = self.stack["services"]["docker-readonly"]
        env = dict(item.split("=", 1) for item in service["environment"])
        self.assertEqual(env["DISABLE_IPV6"], "1")
        self.assertEqual(env["POST"], "0")
        self.assertEqual(env["EXEC"], "0")
        self.assertEqual(env["CONTAINERS"], "1")
        self.assertEqual(service["networks"], ["logs"])
        self.assertTrue(self.stack["networks"]["logs"]["internal"])
        self.assertNotIn("ports", service)
        self.assertEqual(service["volumes"], ["/var/run/docker.sock:/var/run/docker.sock:ro"])

    def test_menu_port_redirects_to_streaming_https_proxy(self):
        text = VHOST.read_text()
        self.assertEqual(text.count("listen 9999;"), 1)
        self.assertIn("return 301 https://nomad.d.lcamaral.com/logs/;", text)
        self.assertIn("location ^~ /logs/", text)
        address = self.stack["services"]["dozzle"]["networks"]["servers-net"]["ipv4_address"]
        self.assertIn(f"proxy_pass http://{address}:8080;", text)
        location = text.split("location ^~ /logs/", 1)[1].split("}", 1)[0]
        self.assertIn("proxy_buffering off;", location)
        self.assertIn("proxy_http_version 1.1;", location)

    def test_admin_uses_custom_embedding_config(self):
        admin = self.stack["services"]["admin"]
        self.assertEqual(admin["image"], "ghcr.io/luiscamaral/project-nomad:v1.35.1-custom-qdrant-timeout")
        env = dict(item.split("=", 1) for item in admin["environment"])
        self.assertEqual(env["EMBEDDING_MODEL_NAME"], "embeddinggemma-2:270m")
        self.assertEqual(env["QDRANT_TIMEOUT_MS"], "1800000")
        self.assertEqual(env["SEARCH_DOCUMENT_PREFIX"], "title: none | text:")
        self.assertEqual(env["SEARCH_QUERY_PREFIX"], "task: search result | query:")

    def test_experiment_cannot_reach_production_data(self):
        services = self.experiment["services"]
        self.assertEqual(set(services), {"ollama", "reranker", "evaluate"})
        for service in services.values():
            self.assertEqual(service["networks"], ["default"])
            self.assertNotIn("ports", service)
            for mount in service.get("volumes", []):
                self.assertFalse(mount.startswith("/"), mount)
        self.assertEqual(services["ollama"]["deploy"]["resources"]["limits"]["memory"], "24G")
        self.assertFalse(services["evaluate"].get("read_only", False))
        self.assertEqual(len(services["evaluate"]["configs"]), 2)
        self.assertEqual(list(services["evaluate"]["depends_on"]), ["ollama"])
        command = " ".join(services["evaluate"]["command"])
        self.assertIn("--rerank-url", command)
        self.assertIn("http://reranker:80", command)
        self.assertIn("--qwen-model qwen3-embedding:4b --qwen-dims 2560", command)
        self.assertEqual(set(self.experiment["volumes"]), {"models", "results", "reranker-models"})
        self.assertIn("text-embeddings-inference", services["reranker"]["image"])
        self.assertEqual(services["reranker"]["command"], ["--model-id", "BAAI/bge-reranker-v2-m3"])
        self.assertEqual(services["reranker"]["deploy"]["resources"]["limits"]["memory"], "8G")
        production = self.stack["services"]["ollama"]
        self.assertEqual(production["container_name"], "nomad_embed_ollama")
        self.assertEqual(production["deploy"]["resources"]["limits"]["memory"], "3G")


if __name__ == "__main__":
    unittest.main()
