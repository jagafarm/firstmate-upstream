#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
export FM_HOME="$ROOT/.test-live/home" PATH="$ROOT/.test-live/bin:$PATH"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
STATE="$FM_HOME/state"
cli() { bash "$ROOT/bin/fm-watch-pane.sh" "$@"; }
. bin/fm-backend.sh
fm_backend_source herdr
TARGET=$(fm_backend_herdr_resolve_watched_pane fm-lab-watch-gate-01m6 watch-live notify)
MARKER=$(fm_backend_herdr_escalation_marker "$STATE" "$TARGET")
printf 'Resolved real Herdr pane: %s\n' "$TARGET"
printf blocked > "$MARKER"
cli remove Notify
[ ! -e "$MARKER" ]
printf 'remove: watch-owned marker retired; registry:\n'; cli list
cli add fm-lab-watch-gate-01m6 watch-live notify Notify --notify-done
printf blocked > "$MARKER"
cli add fm-lab-watch-gate-01m6 watch-live notify Notify
[ ! -e "$MARKER" ]
printf 'replace: watch-owned marker retired; registry:\n'; cli list
printf 'window=%s\nbackend=herdr\nkind=ship\n' "$TARGET" > "$STATE/task-fixture.meta"
printf blocked > "$MARKER"
cli remove Notify
[ "$(cat "$MARKER")" = blocked ]
printf 'remove task-owned registration: task marker retained as %s\n' "$(cat "$MARKER")"
rm "$STATE/task-fixture.meta" "$MARKER"
cli add fm-lab-watch-gate-01m6 watch-live notify Notify
export FM_HERDR_LAB_STATE_DIR="$ROOT/.test-live/lab-state"
env PATH="${PATH#*:}" bin/fm-herdr-lab.sh run fm-lab-watch-gate-01m6 tab rename w1:t1 renamed >/dev/null
cli remove Notify
cli remove Notify
printf 'unresolvable pane: repeated removal succeeded; registry:\n'; cli list
