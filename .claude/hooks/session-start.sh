#!/usr/bin/env bash
# SessionStart hook: re-ground every session on the project operating rules +
# a reminder to consult persistent memory. Injected as additionalContext so the
# non-negotiables are present from token 0, not buried later.
set -o pipefail
command -v jq >/dev/null 2>&1 || exit 0
dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
rules="$dir/.claude/operating-rules.md"
[ -f "$rules" ] || exit 0
ctx="$(cat "$rules")

— Also consult persistent project memory (MEMORY.md / memory notes) before infrastructure work, and keep it tidy."
jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
