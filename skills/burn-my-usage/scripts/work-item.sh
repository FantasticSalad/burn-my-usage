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
valid_host || { echo "invalid BMU_HOST" >&2; exit 2; }
case "$slug" in "" | *[!a-z0-9-]* | -* | *-) echo "invalid item slug" >&2; exit 2 ;; esac
[ -f "$(marker_dir)/$sid" ] || { echo "no active run for this host and session" >&2; exit 2; }
# A marker can outlive an interrupted or damaged run; it is not ownership.
lock="$BMU_HOME/run.lock/owner"
lock_host=$(sed -n '1p' "$lock" 2>/dev/null || true)
lock_primary=$(sed -n '2p' "$lock" 2>/dev/null || true)
lock_ids=$(sed -n '3,$p' "$lock" 2>/dev/null || true)
[ "$lock_host" = "$BMU_HOST" ] && valid_session "$lock_primary" || { echo "run lock identity is missing or invalid" >&2; exit 2; }
first_id=${lock_ids%%$'\n'*}
[ "$first_id" = "$lock_primary" ] || { echo "run lock identity is incomplete" >&2; exit 2; }
matched=0
old_ifs=$IFS
IFS=$'\n'
set -f
for lock_id in $lock_ids; do
  valid_session "$lock_id" || { echo "invalid run lock session" >&2; exit 2; }
  [ "$lock_id" != "$sid" ] || matched=1
done
set +f
IFS=$old_ifs
[ "$matched" = 1 ] && { [ "$BMU_HOST" != codex ] || [ "$sid" = "$lock_primary" ]; } || { echo "this session does not own the run lock" >&2; exit 2; }
# Preserve existing Claude paths; other hosts cannot adopt a same-id Claude item.
owner_key=$sid
[ "$BMU_HOST" != codex ] || owner_key="codex/$sid"
# A bare repository name ("app" rather than its path) is looked up under the roots, as deep as
# repo-check.sh scans: a root itself, or one or two levels below it.
case "$repo" in
  */* | *\\*) ;;
  *)
    if [ ! -d "$repo" ]; then
      found=""
      count=0
      while IFS= read -r root || [ -n "$root" ]; do
        root=${root%$'\r'}
        [ -d "$root" ] || continue
        for candidate in "$root" "$root/$repo" "$root"/*/"$repo"; do
          [ "$(basename "$candidate")" = "$repo" ] || continue
          [ -e "$candidate/.git" ] || continue
          found="$found$candidate
"
          count=$((count + 1))
        done
      done <"$BMU_HOME/roots.txt" 2>/dev/null
      if [ "$count" = 0 ]; then
        echo "no repository named $repo under the folders in roots.txt; pass the repository's path" >&2
        exit 2
      elif [ "$count" -gt 1 ]; then
        echo "more than one repository is named $repo; pass the path of the one you mean:" >&2
        printf '%s' "$found" >&2
        exit 2
      fi
      repo=${found%$'\n'}
    fi
    ;;
esac
# git is a native program: give it C:/... on Windows (see BMU_HOME in lib.sh).
case "$repo" in /*) repo=$(native_path "$repo") ;; esac
top=$(git -C "$repo" rev-parse --show-toplevel) || exit 2
top=$(native_path "$(cd "$top" && pwd -P)")
name=$(basename "$top")
case "$name" in *[!A-Za-z0-9._-]*) echo "repository name is not supported" >&2; exit 2 ;; esac
owner="$BMU_HOME/owned/$owner_key/$name-$slug"
handoff="$BMU_HOME/handoffs/$name/$owner_key-$slug.md"
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
  # A recovered owner may save existing work at any quota level, but creating
  # or adopting a worktree starts new work and requires a fresh go verdict.
  usage=$(bash "$here/usage.sh") || { echo "quota check failed; no item started" >&2; exit 2; }
  verdict=$(printf '%s\n' "$usage" | sed -n 's/^verdict=//p')
  [ "$verdict" = go ] || { echo "quota verdict ${verdict:-unknown}; no item started" >&2; exit 2; }
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
  wt="$BMU_HOME/worktrees/$owner_key/$name-$slug"
  mkdir -p "$(dirname "$wt")" "$(dirname "$owner")" "$(dirname "$handoff")"
  [ ! -e "$wt" ] || { echo "target exists; refusing to adopt it" >&2; exit 2; }
  if [ "$mode" = resume ]; then
    git -C "$top" worktree add "$wt" "$branch"
  else
    # No upstream: from origin/main, git would otherwise track it, and a bare git push from the
    # worktree would aim at the default branch. Pushes always name the burn branch.
    git -C "$top" worktree add --no-track -b "$branch" "$wt" "$def"
  fi
  printf '%s\n' "$wt" >"$owner"
  printf '# %s\n\nBranch: %s\nHost: %s\nOwner: %s\nState: started\nChecks: pending\nNext: implement and verify\n' "$name/$slug" "$branch" "$BMU_HOST" "$sid" >"$handoff"
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
  # Persist recovery evidence before removing anything. A failed handoff write must
  # leave the owned worktree and ownership record available for a later retry.
  printf '\nState: backed up; cleanup pending\nTip: %s\nBackup: %s\n' "$sha" "$(native_path "$bundle")" >>"$handoff"
  # The branch is committed and its bundle verified, so the item is saved whether or not the
  # folder can be removed. Record that and release ownership first: a sync client or virus
  # scanner holding a file must not leave the run unable to stop.
  printf '\nState: saved\nTip: %s\nBackup: %s\nNext: review inbox card; branch retained\n' "$sha" "$(native_path "$bundle")" >>"$handoff"
  rm -f "$owner"
  echo "SAVED=$sha"
  echo "BACKUP=$(native_path "$bundle")"
  if ! git -C "$top" worktree remove "$wt"; then
    # Never force it. The folder is the user's to delete once nothing holds it.
    printf 'Leftover: %s (worktree removal failed; delete the folder by hand)\n' "$(native_path "$wt")" >>"$handoff" || true
    echo "LEFTOVER=$(native_path "$wt")"
    echo "the item is saved, but its worktree folder could not be removed; add a job for the user to delete it" >&2
  fi
else
  echo "unknown mode" >&2; exit 2
fi
