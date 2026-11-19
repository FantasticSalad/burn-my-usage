#!/usr/bin/env bash
# Quoted paths with spaces and apostrophes (F15 in the new-user review). Windows profile
# folders often have both, and setup puts the burn home under the profile by default.
# Synthetic hook inputs only: none of the requested commands are executed.
#   bash tests/guard-quoting.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
guard=${GUARD:-"$here/../skills/burn-my-usage/scripts/guard.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home="$tmp/bmu o'brien home"
export BURN_MY_USAGE_HOME="$home"
mkdir -p "$tmp/code" "$home/active" "$home/runs" "$home/worktrees/sid/old"
printf 'active\n' >"$home/active/quoting"
# The guard's root check is lexical, so a root outside the temp folder (which is always
# writable) can be named without existing. Nothing is created there.
outer="/bmu-synthetic-root/it's my code"
printf '%s\n%s\n' "$tmp/code" "$outer" >"$home/roots.txt"
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}' "$(date +%s)" "$(($(date +%s) + 86400))" >"$home/usage.json"
pass=0 fail=0
escape() { local text=$1; text=${text//\\/\\\\}; text=${text//\"/\\\"}; printf '%s' "$text"; }
check() { # expected, label, shell command
  local output
  output=$(printf '{"session_id":"quoting","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$(escape "$tmp")" "$(escape "$3")" | bash "$guard")
  case "$1:$output" in
    deny:*'"permissionDecision":"deny"'* | allow:) pass=$((pass + 1)) ;;
    *) printf 'FAIL %s\n  %s\n' "$2" "$output"; fail=$((fail + 1)) ;;
  esac
}

# An apostrophe inside double quotes is part of the path.
check allow 'recursive delete inside the run worktrees, home with an apostrophe' "rm -rf \"$home/worktrees/sid/old\""
check allow 'the same, after cd into the home' "cd \"$home\" && rm -rf \"$home/worktrees/sid/old\""
check deny 'recursive delete outside the run folders is still refused' "rm -rf \"$outer/project\""
check deny 'a control file in the home is still protected from rm' "rm \"$home/config.md\""

# A quoted redirect target with spaces is one path, not its first word.
check allow 'redirect into a root with a space and an apostrophe' "echo x > \"$outer/notes.txt\""
check allow 'the same in a compound command' "cd \"$tmp/code\" && grep -E 'a|b' f; echo x > \"$outer/notes.txt\" 2>&1"
check allow 'attached redirect into the same root' "echo x >\"$outer/notes.txt\""
check deny 'redirect into a CI workflow under a folder with a space' "echo x > \"$tmp/code/my dir/.github/workflows/ci.yml\""
check deny 'attached redirect into the same CI workflow' "echo x >\"$tmp/code/my dir/.github/workflows/ci.yml\""
check deny 'single-quoted redirect into the same CI workflow' "echo x > '$tmp/code/my dir/.github/workflows/ci.yml'"
check deny 'appending redirect into agent settings under a folder with a space' "echo x >> \"$tmp/code/my dir/.claude/settings.json\""
check deny 'redirect outside the roots through a spaced path' "echo x > \"/bmu-synthetic-root/elsewhere dir/x.txt\""
check deny 'redirect still refuses parent traversal in a spaced path' "echo x > \"$outer/../../etc dir/x\""
check deny 'unbalanced quotes still expose a later redirect' "echo x > \"$outer/a b > $tmp/code/.github/workflows/ci.yml"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
