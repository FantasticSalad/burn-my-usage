#!/usr/bin/env bash
# Synthetic hook inputs only; no HTTP command is executed.
set -u
here=$(cd "$(dirname "$0")" && pwd)
guard=${GUARD:-"$here/../skills/burn-my-usage/scripts/guard.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
mkdir -p "$BURN_MY_USAGE_HOME/active"
touch "$BURN_MY_USAGE_HOME/active/network-check"
pass=0 fail=0
check(){
  local expected=$1 command=$2 output
  output=$(printf '{"session_id":"network-check","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$tmp" "$command" | bash "$guard")
  case "$expected:$output" in
    deny:*'"permissionDecision":"deny"'*|allow:) pass=$((pass+1)) ;;
    *) printf 'FAIL %s\n' "$command"; fail=$((fail+1)) ;;
  esac
}
check deny 'curl -XPOST https://example.com'
check deny 'curl -dsynthetic https://example.com'
check deny 'curl -Ffield=synthetic https://example.com'
check deny 'curl -Tsynthetic.txt https://example.com'
check deny 'curl --request=POST https://example.com'
check deny 'curl --method=POST https://example.com'
check deny 'curl -X GET -X POST https://example.com'
check deny 'curl -X GET --data=synthetic https://example.com'
check deny 'curl -sSXPOST https://example.com'
check deny 'curl -fsSdsynthetic https://example.com'
check allow 'curl -XGET https://example.com'
check allow 'curl --request=GET https://example.com'
check allow 'curl -xhttp://proxy:8080 -Dheaders.txt https://example.com'
check allow 'curl -f https://example.com'
check allow 'curl -sSXGET https://example.com'
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
