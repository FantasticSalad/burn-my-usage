#!/usr/bin/env bash
# Behavioral checks on synthetic repositories only.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
s="$here/../skills/burn-my-usage/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
unset CLAUDE_CODE_SESSION_ID
mkdir -p "$tmp/code/app" "$tmp/home/active"
g() { git -c user.name=Fixture -c user.email=fixture@example.com -c init.defaultBranch=main "$@"; }
repo="$tmp/code/app"
g -C "$repo" init -q
printf 'original\n' >"$repo/source.txt"
g -C "$repo" add source.txt
g -C "$repo" commit -qm initial
before=$(git -C "$repo" rev-parse HEAD)
printf 'user work\n' >"$repo/unfinished.txt"
printf '%s\n' "$tmp/code" >"$tmp/home/roots.txt"
now=$(date +%s)
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":%s}}}\n' "$now" "$((now+3600))" >"$tmp/home/usage.json"
touch "$tmp/home/active/one" "$tmp/home/active/two"
mkdir "$tmp/home/run.lock"
printf 'claude-code\none\none\n' >"$tmp/home/run.lock/owner"
pass=0
assert() { if eval "$2"; then pass=$((pass + 1)); else echo "FAIL $1"; exit 1; fi; }
out=$(bash "$s/work-item.sh" start one "$repo" repair)
wt=$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')
assert "linked worktree created" '[ -f "$wt/.git" ]'
assert "original branch remains main" '[ "$(git -C "$repo" symbolic-ref --short HEAD)" = main ]'
assert "user uncommitted file untouched" '[ "$(cat "$repo/unfinished.txt")" = "user work" ]'
assert "start is idempotent for owner" 'bash "$s/work-item.sh" start one "$repo" repair | grep -q WORKTREE'
assert "another session cannot finish" '! bash "$s/work-item.sh" finish two "$repo" repair >/dev/null 2>&1'
printf 'new behavior\n' >>"$wt/source.txt"
g -C "$wt" add source.txt
assert "ordinary staged source passes" 'bash "$s/leak-check.sh" "$wt"'
assert "dirty worktree cannot finish" '! bash "$s/work-item.sh" finish one "$repo" repair >/dev/null 2>&1'
# Fake credential generated at runtime, never a real account value.
printf '%s%s\n' ghp_ AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA >"$wt/fake.txt"
g -C "$wt" add fake.txt
set +e
hits=$(bash "$s/leak-check.sh" "$wt"); rc=$?
set -e
assert "synthetic token blocks commit" '[ "$rc" = 1 ]'
assert "report names location" 'case "$hits" in *fake.txt:1:*) true ;; *) false ;; esac'
assert "report never echoes matching value" 'case "$hits" in *AAAAAAAA*) false ;; *) true ;; esac'
printf 'synthetic placeholder\n' >"$wt/fake.txt"
g -C "$wt" add fake.txt
assert "replacement is clean" 'bash "$s/leak-check.sh" "$wt"'
assert "missing repository fails closed" '! bash "$s/leak-check.sh" "$tmp/missing" >/dev/null 2>&1'
g -C "$wt" commit -qm repair
out=$(bash "$s/work-item.sh" finish one "$repo" repair)
assert "verified backup produced" 'case "$out" in *BACKUP=*) true ;; *) false ;; esac'
assert "clean owned worktree removed" '[ ! -e "$wt" ]'
assert "default history unchanged" '[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]'
assert "branch retained" 'git -C "$repo" rev-parse --verify "burn/$(date +%Y-%m-%d)-repair" >/dev/null'
assert "handoff records tip and backup" 'grep -q "State: saved" "$tmp/home/handoffs/app/one-repair.md"'
assert "scope escape refused" '! bash "$s/work-item.sh" start one "$repo/../.." escape >/dev/null 2>&1'
branch="burn/$(date +%Y-%m-%d)-repair"
printf 'claude-code\ntwo\ntwo\n' >"$tmp/home/run.lock/owner"
out=$(bash "$s/work-item.sh" resume two "$repo" repair "$branch")
wt=$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')
assert "approved existing branch can resume in another session" '[ -f "$wt/.git" ]'
bash "$s/work-item.sh" finish two "$repo" repair >/dev/null
assert "resume preserves original default history" '[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]'
# A bare repository name is found under the roots, from any folder.
printf 'claude-code\none\none\n' >"$tmp/home/run.lock/owner"
out=$(cd "$tmp" && bash "$s/work-item.sh" start one app byname)
wt=$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')
assert "a bare repository name is found under the roots" '[ -f "$wt/.git" ]'
assert "the bare name finishes too" '(cd "$tmp" && bash "$s/work-item.sh" finish one app byname >/dev/null)'
set +e
err=$(cd "$tmp" && bash "$s/work-item.sh" start one missing nothing 2>&1)
set -e
assert "an unknown name says to pass the path" 'case "$err" in *roots.txt*path*) true ;; *) false ;; esac'
g -C "$tmp/code" init -q "group/app"
set +e
err=$(cd "$tmp" && bash "$s/work-item.sh" start one app twice 2>&1)
set -e
assert "an ambiguous name lists the candidates" 'case "$err" in *"more than one"*group/app*) true ;; *) false ;; esac'
assert "an ambiguous name creates nothing" '[ ! -e "$tmp/home/owned/one/app-twice" ]'
# A repository with an origin: the item starts from origin's default branch, but must not
# track it, or a bare git push from the worktree would aim at the default branch.
g clone -q "$repo" "$tmp/code/cloned"
out=$(bash "$s/work-item.sh" start one "$tmp/code/cloned" upstream)
wt=$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')
assert "item from origin's default has a worktree" '[ -f "$wt/.git" ]'
assert "item starts at origin's default" '[ "$(git -C "$wt" rev-parse HEAD)" = "$before" ]'
assert "new burn branch has no upstream" '! git -C "$wt" rev-parse -q --verify "@{upstream}" >/dev/null 2>&1'
printf '%d passed, 0 failed\n' "$pass"
