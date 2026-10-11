#!/usr/bin/env bash
set -eu
LAB="$PWD/.gate-boundary-home"
trap 'rm -rf "$LAB"' EXIT
bin/fm-lab-home.sh create "$LAB"
printf 'tmux\n' > "$LAB/config/backend"
printf 'manual\n' > "$LAB/config/backlog-backend"
for value in on-absent pool; do
  printf "on\n" > "$LAB/config/teardown-simulator-cleanup"
  case "$value" in
    on-absent) id=live-absent-01m4m667; expected=1 ;;
    pool) id=pool-781931; expected=0 ;;
  esac
  if [ "$value" = on-absent ]; then
    count=$(xcrun simctl list devices -j | jq --arg n "fm-$id" '[.devices[][]? | select(.name == $n)] | length')
    [ "$count" = 0 ]
    printf "matching_devices_before=%s\n" "$count"
  fi
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
  [ "$calls" = "$expected" ]
  mutations=$(grep -cE "^[+]+ xcrun simctl (shutdown|delete) " "$LAB/teardown.trace" || true)
  printf "simulator_mutation_calls=%s\n" "$mutations"
  [ "$mutations" = 0 ]
  [ ! -e "$LAB/state/$id.meta" ]
  printf 'task_record_removed=true\n'
done
