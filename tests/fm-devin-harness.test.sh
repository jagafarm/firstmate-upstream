#!/usr/bin/env bash
# Portable Devin worker adapter regression. Vendor facts are refreshed by
# fm-devin-signals-live-e2e.test.sh; this suite needs no Devin credentials.
set -u
# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"
# shellcheck source=bin/fm-control-lib.sh
. "$ROOT/bin/fm-control-lib.sh"
# shellcheck source=bin/fm-busy-lib.sh
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=bin/fm-composer-lib.sh
. "$ROOT/bin/fm-composer-lib.sh"
# shellcheck source=bin/fm-agent-process-lib.sh
. "$ROOT/bin/fm-agent-process-lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-devin-harness)
HARNESS="$ROOT/bin/fm-harness.sh"
unset CLAUDECODE PI_CODING_AGENT GROK_AGENT CURSOR_AGENT CURSOR_INVOKED_AS GEMINI_CLI FM_OMP_HARNESS ATLASSIAN_AGENT_TYPE ROVODEV_CLI FM_CONFIG_OVERRIDE FM_HOME

mkdir -p "$TMP_ROOT/names"
for name in devin devin-helper; do ln -s /bin/bash "$TMP_ROOT/names/$name"; done
# shellcheck disable=SC2016
out=$(CLAUDECODE=1 "$TMP_ROOT/names/devin" -c '"$1"; :' _ "$HARNESS")
[ "$out" = devin ] || fail "native Devin ancestry must beat foreign CLAUDECODE: $out"
# shellcheck disable=SC2016
out=$("$TMP_ROOT/names/devin-helper" -c '"$1" ancestry "$$"; :' _ "$HARNESS")
[ "$out" != 'comm devin' ] || fail "unrelated devin-helper claimed the adapter"
[ "$(fm_agent_process_classify_name /opt/bin/devin)" = agent ] || fail "liveness lost Devin"
[ "$(fm_agent_process_classify_name devin-helper)" = other ] || fail "liveness claims unrelated executable"
pass "Devin native identity; anchored liveness"

[ "$(fm_control_interrupt_key devin)" = Escape ] || fail 'wrong interrupt key'
[ "$(fm_control_interrupt_repeat devin)" = 2 ] || fail 'Devin needs double Escape'
[ -z "$(fm_control_interrupt_clear_key devin)" ] || fail 'Devin must not erase a composer draft'
[ "$(fm_control_exit_command devin)" = /quit ] || fail 'wrong exit command'
fm_control_harness_supports_kind devin ship || fail 'ship refused'
fm_control_harness_supports_kind devin scout || fail 'scout refused'
! fm_control_harness_supports_kind devin secondmate || fail 'secondmate accepted'
pass "worker-only resolution and lifecycle capabilities"

[ "$(fm_composer_classify_content 1 '❭ Ask Devin to build features, fix bugs, or work on your code' "$FM_COMPOSER_IDLE_RE_DEFAULT" sensitive '' 1 0)" = empty ] || fail 'idle placeholder not empty'
[ "$(fm_composer_classify_content 1 '❭ unsubmitted draft')" = pending ] || fail 'typed draft not preserved'
[ "$(fm_composer_classify_content 0 '❭')" = empty ] || fail 'Devin glyph not recognized'
for signal in 'Thinking · 5s (esc twice to interrupt)' '❭ Guide Devin while it works'; do
  printf '%s\n' "$signal" | fm_busy_lines_match devin || fail "independent delivery signal lost: $signal"
done
! printf '❭ unsubmitted draft\n' | fm_busy_lines_match devin || fail 'draft read busy'
! printf 'esc to cancel\n' | fm_busy_lines_match devin || fail 'borrowed another harness signal'
pass "composer draft safety and independent delivery signals"

