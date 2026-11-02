#!/usr/bin/env bash
# Own one linked worktree per item; never switch or stash a user's checkout.
# start <session> <repo> <slug> | finish <session> <repo> <slug>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
[ "$#" = 4 ] || [ "$#" = 5 ] || { echo "usage: work-item.sh start|finish <session> <repo> <slug>" >&2; exit 2; }
mode=$1 sid=$2 repo=$3 slug=$4
resume_branch=${5:-}
valid_session "$sid" || exit 2
case "$slug" in "" | *[!a-z0-9-]* | -* | *-) echo "invalid item slug" >&2; exit 2 ;; esac
[ -f "$BMU_HOME/active/$sid" ] || { echo "no active run for this session" >&2; exit 2; }
top=$(git -C "$repo" rev-parse --show-toplevel) || exit 2
top=$(native_path "$(cd "$top" && pwd -P)")
name=$(basename "$top")
case "$name" in *[!A-Za-z0-9._-]*) echo "repository name is not supported" >&2; exit 2 ;; esac
owner="$BMU_HOME/owned/$sid/$name-$slug"
if [ "$mode" = start ] || [ "$mode" = resume ]; then
  [ -f "$BMU_HOME/roots.txt" ] || { echo "setup must write roots.txt first" >&2; exit 2; }
  permitted=0
  while IFS= read -r root || [ -n "$root" ]; do
    root=${root%$'\r'}
    [ -d "$root" ] || continue
    root=$(native_path "$(cd "$root" && pwd -P)")
    case "$top/" in "$root/"*) permitted=1 ;; esac
  done <"$BMU_HOME/roots.txt"
  [ "$permitted" = 1 ] || { echo "repository is outside configured roots" >&2; exit 2; }
  if [ -f "$owner" ]; then
    IFS= read -r wt <"$owner"
    [ -f "$wt/.git" ] || { echo "owned worktree missing; preserve record for recovery" >&2; exit 2; }
    echo "WORKTREE=$(native_path "$wt")"
    exit 0
  fi
  def=$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD || true)
  if [ -z "$def" ]; then
    for candidate in main master trunk develop; do
      if git -C "$top" rev-parse --verify "$candidate^{commit}" >/dev/null 2>&1; then def=$candidate; break; fi
    done
  fi
  [ -n "$def" ] || { echo "default branch is unknown" >&2; exit 2; }
  branch="burn/$(date +%Y-%m-%d)-$slug"
  if [ "$mode" = resume ]; then
    [[ $resume_branch =~ ^burn/[a-z0-9][a-z0-9/-]*$ ]] || exit 2
    branch=$resume_branch
  fi
  wt="$BMU_HOME/worktrees/$sid/$name-$slug"
  mkdir -p "$(dirname "$wt")" "$(dirname "$owner")" "$BMU_HOME/handoffs/$name"
  [ ! -e "$wt" ] || { echo "target exists; refusing to adopt it" >&2; exit 2; }
  if [ "$mode" = resume ]; then
    git -C "$top" worktree add "$wt" "$branch"
  else
    git -C "$top" worktree add -b "$branch" "$wt" "$def"
  fi
  printf '%s\n' "$wt" >"$owner"
  printf '# %s\n\nBranch: %s\nOwner: %s\nState: started\nChecks: pending\nNext: implement and verify\n' "$name/$slug" "$branch" "$sid" >"$BMU_HOME/handoffs/$name/$sid-$slug.md"
  echo "WORKTREE=$(native_path "$wt")"
  echo "BRANCH=$branch"
elif [ "$mode" = finish ]; then
  [ -f "$owner" ] || { echo "this session does not own the worktree" >&2; exit 2; }
  IFS= read -r wt <"$owner"
  [ -f "$wt/.git" ] || exit 2
  [ -z "$(git -C "$wt" status --porcelain)" ] || { echo "uncommitted work remains; leave worktree and handoff" >&2; exit 2; }
  branch=$(git -C "$wt" symbolic-ref --short HEAD)
  case "$branch" in burn/*) ;; *) echo "owned worktree changed branch; refusing cleanup" >&2; exit 2 ;; esac
  sha=$(git -C "$wt" rev-parse HEAD)
  mkdir -p "$BMU_HOME/backups"
  bundle="$BMU_HOME/backups/$name-${branch#burn/}-$sha.bundle"
  # Back up even a pushed branch: local-only policies need verifiable recovery.
  git -C "$wt" bundle create "$bundle" "$branch"
  git -C "$wt" bundle verify "$bundle" >/dev/null
  git -C "$top" worktree remove "$wt"
  rm -f "$owner"
  printf '\nState: saved\nTip: %s\nBackup: %s\nNext: review inbox card; branch retained\n' "$sha" "$(native_path "$bundle")" >>"$BMU_HOME/handoffs/$name/$sid-$slug.md"
  echo "SAVED=$sha"
  echo "BACKUP=$(native_path "$bundle")"
else
  echo "unknown mode" >&2; exit 2
fi
