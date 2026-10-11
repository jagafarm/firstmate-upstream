#!/usr/bin/env bash
set -u
LAB=$(mktemp -d "$PWD/.test-phase-tmp/fm-lab.XXXXXX")
cleanup() { rm -rf "$LAB"; }
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB"
cat > "$LAB/config/spawn-preflight" <<'HOOK'
#!/usr/bin/env bash
printf 'preflight received task=%s; deliberate refusal\n' "$1"
exit 3
HOOK
chmod +x "$LAB/config/spawn-preflight"
for kind in ship scout local-secondmate remote-secondmate batch; do
  case "$kind" in
    ship) args=(live-refuse "$PWD" --mode no-mistakes --yolo off);;
    scout) args=(live-scout "$PWD" --scout);;
    local-secondmate) args=(live-local "$LAB/child" --secondmate);;
    remote-secondmate) args=(live-remote --secondmate);;
    batch) args=("live-batch-a=$PWD" "live-batch-b=$PWD" --mode no-mistakes --yolo off);;
  esac
  printf '\nSCENARIO %s\n' "$kind"
  env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" bin/fm-spawn.sh "${args[@]}"
  rc=$?
  printf 'exit=%s\n' "$rc"
  [ "$rc" -ne 0 ] || exit 1
  [ -z "$(ls -A "$LAB/state")" ] || { ls -A "$LAB/state"; exit 1; }
  [ ! -e "$LAB/child" ] || exit 1
  printf 'state empty; child home absent; no endpoint/worktree creation reached\n'
done
