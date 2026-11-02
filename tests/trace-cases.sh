#!/usr/bin/env bash
# Runs a few guard inputs under bash -x, for diagnosing a platform-specific test failure in CI
# (macOS has bash 3.2, which nobody here runs locally).
#   bash tests/trace-cases.sh
here=$(cd "$(dirname "$0")" && pwd)
guard="$here/../skills/burn-my-usage/scripts/guard.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
mkdir -p "$BURN_MY_USAGE_HOME/active"
touch "$BURN_MY_USAGE_HOME/active/s1"
printf -- '- [ ] Merge\n' >"$BURN_MY_USAGE_HOME/INBOX.md"

run() {
  printf '\n===== %s\n' "$1"
  printf '%s' "$2" | bash -x "$guard" 2>&1 | tail -n 60
}
run "Grep in ~/.aws (should deny)" "{\"session_id\":\"s1\",\"cwd\":\"/tmp\",\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"x\",\"path\":\"$HOME/.aws\"}}"
run "Edit ticks an inbox box (should deny)" "{\"session_id\":\"s1\",\"cwd\":\"/tmp\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$BURN_MY_USAGE_HOME/INBOX.md\",\"old_string\":\"- [ ] Merge\",\"new_string\":\"- [x] Merge\"}}"
