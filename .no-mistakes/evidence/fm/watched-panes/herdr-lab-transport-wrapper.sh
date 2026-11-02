#!/usr/bin/env bash
set -eu
args=("$@")
n=${#args[@]}
if [ "${1:-}" = status ] || [ "${1:-} ${2:-}" = 'api schema' ] || [ "${1:-} ${2:-}" = 'session list' ]; then
  args+=(--session fm-lab-watch-gate-01m6)
  n=${#args[@]}
fi
[ "$n" -ge 2 ] && [ "${args[n-2]}" = --session ] && [ "${args[n-1]}" = fm-lab-watch-gate-01m6 ] || exit 98
if [ -n "${FM_LIVE_READ_LOG:-}" ] && [ "${1:-} ${2:-}" = 'agent get' ]; then
  printf '%s %s\n' "$$" "$(date +%s)" >> "$FM_LIVE_READ_LOG"
  if [ "${FM_LIVE_DELAY_STATUS:-0}" = second ] && [ "$(wc -l < "$FM_LIVE_READ_LOG" | tr -d ' ')" = 2 ]; then
    echo "$$" > "$FM_LIVE_DELAY_LOG"
    sleep 30
  fi
fi
if [ "${FM_LIVE_DELAY_STATUS:-0}" = 1 ] && [ "${1:-} ${2:-}" = 'agent get' ]; then
  echo "$$" >> "$FM_LIVE_DELAY_LOG"
  sleep 30
fi
exec env PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/codex-path:/Users/buruchan_1221/.codeium/windsurf/bin:/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin:/Users/buruchan_1221/Library/Android/sdk/platform-tools:/Users/buruchan_1221/Library/Android/sdk/emulator:/Users/buruchan_1221/Library/Android/sdk/cmdline-tools/latest/bin:/Users/buruchan_1221/Library/Python/3.9/bin:/Users/buruchan_1221/.local/bin:/Users/buruchan_1221/.antigravity/antigravity/bin:/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/pkg/env/global/bin:/Library/Apple/usr/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/Users/buruchan_1221/.codex/tmp/arg0-macos/codex-arg0jAQTVr:/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/codex-path:/Users/buruchan_1221/.codeium/windsurf/bin:/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin:/Users/buruchan_1221/Library/Android/sdk/platform-tools:/Users/buruchan_1221/Library/Android/sdk/emulator:/Users/buruchan_1221/Library/Android/sdk/cmdline-tools/latest/bin:/Users/buruchan_1221/Library/Python/3.9/bin:/Users/buruchan_1221/.local/bin:/Users/buruchan_1221/.antigravity/antigravity/bin:/opt/homebrew/opt/libpq/bin:/Users/buruchan_1221/go/bin:/Users/buruchan_1221/.cargo/bin:/Users/buruchan_1221/bin:/usr/local/sbin FM_HERDR_LAB_STATE_DIR=/Users/buruchan_1221/.no-mistakes/worktrees/cde2eac61d4b/01M6CV1MTS66Y6ANJ9AYFS72RN/.test-live/lab-state /Users/buruchan_1221/.no-mistakes/worktrees/cde2eac61d4b/01M6CV1MTS66Y6ANJ9AYFS72RN/bin/fm-herdr-lab.sh run fm-lab-watch-gate-01m6 "${args[@]:0:n-2}"
