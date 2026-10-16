#!/bin/bash
set -eu
EVIDENCE=/Users/buruchan_1221/.no-mistakes/evidence/01M5254WCSR8NEW1Z9G665FD96
LAB=$(mktemp -d "${TMPDIR%/}/fm-lab.XXXXXX")
LAB=$(cd "$LAB" && pwd -P)
bin/fm-lab-home.sh create "$LAB"
mkdir -p "$LAB/tmux"
touch "$LAB/config/supervision-host"
SERVER_PID=
cleanup() {
 [ -z "$SERVER_PID" ] || kill -CONT "$SERVER_PID" 2>/dev/null || true
 TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null || true
 rm -rf "$LAB"
 echo 'Disposable lab removed; private tmux server stopped.'
}
trap cleanup EXIT
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE TASKS_AXI_FILE TASKS_AXI_BACKEND
export FM_HOME="$LAB" TMUX_TMPDIR="$LAB/tmux"
env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab new-session -d -s primary -x 120 -y 40 -c "$PWD" -e FM_HOME="$LAB" claude
export TMUX="$(tmux -L fm-lab display-message -p '#{socket_path}'),0,0"
tmux -L fm-lab rename-window -t primary fm-live
tmux -L fm-lab new-window -d -t primary -n fm-dead -c "$PWD" /bin/zsh
sleep 5
tmux -L fm-lab capture-pane -p -t primary:fm-live > "$EVIDENCE/claude-primary.txt"
printf 'kind=ship\nwindow=primary:fm-live\n' > "$LAB/state/live.meta"
printf 'kind=ship\nwindow=primary:fm-dead\n' > "$LAB/state/dead.meta"
printf 'kind=ship\nwindow=primary:fm-missing\n' > "$LAB/state/missing.meta"
printf 'kind=secondmate\nwindow=primary:fm-live\n' > "$LAB/state/mate.meta"
for i in 1 2 3 4 5; do
 cp "$LAB/state/dead.meta" "$LAB/state/old-$i.meta"
done
. bin/fm-backend.sh
for endpoint in fm-live fm-dead fm-missing; do
 printf 'Actual endpoint %s classifier: ' "$endpoint"
 fm_backend_agent_state tmux "primary:$endpoint"
 echo
done
check_count() {
 local expected=$1 label=$2 actual
 actual=$(bin/fm-afk-contract.sh live-workers)
 printf '%s: live-workers=%s (expected %s)\n' "$label" "$actual" "$expected"
 [ "$actual" = "$expected" ] || exit 1
}
check_count 1 'Running Claude counts; stopped/missing records and secondmate excluded'
if [ -n "${FM_PHASE_BASE_CONTRACT:-}" ]; then
 base_count=$(bash "$FM_PHASE_BASE_CONTRACT" live-workers)
 printf 'Unmodified base live-workers=%s for same endpoints; fixed live-workers=1.\n' "$base_count"
 [ "$base_count" = 8 ] || exit 1
fi
bin/fm-afk-contract.sh enter
printf 'Default entry cap: '
bin/fm-afk-contract.sh field spend_max_concurrent_workers
[ "$(bin/fm-afk-contract.sh field spend_max_concurrent_workers)" = 4 ] || exit 1
bin/fm-afk-contract.sh enter --words "Spend cap live proof" --spend 1
out=$(bin/fm-spawn.sh task-cap-proof --mode no-mistakes --yolo off 2>&1 || true)
printf '%s\n' "$out"
[[ "$out" == *'caps concurrent workers at 1 and 1 live worker(s)'* ]] || exit 1
printf 'endpoint_task_id=live\nworktree=%s\nproject=%s\nharness=claude\nmode=no-mistakes\nyolo=off\ntasktmp=%s\nmodel=default\neffort=default\n' "$PWD" "$PWD" "$LAB/tasktmp" >> "$LAB/state/live.meta"
out=$(bin/fm-spawn.sh live --relaunch 2>&1 || true)
printf 'Relaunch at full cap: %s\n' "$out"
[[ "$out" != *'caps concurrent workers'* ]] || exit 1
[[ "$out" == *'positively agent-free endpoint'* ]] || exit 1
tmux -L fm-lab kill-window -t primary:fm-live
check_count 0 'After real Claude process exits, retained record releases the cap'
out=$(FM_SUPERVISION_ACTOR=branch bin/fm-spawn.sh task-cap-proof --mode no-mistakes --yolo off 2>&1 || true)
printf 'Under-cap spawn proceeds to next product guard: %s\n' "$out"
[[ "$out" != *'caps concurrent workers'* ]] || exit 1
[[ "$out" == *'queued unblocked work'* ]] || exit 1
now=$(date +%s)
printf 'kind=ship\nwindow=primary:fm-dead\nspawn_gen=s%s.1.1\n' "$now" > "$LAB/state/dead.meta"
check_count 1 'Fresh record counts despite positively dead shell'
out=$(bin/fm-spawn.sh task-cap-proof --mode no-mistakes --yolo off 2>&1 || true)
printf '%s\n' "$out"
[[ "$out" == *'caps concurrent workers at 1 and 1 live worker(s)'* ]] || exit 1
printf 'kind=ship\nwindow=primary:fm-dead\nspawn_gen=s%s.1.1\n' "$((now-121))" > "$LAB/state/dead.meta"
check_count 0 'Dead record releases cap after default 120-second launch grace'
printf 'kind=ship\nbackend=zellij\nwindow=unverified-target\n' > "$LAB/state/unknown.meta"
check_count 1 'Unverified backend remains counted conservatively'
rm "$LAB/state/unknown.meta"
printf 'kind=ship\nwindow=malformed\n' > "$LAB/state/unread.meta"
check_count 1 'Unreadable endpoint remains counted conservatively'
rm "$LAB/state/unread.meta"
# Suspend only this disposable lab server to exercise a real stalled CLI.
rm "$LAB/state/live.meta" "$LAB/state/missing.meta" "$LAB/state/old-"*.meta
SERVER_PID=$(tmux -L fm-lab display-message -p '#{pid}')
kill -STOP "$SERVER_PID"
start=$(date +%s)
FM_AFK_CONTRACT_PROBE_SECONDS=1 check_count 1 'Real stopped tmux service times out and still counts'
elapsed=$(( $(date +%s) - start ))
printf 'Stalled real-service probe returned in %ss with 1s bound.\n' "$elapsed"
[ "$elapsed" -lt 5 ] || exit 1
printf 'kind=ship\nwindow=primary:fm-dead\nspawn_gen=s%s.1.1\n' "$(date +%s)" > "$LAB/state/dead.meta"
start=$(date +%s)
check_count 1 'Fresh launch bypasses even a stalled real-service probe'
elapsed=$(( $(date +%s) - start ))
printf 'Launch-grace check returned in %ss with real service stalled.\n' "$elapsed"
[ "$elapsed" -lt 5 ] || exit 1
kill -CONT "$SERVER_PID"
SERVER_PID=
printf 'done: disposable test record\n' > "$LAB/state/dead.status"
printf 'done: disposable secondmate record\n' > "$LAB/state/mate.status"
# Render the actual return CLI with retained dead records.
bin/fm-afk-return.sh > "$EVIDENCE/live-return.txt" 2>&1 || true
cat "$EVIDENCE/live-return.txt"
grep -F '2 task record(s) at return.' "$EVIDENCE/live-return.txt" >/dev/null || exit 1
echo 'All live assertions passed.'
