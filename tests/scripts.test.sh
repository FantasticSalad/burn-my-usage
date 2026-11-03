#!/usr/bin/env bash
# Tests for the run scripts: usage-tap.sh, usage.sh, start.sh, stop.sh and repo-check.sh.
#   bash tests/scripts.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
s="$here/../skills/burn-my-usage/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
home=$BURN_MY_USAGE_HOME
# These tests may themselves run inside a Claude Code session, which sets this.
unset CLAUDE_CODE_SESSION_ID

pass=0
fail=0
expect() { # label, haystack, needle
  case "$2" in
    *"$3"*) pass=$((pass + 1)) ;;
    *)
      fail=$((fail + 1))
      printf 'FAIL %s\n  wanted: %s\n  got: %s\n' "$1" "$3" "$2"
      ;;
  esac
}
refute() { # label, haystack, needle
  case "$2" in
    *"$3"*)
      fail=$((fail + 1))
      printf 'FAIL %s\n  did not want: %s\n  got: %s\n' "$1" "$3" "$2"
      ;;
    *) pass=$((pass + 1)) ;;
  esac
}

now=$(date +%s)
week_reset=$((now + 50 * 3600))
five_reset=$((now + 90 * 60))
status_json() { # weekly used, five-hour used
  printf '{"model":{"display_name":"Opus"},"cwd":"/x","rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}},"cost":{"total_cost_usd":1.2}}' \
    "$2" "$five_reset" "$1" "$week_reset"
}

# --- usage.sh with no data ---------------------------------------------------------------------
out=$(bash "$s/usage.sh")
expect "no data is unknown" "$out" "verdict=unknown"

# --- usage-tap.sh --------------------------------------------------------------------------
out=$(status_json 41.2 23.5 | bash "$s/usage-tap.sh")
expect "tap prints the weekly figure" "$out" "7d 41%"
expect "tap prints the five-hour figure" "$out" "5h 24%"
saved=$(cat "$home/usage.json")
expect "tap saves rate_limits" "$saved" '"seven_day":{"used_percentage":41.2'
refute "tap keeps nothing else" "$saved" "total_cost_usd"
refute "tap keeps nothing else (cwd)" "$saved" '"cwd"'

# A reply with no rate_limits (start of a session, or an API-key session) keeps the old data.
printf '{"model":{"display_name":"Opus"}}' | bash "$s/usage-tap.sh" >/dev/null
expect "missing rate_limits leaves usage.json alone" "$(cat "$home/usage.json")" "41.2"

# Your own status line still runs, with the same input.
printf 'cat >/dev/null; echo my-own-line' >"$home/statusline-next"
out=$(status_json 41.2 23.5 | bash "$s/usage-tap.sh")
expect "tap hands over to the saved status line" "$out" "my-own-line"
rm "$home/statusline-next"

# --- usage.sh verdicts -------------------------------------------------------------------------
out=$(bash "$s/usage.sh")
expect "41% is go" "$out" "verdict=go"
expect "weekly figure reported" "$out" "weekly_used=41.2"
expect "reset reported" "$out" "weekly_resets_in_hours=50.0"
expect "five-hour reported" "$out" "five_hour_used=23.5"

status_json 86 10 | bash "$s/usage-tap.sh" >/dev/null
expect "86% is wrap at the default 90" "$(bash "$s/usage.sh")" "verdict=wrap"
status_json 90 10 | bash "$s/usage-tap.sh" >/dev/null
expect "90% is stop" "$(bash "$s/usage.sh")" "verdict=stop"
expect "--stop-at overrides" "$(bash "$s/usage.sh" --stop-at 98)" "verdict=go"

mkdir -p "$home"
printf '# Settings\n\n- stop_at: 70   # leave plenty for the weekend\n' >"$home/config.md"
status_json 60 10 | bash "$s/usage-tap.sh" >/dev/null
out=$(bash "$s/usage.sh")
expect "stop_at read from config.md" "$out" "stop_at=70"
expect "60% under a 70 line is go" "$out" "verdict=go"
status_json 66 10 | bash "$s/usage-tap.sh" >/dev/null
expect "66% under a 70 line is wrap" "$(bash "$s/usage.sh")" "verdict=wrap"
rm "$home/config.md"

# Stale data: the status line stopped updating.
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}\n' $((now - 3 * 3600)) "$week_reset" >"$home/usage.json"
out=$(bash "$s/usage.sh")
expect "three-hour-old data is unknown" "$out" "verdict=unknown"
expect "stale reason given" "$out" "minutes old"

# The weekly window reset after the data was saved.
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":95,"resets_at":%s}}}\n' "$now" $((now - 60)) >"$home/usage.json"
expect "a passed reset is unknown, not stop" "$(bash "$s/usage.sh")" "verdict=unknown"

# A gateway spend limit counts too.
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":20,"resets_at":%s},"spend_limit":{"used_percentage":93,"resets_at":%s}}}\n' "$now" "$week_reset" "$week_reset" >"$home/usage.json"
expect "spend limit past the line is stop" "$(bash "$s/usage.sh")" "verdict=stop"