state="$TMP_ROOT/hook state"
mkdir -p "$state"
gen=$("$ROOT/bin/fm-busy-event.sh" arm "$state" worker)
printf '%s\n' '{"agent":{"model":"swe-2-high"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"true"}]}]}}' > "$TMP_ROOT/user.json"
"$ROOT/bin/fm-devin-config.sh" "$state" worker "$gen" "$TMP_ROOT/user.json" || fail 'config writer failed'
config="$state/worker.devin-config.json"
jq -e '.agent.model == "swe-2-high" and (.hooks.Stop | length) == 2' "$config" >/dev/null || fail 'user settings/hooks lost'
run_hook() { bash -c "$(jq -r --arg event "$1" '.hooks[$event][-1].hooks[0].command' "$config")"; }
run_hook UserPromptSubmit
[ "$(fm_busy_classify tmux fake:w devin worker "$state")" = 'busy devin-hook' ] || fail 'submit did not open busy'
run_hook Stop
[ "$(fm_busy_classify tmux fake:w devin worker "$state")" = 'idle devin-hook' ] || fail 'Stop did not settle'
assert_present "$state/worker.turn-ended" 'Stop notification absent'
run_hook UserPromptSubmit
run_hook SessionEnd
[ "$(fm_busy_classify tmux fake:w devin worker "$state")" = 'idle devin-hook' ] || fail 'SessionEnd did not settle'
"$ROOT/bin/fm-busy-event.sh" arm "$state" worker >/dev/null
rm "$state/worker.turn-ended"
run_hook Stop
[ "$(fm_busy_classify tmux fake:w devin worker "$state")" = 'busy fm-spawn' ] || fail 'stale Stop cleared replacement'
assert_absent "$state/worker.turn-ended" 'stale Stop woke replacement'
[ "$(fm_control_harness_wiring_paths devin /unused "$state" worker)" = "$config" ] || fail 'config retirement missing'
printf 'broken' > "$TMP_ROOT/invalid.json"
! "$ROOT/bin/fm-devin-config.sh" "$state" worker "$gen" "$TMP_ROOT/invalid.json" 2>/dev/null || fail 'invalid source accepted'
jq -e . "$config" >/dev/null || fail 'failed write replaced valid config'
pass "private config preserves user hooks; lifecycle and stale-generation rejection"

# A user config that opts into both must still produce a worker config with no
# commit attribution and no imported Claude Code hooks; other import choices
# the user made survive.
printf '%s\n' '{"attribution":true,"read_config_from":{"claude":true,"cursor":false}}' > "$TMP_ROOT/opted-in.json"
"$ROOT/bin/fm-devin-config.sh" "$state" worker "$gen" "$TMP_ROOT/opted-in.json" || fail 'config writer failed'
jq -e '.attribution == false' "$config" >/dev/null \
  || fail 'worker config keeps Devin commit attribution (Co-Authored-By: Devin trailer)'
jq -e '.read_config_from.claude == false and .read_config_from.cursor == false' "$config" >/dev/null \
  || fail 'worker config imports Claude Code hooks or dropped a user import choice'
"$ROOT/bin/fm-devin-config.sh" "$state" worker "$gen" /nonexistent/config.json || fail 'absent source refused'
jq -e '.attribution == false and .read_config_from.claude == false' "$config" >/dev/null \
  || fail 'an absent user config must still disable attribution and Claude hook import'
pass "worker config forces attribution off and Claude Code hook import off"

# With config/keep-ai-trailers, fm-spawn passes FM_KEEP_AI_TRAILERS=1: the
# worker config leaves Devin's attribution as the source had it (absent means
# Devin's default, on) while Claude hook import stays off.
FM_KEEP_AI_TRAILERS=1 "$ROOT/bin/fm-devin-config.sh" "$state" worker "$gen" "$TMP_ROOT/opted-in.json" || fail 'config writer failed'
jq -e '.attribution == true and .read_config_from.claude == false' "$config" >/dev/null \
  || fail 'keep-ai-trailers must leave the source attribution on and still disable Claude hook import'
FM_KEEP_AI_TRAILERS=1 "$ROOT/bin/fm-devin-config.sh" "$state" worker "$gen" /nonexistent/config.json || fail 'absent source refused'
jq -e 'has("attribution") | not' "$config" >/dev/null \
  || fail 'keep-ai-trailers must not write attribution=false for an absent user config'
FM_KEEP_AI_TRAILERS=0 "$ROOT/bin/fm-devin-config.sh" "$state" worker "$gen" "$TMP_ROOT/opted-in.json" || fail 'config writer failed'
jq -e '.attribution == false' "$config" >/dev/null \
  || fail 'FM_KEEP_AI_TRAILERS=0 must still force attribution off'
