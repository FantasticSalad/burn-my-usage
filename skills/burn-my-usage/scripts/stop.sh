#!/usr/bin/env bash
# Ends a burn run for this session: removes its marker, so the guard stops enforcing.
#   bash stop.sh <session id>
set -u
. "$(dirname "$0")/lib.sh"

if ! ids=$(session_ids "${1:-}"); then
  echo "ERROR: pass the session id (letters, digits, - and _ only)" >&2
  exit 2
fi
# A normal finish must save and release every owned item first.
for sid in $ids; do
  for owner in "$BMU_HOME/owned/$sid"/*; do
    [ -f "$owner" ] || continue
    echo "WORK_REMAINS: save the item, finish its owned worktree and handoff, then stop" >&2
    exit 2
  done
done
stopped=0
for sid in $ids; do
  if [ -f "$BMU_HOME/active/$sid" ]; then
    rm -f "$BMU_HOME/active/$sid"
    stopped=1
  fi
done
if [ "$stopped" = 1 ]; then
  echo "STOPPED: the guard is off for this session."
else
  echo "NOT_ACTIVE: no run was active in this session."
fi
