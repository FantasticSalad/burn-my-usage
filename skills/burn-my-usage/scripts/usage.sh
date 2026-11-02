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

stop_at=$(config_value stop_at 90)
if [ "${1:-}" = --stop-at ] && [ -n "${2:-}" ]; then stop_at=$2; fi
stop_at=${stop_at%\%}
if ! awk -v n="$stop_at" 'BEGIN { exit !(n ~ /^[0-9]+([.][0-9]+)?$/ && n > 0 && n < 100) }'; then
  echo "verdict=unknown"
  echo "reason=stop_at must be greater than zero and below 100"
  exit 0
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

age_min=$(( (now - ${captured:-0}) / 60 ))
echo "age_minutes=$age_min"
[ -n "$week" ] && echo "weekly_used=$week"
[ -n "$week_reset" ] && echo "weekly_resets_in_hours=$(awk -v a="$week_reset" -v n="$now" 'BEGIN { printf "%.1f", (a - n) / 3600 }')"
[ -n "$five" ] && echo "five_hour_used=$five"
[ -n "$five_reset" ] && echo "five_hour_resets_in_minutes=$(( (five_reset - now) / 60 ))"
[ -n "$spend" ] && echo "spend_used=$spend"

# The window that is closest to the stop line decides.
used=$(awk -v a="${week:-}" -v b="${spend:-}" 'BEGIN { m = -1; if (a != "") m = a + 0; if (b != "" && b + 0 > m) m = b + 0; print m }')

if [ "$age_min" -lt 0 ] || [ "$age_min" -gt 60 ]; then
  echo "verdict=unknown"
  echo "reason=usage data is $age_min minutes old. The status line only updates in interactive sessions, so a claude -p run never refreshes it"
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

awk -v u="$used" -v s="$stop_at" -v h="$(awk -v a="${week_reset:-0}" -v n="$now" 'BEGIN { printf "%.1f", (a - n) / 3600 }')" 'BEGIN {
  if (u >= s) {
    print "verdict=stop"
    printf "reason=%.1f%% used, at or past the stop line of %s%%\n", u, s
  } else if (u >= s - 5) {
    print "verdict=wrap"
    printf "reason=%.1f%% used, within 5 points of the stop line of %s%%. Finish the item in hand, then finish the run\n", u, s
  } else {
    print "verdict=go"
    if (h > 0) printf "reason=%.1f%% used, %.1f points to the stop line, weekly reset in %.1f hours\n", u, s - u, h
    else printf "reason=%.1f%% used, %.1f points to the stop line\n", u, s - u
  }
}'
