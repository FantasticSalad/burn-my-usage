#!/usr/bin/env bash
# Start-of-run check over every git repository under the given folders. Read-only apart from
# `git fetch`. One line per repo, then every open burn/ branch.
#
#   bash repo-check.sh [--no-fetch] <folder>...
#
# Finds repositories up to two levels down (~/code/app and ~/code/org/app), skipping
# node_modules, vendor and hidden folders.
#
# NOTE column:
#   BEHIND       the local default branch is behind origin. Branch from origin/<default>, and
#                fast-forward the local one only if it has no commits of its own.
#   DIVERGED     the local default branch has commits origin lacks AND is behind. Someone's
#                work, or a sync tool rolled history back. Don't touch this repo; report it.
#   UNPUSHED     commits on the local default branch that origin lacks (the user's, not yours).
#   OFF-DEFAULT  the working copy is not on the default branch.
#   DIRTY        uncommitted changes. Never stage, stash or discard them; work in a worktree.
#   NO-REMOTE    no origin: branches stay local.
#   FETCH-FAILED could not reach origin; ahead/behind may be stale.
set -u

fetch=1
if [ "${1:-}" = --no-fetch ]; then
  fetch=0
  shift
fi
[ $# -gt 0 ] || set -- "$PWD"

now=$(date +%s)
printf '%-28s %-34s %-8s %-7s %-5s %-6s %s\n' REPO BRANCH DEFAULT 'AHD/BHD' DIRTY 'IDLE' NOTE
burns=""

check_repo() {
  local d=$1 name=$2 note="" def br ab ahead behind dirty last idle b state merged count age
  if [ "$fetch" = 1 ] && git -C "$d" remote get-url origin >/dev/null 2>&1; then
    git -C "$d" fetch -q --prune origin 2>/dev/null || note="FETCH-FAILED "
  fi
  if ! git -C "$d" remote get-url origin >/dev/null 2>&1; then note="${note}NO-REMOTE "; fi
  def=$(git -C "$d" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  def=${def#origin/}
  if [ -z "$def" ]; then
    for c in main master trunk develop; do
      if git -C "$d" rev-parse -q --verify "refs/remotes/origin/$c" >/dev/null ||
        git -C "$d" rev-parse -q --verify "refs/heads/$c" >/dev/null; then
        def=$c
        break
      fi
    done
  fi
  br=$(git -C "$d" symbolic-ref -q --short HEAD 2>/dev/null || echo '(detached)')
  ab=$(git -C "$d" rev-list --left-right --count "$def...origin/$def" 2>/dev/null | tr '\t' '/')
  ahead=${ab%/*}
  behind=${ab#*/}
  if [ "${behind:-0}" != 0 ] && [ "${ahead:-0}" != 0 ]; then
    note="${note}DIVERGED "
  elif [ "${behind:-0}" != 0 ]; then
    note="${note}BEHIND "
  elif [ "${ahead:-0}" != 0 ]; then
    note="${note}UNPUSHED "
  fi
  [ "$br" != "$def" ] && note="${note}OFF-DEFAULT "
  dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$dirty" != 0 ] && note="${note}DIRTY "
  last=$(git -C "$d" log -1 --format=%ct --all 2>/dev/null)
  idle=$(( (now - ${last:-$now}) / 86400 ))d
  printf '%-28s %-34s %-8s %-7s %-5s %-6s %s\n' "$name" "$br" "${def:-?}" "${ab:-?}" "$dirty" "$idle" "$note"

  for b in $(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads); do
    [ "$b" = "$def" ] && continue
    git -C "$d" merge-base --is-ancestor "$b" "$def" 2>/dev/null && continue
    if git -C "$d" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      count=$(git -C "$d" rev-list --count "origin/$b..$b")
      state="pushed"
      [ "$count" != 0 ] && state="pushed, $count local commits not pushed"
    else
      state="local only"
    fi
    merged=""
    if [ -n "$def" ] && git -C "$d" merge-base --is-ancestor "$b" "$def" 2>/dev/null; then merged=", merged"; fi
    count=$(git -C "$d" rev-list --count "$def..$b" 2>/dev/null)
    age=$(( (now - $(git -C "$d" log -1 --format=%ct "$b")) / 86400 ))
    burns="${burns}  ${name}: ${b} (${count:-?} commits on ${def}, ${state}${merged}, last commit ${age}d ago)\n"
  done
  printf '  Worktrees for %s:\n' "$name"
  git -C "$d" worktree list --porcelain
  git -C "$d" stash list --format='  Stash: %gd %s'
  git -C "$d" for-each-ref --format='  Remote: %(refname:short) %(subject)' --no-merged="$def" refs/remotes
}

for root in "$@"; do
  root=${root%/}
  if [ -e "$root/.git" ]; then
    check_repo "$root" "$(basename "$root")"
    continue
  fi
  while IFS= read -r g; do
    d=${g%/.git}
    check_repo "$d" "${d#"$root"/}"
  done < <(find "$root" -mindepth 2 -maxdepth 3 -name .git \
    -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.*/.git' 2>/dev/null | sort)
done

printf '\nOpen branches (all prefixes):\n'
if [ -n "$burns" ]; then printf '%b' "$burns"; else printf '  none\n'; fi
