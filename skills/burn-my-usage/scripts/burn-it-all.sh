#!/usr/bin/env bash
# UserPromptSubmit hook: when the user types exactly BURN IT ALL, this session's burn run may
# use up to 100% of the weekly limit instead of stop_at. For this run only; stop.sh ends it.
#
# Only the user's own message reaches this hook, so a run can't arm it by claiming the user
# said yes. The marker it writes, <burn home>/burn-it-all/<session id>, is one of the run's
# controls: the guard refuses the run's own writes to it and any shell command naming this
# script. Typed when no run is active, it arms the next run started in this session within
# the hour (start.sh drops older arms).
#
# Every other message costs one bash start and a pattern match, and prints nothing.
set -u
IFS= read -r -d '' input || true
case "$input" in *'BURN IT ALL'*) ;; *) exit 0 ;; esac
. "$(dirname "$0")/lib.sh"

field() { # JSON string field -> REPLY, or ""
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  REPLY=""
  [[ $input =~ $re ]] && REPLY=${BASH_REMATCH[1]}
  return 0
}
field prompt
text=$REPLY
# The whole message, give or take spaces and a closing ! or ., and in capitals. A message that
# only mentions the phrase ("what does BURN IT ALL do?") is not the user saying it.
text=${text#"${text%%[![:space:]]*}"}
text=${text%"${text##*[![:space:]]}"}
text=${text%[.!]}
case "$text" in 'BURN IT ALL') ;; *) exit 0 ;; esac
field session_id
sid=$REPLY
valid_session "$sid" || exit 0
[ "$BMU_HOST" = claude-code ] || exit 0

mkdir -p "$BMU_HOME/burn-it-all" 2>/dev/null || exit 0
date +%s >"$BMU_HOME/burn-it-all/$sid" 2>/dev/null || exit 0

if [ -f "$(marker_dir)/$sid" ]; then
  user="BURN IT ALL: this run now goes to 100% of your weekly limit, for this run only. Make sure extra usage is off in claude.ai Settings > Usage, or you'll be billed past your limit."
  agent="The user typed BURN IT ALL. usage.sh now uses a 100% stop line for this run (stop_at=100, burn_it_all=on). Carry on with the run; tell the user in one line that it will go to 100% and to check extra usage is off."
else
  user="BURN IT ALL: the next run you start in this session (within the hour) goes to 100% of your weekly limit. Make sure extra usage is off in claude.ai Settings > Usage, or you'll be billed past your limit."
  agent="The user typed BURN IT ALL with no run active in this session. If the last run stopped at its line, start /burn-my-usage again: that run will use a 100% stop line."
fi
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$user" "$agent"
exit 0
