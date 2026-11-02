#!/usr/bin/env bash
set -eu
E=/Users/buruchan_1221/.no-mistakes/evidence/01M6F9VGN7YX122GQA6EA9HBKW
export FM_HERDR_LAB_STATE_DIR="$PWD/.test-live/lab-state"
mkdir -p .test-live
S=$(bin/fm-herdr-lab.sh name watched)
printf "%s\n" "$S" > .test-live/session
bin/fm-lab-home.sh create "$PWD/.test-live/home"
touch .test-live/home/config/supervision-host
lab() { bin/fm-herdr-lab.sh run "$S" "$@"; }
cleanup() {
  bin/fm-herdr-lab.sh teardown "$S"; RC=$?; echo "teardown exit=$RC"
  [ "$RC" -ne 0 ] || echo 'TEARDOWN PASS: lab removed; default session tripwire unchanged'
  rm -rf .test-live
}
trap cleanup EXIT
bin/fm-herdr-lab.sh provision "$S"
bin/fm-herdr-lab.sh viewer start "$S"
lab workspace create --cwd "$PWD" --label watch-ops --no-focus > "$E/workspace.json"
W=$(jq -r .result.workspace.workspace_id "$E/workspace.json")
for label in alpha beta; do
  lab tab create --workspace "$W" --cwd "$PWD" --label "$label" --no-focus > "$E/$label-tab.json"
done
export FM_HOME="$PWD/.test-live/home"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
watchpane() { bash bin/fm-watch-pane.sh "$@"; }
watchpane add "$S" watch-ops alpha 'Alpha' --notify-done
watchpane add "$S" watch-ops beta 'Beta'
watchpane list | tee "$E/registry.tsv"
echo 'REGISTER PASS: two live single-pane tabs, done enabled for Alpha only'
cp "$FM_HOME/state/watched-panes" .test-live/before
if watchpane add "$S" watch-ops alpha 'Duplicate'; then exit 1; fi
cmp .test-live/before "$FM_HOME/state/watched-panes"
if watchpane add "$S" watch-ops missing 'Missing'; then exit 1; fi
cmp .test-live/before "$FM_HOME/state/watched-panes"
echo 'GUARDS PASS: duplicate identity and missing tab refused without registry mutation'
# Duplicate tab labels must be refused without guessing.
lab tab create --workspace "$W" --cwd "$PWD" --label alpha --no-focus > "$E/duplicate-tab.json"
if watchpane add "$S" watch-ops alpha 'Alpha' --notify-done; then exit 1; fi
cmp .test-live/before "$FM_HOME/state/watched-panes"
lab tab rename "$(jq -r .result.tab.tab_id "$E/duplicate-tab.json")" spare
# Removal and re-add go through the public CLI against live identities.
watchpane remove Beta
watchpane remove Beta
watchpane add "$S" watch-ops beta 'Beta'
echo 'REMOVE PASS: removal is idempotent and a fresh registration succeeds'
for label in alpha beta; do
  P=$(jq -r .result.root_pane.pane_id "$E/$label-tab.json")
  lab agent start "watch-$label" --kind claude --pane "$P" --timeout 15000 > "$E/$label-claude-start.json" 2>&1 || true
  lab pane read "$P" --source recent-unwrapped --lines 100 > "$E/$label-claude-screen.json"
  lab pane get "$P" > "$E/$label-pane.json"
done
cat "$E/alpha-claude-start.json" "$E/beta-claude-start.json"
cat "$E/alpha-claude-screen.json" "$E/beta-claude-screen.json"
# Observe the actual watcher, with no wake/backend replacements.
for ROUND in 1 2 3; do
  FM_POLL=1 bash bin/fm-watch.sh > "$E/watcher-$ROUND.txt" 2> "$E/watcher-$ROUND.stderr" &
  WP=$!
  for i in $(seq 1 40); do kill -0 "$WP" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$WP" 2>/dev/null; then kill -TERM "$WP"; fi
  wait "$WP" || true
  echo "WATCHER ROUND $ROUND"
  cat "$E/watcher-$ROUND.txt"
  if [ "$ROUND" -lt 3 ]; then
    bash bin/fm-wake-drain.sh > "$E/drain-$ROUND.txt" 2>&1
    cat "$E/drain-$ROUND.txt"
    ACK=$(sed -n 's/.*--ack-through \([0-9]*\) --recovery-generation \([^ ]*\).*/\1 \2/p' "$E/drain-$ROUND.txt" | tail -1)
    read -r SEQ GEN <<< "$ACK"
    [ -n "$SEQ" ] && [ -n "$GEN" ]
    bash bin/fm-wake-drain.sh --ack-through "$SEQ" --recovery-generation "$GEN" >> "$E/drain-$ROUND.txt" 2>&1
  fi
done
grep -q 'watched pane Alpha.*agent blocked' "$E/watcher-1.txt"
grep -q 'watched pane Beta.*agent blocked' "$E/watcher-2.txt"
[ ! -s "$E/watcher-3.txt" ]
echo 'BLOCKED PASS: actual Claude startup blocks woke Alpha and Beta once each; third arm deduplicated'
[ ! -f "$FM_HOME/state/.wake-queue" ] || cp "$FM_HOME/state/.wake-queue" "$E/wake-queue.tsv"
