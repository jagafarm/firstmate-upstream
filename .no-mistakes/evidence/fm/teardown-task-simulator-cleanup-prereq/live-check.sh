#!/usr/bin/env bash
set -e
unset FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
root=$PWD
lab="$root/.test-tmp/live-home"
bin/fm-lab-home.sh create "$lab" >/dev/null
trap 'rm -rf "$lab"' EXIT
export FM_HOME="$lab"
printf 'manual\n' > "$lab/config/backlog-backend"
cat > "$lab/config/spawn-preflight" <<'HOOK'
#!/usr/bin/env bash
printf 'preflight received: %s\n' "$1" >&2
exit 3
HOOK
chmod +x "$lab/config/spawn-preflight"
for kind in ship scout secondmate; do
  args=(--mode local-only --yolo off)
  case "$kind" in scout) args=(--scout);; secondmate) args=(--secondmate);; esac
  rc=0
  out=$(bin/fm-spawn.sh "live-$kind-z1" "$lab/projects/missing" "${args[@]}" 2>&1) || rc=$?
  printf '%s refusal exit=%s\n%s\n' "$kind" "$rc" "$out"
  [ "$rc" = 1 ] && [[ "$out" == *'refused by'* ]] || exit 1
  [ -z "$(ls -A "$lab/state")" ]
done
rc=0
out=$(bin/fm-spawn.sh "live-batch-z1=$lab/projects/missing" "live-batch-z2=$lab/projects/missing" --mode local-only --yolo off 2>&1) || rc=$?
printf 'batch refusal exit=%s\n%s\n' "$rc" "$out"
[[ "$out" == *'spawn of live-batch-z1 refused by'* && "$out" == *'spawn of live-batch-z2 refused by'* ]] || exit 1
[ -z "$(ls -A "$lab/state")" ]
printf 'refused spawns: no state records or project created\n'
rc=0
out=$(bin/fm-spawn.sh live-relaunch-z1 --relaunch 2>&1) || rc=$?
printf 'relaunch of nonexistent task exit=%s\n%s\n' "$rc" "$out"
[[ "$out" != *'preflight received'* && "$out" != *'refused by'* ]] || exit 1
# A successful hook must permit the next validation, without launching a worker.
sed 's/exit 3/exit 0/' "$lab/config/spawn-preflight" > "$lab/config/new-hook"
mv "$lab/config/new-hook" "$lab/config/spawn-preflight"
chmod +x "$lab/config/spawn-preflight"
rc=0
out=$(bin/fm-spawn.sh live-pass-z1 "$lab/projects/missing" --mode local-only --yolo off --branch-prefix 'bad prefix/' 2>&1) || rc=$?
printf 'successful hook reaches branch validation exit=%s\n%s\n' "$rc" "$out"
[[ "$out" == *'preflight received: live-pass-z1'* && "$out" == *'must form a valid git branch'* ]] || exit 1
rm -f "$lab/config/backlog-backend"
printf '# Backlog\n\n## In flight\n\n## Queued\n\n## Done\n' > "$lab/data/backlog.md"
for setting in absent invalid pool enabled-absent; do
  id="live-clean-$setting-z1"
  rm -f "$lab/config/teardown-simulator-cleanup"
  case "$setting" in enabled-absent)
    matches=$(xcrun simctl list devices -j | jq --arg n "fm-$id" '[.devices[][]? | select(.name == $n)] | length')
    printf 'enabled no-device precondition: exact-name matches=%s\n' "$matches"
    [ "$matches" = 0 ] || exit 1
    printf 'on\n' > "$lab/config/teardown-simulator-cleanup";; invalid) printf 'enabled\n' > "$lab/config/teardown-simulator-cleanup";; pool) id=pool-923871; printf 'on\n' > "$lab/config/teardown-simulator-cleanup";; esac
  tasks-axi add "$id" 'live cleanup check' --kind ship --file "$lab/data/backlog.md" >/dev/null
  tasks-axi start "$id" --file "$lab/data/backlog.md" >/dev/null
  printf 'worktree=%s\nproject=%s\nkind=ship\nmode=no-mistakes\nharness=codex\n' "$lab/missing-wt" "$lab/projects/missing" > "$lab/state/$id.meta"
  rc=0
  out=$(bin/fm-teardown.sh "$id" --legacy-record 2>&1) || rc=$?
  printf 'teardown %s exit=%s\n%s\n' "$setting" "$rc" "$out"
  [ "$rc" = 0 ] && [ ! -e "$lab/state/$id.meta" ] || exit 1
  printf 'task record removed for %s\n' "$setting"
done
