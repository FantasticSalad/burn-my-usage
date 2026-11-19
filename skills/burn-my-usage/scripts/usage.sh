#!/usr/bin/env bash
# Reads <burn home>/usage.json (written by usage-tap.sh) and says whether a run should keep
# going. Prints key=value lines, ending with verdict= and reason=.
#
#   bash usage.sh [--stop-at N]
#
# verdict:
#   go       keep working
#   wrap     within 5 points of the stop line: finish the item in hand, then finish the run
#   stop     at or past the stop line: save work in progress and finish now
#   unknown  no fresh data: save current work, write a handoff and stop
#
# The stop line is stop_at in config.md (default 90): the share of the weekly limit the run may
# use, counting what you used yourself earlier in the week. It leaves headroom; sampled usage
# cannot guarantee that paid extra usage will never be reached.
set -u
. "$(dirname "$0")/lib.sh"

if ! valid_host; then
  echo 'verdict=unknown'
  echo 'reason=invalid BMU_HOST'
  exit 0
fi
if [ "$BMU_HOST" = codex ]; then
  if ! command -v node >/dev/null 2>&1; then
    echo 'verdict=unknown'
    echo 'reason=Node is required to check live Codex quota'
    exit 0
  fi
  # Node is a native Windows program: give it Windows paths. Git Bash doesn't convert a path
  # with an apostrophe in it, and Node would read /c/Users/... as C:\c\Users\...
  BURN_MY_USAGE_HOME=$(native_path "$BMU_HOME") exec node "$(native_path "$(cd "$(dirname "$0")" && pwd)")/usage-codex.mjs" check "${1:-}" "${2:-}"
fi

stop_at=$(config_value stop_at 90)
if [ "${1:-}" = --stop-at ] && [ -n "${2:-}" ]; then stop_at=$2; fi
stop_at=${stop_at%\%}
if ! awk -v n="$stop_at" 'BEGIN { exit !(n ~ /^[0-9]+([.][0-9]+)?$/ && n > 0 && n < 100) }'; then
  echo "verdict=unknown"
  echo "reason=stop_at must be greater than zero and below 100"
  exit 0
fi
# BURN IT ALL: the user typed it in this run's session (burn-it-all.sh), so this run may go to
# 100%. Only for the run that holds the lock; stop.sh removes the arm. The wrap window
# shrinks to one point, or the run would wrap up at 95% anyway.
wrap=5
if [ -f "$BMU_HOME/run.lock/owner" ]; then
  for sid in $(sed -n '3,$p' "$BMU_HOME/run.lock/owner"); do
    if valid_session "$sid" && [ -f "$BMU_HOME/burn-it-all/$sid" ]; then
      stop_at=100
      wrap=1
      echo "burn_it_all=on"
      break
    fi
  done
fi

f="$BMU_HOME/usage.json"
now=$(date +%s)
echo "stop_at=$stop_at"

if [ ! -s "$f" ]; then
  echo "verdict=unknown"
  echo "reason=no usage data. The status line tap isn't installed, or no reply has come back yet in a session that has it (see setup.md)"
  exit 0
fi
j=$(cat "$f")

if ! j=$(printf '%s\n' "$j" | awk -f "$(dirname "$0")/usage-validate.awk"); then
  echo 'verdict=unknown'
  echo 'reason=malformed usage data'
  exit 0
fi

num() { # regex -> first capture, or nothing
  [[ $j =~ $1 ]] && printf '%s' "${BASH_REMATCH[1]}"
}
win() { # window key -> "used resets_at"
  local used reset
  used=$(num "\"$1\"[[:space:]]*:[[:space:]]*\{[^}]*\"used_percentage\"[[:space:]]*:[[:space:]]*([0-9.]+)")
  reset=$(num "\"$1\"[[:space:]]*:[[:space:]]*\{[^}]*\"resets_at\"[[:space:]]*:[[:space:]]*([0-9]+)")
  printf '%s %s' "${used:-}" "${reset:-}"
}

