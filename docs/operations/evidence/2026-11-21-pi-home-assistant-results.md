# Home Assistant result view checks

## Original report

The user's screenshot showed `/ha-snapshot` in the old editor. The snapshot state appeared inside a JSON string with literal `\n` separators. The editor opened near the end. The screenshot is not stored in this repo because it contains private entity names.

## Checks on the fix

At `2026-11-21T22:32:08Z`, two disposable Pi 1.6.0 terminal sessions tested the display. One used `pi --approve --no-session --tui-mode fullscreen`. The other used `pi --approve --no-session --tui-mode regular`. Each used a temporary `PI_CODING_AGENT_DIR`.

Both sessions connected via the existing Keychain entry to the Home Assistant HTTPS MCP endpoint. They ran `/ha-snapshot`, `/ha-prompt`, `/ha-tools`, and `/ha time`. The probe checked screen text in memory and printed pass flags only. It did not save the responses or the token.

| Check | Fullscreen | Regular |
| --- | --- | --- |
| Snapshot opens at line 1 and shows state on separate lines | Pass | Pass |
| Snapshot has no JSON envelope or editor footer | Pass | Pass |
| Page Down advances. End reaches the bottom. Home returns to line 1. | Pass | Pass |
| Resize from 105 × 44 to 40 × 18 keeps the title and close hint | Pass | Pass |
| Prompt shows its message text without the JSON envelope | Pass | Pass |
| Tool list opens with 32 tools. Time shows the tool result. | Pass | Pass |
| Write preview shows exact test arguments. Escape cancels before send. | Pass | Pass |
| `/ha-disconnect` reports success | Pass | Pass |

`node --test tests/pi-home-assistant.test.ts` passed six tests. They cover the tool map, client, text formatting, redaction, display limit, and write gate. Strict TypeScript passed against Pi and `pi-tui` 1.6.0 declarations.

No device write ran. Native model calls were not tested in this check. The probe did not change Home Assistant or global Pi settings.
