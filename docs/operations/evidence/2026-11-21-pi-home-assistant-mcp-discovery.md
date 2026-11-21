# Pi and Home Assistant MCP discovery

Scope: Pi 1.6.0 on the workstation and the Home Assistant MCP route. No credentials or device actions were used.

## Live observations

At `2026-11-21T19:48:43Z` and `2026-11-21T19:48:57Z`, the workstation sent `initialize` to each URL. The requests used this probe with no proxy, no redirects, and the default TLS checks:

```sh
curl --noproxy '*' --silent --show-error --max-time 8 \
  --output /dev/null --write-out 'HTTP %{http_code}; TLS verify %{ssl_verify_result}\n' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --data-binary '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"pi-ha-audit","version":"0.1"}}}' \
  "$url"
```

| URL | Result |
| --- | --- |
| `http://ha.iot.lcamaral.com:8123/api/mcp` | HTTP 401 |
| `https://ha.iot.lcamaral.com:8123/api/mcp` | No HTTP response. curl error 35: `tlsv1 alert protocol version`. |
| `https://ha.home.lcamaral.com/api/mcp` | HTTP 401. TLS verify result 0. |

At `2026-11-21T19:49:12Z` and `2026-11-21T19:49:20Z`, `curl --noproxy '*' --silent --show-error --max-time 8` sent GET requests to these paths on `https://ha.home.lcamaral.com`:

| Path | Result |
| --- | --- |
| `/.well-known/oauth-protected-resource/api/mcp` | HTTP 404 |
| `/.well-known/oauth-protected-resource` | HTTP 404 |
| `/.well-known/oauth-authorization-server` | HTTP 200. `client_id_metadata_document_supported: true`. `code_challenge_methods_supported: ["S256"]`. No `issuer` field in the parsed response. |

A second HTTPS `initialize` returned `HTTP/1.1 401 Unauthorized` at `2026-11-21T19:49:20Z`. A header filter found no `WWW-Authenticate` header.

## Reference sources

- `pi --version` returned `1.6.0`. Its installed `docs/mcp.md` describes built-in Streamable HTTP, OAuth, and tool exposure controls.
- `dockermaster/docker/compose/nginx-rproxy/vhost.d/ha.home.lcamaral.com.conf` describes the HTTPS proxy and an HTTP upstream. This is a repo record. It does not verify the live proxy or its upstream route.
- `terraform/portainer/vault.tf` describes the Home Assistant metrics credential. No Vault values were read.
- [Home Assistant MCP docs](https://www.home-assistant.io/integrations/mcp_server/) describe tools, a prompt, and an optional state resource. These are upstream features, not a list from this server.
- [Pi extension docs](https://docs.pi.dev/latest/extensions) describe extension commands, tool hooks, and MCP registration.

## Limits

No authenticated MCP session ran. The live server version, tool list, prompts, and resources remain unknown. OAuth sign-in was not tested. The metadata results may affect OAuth discovery, but no cause was confirmed. The server and proxy configs were not inspected on the live hosts. No Home Assistant settings, devices, or Pi settings changed.
