#!/usr/bin/env bash
set -u
LAB="$PWD/.gate-live-home"
trap 'rm -rf "$LAB"' EXIT
bin/fm-lab-home.sh create "$LAB"
printf 'claude\n' > "$LAB/config/harness"
printf 'tmux\n' > "$LAB/config/backend"
cat > "$LAB/config/spawn-preflight" <<'HOOK'
#!/usr/bin/env bash
echo "preflight denies task=$1" >&2
exit 3
HOOK
chmod +x "$LAB/config/spawn-preflight"
for kind in ship scout local remote; do
  case "$kind" in
    ship) args=(live-deny-ship "$PWD" --mode local-only --yolo off) ;;
    scout) args=(live-deny-scout "$PWD" --scout) ;;
    local) args=(live-deny-local "$LAB/child" --secondmate) ;;
    remote) args=(live-deny-remote --secondmate) ;;
  esac
  printf '\nDRIVE %s\n' "$kind"
  rc=0
  env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" bin/fm-spawn.sh "${args[@]}" || rc=$?
  printf 'exit=%s task_records=%s\n' "$rc" "$(ls -A "$LAB/state" | wc -l | tr -d ' ')"
  [ "$rc" = 1 ] && [ -z "$(ls -A "$LAB/state")" ] || exit 1
  [ ! -e "$LAB/child" ] || exit 1
done
