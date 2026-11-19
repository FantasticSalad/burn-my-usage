#!/usr/bin/env bash
# A run must be able to finish and stop when a worktree folder can't be removed (F18 in
# the new-user review). Synthetic repositories only.
#   bash tests/recovery.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
s="$here/../skills/burn-my-usage/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset CLAUDE_CODE_SESSION_ID BMU_HOST BMU_SESSION_ID
mkdir -p "$tmp/code/app"
# Each section gets its own burn home, so one failure doesn't hold the next run's lock.
new_home() {
  home="$tmp/home-$1"
  export BURN_MY_USAGE_HOME="$home"
  mkdir -p "$home"
  printf 'synthetic config\n' >"$home/config.md"
  printf '%s\n' "$tmp/code" >"$home/roots.txt"
  local now=$(date +%s)
  printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":%s}}}\n' "$now" "$((now+3600))" >"$home/usage.json"
}
g() { git -c user.name=Fixture -c user.email=fixture@example.com -c init.defaultBranch=main "$@"; }
repo="$tmp/code/app"
g -C "$repo" init -q
printf 'original\n' >"$repo/source.txt"
g -C "$repo" add source.txt
g -C "$repo" commit -qm initial

# A git that fails `worktree remove` the way OneDrive did.
REAL_GIT=$(command -v git)
export REAL_GIT
mkdir -p "$tmp/shim"
cp "$here/fixtures/git-remove-fails.sh" "$tmp/shim/git"
chmod +x "$tmp/shim/git"
locked() { PATH="$tmp/shim:$PATH" "$@"; }

pass=0
fail=0
check() { # label, condition
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; fi
}

# Run from the temp folder: a git command given an empty path then acts on the fixture, never
# on the checkout running these tests.
cd "$tmp" || exit 1

# Makes a committed item in session $1, slug $2; sets $wt. Stops the whole test if the
# fixture can't be made, so no later step runs on an empty path.
make_item() {
  local out
  out=$(bash "$s/work-item.sh" start "$1" "$repo" "$2")
  wt=$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')
  case "$wt" in "" | /) echo "FAIL could not create fixture item $2" >&2; exit 1 ;; esac
  printf '%s\n' "$2" >>"$wt/source.txt"
  g -C "$wt" add source.txt
  g -C "$wt" commit -qm "$2"
}

# --- finish saves the item even when the folder can't be removed ---------------------------
new_home a
bash "$s/start.sh" sess-a >/dev/null
make_item sess-a stuck
out=$(locked bash "$s/work-item.sh" finish sess-a "$repo" stuck 2>&1); rc=$?
check "finish succeeds once the backup verifies" '[ "$rc" = 0 ]'
check "finish reports the saved tip" '[[ $out == *SAVED=* && $out == *BACKUP=* ]]'
check "finish reports the leftover folder" '[[ $out == *LEFTOVER=* ]]'
check "the leftover folder is really there" '[ -d "$wt" ]'
check "the owner record is released" '[ ! -e "$home/owned/sess-a/app-stuck" ]'
check "the handoff says saved" 'grep -q "State: saved" "$home/handoffs/app/sess-a-stuck.md"'
check "the handoff names the leftover folder" 'grep -q "^Leftover: " "$home/handoffs/app/sess-a-stuck.md"'
check "the branch is retained" 'git -C "$repo" rev-parse --verify -q "burn/$(date +%Y-%m-%d)-stuck" >/dev/null'
out=$(bash "$s/stop.sh" sess-a 2>&1)
check "the run then stops normally" '[[ $out == *STOPPED* ]]'
check "the guard marker is gone" '[ ! -e "$home/active/sess-a" ]'
rm -rf "$wt"

# --- stop can release a record left by an older version ------------------------------------
# Older versions exited before releasing the record, leaving a folder git no longer knows.
new_home b
bash "$s/start.sh" sess-b >/dev/null
make_item sess-b orphan
orphan_wt=$wt
admin=$(git -C "$wt" rev-parse --absolute-git-dir)
case "$admin" in */code/app/.git/worktrees/?*) rm -rf "$admin" ;; *) echo "FAIL unexpected admin folder $admin" >&2; exit 1 ;; esac
make_item sess-b live
live_wt=$wt
out=$(bash "$s/stop.sh" sess-b 2>&1); rc=$?
check "plain stop still refuses" '[ "$rc" = 2 ] && [[ $out == *WORK_REMAINS* ]]'
check "plain stop names the recovery option" '[[ $out == *--release-orphans* ]]'
out=$(bash "$s/stop.sh" --release-orphans sess-b 2>&1); rc=$?
check "a live owned worktree still blocks release" '[ "$rc" = 2 ] && [[ $out == *WORK_REMAINS* ]]'
check "nothing is released while live work remains" '[ -f "$home/owned/sess-b/app-orphan" ] && [ -f "$home/owned/sess-b/app-live" ]'
check "the guard stays on while live work remains" '[ -e "$home/active/sess-b" ]'
bash "$s/work-item.sh" finish sess-b "$repo" live >/dev/null
out=$(bash "$s/stop.sh" --release-orphans sess-b 2>&1); rc=$?
check "release-orphans stops the run" '[ "$rc" = 0 ] && [[ $out == *STOPPED* ]]'
check "release-orphans names what it released" '[[ $out == *RELEASED=app-orphan* ]]'
check "the orphan record is gone" '[ ! -e "$home/owned/sess-b/app-orphan" ]'
check "the orphan folder is left for the user" '[ -d "$orphan_wt" ]'
check "the guard marker is gone after release" '[ ! -e "$home/active/sess-b" ]'
check "the live item was saved normally" '[ ! -e "$live_wt" ]'
rm -rf "$orphan_wt"

# --- a record pointing inside another repository is not mistaken for a live worktree -------
new_home c
bash "$s/start.sh" sess-c >/dev/null
mkdir -p "$home/owned/sess-c" "$repo/sub"
printf '%s\n' "$repo/sub" >"$home/owned/sess-c/app-inner"
out=$(bash "$s/stop.sh" --release-orphans sess-c 2>&1)
check "a folder inside another repository counts as orphaned" '[[ $out == *STOPPED* ]]'

# --- an unknown option is an error, not a session id ---------------------------------------
new_home d
bash "$s/start.sh" sess-d >/dev/null
out=$(bash "$s/stop.sh" --release-everything sess-d 2>&1); rc=$?
check "an unknown option is refused" '[ "$rc" = 2 ] && [ -e "$home/active/sess-d" ]'
bash "$s/stop.sh" sess-d >/dev/null

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