captured=$(num '"captured_at"[[:space:]]*:[[:space:]]*([0-9]+)')
set -- $(win seven_day)
week=${1:-}
week_reset=${2:-}
set -- $(win five_hour)
five=${1:-}
five_reset=${2:-}
set -- $(win spend_limit)
spend=${1:-}
spend_reset=${2:-}

if [ -z "$captured" ] || { [ -n "$week" ] && [ -z "$week_reset" ]; } ||
  ! awk -v w="$week" -v f="$five" -v s="$spend" 'BEGIN {
    split(w " " f " " s, a, " ");
    for (i in a) if (a[i] != "" && (a[i] !~ /^[0-9]+([.][0-9]+)?$/ || a[i]+0 > 100)) exit 1
  }'; then
  echo 'verdict=unknown'
  echo 'reason=malformed usage data'
  exit 0
fi

age_min=$(( (now - ${captured:-0}) / 60 ))
echo "age_minutes=$age_min"
[ -n "$week" ] && echo "weekly_used=$week"
[ -n "$week_reset" ] && echo "weekly_resets_in_hours=$(awk -v a="$week_reset" -v n="$now" 'BEGIN { printf "%.1f", (a - n) / 3600 }')"
[ -n "$five" ] && echo "five_hour_used=$five"
[ -n "$five_reset" ] && echo "five_hour_resets_in_minutes=$(( (five_reset - now) / 60 ))"
[ -n "$spend" ] && echo "spend_used=$spend"

# The window that is closest to the stop line decides.
used=$(awk -v a="${week:-}" -v b="${spend:-}" 'BEGIN { m = -1; if (a != "") m = a + 0; if (b != "" && b + 0 > m) m = b + 0; print m }')

if [ "$captured" -gt "$now" ] || [ $((now - captured)) -gt 3600 ]; then
  echo "verdict=unknown"
  echo "reason=usage data is $age_min minutes old. The status line only updates in interactive sessions, so a claude -p run never refreshes it"
  exit 0
fi
if { [ -n "$five_reset" ] && [ "$five_reset" -le "$now" ]; } ||
   { [ -n "$spend_reset" ] && [ "$spend_reset" -le "$now" ]; }; then
  echo 'verdict=unknown'
  echo 'reason=a usage window reset since the data was saved'
  exit 0
fi
if [ -n "$week_reset" ] && [ "$week_reset" -le "$now" ]; then
  echo "verdict=unknown"
  echo "reason=the weekly window has reset since the data was saved; it refreshes on the next reply"
  exit 0
fi
if [ "$used" = -1 ]; then
  echo "verdict=unknown"
  echo "reason=usage.json has no weekly or spend figure"
  exit 0
fi
if [ -n "$five" ] && awk -v f="$five" 'BEGIN { exit !(f >= 100) }'; then
  echo 'verdict=stop'
  echo 'reason=the five-hour window is exhausted'
  exit 0
fi

awk -v u="$used" -v s="$stop_at" -v w="$wrap" -v h="$(awk -v a="${week_reset:-0}" -v n="$now" 'BEGIN { printf "%.1f", (a - n) / 3600 }')" 'BEGIN {
  if (u >= s) {
    print "verdict=stop"
    printf "reason=%.1f%% used, at or past the stop line of %s%%\n", u, s
  } else if (u >= s - w) {
    print "verdict=wrap"
    printf "reason=%.1f%% used, within %s points of the stop line of %s%%. Finish the item in hand, then finish the run\n", u, w, s
  } else {
    print "verdict=go"
    if (h > 0) printf "reason=%.1f%% used, %.1f points to the stop line, weekly reset in %.1f hours\n", u, s - u, h
    else printf "reason=%.1f%% used, %.1f points to the stop line\n", u, s - u
  }
}'
