#!/usr/bin/env bash
# Status line command that records your plan's usage for burn runs.
#
# Claude Code passes the status line command a JSON blob on every update, and for Pro and Max
# subscribers it includes rate_limits: the 5-hour and 7-day windows, each with
# used_percentage and resets_at. This saves that one object to <burn home>/usage.json, which
# is how a run knows how much of the week is left. Nothing else from the blob is kept.
#
# Then it prints a status line: your own, if setup saved your previous status line command in
# <burn home>/statusline-next, or a short default.
#
# setup copies this file to <burn home>/bin/ and points statusLine at the copy, because the
# plugin's own folder moves when the plugin updates.
set -u
home=${BURN_MY_USAGE_HOME:-$HOME/.burn-my-usage}
IFS= read -r -d '' input || true

# rate_limits holds objects one level deep: five_hour, seven_day, and sometimes spend_limit.
re='"rate_limits"[[:space:]]*:[[:space:]]*(\{([^{}]|\{[^{}]*\})*\})'
if [[ $input =~ $re ]]; then
  rl=${BASH_REMATCH[1]}
  if mkdir -p "$home" 2>/dev/null; then
    now=$(date +%s)
    tmp="$home/.usage.json.$$"
    printf '{"captured_at":%s,"rate_limits":%s}\n' "$now" "$rl" >"$tmp" && mv -f "$tmp" "$home/usage.json"
  fi
fi

if [ -s "$home/statusline-next" ]; then
  next=$(cat "$home/statusline-next")
  printf '%s' "$input" | bash -c "$next"
  exit 0
fi

pct() { # window name -> rounded used_percentage, or nothing
  local r="\"$1\"[[:space:]]*:[[:space:]]*\{[^}]*\"used_percentage\"[[:space:]]*:[[:space:]]*([0-9.]+)"
  [[ ${rl:-} =~ $r ]] && printf '%.0f' "${BASH_REMATCH[1]}"
}
week=$(pct seven_day)
five=$(pct five_hour)
line=""
[ -n "$week" ] && line="7d ${week}%"
[ -n "$five" ] && line="${line:+$line · }5h ${five}%"
for f in "$home"/active/*; do
  if [ -f "$f" ]; then
    line="${line:+$line · }burn run active"
    break
  fi
done
printf '%s\n' "${line:-burn-my-usage: no plan usage data yet}"
