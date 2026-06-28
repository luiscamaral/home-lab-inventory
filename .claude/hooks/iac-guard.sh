#!/usr/bin/env bash
# PreToolUse(Bash) IaC guard.
# Re-surfaces the project non-negotiables (.claude/operating-rules.md) when a
# command looks like a DIRECT host/router config write or a DESTRUCTIVE infra op,
# and forces a conscious confirmation ("ask"). This survives context pollution
# because it fires at tool-call time, not from fading recall.
# Fail-open: any parse problem -> allow silently (never break tooling).
set -o pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Broad categories (write/destructive verbs) — deliberately not a per-incident list.
direct_write='write_config|write_config\(|sysrc[[:space:]]|(qm|pct)[[:space:]]+set[[:space:]]|tee[[:space:]]+/(etc|conf|cf|usr/local)|>>?[[:space:]]*/(etc|conf|cf)/|crontab[[:space:]]+-|(cp|mv|sed[[:space:]]+-i|tee|>>?)[[:space:]]*[^|]*config\.xml'
destructive='ifconfig[[:space:]]+[a-z0-9.]+[[:space:]]+(down|up)|pfctl[[:space:]]+-[A-Za-z]*[FdR]|docker[[:space:]]+rm[[:space:]]+-f|docker[[:space:]]+compose[[:space:]]+down|(qm|pct)[[:space:]]+(stop|destroy|reset|rollback|shutdown)|(^|[[:space:]])(reboot|shutdown|halt|poweroff)([[:space:]]|$)|mkfs|lvremove|zfs[[:space:]]+destroy|zpool[[:space:]]+destroy|rm[[:space:]]+-rf[[:space:]]+/'

if printf '%s' "$cmd" | grep -Eq "$direct_write|$destructive"; then
  reason='IaC GATE — this looks like a direct host/config write or a destructive infra op.
Project non-negotiables (.claude/operating-rules.md):
 1. Changes go through IaC, NOT direct host edits: terraform/ OR pfsense/*.yml + pfsense/scripts/ applied via scripts/sync-*.py. Never edit config.xml / write_config / hand-place cron+scripts.
 2. Destructive / host / network changes need explicit user approval with options + rollback FIRST.
 3. State before acting: which IaC mechanism? destructive? rollback? approved?
If this is genuinely via IaC and approved, confirm; otherwise stop and reroute through IaC.'
  jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
fi
exit 0
