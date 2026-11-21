# Evidence: what triggers Antigravity login prompts on the workstation

- Collected: 2026-11-20 15:25:22Z to 15:26:24Z (08:25 to 08:26 local)
- Host: local macOS workstation (user `lamaral`). No homelab hosts were checked.
- Collector: pi session `01a1f98f-bfb0-71a6-acea-5bd89a3afc31` (pi PID 59542)
- Secrets: none were read. I listed OAuth files by name only and did not read them.

## Direct observations

### O1. Live agy process and its parent chain

Command: `ps -axo pid,ppid,user,lstart,etime,command`, then a walk up the parent chain.

```text
59850 59542 Fri Nov 20 08:25:10 2026  agy --print /usage --output-format json
59542 14678 Fri Nov 20 08:25:09 2026  pi            (ttys036, this session)
14678 94770 Fri Nov 13 12:25:20 2026  -zsh
94770     1 Thu Nov 12 09:16:14 2026  wezterm-gui
```

The process exited before 15:25:42Z.

### O2. agy log for that run

Source: `~/.gemini/antigravity-cli/log/cli-20261120_082513.log` (lines matched by grep)

```text
08:25:13.518 error getting token source: You are not logged into Antigravity.
08:25:13.605 printmode.go:409] Print mode: not authenticated, trying silent auth
08:25:13.622 printmode.go:415] Print mode: silent auth failed
08:25:13.622 printmode.go:432] Print mode: triggering interactive OAuth
08:25:13.622 browser.go:56] consumerOAuth: starting OAuth flow
08:25:40.900 server.go:4467] Got signal terminated, shutting down
08:25:40.900 printmode.go:472] Print mode: auth cancelled or interrupted
```

The OAuth flow ran about 30 s after spawn, then got SIGTERM.

### O3. Which code spawns that command

Command: `grep -rIn '"/usage"'` over `~/.pi/agent/extensions` and `~/.pi/agent/npm/node_modules`.

- `~/.pi/agent/extensions/usage-windows.ts:103`: `execFile("agy", ["--print", "/usage", "--output-format", "json"], { timeout: AGY_TIMEOUT_MS })`.
  The argument list matches the live process exactly.
- In the same file:
  - `AGY_REFRESH_MS = PI_USAGE_AGY_MS || 10 min`
  - `AGY_TIMEOUT_MS = 30 s`
  - `session_start` calls `refresh`, then runs `setInterval(refresh, REFRESH_MS = 60 s)`.
  - agy runs at most once every 10 min per pi session.
- `pi-antigravity-bridge/src/usage.ts:121` uses different arguments: it adds `--print-timeout`.
  It runs only from the manual `/agy quota` command (`extensions/index.ts:1606`).

### O4. How often it happened

Source: file names and grep over `~/.gemini/antigravity-cli/log/`.

- 2026-11-20: 83 agy log files. 29 of them contain `triggering interactive OAuth`.
- First prompt today: `cli-20261120_025845.log`. Last: `cli-20261120_082513.log`.
- `cli-20261120_000427.log` shows `Auth succeeded` and no OAuth trigger.
- 2026-11-16: 1 OAuth trigger (`cli-20261116_162151.log`).
- Recent runs: 07:51, 08:01, 08:11, 08:21, 08:25. All have `promptLength=6`, which matches `/usage`.

### O5. Other context

- 25 interactive `pi` processes were running (`ps`, ttys002 to ttys044).
  Each one loads `usage-windows.ts`.
- mise `antigravity-cli` install dir changed at 08:21 to 08:22 (1.5.7 to 1.5.12, `latest`).
  The agy log reports language server version 1.5.13.
- Nothing matched in crontab or LaunchAgents. The watchman plist matched only through a PATH string.

## Finding

The `agy` CLI is logged out. The pi extension `usage-windows.ts` runs
`agy --print /usage` when a pi session starts and every 10 min after that.
Each run fails silent auth, so agy starts an interactive browser OAuth flow.
The extension kills it after 30 s. (O1 to O4)

## Hypotheses (not verified)

- H1. Login was lost between 00:04 and 02:58 local on 2026-11-20. The cause is unknown.
  It may relate to the agy self-update or the mise upgrade. Neither was confirmed.
- H2. Many pi sessions each poll on their own 10-min timer, so prompts can repeat often.
  Which PIDs spawned the earlier runs was not captured.

## Not checked

- The parent PIDs of runs before 08:25. Only the live run was traced.
- Browser history, to see whether a login tab opened.
- The Antigravity IDE app's own sign-in state.

## Follow-up: why the login breaks again (collected 2026-11-20 17:42Z to 17:45Z)

Source: `~/.gemini/antigravity-cli/log/cli-*.log` for 2026-11-18 to 2026-11-20.
I split mixed log lines on timestamps. Keychain: `security dump-keychain` and
`find-generic-password` without `-w`, so I read metadata only and no secrets.

### O6. Correct failure marker

Every run logs `Print mode: not authenticated, trying silent auth`. The real failure
line is `silent auth failed`. My first per-file status in O4 was too broad.
Runs with a print-mode start, 2026-11-18 to 2026-11-20 (`/tmp/agy-auth-timeline.txt`):
1064 ok, 42 ok+refresh, 46 failed, 2 failed then logged in, 14 unclear.

### O7. The token lasts one hour and is kept in the keychain

- `keyringAuth: loaded token, expiry=…` shows a one-hour access token.
  The login at 10:41:09 local got expiry 11:41:09.
- Keychain item: service `gemini`, account `antigravity`.
  Created and modified at `20261120174110Z`, which is the user's login at 10:41 local.
  So the item was missing before that login.

### O8. Only two switches from working to failing, and both follow a token refresh

| Last good run | What it did | Next run |
|---|---|---|
| 02:49:55 (`inventory` session) and 02:49:56 (`crafts` session) | Both loaded the same expired token and both refreshed it within 0.8 s. Both logged `Failed keyring SaveToken, falling back to file when applicable: exit status 45` | 02:58:45 failed |
| 09:31:01 (`authorian-plans-internal` session) | Loaded the expired token, then logged `token refreshed, new expiry=10:31:00`. No save success or failure appears. `Language server shutdown timed out` at 09:31:09 | 09:32:01 failed, with no keychain read logged |

- `Failed keyring SaveToken … exit status 45` shows up in 12 logs between 2026-11-19 and 2026-11-20.
- Not every refresh breaks login: 42 refreshes left it working.
- The agy logs show no explicit delete, logout, or `invalid_grant`.

### O9. How many agy runs there are

- Today agy ran about twice per 10 minutes, at xx:x1:01 and xx:x2:01.
- The runs came from several pi workspaces: `inventory`, `crafts`, `solidcraft`, `authorian-plans-internal`.
- Log names only go down to the second, so runs that start in the same second share one file.

### Hypotheses (not verified)

- H3. agy writes the refreshed token in two steps, delete then add, through `/usr/bin/security`.
  Exit status 45 matches `errSecDuplicateItem` (-25299 & 0xFF).
  Concurrent refreshes, or a process exiting between the two steps, can leave the item missing.
  The next run then finds no token and opens the browser OAuth.
- H4. Many agy processes raise the chance of this race.
  Each pi session polls on its own, the extension kills agy after 30 s, and the token expires every hour.

### Not checked

- The agy source code, to confirm how it saves the token.
- Whether the Antigravity IDE or gemini-cli also writes the `gemini`/`antigravity` keychain item.
