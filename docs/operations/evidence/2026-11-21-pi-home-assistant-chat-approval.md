# Home Assistant chat approval checks

The earlier pane check at `2026-11-21T22:47:31Z` found a template tool waiting at `Enter: continue`. The old flow used a review dialog and a second confirmation. No request was sent during that check.

`node --test tests/pi-home-assistant.test.ts` passed seven tests before the PR. The approval tests verify the snapshot of arguments, one pending request, expiry, cancellation, and single use. They also verify that RPC and extension messages cannot approve a request. A test checks that changing the Pi transcript branch clears the request. Strict TypeScript passed against Pi and `pi-tui` 1.6.0.

A disposable Pi 1.6.0 terminal connected to the Home Assistant HTTPS MCP endpoint. The shortcut `/ha template` with the constant expression `{{ 2 + 2 }}` showed an approval card in chat. The terminal accepted the exact `approve` reply and showed a completed result. No device write was sent. The PR has the post-merge Herdr check.
