#!/usr/bin/env bash
set -u
s=$(cd "$(dirname "$0")/../skills/burn-my-usage/scripts" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
unset CLAUDE_CODE_SESSION_ID BMU_SESSION_ID BMU_HOST
fail=0
check() { if ! eval "$2"; then echo "FAIL: $1"; fail=$((fail+1)); fi; }
out=$(bash "$s/start.sh" first 2>&1 || true)
check 'no config leaves home absent' '[ ! -e "$BURN_MY_USAGE_HOME" ]'
mkdir -p "$BURN_MY_USAGE_HOME"
printf 'config\n' >"$BURN_MY_USAGE_HOME/config.md"
printf '%s\n' "$tmp/code" >"$BURN_MY_USAGE_HOME/roots.txt"
bash "$s/start.sh" first >"$tmp/first" & p1=$!
BMU_HOST=codex bash "$s/start.sh" second >"$tmp/second" & p2=$!
wait "$p1" || true
wait "$p2" || true
check 'one winner' '[ "$(cat "$tmp/first" "$tmp/second" | grep -c "RUN_DIR=")" = 1 ]'
check 'one loser' '[ "$(cat "$tmp/first" "$tmp/second" | grep -c "OTHER_RUN_ACTIVE=")" = 1 ]'
check 'only one run directory' '[ "$(find "$BURN_MY_USAGE_HOME/runs" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d " ")" = 1 ]'
check 'owner file holds one claim' '[ "$(wc -l <"$BURN_MY_USAGE_HOME/run.lock/owner" | tr -d " ")" = 3 ]'
owner=$(sed -n '2p' "$BURN_MY_USAGE_HOME/run.lock/owner")
host=$(sed -n '1p' "$BURN_MY_USAGE_HOME/run.lock/owner")
BMU_HOST=codex bash "$s/stop.sh" stranger >/dev/null
check 'stranger cannot release lock' '[ -d "$BURN_MY_USAGE_HOME/run.lock" ]'
BMU_HOST="$host" bash "$s/stop.sh" "$owner" >/dev/null
check 'owner releases lock' '[ ! -e "$BURN_MY_USAGE_HOME/run.lock" ]'
# uutils mkdir (Ubuntu 26.04) can report success to both of two simultaneous calls. Stand in
# for that with a mkdir that never fails: the owner file must still let only one run start.
mkdir() { command mkdir -p "$@"; }
export -f mkdir
bash "$s/start.sh" holder >/dev/null 2>&1
out=$(BMU_HOST=codex bash "$s/start.sh" intruder 2>&1 || true)
unset -f mkdir
check 'owner file decides when mkdir always succeeds' '[[ $out == *"OTHER_RUN_ACTIVE= holder"* && $(sed -n 2p "$BURN_MY_USAGE_HOME/run.lock/owner") == holder && ! -e "$BURN_MY_USAGE_HOME/active/codex/intruder" ]]'
bash "$s/stop.sh" holder >/dev/null
check 'holder releases lock' '[ ! -e "$BURN_MY_USAGE_HOME/run.lock" ]'
BMU_HOST=codex BMU_SESSION_ID=codex-id bash "$s/start.sh" >"$tmp/codex"
check 'Codex marker isolated' '[ -f "$BURN_MY_USAGE_HOME/active/codex/codex-id" ]'
rm() { return 1; }
export -f rm
out=$(BMU_HOST=codex BMU_SESSION_ID=codex-id bash "$s/stop.sh" 2>&1 || true)
unset -f rm
check 'failed marker removal retains ownership' '[[ $out == *"run lock retained"* && -d "$BURN_MY_USAGE_HOME/run.lock" && -f "$BURN_MY_USAGE_HOME/active/codex/codex-id" ]]'
mkdir -p "$BURN_MY_USAGE_HOME/owned/codex/codex-id"
printf 'owned\n' >"$BURN_MY_USAGE_HOME/owned/codex/codex-id/item"
out=$(BMU_HOST=codex BMU_SESSION_ID=codex-id bash "$s/stop.sh" 2>&1 || true)
check 'Codex owned work blocks stop' '[[ $out == *WORK_REMAINS* && -d "$BURN_MY_USAGE_HOME/run.lock" ]]'
rm "$BURN_MY_USAGE_HOME/owned/codex/codex-id/item"
BMU_HOST=codex BMU_SESSION_ID=codex-id bash "$s/stop.sh" >/dev/null
printf 'legacy marker\n' >"$BURN_MY_USAGE_HOME/active/old-session"
out=$(bash "$s/start.sh" new-session 2>&1 || true)
check 'legacy marker blocks claim' '[[ $out == *OTHER_RUN_ACTIVE* && ! -e "$BURN_MY_USAGE_HOME/active/new-session" ]]'
BMU_HOST=invalid bash "$s/start.sh" invalid >"$tmp/invalid" 2>&1 || true
check 'invalid host refused' 'grep -q ERROR "$tmp/invalid"'
echo "runtime failures: $fail"
[ "$fail" = 0 ]