pass "keep-ai-trailers leaves Devin attribution on"

case_dir="$TMP_ROOT/spawn"
fakebin=$(make_spawn_fakebin "$case_dir/fake" claude)
fm_fake_exit0 "$fakebin" devin
home="$case_dir/home"
proj="$case_dir/project"
wt="$case_dir/wt"
fm_test_spawn_home "$home" devin
fm_git_worktree "$proj" "$wt" devin-test
fm_test_spawn_brief "$home" devin-worker
if ! out=$(FM_FAKE_LAUNCH_LOG="$case_dir/launch" fm_test_run_spawn "$home" "$wt" "$fakebin" devin-worker "$proj" --scout --harness devin --model fusion-claude-fable-5-1-high-sidekick-swe-2-medium --effort xhigh 2>&1)
then fail "spawn failed: $out"; fi
launch=$(cat "$case_dir/launch")
assert_contains "$launch" '--permission-mode dangerous --respect-workspace-trust false' 'autonomy/trust flags missing'
assert_contains "$launch" "--config '$home/state/devin-worker.devin-config.json'" 'private config missing'
assert_contains "$launch" "--model 'fusion-claude-fable-5-1-high-sidekick-swe-2-medium'" 'Fusion model lost'
assert_contains "$launch" 'encode launch-brief' 'typed launch envelope lost'
case "$launch" in *--effort*|*--thinking*) fail 'independent effort reached Devin argv' ;; esac
assert_grep 'effort=xhigh' "$home/state/devin-worker.meta" 'effort not recorded'
assert_present "$home/state/devin-worker.devin-config.json" 'spawn did not wire hooks'
[ "$(fm_busy_classify tmux fake:w devin devin-worker "$home/state")" = 'busy fm-spawn' ] || fail 'launch not armed'
if out=$(fm_test_run_spawn "$home" "$wt" "$fakebin" devin-sm "$proj" --secondmate --harness devin 2>&1)
then fail 'Devin secondmate launch accepted'; fi
assert_contains "$out" 'crewmate/scout adapter only' 'wrong secondmate refusal'
pass "scout launch carries Fusion, autonomy, typed brief and hooks; effort recorded only"

# The opt-in config/devin-permissions.worker.json overlay merges into the
# generated config's .permissions: entries append uniquely and overlay
# ask/deny entries win over base allow. The writer resolves the overlay
# through FM_CONFIG_OVERRIDE (what fm-spawn passes) and falls back to
# $FM_HOME/config for direct use; an absent file leaves the generated config
# untouched and a malformed or symlinked file refuses before install.
perm_state="$TMP_ROOT/perm-state"
mkdir -p "$perm_state"
printf '%s\n' '{"permissions":{"allow":["Exec(git)","Exec(codex)"],"ask":["Exec(git push)"]}}' > "$TMP_ROOT/perm-user.json"
pgen=$("$ROOT/bin/fm-busy-event.sh" arm "$perm_state" worker)
ov_home="$TMP_ROOT/ov-home"
mkdir -p "$ov_home/config"
printf '%s\n' '{"allow":["Exec(bin/fm-)","Exec(git)"],"ask":["Exec(codex)","Exec(git merge)"],"deny":["Exec(sudo)"]}' > "$ov_home/config/devin-permissions.worker.json"
FM_CONFIG_OVERRIDE="$ov_home/config" "$ROOT/bin/fm-devin-config.sh" "$perm_state" worker "$pgen" "$TMP_ROOT/perm-user.json" \
  || fail 'config writer refused a valid overlay'
jq -e '.permissions == {"allow":["Exec(git)","Exec(bin/fm-)"],"ask":["Exec(git push)","Exec(codex)","Exec(git merge)"],"deny":["Exec(sudo)"]}' "$perm_state/worker.devin-config.json" >/dev/null \
  || fail "overlay merge mismatch: $(jq -c .permissions "$perm_state/worker.devin-config.json")"
rm "$perm_state/worker.devin-config.json"
FM_HOME="$ov_home" "$ROOT/bin/fm-devin-config.sh" "$perm_state" worker "$pgen" "$TMP_ROOT/perm-user.json" \
  || fail 'config writer refused a valid overlay via FM_HOME'
