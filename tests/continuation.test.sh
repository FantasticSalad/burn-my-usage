#!/usr/bin/env bash
# Lifecycle decisions use a synthetic usage boundary; transport is tested separately.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$here/../skills/burn-my-usage/scripts" "$tmp/scripts"
s="$tmp/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'printf "verdict=%s\n" "$(cat "$BURN_MY_USAGE_HOME/verdict")"' >"$s/usage.sh"
export BURN_MY_USAGE_HOME="$tmp/home" BMU_HOST=codex BMU_SESSION_ID=owner
unset CLAUDE_CODE_SESSION_ID
mkdir -p "$tmp/home" "$tmp/code/app"
repo="$tmp/code/app"
g() { git -c user.name=Fixture -c user.email=fixture@example.com -c init.defaultBranch=main "$@"; }
g -C "$repo" init -q
printf 'source\n' >"$repo/source"
g -C "$repo" add source
g -C "$repo" commit -qm initial
printf '%s\n' "$tmp/code" >"$tmp/home/roots.txt"
printf 'config\n' >"$tmp/home/config.md"
pass=0
assert() { if eval "$2"; then pass=$((pass+1)); else echo "FAIL: $1"; exit 1; fi; }
bash "$s/start.sh" owner >/dev/null
mv "$tmp/home/run.lock/owner" "$tmp/owner.saved"
assert 'missing lock identity cannot start work' '! bash "$s/work-item.sh" start owner "$repo" blocked >/dev/null 2>&1 && [ ! -e "$tmp/home/owned" ]'
printf 'claude-code\nowner\nowner\n' >"$tmp/home/run.lock/owner"
assert 'mismatched host cannot start work' '! bash "$s/work-item.sh" start owner "$repo" blocked >/dev/null 2>&1 && [ ! -e "$tmp/home/owned" ]'
printf 'codex\nstranger\nstranger\n' >"$tmp/home/run.lock/owner"
assert 'mismatched session cannot start work' '! bash "$s/work-item.sh" start owner "$repo" blocked >/dev/null 2>&1 && [ ! -e "$tmp/home/owned" ]'
mv "$tmp/owner.saved" "$tmp/home/run.lock/owner"
for verdict in wrap stop unknown; do
  printf '%s\n' "$verdict" >"$tmp/home/verdict"
  assert "$verdict refuses new work" '! bash "$s/work-item.sh" start owner "$repo" blocked >/dev/null 2>&1'
  assert "$verdict creates no owner" '[ ! -e "$tmp/home/owned/codex/owner/app-blocked" ]'
done
printf 'go\n' >"$tmp/home/verdict"
out=$(bash "$s/work-item.sh" start owner "$repo" repair)
wt=$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')
assert 'go starts work' '[ -f "$wt/.git" ]'
printf 'stop\n' >"$tmp/home/verdict"
assert 'stop preserves existing owner for recovery' 'bash "$s/work-item.sh" start owner "$repo" repair | grep -q WORKTREE'
assert 'unrelated owner cannot finish' '! bash "$s/work-item.sh" finish stranger "$repo" repair >/dev/null 2>&1'
assert 'stop refuses unfinished work' '! bash "$s/stop.sh" owner >/dev/null 2>&1'
mv "$tmp/home/run.lock/owner" "$tmp/owner.saved"
assert 'missing lock cannot finish or recover existing work' '! bash "$s/work-item.sh" finish owner "$repo" repair >/dev/null 2>&1 && ! bash "$s/work-item.sh" start owner "$repo" repair >/dev/null 2>&1 && [ -f "$wt/.git" ] && [ -f "$tmp/home/owned/codex/owner/app-repair" ]'
mv "$tmp/owner.saved" "$tmp/home/run.lock/owner"
bash "$s/work-item.sh" finish owner "$repo" repair >/dev/null
assert 'handoff saved before ownership released' 'grep -q "State: saved" "$tmp/home/handoffs/app/codex/owner-repair.md" && [ ! -e "$tmp/home/owned/codex/owner/app-repair" ]'
# Inject lock removal failure after owner deletion and verify retry can recover.
rmdir() { case "$1" in */run.lock) return 1 ;; *) command rmdir "$@" ;; esac; }
export -f rmdir
assert 'failed lock removal retains owner and marker' '! bash "$s/stop.sh" owner >/dev/null 2>&1 && [ -f "$tmp/home/run.lock/owner" ] && [ -f "$tmp/home/active/codex/owner" ]'
unset -f rmdir
bash "$s/stop.sh" owner >/dev/null
assert 'same owner can retry release' '[ ! -e "$tmp/home/run.lock" ]'
printf '%d passed, 0 failed\n' "$pass"
