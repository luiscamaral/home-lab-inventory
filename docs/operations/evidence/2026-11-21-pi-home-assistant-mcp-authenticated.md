# Authenticated Home Assistant MCP discovery

## Live observations

Collection began at `2026-11-21T19:56:04Z` on the workstation. The source was `https://ha.home.lcamaral.com/api/mcp`. A Python `urllib.request` client sent Streamable HTTP POST requests. It verified TLS and disabled redirects and proxies. It read the `HA-TOKEN` Keychain value from standard input. The token and response bodies were not saved.

| JSON-RPC method | Result |
| --- | --- |
| `initialize` with protocol `2025-06-18` | HTTP 200 JSON. Server name `home-assistant`, empty version, no instructions, no session ID. The server accepted `2025-06-18`. |
| `notifications/initialized` | HTTP 202. |
| `tools/list` | HTTP 200 JSON. One page, 32 tools. |
| `prompts/list` | HTTP 200 JSON. One prompt, `Merged LLM API`, with no arguments. |
| `resources/list` | HTTP 200 JSON. One resource, `assist_context_snapshot`, at `homeassistant://assist/context-snapshot`. Media type `text/plain`. |
| `resources/templates/list` | HTTP 200 JSON with RPC error `-32601`. |

The server advertised tools, prompts, and resources. It set `listChanged: false` for all three and `subscribe: false` for resources.

## Tool inventory

The server marked these 12 tools `readOnlyHint: true`. It also marked `homeassistant__GetLiveContext` and `llm__GetDateTime` `destructiveHint: true`. These are server annotations, not proof of behavior.

| Tool | Input fields |
| --- | --- |
| `homeassistant__GetLiveContext` | `name`, `domain`, `area` |
| `llm__GetDateTime` | None |
| `todo__get_items` | `todo_list` (required), `status` |
| `config__get_config_entries` | `domain`, `status` |
| `config__search_integrations` | `query` (required), `type` |
| `hassio__get_logs` | `source`, `start_time`, `end_time`, `level`, `contains`, `limit` |
| `history__get_history` | `entity_ids` (required), `start_time`, `end_time`, `period` |
| `homeassistant__render_template` | `template` (required), `variables` |
| `homeassistant__search_actions` | `query` (required) |
| `search__search` | `query` (required), `type`, `offset` |
| `system_health__get_system_info` | None |
| `system_log__get_entries` | `level`, `logger`, `limit`, `include_traceback` |

The other 20 tools had `readOnlyHint: false`:

```text
assist_satellite__HassBroadcast
intent__HassTurnOn
intent__HassTurnOff
intent__HassSetPosition
intent__HassStopMoving
intent__HassCancelAllTimers
light__HassLightSet
media_player__HassMediaUnpause
media_player__HassMediaPause
media_player__HassMediaNext
media_player__HassMediaPrevious
media_player__HassSetVolume
media_player__HassSetVolumeRelative
media_player__HassMediaPlayerMute
media_player__HassMediaPlayerUnmute
todo__HassListAddItem
todo__HassListCompleteItem
todo__HassListRemoveItem
config__reload_config_entry
homeassistant__call_action
```

## Pi connection check

At `2026-11-21T19:57:02Z`, `pi mcp list --json` ran with a temporary `PI_CODING_AGENT_DIR`. The config set `home_assistant` to the HTTPS route with `exposure: hidden`. It set `homeassistant__GetLiveContext` to `direct` and `history__get_history` to `codemode`.

Pi reported `state: connected`, `exposure: hidden`, and 32 tools. The captured output did not show per-tool exposure. This check verified the connection, not the tool allowlist. The shell removed the temporary directory.

## Extension verification

At `2026-11-21T20:05:34Z`, a Node script loaded `HomeAssistantClient` from the project extension. It used Keychain through standard input and connected to the same HTTPS URL. It compared `tools/list` to the alias map, called `llm__GetDateTime`, and read the prompt and snapshot. It printed counts and the error flag only.

```text
live tools=32 mapped=32 missing=0 unmapped=0
DateTime: isError=false content blocks=1
prompt messages=1
snapshot contents=1
```

Before `2026-11-21T20:08:29Z`, a separate Pi 1.6.0 run used a temporary agent directory. In RPC mode, `get_commands` listed the seven extension commands and `skill:home-assistant`. In terminal mode, `/ha-connect` succeeded. `/ha-status` reported `32/32 mapped tools`. `/ha time` opened the `llm__GetDateTime` local view. `/ha-disconnect` reported that Home Assistant disconnected.

The mock tests ran with `node --test tests/pi-home-assistant.test.ts`: 3 passed. Strict TypeScript checks used the installed Pi 1.6.0 type declarations and passed.

## Limits

Only the read-only time tool ran live. The client did not test OAuth or authenticate over plain HTTP. The handshake reported no version. No device actions or Home Assistant settings changed. Native model tool calls were not sent to a model provider.