jq -e '.permissions.deny == ["Exec(sudo)"]' "$perm_state/worker.devin-config.json" >/dev/null \
  || fail 'FM_HOME overlay path not honored'
FM_HOME="$TMP_ROOT/nohome" "$ROOT/bin/fm-devin-config.sh" "$perm_state" worker "$pgen" "$TMP_ROOT/perm-user.json" \
  || fail 'config writer failed without overlay'
jq -e '.permissions == {"allow":["Exec(git)","Exec(codex)"],"ask":["Exec(git push)"]}' "$perm_state/worker.devin-config.json" >/dev/null \
  || fail 'absent overlay changed generated permissions'
bad_state="$TMP_ROOT/bad-state"
mkdir -p "$bad_state"
bgen=$("$ROOT/bin/fm-busy-event.sh" arm "$bad_state" worker)
printf '%s\n' '{"allow":["x"],"extra":[]}' > "$ov_home/config/devin-permissions.worker.json"
! FM_CONFIG_OVERRIDE="$ov_home/config" "$ROOT/bin/fm-devin-config.sh" "$bad_state" worker "$bgen" "$TMP_ROOT/perm-user.json" 2>/dev/null \
  || fail 'overlay with a foreign key was accepted'
assert_absent "$bad_state/worker.devin-config.json" 'malformed overlay still installed a config'
printf '%s\n' '{"allow":"x"}' > "$ov_home/config/devin-permissions.worker.json"
! FM_CONFIG_OVERRIDE="$ov_home/config" "$ROOT/bin/fm-devin-config.sh" "$bad_state" worker "$bgen" "$TMP_ROOT/perm-user.json" 2>/dev/null \
  || fail 'overlay with a non-array value was accepted'
assert_absent "$bad_state/worker.devin-config.json" 'malformed overlay still installed a config'
printf '%s\n' '{"deny":["Exec(sudo)"]}' > "$TMP_ROOT/real-overlay.json"
rm "$ov_home/config/devin-permissions.worker.json"
ln -s "$TMP_ROOT/real-overlay.json" "$ov_home/config/devin-permissions.worker.json"
! FM_CONFIG_OVERRIDE="$ov_home/config" "$ROOT/bin/fm-devin-config.sh" "$bad_state" worker "$bgen" "$TMP_ROOT/perm-user.json" 2>/dev/null \
  || fail 'symlinked overlay was accepted'
assert_absent "$bad_state/worker.devin-config.json" 'symlinked overlay still installed a config'
rm "$TMP_ROOT/real-overlay.json"
for overlay_source in FM_CONFIG_OVERRIDE FM_HOME; do
  if [ "$overlay_source" = FM_CONFIG_OVERRIDE ]; then overlay_dir="$ov_home/config"; else overlay_dir="$ov_home"; fi
  ! env "$overlay_source=$overlay_dir" "$ROOT/bin/fm-devin-config.sh" "$bad_state" worker "$bgen" "$TMP_ROOT/perm-user.json" 2>/dev/null \
    || fail "dangling overlay symlink was accepted via $overlay_source"
  assert_absent "$bad_state/worker.devin-config.json" 'dangling overlay symlink still installed a config'
done
rm "$ov_home/config/devin-permissions.worker.json"
for rules in '' '{} {}' '{} {"allow":["Exec(git)"]}' '{} {"ask":["Exec(git push)"]}' '{} {"deny":["Exec(rm -rf)"]}' 'null' '[]' '{"deny":[1]}'; do
  printf '%s\n' "$rules" > "$ov_home/config/devin-permissions.worker.json"
  for overlay_source in FM_CONFIG_OVERRIDE FM_HOME; do
    if [ "$overlay_source" = FM_CONFIG_OVERRIDE ]; then overlay_dir="$ov_home/config"; else overlay_dir="$ov_home"; fi
    ! env "$overlay_source=$overlay_dir" "$ROOT/bin/fm-devin-config.sh" "$bad_state" worker "$bgen" "$TMP_ROOT/perm-user.json" 2>/dev/null \
      || fail "invalid overlay was accepted via $overlay_source: $rules"
    assert_absent "$bad_state/worker.devin-config.json" 'invalid overlay still installed a config'
    before=$(cat "$perm_state/worker.devin-config.json")
    ! env "$overlay_source=$overlay_dir" "$ROOT/bin/fm-devin-config.sh" "$perm_state" worker "$pgen" "$TMP_ROOT/perm-user.json" 2>/dev/null \
      || fail 'invalid overlay replaced an existing config'
    [ "$(cat "$perm_state/worker.devin-config.json")" = "$before" ] || fail 'refused overlay changed the installed config'
  done
