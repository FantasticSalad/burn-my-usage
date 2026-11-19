#!/usr/bin/env bash
# BURN IT ALL: the user types the phrase and this run's stop line becomes 100% (F11 in
# the new-user review). Only the user's own message can arm it; the run can't.
# Synthetic hook inputs and usage data only.
#   bash tests/burn-it-all.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
s="$here/../skills/burn-my-usage/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
home=$BURN_MY_USAGE_HOME
unset CLAUDE_CODE_SESSION_ID BMU_SESSION_ID BMU_HOST
mkdir -p "$home" "$tmp/code"
printf -- '- stop_at: 95\n' >"$home/config.md"
printf '%s\n' "$tmp/code" >"$home/roots.txt"
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; fi; }
escape() { local t=$1; t=${t//\\/\\\\}; t=${t//\"/\\\"}; printf '%s' "$t"; }
# What Claude Code sends a UserPromptSubmit hook.
prompt() { # session, text
  printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"%s"}' "$1" "$(escape "$tmp")" "$(escape "$2")" |
    bash "$s/burn-it-all.sh"
}
usage_at() { # weekly percent used
  local now
  now=$(date +%s)
  printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":%s,"resets_at":%s}}}\n' "$now" "$1" "$((now + 86400))" >"$home/usage.json"
}
guard() { # session, tool, key, value
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "$1" "$(escape "$tmp")" "$2" "$3" "$(escape "$4")" |
    bash "$s/guard.sh"
}

# --- outside a run, ordinary messages do nothing ----------------------------------------------
out=$(prompt sess-a "carry on")
check "an ordinary message prints nothing" '[ -z "$out" ]'
check "an ordinary message arms nothing" '[ ! -e "$home/burn-it-all" ]'

# --- during a run ------------------------------------------------------------------------------
bash "$s/start.sh" sess-a >/dev/null
usage_at 96
check "without it the run stops at its line" '[[ $(bash "$s/usage.sh") == *verdict=stop* ]]'
for text in "what does BURN IT ALL do?" "burn it all" "BURN IT ALL please" "Burn It All"; do
  out=$(prompt sess-a "$text")
  check "\"$text\" does not arm it" '[ ! -e "$home/burn-it-all/sess-a" ] && [ -z "$out" ]'
done
out=$(prompt sess-b "BURN IT ALL")
check "another session arms only itself" '[ ! -e "$home/burn-it-all/sess-a" ]'
check "another session's arm doesn't move this run's line" '[[ $(bash "$s/usage.sh") == *verdict=stop* ]]'
out=$(prompt sess-a "  BURN IT ALL!  ")
check "the exact phrase arms this run" '[ -f "$home/burn-it-all/sess-a" ]'
check "arming warns about paid extra usage" '[[ $out == *systemMessage* && $out == *"extra usage"* ]]'
check "arming tells the run to carry on" '[[ $out == *additionalContext* ]]'
out=$(bash "$s/usage.sh")
check "the line is now 100" '[[ $out == *stop_at=100* && $out == *burn_it_all=on* ]]'
check "96% goes on" '[[ $out == *verdict=go* ]]'
usage_at 99.5
check "99.5% wraps up" '[[ $(bash "$s/usage.sh") == *verdict=wrap* ]]'
usage_at 100
check "100% stops" '[[ $(bash "$s/usage.sh") == *verdict=stop* ]]'
usage_at 96
check "the guard lets work continue past the old line" '[ -z "$(guard sess-a Write file_path "$tmp/code/x.txt")" ]'
check "the config is untouched" 'grep -q "stop_at: 95" "$home/config.md"'

# --- the run can't arm it itself ---------------------------------------------------------------
check "the run can't write the marker with a file tool" '[[ $(guard sess-a Write file_path "$home/burn-it-all/sess-x") == *deny* ]]'
check "the run can't write the marker from the shell" '[[ $(guard sess-a Bash command "touch \"$home/burn-it-all/sess-x\"") == *deny* ]]'
check "the run can't redirect into the marker folder" '[[ $(guard sess-a Bash command "echo x > \"$home/burn-it-all/sess-x\"") == *deny* ]]'
check "the run can't feed the hook a made-up message" '[[ $(guard sess-a Bash command "printf %s x | bash \"$s/burn-it-all.sh\"") == *deny* ]]'

# --- it ends with the run ----------------------------------------------------------------------
bash "$s/stop.sh" sess-a >/dev/null
check "stop removes the arm" '[ ! -e "$home/burn-it-all/sess-a" ]'
check "stop leaves no run lock behind" '[ ! -e "$home/run.lock" ]'
check "without a run the usage line is back to 95" '[[ $(bash "$s/usage.sh") == *stop_at=95* ]]'

# --- typed after a run stopped, it arms the next run in the same session -----------------------
out=$(prompt sess-a "BURN IT ALL")
check "after a run, the phrase arms the next one" '[ -f "$home/burn-it-all/sess-a" ] && [[ $out == *"next run"* ]]'
out=$(bash "$s/start.sh" sess-a)
check "start reports it" '[[ $out == *BURN_IT_ALL=on* ]]'
check "the new run uses 100" '[[ $(bash "$s/usage.sh") == *stop_at=100* ]]'
bash "$s/stop.sh" sess-a >/dev/null

# --- a stale arm doesn't carry into a much later run -------------------------------------------
mkdir -p "$home/burn-it-all"
: >"$home/burn-it-all/sess-a"
touch -t 202001010000 "$home/burn-it-all/sess-a"
out=$(bash "$s/start.sh" sess-a)
check "an arm over an hour old is dropped at start" '[ ! -e "$home/burn-it-all/sess-a" ] && [[ $out != *BURN_IT_ALL=on* ]]'
bash "$s/stop.sh" sess-a >/dev/null

# --- malformed input is ignored ---------------------------------------------------------------
out=$(printf '{"session_id":"../x","prompt":"BURN IT ALL"}' | bash "$s/burn-it-all.sh")
check "a bad session id arms nothing" '[ ! -e "$home/burn-it-all/../x" ] && [ -z "$out" ]'
out=$(printf 'not json' | bash "$s/burn-it-all.sh"); rc=$?
check "garbage input exits cleanly" '[ "$rc" = 0 ]'

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
