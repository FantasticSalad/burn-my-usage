#!/usr/bin/env bash
# Hooks for until-limit runs (start.sh --until-limit), which have no stop line and work until
# Claude Code's usage limit stops them. For clients whose status line doesn't refresh, such as
# the VS Code panel, where usage.sh would otherwise see no fresh usage data and stop the run.
#
#   StopFailure (matcher rate_limit): the usage limit ended a turn. If this session holds an
#     until-limit run, record when in <burn home>/limit-hit/<session id>. usage.sh then says
#     stop, and the guard tells the run once to wrap up.
#   UserPromptSubmit: the next turn after that (the user coming back, or Claude Code carrying
#     on by itself after the reset) gets told to save the item in hand and finish the run.
#
# Outside an until-limit run both cost one bash start and print nothing. The marker is one of
# the run's controls: the guard refuses the run's own writes to the limit-hit folder.
set -u
IFS= read -r -d '' input || true
# Every message in every session comes here: leave before any child process unless this
# session holds a run.
re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
[[ $input =~ $re ]] || exit 0
sid=${BASH_REMATCH[1]}
[ -f "${BURN_MY_USAGE_HOME:-$HOME/.burn-my-usage}/active/$sid" ] || exit 0
. "$(dirname "$0")/lib.sh"
[ "$BMU_HOST" = claude-code ] || exit 0

field() { # JSON string field -> REPLY, or ""
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  REPLY=""
  [[ $input =~ $re ]] && REPLY=${BASH_REMATCH[1]}
  return 0
}
# Only the session that holds an until-limit run.
grep -qx 'mode until-limit' "$BMU_HOME/active/$sid" 2>/dev/null || exit 0
field hook_event_name
event=$REPLY

case "$event" in
  StopFailure)
    # hooks.json registers this for the rate_limit matcher only, so every call is a limit.
    # The first hit counts: a message sent before the reset fails again and must not move it.
    [ -f "$BMU_HOME/limit-hit/$sid" ] && exit 0
    mkdir -p "$BMU_HOME/limit-hit" 2>/dev/null || exit 0
    printf '%s\n%s\n' "$(date +%s)" "$(date '+%Y-%m-%d %H:%M (UTC%z)')" >"$BMU_HOME/limit-hit/$sid" 2>/dev/null
    ;;
  UserPromptSubmit)
    [ -f "$BMU_HOME/limit-hit/$sid" ] || exit 0
    when=$(sed -n '2p' "$BMU_HOME/limit-hit/$sid")
    # The guard says this too, on the first tool call, unless this message already has.
    : >"$BMU_HOME/limit-hit/$sid.told" 2>/dev/null
    user="Burn run: the usage limit stopped it at ${when:-an unrecorded time}. It is wrapping up now: saving the item in hand and writing the report."
    agent="The usage limit stopped this until-limit burn run at ${when:-an unrecorded time}, so the run is over. Start nothing new. Commit the item in hand to its branch with WIP: in the message, update its card, then finish the run (workflow section 7) and report. Then answer the user's message, if it asked something."
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$user" "$agent"
    ;;
esac
exit 0
