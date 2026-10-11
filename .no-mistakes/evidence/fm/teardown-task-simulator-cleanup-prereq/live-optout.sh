#!/usr/bin/env bash
set -eu
LAB="$PWD/.gate-optout-home"
trap 'rm -rf "$LAB"' EXIT
bin/fm-lab-home.sh create "$LAB"
printf 'tmux\n' > "$LAB/config/backend"
printf 'manual\n' > "$LAB/config/backlog-backend"
for value in absent off yes empty; do
  case "$value" in
    absent) rm -f "$LAB/config/teardown-simulator-cleanup" ;;
    empty) : > "$LAB/config/teardown-simulator-cleanup" ;;
    *) printf '%s\n' "$value" > "$LAB/config/teardown-simulator-cleanup" ;;
  esac
  id="live-optout-$value"
  cat > "$LAB/state/$id.meta" <<META
window=fm-lab-missing:fm-$id
endpoint_task_id=$id
worktree=$LAB/missing-wt
project=$LAB/missing-project
kind=ship
mode=local-only
spawn_gen=live-$id
META
  printf '\nDRIVE switch=%s\n' "$value"
  env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" TMUX="$LAB/no-socket,1,0" bash -x bin/fm-teardown.sh "$id" --force > "$LAB/teardown.stdout" 2> "$LAB/teardown.trace"
  cat "$LAB/teardown.stdout"
  calls=$(grep -cE "^[+]+ xcrun " "$LAB/teardown.trace" || true)
  printf "executed_xcrun_calls=%s\n" "$calls"
  [ "$calls" = 0 ]
  [ ! -e "$LAB/state/$id.meta" ]
  printf 'task_record_removed=true\n'
done
