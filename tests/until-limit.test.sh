#!/usr/bin/env bash
# Until-limit runs: no stop line and no usage data needed; Claude Code's usage limit ends the
# run (a StopFailure hook records it), and the next turn wraps up.
# Synthetic hook inputs and usage data only.
#   bash tests/until-limit.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
s="$here/../skills/burn-my-usage/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
home=$BURN_MY_USAGE_HOME
unset CLAUDE_CODE_SESSION_ID BMU_SESSION_ID BMU_HOST
mkdir -p "$home" "$tmp/code"
printf -- '- stop_at: 90\n' >"$home/config.md"
printf '%s\n' "$tmp/code" >"$home/roots.txt"
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; fi; }
escape() { local t=$1; t=${t//\\/\\\\}; t=${t//\"/\\\"}; printf '%s' "$t"; }
# What Claude Code sends the hooks.
limit() { # session: a turn ended on the usage limit
  printf '{"session_id":"%s","hook_event_name":"StopFailure","cwd":"%s","error":"rate_limit"}' "$1" "$(escape "$tmp")" |
    bash "$s/until-limit.sh"
}
prompt() { # session, text
  printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"%s"}' "$1" "$(escape "$tmp")" "$(escape "$2")" |
    bash "$s/until-limit.sh"
}
guard() { # session, tool, key, value
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "$1" "$(escape "$tmp")" "$2" "$3" "$(escape "$4")" |
    bash "$s/guard.sh"
}
usage_at() { # weekly percent used, captured this many seconds ago
  local now
  now=$(date +%s)
  printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":%s,"resets_at":%s}}}\n' "$((now - $2))" "$1" "$((now + 86400))" >"$home/usage.json"
}

# --- an ordinary run is unchanged ---------------------------------------------------------------
bash "$s/start.sh" sess-a >/dev/null
check "an ordinary run has no mode line" '! grep -q mode "$home/active/sess-a"'
check "an ordinary run without usage data is unknown" '[[ $(bash "$s/usage.sh") == *verdict=unknown* ]]'
limit sess-a
check "a limit in an ordinary run records nothing" '[ ! -e "$home/limit-hit" ]'
check "the guard still needs fresh usage there" '[[ $(guard sess-a Write file_path "$tmp/code/x.txt") == *deny* ]]'
bash "$s/stop.sh" sess-a >/dev/null

# --- an until-limit run works without usage data ------------------------------------------------
out=$(bash "$s/start.sh" --until-limit sess-a)
check "start reports the mode and warns about extra usage" '[[ $out == *UNTIL_LIMIT=on* && $out == *"Extra usage must be off"* ]]'
check "the marker records the mode" 'grep -qx "mode until-limit" "$home/active/sess-a"'
out=$(bash "$s/usage.sh")
check "no usage data: go" '[[ $out == *until_limit=on* && $out == *verdict=go* ]]'
usage_at 50 7200
check "stale usage data: go" '[[ $(bash "$s/usage.sh") == *verdict=go* ]]'
usage_at 96 0
check "past the configured line: still go" '[[ $(bash "$s/usage.sh") == *verdict=go* ]]'
rm -f "$home/usage.json"
check "the guard lets work go on without usage data" '[ -z "$(guard sess-a Write file_path "$tmp/code/x.txt")" ]'
out=$(prompt sess-a "how's it going?")
check "a message before the limit adds nothing" '[ -z "$out" ]'
check "the guard self-test still works" '[[ $(guard sess-a Bash command "echo burn-guard-selftest") == *"self-test OK"* ]]'

# --- another session's limit doesn't end it -----------------------------------------------------
limit sess-b
check "another session's limit records nothing" '[ ! -e "$home/limit-hit/sess-b" ]'
check "and the run goes on" '[[ $(bash "$s/usage.sh") == *verdict=go* ]]'

# --- the usage limit stops it -------------------------------------------------------------------
limit sess-a
check "the limit is recorded" '[ -f "$home/limit-hit/sess-a" ]'
first=$(cat "$home/limit-hit/sess-a")
out=$(bash "$s/usage.sh")
check "usage now says stop, with the time" '[[ $out == *verdict=stop* && $out == *"usage limit stopped this run at 2"* ]]'
sleep 1
limit sess-a
check "a second failure keeps the first time" '[ "$(cat "$home/limit-hit/sess-a")" = "$first" ]'

# --- the next turn wraps up ---------------------------------------------------------------------
# Claude Code carrying on by itself after the reset: no message, so the guard says it once.
out=$(guard sess-a Read file_path "$tmp/code/x.txt")
check "the first call after the limit is told to wrap up" '[[ $out == *deny* && $out == *"section 7"* ]]'
check "only once" '[ -z "$(guard sess-a Read file_path "$tmp/code/x.txt")" ]'
check "the guard refuses new work" '[[ $(guard sess-a Write file_path "$tmp/code/x.txt") == *"fresh usage below the stop line"* ]]'
# The user coming back: the message says it, and the guard then doesn't.
rm -f "$home/limit-hit/sess-a.told"
out=$(prompt sess-a "back")
check "the next message is told to wrap up" '[[ $out == *additionalContext* && $out == *"section 7"* && $out == *systemMessage* ]]'
check "then the guard doesn't say it again" '[ -z "$(guard sess-a Read file_path "$tmp/code/x.txt")" ]'

# --- the run can't clear the record itself ------------------------------------------------------
check "not with a file tool" '[[ $(guard sess-a Write file_path "$home/limit-hit/sess-a") == *deny* ]]'
check "not from the shell" '[[ $(guard sess-a Bash command "rm -f \"$home/limit-hit/sess-a\"") == *deny* ]]'
check "not by restarting itself" '[[ $(bash "$s/start.sh" sess-a) == *OTHER_RUN_ACTIVE* ]]'

# --- it ends with the run -----------------------------------------------------------------------
out=$(bash "$s/stop.sh" sess-a)
check "stop ends the run" '[[ $out == *STOPPED* ]] && [ ! -e "$home/run.lock" ]'
check "stop removes the record" '[ ! -e "$home/limit-hit/sess-a" ] && [ ! -e "$home/limit-hit/sess-a.told" ]'
check "without a run, usage is back to the configured line" '[[ $(bash "$s/usage.sh") == *stop_at=90* ]]'
out=$(prompt sess-a "hello")
check "after the run, messages add nothing" '[ -z "$out" ]'

# --- a stale record doesn't end a new run -------------------------------------------------------
mkdir -p "$home/limit-hit"
printf '1\nold\n' >"$home/limit-hit/sess-a"
bash "$s/start.sh" --until-limit sess-a >/dev/null
check "start clears an old record" '[ ! -e "$home/limit-hit/sess-a" ] && [[ $(bash "$s/usage.sh") == *verdict=go* ]]'
bash "$s/stop.sh" sess-a >/dev/null

# --- Codex can't use it; malformed input is ignored ---------------------------------------------
out=$(BMU_HOST=codex bash "$s/start.sh" --until-limit sess-c 2>&1); rc=$?
check "Codex refuses the mode" '[ "$rc" != 0 ] && [ ! -e "$home/run.lock" ]'
out=$(printf '{"session_id":"../x","hook_event_name":"StopFailure"}' | bash "$s/until-limit.sh")
check "a bad session id records nothing" '[ -z "$(ls "$home/limit-hit" 2>/dev/null)" ] && [ -z "$out" ]'
out=$(printf 'not json' | bash "$s/until-limit.sh"); rc=$?
check "garbage input exits cleanly" '[ "$rc" = 0 ] && [ -z "$out" ]'

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
