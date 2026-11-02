#!/usr/bin/env bash
# Hook decisions only: git push is never executed.
set -u
here=$(cd "$(dirname "$0")" && pwd)
guard=${GUARD:-"$here/../skills/burn-my-usage/scripts/guard.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
mkdir -p "$tmp/app" "$tmp/mock" "$BURN_MY_USAGE_HOME/active"
cp "$here/fixtures/mock-gh.sh" "$tmp/mock/gh"
chmod +x "$tmp/mock/gh"
export PATH="$tmp/mock:$PATH"
printf 'active\n' >"$BURN_MY_USAGE_HOME/active/push-check"
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}' "$(date +%s)" "$(($(date +%s) + 86400))" >"$BURN_MY_USAGE_HOME/usage.json"
git -C "$tmp/app" init -q
git -C "$tmp/app" remote add origin https://github.com/example/private.git
pass=0 fail=0
check(){
  local expected=$1 label=$2 output
  printf 'push_branches: %s\n' "$3" >"$BURN_MY_USAGE_HOME/config.md"
  output=$(printf '{"session_id":"push-check","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push origin burn/synthetic"}}' "$tmp/app" | bash "$guard")
  case "$expected:$output" in
    deny:*'"permissionDecision":"deny"'*|allow:) pass=$((pass+1)) ;;
    *) printf 'FAIL %s\n' "$label"; fail=$((fail+1)) ;;
  esac
}
check allow 'single private origin' private
git -C "$tmp/app" config --add remote.origin.pushurl https://github.com/example/private.git
git -C "$tmp/app" config --add remote.origin.pushurl https://github.com/example/public.git
check deny 'private policy refuses multiple destinations' private
git -C "$tmp/app" config --unset-all remote.origin.pushurl
git -C "$tmp/app" remote set-url origin https://github.com/example/public.git
check deny 'private policy refuses public origin' private
check allow 'explicit all policy permits one public origin' all
git -C "$tmp/app" config --add remote.origin.pushurl https://github.com/example/public.git
git -C "$tmp/app" config --add remote.origin.pushurl https://github.com/example/private.git
check deny 'all policy still requires one destination' all
check deny 'never policy refuses push' never
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
