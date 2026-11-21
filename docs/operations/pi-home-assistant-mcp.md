# Home Assistant MCP in Pi

This project extension maps the 32 tools found on Home Assistant. It needs Pi 1.6.0, a trusted inventory checkout,
macOS Keychain, and access to the LAN HTTPS proxy. It does not add a global Pi server or change Home Assistant.

## Use it

1. Open Pi from the inventory checkout. Review the project extension before you trust the checkout.
2. If Pi was open before the extension landed, run `/reload`.
3. Run `/ha-connect`. Pi reads the existing `HA-TOKEN` entry for your account. It keeps the token in memory and sends it
   only to `https://ha.home.lcamaral.com/api/mcp`.
4. Run `/ha-tools` to see the aliases, live argument names, and required fields. Run `/mcp` to check the native connection.
5. Run `/ha-disconnect` when done. Switching Pi sessions also disconnects the server. Other Herdr panes do not connect
   unless you run `/ha-connect` there.

| Command | Use |
| --- | --- |
| `/ha-status` | Check the registration and native mapped tool count. |
| `/ha-tools` | Compare the local map with the live tool list. |
| `/ha <alias> [JSON]` | Run a tool with exact arguments and no model call. |
| `/ha-prompt` | View the server prompt. Pi does not send it to the model or transcript. |
| `/ha-snapshot` | View the state of entities exposed to Assist. |
| `/ha-disconnect` | Remove the session registration and close the shortcut connection. |
| `/skill:home-assistant` | Load the workflow for model-assisted reads and writes. |

```text
/ha time
/ha state {"domain":"light"}
/ha history {"entity_ids":["sensor.example"],"period":"1h"}
/ha light {"name":"Example lamp","brightness":30}
```

Use Tab after `/ha` for the aliases. Use `/ha-tools` for live argument names and required fields. For types and accepted
values, inspect the tool schema in native Pi tool discovery. The shortcut sends arguments as supplied and lets Home
Assistant check them.

## Commands by task

| Task | Aliases |
| --- | --- |
| State and history | `state`, `time`, `search`, `history`, `template` |
| Logs and integrations | `health`, `logs`, `system-log`, `integrations`, `integration-search`, `integration-reload` |
| Lights and covers | `on`, `off`, `light`, `position`, `stop` |
| Media and announcements | `play`, `pause`, `next`, `previous`, `volume`, `volume-step`, `mute`, `unmute`, `broadcast` |
| To-do lists and timers | `todo-items`, `todo-add`, `todo-complete`, `todo-remove`, `timers-cancel` |
| Other actions | `action-search`, `action` |

## Tool access and approvals

Pi exposes reads through `codemode`. It exposes the write tools and `template` on demand. Use tool search or scope
`searchTools()` to `inventory_ha`. Native Pi can also list and read the Assist snapshot. The local shortcut client
supports this server's JSON replies. Native Pi supports streaming tool replies.

Both paths require terminal review for all 20 writes and for `template`. Read the tool name and JSON. Press Enter to
continue to a separate confirmation. Escape cancels.

Pi blocks unmapped tools and blocks writes outside the Pi terminal. The extension does not retry writes. If the result
is unclear, check the live state before you retry.

A terminal confirmation does not approve an infrastructure change. Do not use generic actions or integration reloads to
bypass the repo's approval and apply rules. Use a Home Assistant account with only the permissions you need. This
extension gates its own tools. It is not a sandbox for shell commands or other extensions.

Shortcut results open at the top of a read-only view. Use Up and Down to scroll, Page Up and Page Down to move a page,
or Home and End to jump. Press Escape or Enter to close the result. The view shows the snapshot and prompt text without
wrapping them in JSON. Large results may reach the display limit. Use a narrower query for more detail.

Shortcut results do not enter the Pi transcript. Native MCP results can reach the model and transcript. Do not share
private logs or whole-house snapshots when a narrower query will do. Keep the token out of prompts, files, and terminal
history.

## Test and remove

Run `node --test tests/pi-home-assistant.test.ts` from the repository root. The tests use a mock server. They do not read
Keychain or contact Home Assistant.

For a live read-only check, run `/ha-connect`, `/ha-tools`, `/ha time`, `/ha-prompt`, and `/ha-snapshot`. Check that each
view opens at line 1. In the snapshot, page down, jump back to the top, and resize the pane. Close the result and run
`/ha-disconnect`. Do not send a live write to test the setup.

To stop now, run `/ha-disconnect`. To remove the project feature, revert its PR and run `/reload`. There is no
server-side change to roll back.

See the [authenticated tool inventory](evidence/2026-11-21-pi-home-assistant-mcp-authenticated.md).
