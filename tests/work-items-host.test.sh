#!/usr/bin/env bash
# Exercise the shared item lifecycle under the Codex identity without a model.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
s="$here/../skills/burn-my-usage/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$s" "$tmp/scripts"
s="$tmp/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'echo verdict=go' >"$s/usage.sh"
export BURN_MY_USAGE_HOME="$tmp/home" BMU_HOST=codex BMU_SESSION_ID=same
unset CLAUDE_CODE_SESSION_ID
mkdir -p "$tmp/code/app" "$tmp/home"
repo="$tmp/code/app"
g() { git -c user.name=Fixture -c user.email=fixture@example.com -c init.defaultBranch=main "$@"; }
g -C "$repo" init -q
printf 'original\n' >"$repo/source.txt"
g -C "$repo" add source.txt
g -C "$repo" commit -qm initial
before=$(git -C "$repo" rev-parse HEAD)
printf 'unfinished user work\n' >"$repo/unfinished.txt"
printf '%s\n' "$tmp/code" >"$tmp/home/roots.txt"
printf '%s\n' '- stop_at: 90' >"$tmp/home/config.md"
pass=0
assert() { if eval "$2"; then pass=$((pass + 1)); else echo "FAIL $1"; exit 1; fi; }
bash "$s/start.sh" same >/dev/null
out=$(bash "$s/work-item.sh" start same "$repo" repair)
wt=$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')
assert "Codex item uses a provider-owned path" '[ -f "$tmp/home/owned/codex/same/app-repair" ]'
assert "original checkout remains on main" '[ "$(git -C "$repo" symbolic-ref --short HEAD)" = main ]'
assert "original unfinished work is intact" '[ "$(cat "$repo/unfinished.txt")" = "unfinished user work" ]'
assert "a foreign Claude session cannot finish the item" '! BMU_HOST=claude-code bash "$s/work-item.sh" finish same "$repo" repair >/dev/null 2>&1'
assert "stop refuses to abandon a Codex item" '! bash "$s/stop.sh" same >/dev/null 2>&1'
assert "owner can find an already-owned item" 'bash "$s/work-item.sh" start same "$repo" repair | grep -q WORKTREE'
printf 'fixed behavior\n' >>"$wt/source.txt"
g -C "$wt" add source.txt
bash "$s/leak-check.sh" "$wt"
g -C "$wt" commit -qm repair
handoff="$tmp/home/handoffs/app/codex/same-repair.md"
mv "$handoff" "$handoff.saved"
mkdir "$handoff"
assert "failed handoff preserves owned worktree" '! bash "$s/work-item.sh" finish same "$repo" repair >/dev/null 2>&1 && [ -f "$wt/.git" ] && [ -f "$tmp/home/owned/codex/same/app-repair" ]'
rmdir "$handoff"
mv "$handoff.saved" "$handoff"
out=$(bash "$s/work-item.sh" finish same "$repo" repair)
assert "Codex item has a verified backup" 'case "$out" in *BACKUP=*) true ;; *) false ;; esac'
assert "Codex handoff is provider-scoped and saved" 'grep -q "State: saved" "$tmp/home/handoffs/app/codex/same-repair.md"'
assert "owned worktree is removed" '[ ! -e "$wt" ]'
assert "default history remains unchanged" '[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]'
assert "review branch remains available" 'git -C "$repo" rev-parse --verify "burn/$(date +%Y-%m-%d)-repair" >/dev/null'
bash "$s/stop.sh" same >/dev/null
assert "stop removes Codex marker and lock" '[ ! -e "$tmp/home/active/codex/same" ] && [ ! -e "$tmp/home/run.lock" ]'
# An unfinished legacy item is still owned by Claude even with an equal session id.
mkdir -p "$tmp/home/owned/same"
printf 'legacy item\n' >"$tmp/home/owned/same/app-legacy"
bash "$s/start.sh" same >/dev/null
assert "Codex does not adopt legacy ownership records" '! bash "$s/work-item.sh" finish same "$repo" legacy >/dev/null 2>&1'
bash "$s/stop.sh" same >/dev/null
assert "Codex stop preserves foreign ownership record" '[ -f "$tmp/home/owned/same/app-legacy" ]'
printf '%d passed, 0 failed\n' "$pass"
