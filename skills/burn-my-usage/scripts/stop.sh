#!/usr/bin/env bash
# Ends a burn run for this session: removes its marker, so the guard stops enforcing.
#   bash stop.sh <session id>
#   bash stop.sh --release-orphans <session id>
#        also release ownership records whose worktree git no longer knows about (left by a
#        failed cleanup). Nothing is deleted but the records; a live owned worktree still
#        blocks the stop.
set -u
. "$(dirname "$0")/lib.sh"

release_orphans=0
case "${1:-}" in
  --release-orphans) release_orphans=1; shift ;;
  -*) echo "ERROR: unknown option ${1}" >&2; exit 2 ;;
esac

# An owner record is orphaned when its path is not the top of a git worktree any more: the
# folder is gone, or its .git link points at an admin folder git has already deleted. Commits
# live in the repository, not the folder, so releasing such a record can't lose saved work.
orphaned() { # owner record
  local wt="" top
  IFS= read -r wt <"$1" || [ -n "$wt" ] || return 0
  wt=${wt%$'\r'}
  [ -d "$wt" ] || return 0
  top=$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ "$(cd "$top" && pwd -P)" != "$(cd "$wt" && pwd -P)" ]
}

if ! ids=$(session_ids "${1:-}"); then
  echo "ERROR: pass the session id (letters, digits, - and _ only)" >&2
  exit 2
fi
primary=${ids%%
*}
lockhost=$(sed -n '1p' "$BMU_HOME/run.lock/owner" 2>/dev/null || true)
lockid=$(sed -n '2p' "$BMU_HOME/run.lock/owner" 2>/dev/null || true)
if [ "$lockhost" != "$BMU_HOST" ] || [ "$lockid" != "$primary" ]; then
  echo 'NOT_ACTIVE: this session does not own the run lock.'
  exit 0
fi
ids=$(sed -n '3,$p' "$BMU_HOME/run.lock/owner")
# A normal finish must save and release every owned item first. Check every record before
# releasing any, so a refused stop changes nothing.
live=0
orphans=""
for sid in $ids; do
  owner_key=$sid
  [ "$BMU_HOST" = codex ] && owner_key="codex/$sid"
  for owner in "$BMU_HOME/owned/$owner_key"/*; do
    [ -f "$owner" ] || continue
    if orphaned "$owner"; then
      orphans="$orphans$owner
"
    else
      live=1
    fi
  done
done
if [ "$live" = 1 ] || { [ -n "$orphans" ] && [ "$release_orphans" = 0 ]; }; then
  echo "WORK_REMAINS: save the item, finish its owned worktree and handoff, then stop" >&2
  if [ -n "$orphans" ]; then
    echo "Some records point at worktrees git no longer knows (a failed cleanup). Once every live" >&2
    echo "item is finished, and if their branches are committed or backed up, run" >&2
    echo "stop.sh --release-orphans <session id> to release them." >&2
  fi
  exit 2
fi
while IFS= read -r owner; do
  [ -n "$owner" ] || continue
  if ! rm -f "$owner"; then
    echo "ERROR: could not release $owner; run lock retained" >&2
    exit 1
  fi
  echo "RELEASED=$(basename "$owner") (any folder left behind is the user's to delete)"
done <<EOF
$orphans
EOF
stopped=0
markers=$(marker_dir)
backup=$(mktemp -d "$BMU_HOME/.stop-backup.XXXXXX") || {
  echo 'ERROR: cannot prepare marker backups; run lock retained' >&2
  exit 1
}
if ! cp "$BMU_HOME/run.lock/owner" "$backup/owner"; then
  echo 'ERROR: cannot back up owner; run lock retained' >&2
  exit 1
fi
mkdir "$backup/markers" || { echo 'ERROR: cannot prepare marker backups; run lock retained' >&2; exit 1; }
for sid in $ids; do
  if [ -f "$markers/$sid" ] && ! cp "$markers/$sid" "$backup/markers/$sid"; then
    echo 'ERROR: cannot back up markers; run lock retained' >&2
    exit 1
  fi
done
restore_markers() {
  restored=1
  for saved in "$backup/markers"/*; do
    [ -f "$saved" ] || continue
    cp "$saved" "$markers/$(basename "$saved")" || restored=0
  done
  if [ "$restored" = 0 ]; then
    echo 'ERROR: marker restoration failed; guard coverage may be incomplete' >&2
  fi
}
for sid in $ids; do
  if [ -f "$markers/$sid" ]; then
    if ! rm -f "$markers/$sid"; then
      restore_markers
      echo 'ERROR: could not remove marker; run lock retained' >&2
      exit 1
    fi
    stopped=1
  fi
  # BURN IT ALL lasts for one run only, and so does a usage limit an until-limit run hit.
  rm -f "$BMU_HOME/burn-it-all/$sid" "$BMU_HOME/limit-hit/$sid" "$BMU_HOME/limit-hit/$sid.told"
done
if ! rm -f "$BMU_HOME/run.lock/owner" || ! rmdir "$BMU_HOME/run.lock"; then
  cp "$backup/owner" "$BMU_HOME/run.lock/owner" || echo 'ERROR: owner restoration failed' >&2
  restore_markers
  echo "ERROR: could not release run lock; recovery backup retained at $backup" >&2
  exit 1
fi
rm -f "$backup/markers"/* "$backup/owner"
rmdir "$backup/markers" || echo "WARNING: marker backup directory retained at $backup" >&2
rmdir "$backup" || echo "WARNING: recovery backup retained at $backup" >&2
if [ "$stopped" = 1 ]; then
  echo "STOPPED: the guard is off for this session."
else
  echo "NOT_ACTIVE: no run was active in this session."
fi
