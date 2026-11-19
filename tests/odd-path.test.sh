#!/usr/bin/env bash
# The scripts must work from a folder whose path has a space and an apostrophe, as Windows
# profile folders often do (F19 in the new-user review). Git Bash doesn't convert such a
# path for a native program like Node, which then reads /c/Users/... as C:\c\Users\...
# Synthetic data only.
#   bash tests/odd-path.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if ! command -v node >/dev/null 2>&1; then
  echo "SKIP odd-path checks: Node 18+ is not installed"
  exit 0
fi
odd="$tmp/o'brien dir"
mkdir -p "$odd/home"
cp -R "$here/../skills/burn-my-usage/scripts" "$odd/scripts"
unset CLAUDE_CODE_SESSION_ID BMU_SESSION_ID
export BURN_MY_USAGE_HOME="$odd/home" BMU_HOST=codex
fail=0
check() { if ! eval "$2"; then echo "FAIL: $1"; fail=$((fail + 1)); fi; }
now=$(date +%s)
# Store a snapshot through the copied script, giving Node paths it can read on any platform.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
# The live quota path must use a synthetic client, never a real account in an offline test.
export BMU_CODEX_BIN=$(node -p 'process.execPath')
export NODE_OPTIONS="--require=\"$(native "$here/fixtures/codex-quota-server.cjs")\""
printf '{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":5,"windowDurationMins":10080,"resetsAt":%s},"secondary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":%s}}}}' "$((now + 3600))" "$((now + 1800))" |
  BURN_MY_USAGE_HOME=$(native "$odd/home") node "$(native "$odd/scripts/usage-codex.mjs")" ingest >/dev/null
check 'the snapshot was stored' '[ -f "$odd/home/usage/codex.json" ]'
out=$(bash "$odd/scripts/usage.sh" 2>&1)
check 'usage.sh refreshes Codex usage from a path with a space and an apostrophe' '[[ $out == *verdict=go* ]]'
check 'Node found the script' '[[ $out != *"Cannot find module"* ]]'
[ "$fail" = 0 ] || printf '%s\n' "$out"

# git is a native program too. Below, every path is the Git Bash form (/tmp/..., or $HOME as
# /c/Users/...), which is what a user's ~/code root or default burn home looks like.
unset BMU_HOST
g() { git -c user.name=Fixture -c user.email=fixture@example.com -c init.defaultBranch=main "$@"; }
code="$odd/code"
mkdir -p "$code/app"
g -C "$(native "$code/app")" init -q
printf 'x\n' >"$code/app/a.txt"
g -C "$(native "$code/app")" add a.txt
g -C "$(native "$code/app")" commit -qm one

out=$(bash "$odd/scripts/repo-check.sh" --no-fetch "$code" 2>&1)
check 'repo-check reads a repo under a root with an apostrophe' '[[ $out == *"app "*main*main* && $out != *fatal* ]]'

# The default burn home, under a profile folder with an apostrophe.
unset BURN_MY_USAGE_HOME
export HOME="$odd/profile"
mkdir -p "$HOME/.burn-my-usage/active"
printf '%s\n' "$code" >"$HOME/.burn-my-usage/roots.txt"
: >"$HOME/.burn-my-usage/active/odd"
mkdir "$HOME/.burn-my-usage/run.lock"
printf 'claude-code\nodd\nodd\n' >"$HOME/.burn-my-usage/run.lock/owner"
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":%s}}}\n' "$now" "$((now+3600))" >"$HOME/.burn-my-usage/usage.json"
out=$(bash "$odd/scripts/work-item.sh" start odd "$code/app" probe 2>&1)
check 'the item worktree is created inside the default burn home' '[ -f "$HOME/.burn-my-usage/worktrees/odd/app-probe/.git" ]'
wt=$(git -C "$(native "$code/app")" worktree list --porcelain | sed -n 's/^worktree //p' | grep probe)
check 'git agrees where the worktree is' '[[ $wt == *"o'"'"'brien dir/profile/.burn-my-usage/worktrees/odd/app-probe" ]]'
[ -z "$wt" ] || git -C "$(native "$code/app")" worktree remove --force "$wt" >/dev/null 2>&1

# start.sh names the commit when it runs from a git checkout of the plugin.
plug="$odd/plug"
mkdir -p "$plug/.claude-plugin" "$plug/skills/burn-my-usage"
cp -R "$odd/scripts" "$plug/skills/burn-my-usage/scripts"
printf '{"name":"synthetic","version":"9.9.9"}\n' >"$plug/.claude-plugin/plugin.json"
g -C "$(native "$plug")" init -q
g -C "$(native "$plug")" add -A
g -C "$(native "$plug")" commit -qm plug
out=$(bash "$plug/skills/burn-my-usage/scripts/start.sh" --paths 2>&1)
check 'start.sh reads the commit from a checkout with an apostrophe in its path' '[[ $out == *VERSION=9.9.9* && $out == *COMMIT=* ]]'

echo "odd-path failures: $fail"
[ "$fail" = 0 ]