# --- start.sh and stop.sh -------------------------------------------------------------------
out=$(bash "$s/start.sh" "../evil" 2>&1)
expect "start rejects a bad session id" "$out" "ERROR"
# Without a config, start refuses and creates nothing.
rm -rf "$home/active" "$home/runs"
out=$(bash "$s/start.sh" sess-1 2>&1); rc=$?
expect "start without config is refused" "$out" "NO_CONFIG"
expect "start without config exits 3" "$rc" "3"
expect "start without config reports it" "$out" "HAS_config=no"
refute "start without config marks no session" "$(ls "$home")" "active"
refute "start without config makes no run folder" "$(ls "$home")" "runs"
printf 'synthetic config\n' >"$home/config.md"
out=$(bash "$s/start.sh" sess-1)
expect "start marks the session" "$(ls "$home/active")" "sess-1"
expect "start reports the run dir" "$out" "RUN_DIR="
expect "start reports the config" "$out" "HAS_config=yes"
refute "no other run yet" "$out" "OTHER_RUN_ACTIVE"
out=$(bash "$s/start.sh" sess-2)
expect "a second session sees the first run" "$out" "OTHER_RUN_ACTIVE= sess-1"
mkdir -p "$home/owned/sess-1"
printf 'synthetic worktree\n' >"$home/owned/sess-1/item"
expect "stop refuses unfinished owned work" "$(bash "$s/stop.sh" sess-1 2>&1)" WORK_REMAINS
expect "refused stop keeps guard marker" "$(ls "$home/active")" sess-1
rm "$home/owned/sess-1/item"
out=$(bash "$s/stop.sh" sess-1)
expect "stop removes the marker" "$out" "STOPPED"
refute "marker gone" "$(ls "$home/active")" "sess-1"
expect "stop is idempotent" "$(bash "$s/stop.sh" sess-1)" "NOT_ACTIVE"
bash "$s/stop.sh" sess-2 >/dev/null

# With no id passed (an older Claude Code that doesn't substitute ${CLAUDE_SESSION_ID}), the
# environment's session id is used; if both are present and differ, both are marked.
expect "no id and no env is an error" "$(bash "$s/start.sh" 2>&1)" "ERROR"
out=$(CLAUDE_CODE_SESSION_ID=env-sess bash "$s/start.sh")
expect "falls back to CLAUDE_CODE_SESSION_ID" "$(ls "$home/active")" "env-sess"
out=$(CLAUDE_CODE_SESSION_ID=env-sess bash "$s/start.sh" arg-sess)
expect "different ids: both marked (arg)" "$(ls "$home/active")" "arg-sess"
expect "different ids: both marked (env)" "$(ls "$home/active")" "env-sess"
expect "different ids are reported" "$out" "SESSION_IDS_DIFFER"
expect "a bad id is an error even with env set" "$(CLAUDE_CODE_SESSION_ID=env-sess bash "$s/start.sh" '../x' 2>&1)" "ERROR"
out=$(CLAUDE_CODE_SESSION_ID=env-sess bash "$s/stop.sh" arg-sess)
expect "stop clears both" "$out" "STOPPED"
refute "both markers gone" "$(ls "$home/active")" "sess"

# --paths changes nothing.
rm -rf "$home/runs"
out=$(bash "$s/start.sh" --paths)
expect "--paths prints the home" "$out" "BURN_HOME="
refute "--paths makes no run folder" "$(ls "$home")" "runs"

# --- repo-check.sh ------------------------------------------------------------------------------
g() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }
code="$tmp/code dir"
mkdir -p "$code/origin.git" "$code/org/app" "$code/lib"
g init -q --bare "$code/origin.git"
g -C "$code/org/app" init -q
printf 'x\n' >"$code/org/app/a.txt"
g -C "$code/org/app" add a.txt
g -C "$code/org/app" commit -q -m one
g -C "$code/org/app" remote add origin "$code/origin.git"
g -C "$code/org/app" push -q origin main
g -C "$code/org/app" remote set-head origin main
g -C "$code/org/app" switch -q -c burn/2026-10-08-fix
printf 'y\n' >>"$code/org/app/a.txt"
g -C "$code/org/app" commit -q -am fix
g -C "$code/org/app" switch -q main
printf 'dirty\n' >"$code/org/app/b.txt"
g -C "$code/lib" init -q
printf 'x\n' >"$code/lib/a.txt"
g -C "$code/lib" add a.txt
g -C "$code/lib" commit -q -m one

out=$(bash "$s/repo-check.sh" "$code")
expect "finds a repo two levels down, in a folder with a space" "$out" "org/app"
expect "finds a repo one level down" "$out" "lib "
expect "flags uncommitted work" "$out" "DIRTY"
expect "flags no remote" "$out" "NO-REMOTE"
expect "lists the burn branch" "$out" "org/app: burn/2026-10-08-fix (1 commits on main, local only"
refute "a bare repo is not listed" "$out" "origin.git "

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
