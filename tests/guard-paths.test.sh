#!/usr/bin/env bash
# Synthetic hook inputs only: none of the requested writes are executed.
set -u
here=$(cd "$(dirname "$0")" && pwd)
guard=${GUARD:-"$here/../skills/burn-my-usage/scripts/guard.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
mkdir -p "$tmp/code" "$BURN_MY_USAGE_HOME/active" "$BURN_MY_USAGE_HOME/runs"
printf 'active\n' >"$BURN_MY_USAGE_HOME/active/path-check"
printf '%s\n' "$tmp/code" >"$BURN_MY_USAGE_HOME/roots.txt"
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}' "$(date +%s)" "$(($(date +%s) + 86400))" >"$BURN_MY_USAGE_HOME/usage.json"
pass=0 fail=0
escape(){ local text=$1; text=${text//\\/\\\\}; text=${text//\"/\\\"}; printf '%s' "$text"; }
check(){
  local expected=$1 label=$2 tool=$3 key=$4 value=$5 output
  output=$(printf '{"session_id":"path-check","cwd":"%s","tool_name":"%s","tool_input":{"%s":"%s","content":"synthetic"}}' "$(escape "$tmp")" "$tool" "$key" "$(escape "$value")" | bash "$guard")
  case "$expected:$output" in
    deny:*'"permissionDecision":"deny"'*|allow:) pass=$((pass+1)) ;;
    *) printf 'FAIL %s\n' "$label"; fail=$((fail+1)) ;;
  esac
}
check deny 'file path cannot traverse into controls' Write file_path "$BURN_MY_USAGE_HOME/runs/../config.md"
check deny 'redirect cannot traverse into controls' Bash command "echo synthetic > \"$BURN_MY_USAGE_HOME/runs/../config.md\""
check deny 'file path cannot traverse out of an allowed prefix' Write file_path "$tmp/code/../../../../guard-outside.txt"
check deny 'redirect cannot traverse out of an allowed prefix' Bash command "echo synthetic > \"$tmp/code/../../../../guard-outside.txt\""
check allow 'canonical run log remains writable' Write file_path "$BURN_MY_USAGE_HOME/runs/log.md"
check allow 'reading config does not require write permission' Read file_path "$BURN_MY_USAGE_HOME/runs/../config.md"
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
