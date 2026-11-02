#!/usr/bin/env bash
# End-to-end test: a real, headless burn run on two throwaway repos, then checks on what it
# left behind. It calls the model, so it uses plan usage (about 40 turns) and isn't part of
# run-all.sh or CI. Run it by hand after changing SKILL.md, the scripts or the guard.
#
#   bash tests/e2e/run.sh            # needs `claude` on PATH, signed in, and node
#   CLAUDE=/path/to/claude bash tests/e2e/run.sh
#   KEEP=1 bash tests/e2e/run.sh     # keep the workspace to look at afterwards
#
# The workspace:
#   code/csvkit  a small Node module whose toCsv doesn't quote commas; the wishlist asks for
#                RFC 4180 quoting
#   code/notes   a repo with an untracked file: the user's work in progress
#   home/        the burn home: config, roots, wishlist, an empty inbox
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
claude=${CLAUDE:-claude}
fixture="$here/fixture"
ws=$(mktemp -d)
preserve=${KEEP:-0}
cleanup() {
  if [ "$preserve" = 1 ]; then echo "fixture retained: $(native "$ws")"; else rm -rf "$ws"; fi
}
trap cleanup EXIT

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
g() { git -c user.name=Fixture -c user.email=fixture@example.com -c init.defaultBranch=main -c core.autocrlf=false "$@"; }

mkdir -p "$ws/code" "$ws/home"
cp -r "$fixture/csvkit" "$ws/code/csvkit"
g -C "$ws/code/csvkit" init -q
g -C "$ws/code/csvkit" add -A
g -C "$ws/code/csvkit" commit -q -m "csvkit: first version"
main_before=$(git -C "$ws/code/csvkit" rev-parse main)

mkdir -p "$ws/code/notes"
cp "$fixture/csvkit/README.md" "$ws/code/notes/notes.md"
g -C "$ws/code/notes" init -q
g -C "$ws/code/notes" add -A
g -C "$ws/code/notes" commit -q -m notes
notes_before=$(git -C "$ws/code/notes" rev-parse HEAD)
cp "$fixture/wishlist.md" "$ws/code/notes/half-written.md"

code=$(native "$ws/code")
home=$(native "$ws/home")
cp "$repo/skills/burn-my-usage/templates/INBOX.md" "$repo/skills/burn-my-usage/templates/lessons.md" "$ws/home/"
cp "$fixture/wishlist.md" "$fixture/recurring.md" "$ws/home/"
sed "s#__CODE__#$code#" "$fixture/config.md" >"$ws/home/config.md"
printf '%s\n' "$code" >"$ws/home/roots.txt"

# Synthetic pacing sample for this bounded fixture; not real account usage.
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}' "$(date +%s)" "$(($(date +%s) + 86400))" >"$ws/home/usage.json"
echo "workspace: $(native "$ws")"
echo "running the burn (this takes several minutes)..."
(
  cd "$ws/code" &&
    BURN_MY_USAGE_HOME="$home" "$claude" -p "/burn-my-usage:burn-my-usage" \
      --plugin-dir "$(native "$repo")" \
      --permission-mode auto --max-turns 60 --max-budget-usd 3 \
      --add-dir "$home" \
      --setting-sources project,local \
      --output-format stream-json --verbose \
      --append-system-prompt "This is an automated end-to-end test of the burn-my-usage plugin, run headless. Work only on the repositories under $code and the burn home $home. Follow host safety controls; this fixture is not permission to access other repositories." \
      >"$ws/run.jsonl" 2>"$ws/run.err"
)
claude_status=$?
echo "claude exited $claude_status"
node "$here/result.mjs" "$ws/run.jsonl"
[ "$claude_status" = 0 ] || preserve=1

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

csv="$ws/code/csvkit"
branch=$(git -C "$csv" for-each-ref --format='%(refname:short)' 'refs/heads/burn/*' | head -n 1)
check "a burn/ branch was made" '[ -n "$branch" ]'
check "main is unchanged" '[ "$(git -C "$csv" rev-parse main)" = "$main_before" ]'
check "the repo is back on main" '[ "$(git -C "$csv" symbolic-ref --short HEAD)" = main ]'
check "nothing uncommitted left in csvkit" '[ -z "$(git -C "$csv" status --porcelain)" ]'
check "notes: history unchanged" '[ "$(git -C "$ws/code/notes" rev-parse HEAD)" = "$notes_before" ]'
check "notes: the untracked file is still there" '[ -f "$ws/code/notes/half-written.md" ]'
if [ -n "$branch" ]; then
  wt="$ws/wt"
  git -C "$csv" worktree add -q --detach "$wt" "$branch" || { echo "FAIL verification worktree could not be created"; exit 1; }
  check "the branch's tests pass" '(cd "$wt" && node --test >/dev/null 2>&1)'
  # Its tests on main's code: they should fail.
  git -C "$wt" show "main:src/csv.js" >"$ws/old-csv.js"
  cp "$ws/old-csv.js" "$wt/src/csv.js"
  check "the branch's tests fail on main's code" '! (cd "$wt" && node --test >/dev/null 2>&1)'
  git -C "$csv" worktree remove --force "$wt" 2>/dev/null
  check "the inbox has a card for the branch" 'grep -q "$branch" "$ws/home/INBOX.md"'
fi
check "no box in the inbox is ticked" '! grep -qE "\[[xX]\]" "$ws/home/INBOX.md"'
check "the guard self-test refused" 'grep -q "self-test OK" "$ws/home/guard.log"'
check "all owned item worktrees were saved" '[ -z "$(find "$ws/home/owned" -type f 2>/dev/null)" ]'
check "the run stopped its guard" '[ -z "$(ls -A "$ws/home/active" 2>/dev/null)" ]'
check "a run log was written" 'ls "$ws"/home/runs/*/log.md >/dev/null 2>&1'
check "nothing written beside code/ and home/" '[ -z "$(ls -A "$ws" | grep -vxE "code|home|old-csv\.js|run\.err|run\.jsonl|wt")" ]'

refusals=$(grep -vc "self-test OK" "$ws/home/guard.log" 2>/dev/null)
printf '\nguard refusals besides the self-test: %s (each one is worth reading)\n' "${refusals:-0}"
[ "${refusals:-0}" = 0 ] || grep -v "self-test OK" "$ws/home/guard.log" | cut -f3-
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ] || preserve=1
[ "$fail" = 0 ]
