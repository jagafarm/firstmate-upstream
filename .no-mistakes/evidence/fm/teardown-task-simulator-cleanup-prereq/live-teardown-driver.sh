#!/usr/bin/env bash
set -eu
LAB=$(mktemp -d "$PWD/.test-phase-tmp/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB"
mkdir -p "$LAB/tmux"
cleanup() { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null || true; rm -rf "$LAB"; }
trap cleanup EXIT

socket="$LAB/tmux/tmux-$(id -u)/fm-lab"
printf 'manual\n' > "$LAB/config/backlog-backend"
for setting in absent unknown pool; do
  id="live-$setting"
  case "$setting" in
    absent) rm -f "$LAB/config/teardown-simulator-cleanup";;
    unknown) printf 'enabled\n' > "$LAB/config/teardown-simulator-cleanup";;
    pool) id=pool-982739; printf 'on\n' > "$LAB/config/teardown-simulator-cleanup";;
  esac

  cat > "$LAB/state/$id.meta" <<META
window=isolated:fm-$id
endpoint_task_id=$id
backend=tmux
worktree=$LAB/already-removed-$id
project=$LAB/projects/already-removed
kind=ship
mode=local-only
spawn_gen=live-$id
META
  printf '\nSCENARIO cleanup switch=%s task=%s\n' "$setting" "$id"
  env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" TMUX="$socket,0,0" bin/fm-teardown.sh "$id" --force
  [ ! -e "$LAB/state/$id.meta" ]
  if TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab has-session -t "isolated:fm-$id" 2>/dev/null; then exit 1; fi
  printf 'task record removed; already-absent endpoint handled\n'
done
