# Pi Anthropic prompt cache check

Collected: 2026-11-18 20:55–20:57 UTC. Scope: local Pi configuration, environment, documentation, and saved session usage. No requests were sent to Anthropic.

## Direct observations

- The current process has `PI_PROVIDER=openai-codex` and `PI_MODEL=gpt-6.1-terra`. It does not use Anthropic.
- `PI_CACHE_RETENTION` is unset in this process. `ANTHROPIC_BASE_URL` is set to a URL with host `127.0.0.1`. The URL and credentials are not recorded here.
- `~/.pi/agent/settings.json` has no `cacheWarming` setting. `.pi/settings.json` was not found. Pi 1.5.2 `docs/settings.md` says the global default is `idle`, subject to eligibility and cost checks.
- `~/.pi/agent/models.json` lists `ollama` and `deepseek`, not a custom Anthropic provider. The global package list includes `npm:@gotgenes/pi-anthropic-auth`.
- A local scan of all 210 session JSONL files found 181 Anthropic usage records dated 2026-11-18. Of these, 161 report nonzero cache reads and 170 report nonzero cache writes. They report 90,920,338 cache-read tokens, 6,296,577 cache-write tokens, and 376 regular input tokens. These are sums of reported usage, not unique tokens or a billing audit.
- At 2026-11-18 18:58:20 UTC, a saved `claude-fable-5-2` usage record reports 814,698 cache-read tokens and 997 cache-write tokens. This is historical session evidence, not a live request.

## Collection method

- `date -u` and selected process environment variable names and values. The base URL was parsed to report only its host.
- Python loaded only relevant keys from Pi settings and model configuration. It did not print credentials.
- Python scanned `~/.pi/agent/sessions/**/*.jsonl`, selected Anthropic usage records by UTC timestamp, and aggregated token counters. It did not copy session content.
- Reviewed Pi 1.5.2 `docs/settings.md`, `docs/environment-variables.md`, and `docs/models-configuration.md` for cache defaults and provider options.

## Follow-up: retention and optimization

Collected: 2026-11-18 20:58–20:59 UTC.

- The installed Pi AI 1.5.2 `dist/api/anthropic-messages.js` contains `resolveCacheRetention` and `getCacheControl`. It uses short retention by default. A request option or `PI_CACHE_RETENTION=long` can override this. Long retention adds `ttl: "1h"` only when model compatibility permits it.
- In this process, `PI_CACHE_RETENTION` is unset. A search of `~/.zshenv`, `~/.zprofile`, and `~/.zshrc` did not find it. This does not prove the effective retention of another Pi process or a request modified by an extension.
- Anthropic's [prompt caching documentation](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), fetched at 20:58 UTC, states that the default lifetime is five minutes. It lists a one-hour option. API cache writes cost 1.25 times base input price for five minutes and twice base input price for one hour. Cache-read multipliers vary by model. Subscription accounting may differ.
- `~/.pi/agent/settings.json` sets `defaultThinkingLevel` to `high`. It has no explicit `showCacheMissNotices`, `cacheWarming`, `compaction`, `defaultTools`, or `codemode` settings. Pi 1.5.2 `docs/settings.md` documents the defaults. Cache warming defaults to `idle` for eligible models, but it is not proof that a specific session qualifies.
- `~/.zshrc` sets `ANTHROPIC_BASE_URL` to a local Headroom endpoint on port 8787. `lsof -nP -iTCP:8787 -sTCP:LISTEN` returned no listener at 20:58 UTC. We do not know whether Pi uses that endpoint. Another session can override it. We do not know whether the installed authentication extension needs it. No connection test or request payload inspection was performed.
- Pi 1.5.2 `docs/codemode.md` says codemode can filter tool results before they enter model context. It is not explicitly enabled in global `defaultTools`. Actual workload benefit is unmeasured.

## Limits

The process environment belongs to this OpenAI Codex session. Other Pi sessions may have different settings or proxy routes. The local proxy, its upstream, exact cache retention, active Anthropic request payload, and provider billing were not checked. Saved usage demonstrates historical cache activity, not present availability or ideal cost settings. Zero counters can include failed or incomplete requests. Cache warming eligibility was not checked for a specific Anthropic session.
