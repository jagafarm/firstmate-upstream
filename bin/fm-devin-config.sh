#!/usr/bin/env bash
# Write a private Devin worker config, preserving user settings and hooks.
# Usage: fm-devin-config.sh <state-dir> <task-id> <busy-gen> [<user-config>]
# The default source is ~/.config/devin/config.json (Devin's --config default).
# An absent source starts from {}; unreadable or malformed sources refuse.
# Output: <state-dir>/<task-id>.devin-config.json, mode 600, atomically replaced.
# No project or user config is edited. fm-control-lib.sh owns retirement.
# read_config_from.claude=false is forced for every worker,
# because Devin otherwise runs every Claude Code hook it finds (~/.claude and
# the project's .claude/settings*.json), including Herdr's hook that reports
# the pane as a Claude agent; it also drops Devin's CLAUDE.md, .claude/skills,
# and Claude MCP imports, while AGENTS.md and .agents/skills still load.
# attribution=false is forced too, because Devin otherwise adds a
# Co-Authored-By: Devin trailer and a Generated with Devin line to commits
# and PRs, unless FM_KEEP_AI_TRAILERS=1 (fm-spawn sets it when the home has
# config/keep-ai-trailers); then the source's attribution setting is kept.
# UserPromptSubmit opens a turn; Stop and SessionEnd close it. Devin 3000.11.1
# emits no Stop on double-Escape cancellation, so fm-control invalidates its
# state to unknown after delivering that interrupt, never fabricating idle.
# Turn-end touches follow a successful generation-bound apply; events
# rejected as stale emit no notification.
# Permission overlay (opt-in): the home config dir - $FM_CONFIG_OVERRIDE, or
# $FM_HOME/config when the override is unset - may carry
# devin-permissions.worker.json. docs/configuration.md "Devin permission
# mode and permission overlay" owns its operator contract.
# Validation and merge finish in a temporary file before atomic installation,
# so refusal preserves the previously installed config.
set -eu
case "${1:-}" in
  -h|--help)
    sed -n '2,/^set -eu/{ /^#/s/^# \{0,1\}//p; }' "$0"
    exit 0
    ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE=${1:?state directory required}
ID=${2:?task id required}
GEN=${3:?busy generation required}
SOURCE=${4:-$HOME/.config/devin/config.json}
KEEP=${FM_KEEP_AI_TRAILERS:-0}
case "$ID" in ''|*[!A-Za-z0-9._-]*) echo 'error: invalid task id' >&2; exit 1 ;; esac
[ -d "$STATE" ] || { echo 'error: state directory missing' >&2; exit 1; }
STATE=$(cd "$STATE" && pwd -P)
quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
prefix="$(quote "$SCRIPT_DIR/fm-busy-event.sh") apply $(quote "$STATE") $(quote "$ID")"
suffix="--gen $(quote "$GEN") --source devin-hook"
submit="$prefix busy $suffix --event user-prompt-submit >/dev/null 2>&1 || true"
stop="$prefix idle $suffix --event stop >/dev/null 2>&1 && touch $(quote "$STATE/$ID.turn-ended"); true"
end="$prefix idle $suffix --event session-end >/dev/null 2>&1 || true"
if [ ! -e "$SOURCE" ] && [ ! -L "$SOURCE" ]; then SOURCE=/dev/null; fi
umask 077
temp=$(mktemp "$STATE/.$ID.devin-config.XXXXXX")
trap 'rm -f "$temp" "$temp.next"' EXIT
jq -s --arg keep "$KEEP" --arg submit "$submit" --arg stop "$stop" --arg end "$end" '
  (if length == 0 then {} elif length == 1 then .[0] else error("expected one config object") end) |
  if type != "object" then error("expected config object") else . end |
  (if $keep == "1" then . else .attribution = false end) |
  .read_config_from = ((.read_config_from // {}) + {claude: false}) |
  .hooks = (.hooks // {}) |
  def hook($cmd): {hooks: [{type: "command", command: $cmd, timeout: 10}]};
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [hook($submit)]) |
  .hooks.Stop = ((.hooks.Stop // []) + [hook($stop)]) |
  .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [hook($end)])
' "$SOURCE" > "$temp"
overlay=
if [ -n "${FM_CONFIG_OVERRIDE:-}" ]; then
  overlay=$FM_CONFIG_OVERRIDE/devin-permissions.worker.json
elif [ -n "${FM_HOME:-}" ]; then
  overlay=$FM_HOME/config/devin-permissions.worker.json
fi
if [ -n "$overlay" ] && { [ -e "$overlay" ] || [ -L "$overlay" ]; }; then
  [ -f "$overlay" ] && [ ! -L "$overlay" ] && [ -r "$overlay" ] \
    || { echo "error: Devin permission overlay must be a readable regular non-symlink file: $overlay" >&2; exit 1; }
  jq --slurpfile overlay "$overlay" '
    ($overlay
      | if length == 1 then .[0] else error("expected one permission overlay object") end
      | if type == "object" and ((keys - ["allow","ask","deny"]) | length == 0)
          and all(.[]; type == "array" and all(.[]; type == "string"))
        then . else error("permission overlay must hold only allow/ask/deny string arrays") end) as $rules
    | .permissions = (.permissions // {})
    | if (.permissions | type) != "object" then error("permissions must be an object") else . end
    | reduce ("allow", "ask", "deny") as $k (.;
        .permissions[$k] = ((.permissions[$k] // []) + (($rules[$k] // []) - (.permissions[$k] // []))))
    | .permissions.allow -= (($rules.ask // []) + ($rules.deny // []))
  ' "$temp" > "$temp.next"
  mv -f "$temp.next" "$temp"
fi
mv "$temp" "$STATE/$ID.devin-config.json"