done
printf '%s\n' '{}' > "$ov_home/config/devin-permissions.worker.json"
FM_HOME="$ov_home" "$ROOT/bin/fm-devin-config.sh" "$perm_state" worker "$pgen" "$TMP_ROOT/perm-user.json" \
  || fail 'empty overlay object was refused'
jq -e '.permissions == {"allow":["Exec(git)","Exec(codex)"],"ask":["Exec(git push)"],"deny":[]}' "$perm_state/worker.devin-config.json" >/dev/null \
  || fail 'empty overlay object changed permission rules'
pass "permission overlay merges uniquely, stricter wins, refuses malformed input"

# config/devin-permission-mode selects the Devin launch permission flag:
# absent or `dangerous` keeps the verified dangerous posture, `smart` swaps
# only that flag so the config's allow/ask/deny rules are enforced, and any
# other token refuses before any endpoint, worktree, or task record exists.
printf 'smart\n' > "$home/config/devin-permission-mode"
fm_test_spawn_brief "$home" devin-smart
if ! out=$(FM_FAKE_LAUNCH_LOG="$case_dir/launch-smart" fm_test_run_spawn "$home" "$wt" "$fakebin" devin-smart "$proj" --scout --harness devin 2>&1)
then fail "smart-mode spawn failed: $out"; fi
launch=$(cat "$case_dir/launch-smart")
assert_contains "$launch" '--permission-mode smart --respect-workspace-trust false' 'smart launch missing the smart flag'
assert_not_contains "$launch" '--permission-mode dangerous' 'smart launch still carries dangerous'
printf 'dangerous\n' > "$home/config/devin-permission-mode"
fm_test_spawn_brief "$home" devin-expl
if ! out=$(FM_FAKE_LAUNCH_LOG="$case_dir/launch-expl" fm_test_run_spawn "$home" "$wt" "$fakebin" devin-expl "$proj" --scout --harness devin 2>&1)
then fail "explicit dangerous spawn failed: $out"; fi
assert_contains "$(cat "$case_dir/launch-expl")" '--permission-mode dangerous --respect-workspace-trust false' 'explicit dangerous lost the flag'
printf 'yolo\n' > "$home/config/devin-permission-mode"
fm_test_spawn_brief "$home" devin-bogus
if out=$(FM_FAKE_LAUNCH_LOG="$case_dir/launch-bogus" fm_test_run_spawn "$home" "$wt" "$fakebin" devin-bogus "$proj" --scout --harness devin 2>&1)
then fail 'an unrecognized devin-permission-mode token launched'; fi
assert_contains "$out" "config/devin-permission-mode holds 'yolo'" 'refusal must name the file and the token'
assert_contains "$out" 'smart' 'refusal must list smart as an accepted value'
assert_absent "$home/state/devin-bogus.meta" 'refusal must happen before meta is written'
assert_absent "$case_dir/launch-bogus" 'refusal must launch nothing'
rm "$home/config/devin-permission-mode"

# The permission overlay reaches the generated worker config through a spawn.
printf '%s\n' '{"deny":["Exec(rm -rf)"],"ask":["Exec(git push)"]}' > "$home/config/devin-permissions.worker.json"
fm_test_spawn_brief "$home" devin-ov
if ! out=$(FM_FAKE_LAUNCH_LOG="$case_dir/launch-ov" fm_test_run_spawn "$home" "$wt" "$fakebin" devin-ov "$proj" --scout --harness devin 2>&1)
then fail "overlay spawn failed: $out"; fi
jq -e '.permissions.deny == ["Exec(rm -rf)"] and .permissions.ask == ["Exec(git push)"]' "$home/state/devin-ov.devin-config.json" >/dev/null \
  || fail 'spawned config lost the overlay merge'
pass "config/devin-permission-mode and the permission overlay reach Devin launches"
