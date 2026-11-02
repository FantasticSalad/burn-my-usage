#!/usr/bin/env bash
# Starts a burn run: marks this session active (which switches the guard on for it), makes a
# run folder, and prints what the run needs to know.
#   bash start.sh <session id>
#   bash start.sh --paths      print the paths and what exists; change nothing (plan, status)
set -u
. "$(dirname "$0")/lib.sh"

report_files() {
  for f in config.md INBOX.md wishlist.md recurring.md lessons.md roots.txt usage.json guard.log; do
    if [ -f "$BMU_HOME/$f" ]; then echo "HAS_${f%%.*}=yes"; else echo "HAS_${f%%.*}=no"; fi
  done
}

if [ "${1:-}" = --paths ]; then
  echo "BURN_HOME=$(native_path "$BMU_HOME")"
  echo "LOCAL_TIME=$(date '+%Y-%m-%d %H:%M %Z')"
  report_files
  exit 0
fi

if ! ids=$(session_ids "${1:-}"); then
  echo "ERROR: pass the session id (letters, digits, - and _ only)" >&2
  exit 2
fi

mkdir -p "$BMU_HOME/active" "$BMU_HOME/runs"

# Markers left by runs that died are harmless (each only guards its own session), but prune
# old ones so the folder stays readable.
find "$BMU_HOME/active" -type f -mtime +14 -exec rm -f {} + 2>/dev/null

others=""
for f in $(find "$BMU_HOME/active" -type f -mmin -720 2>/dev/null); do
  case " $(echo $ids) " in *" $(basename "$f") "*) continue ;; esac
  others="$others $(basename "$f")"
done

stamp=$(date +%Y-%m-%d-%H%M)
run_dir="$BMU_HOME/runs/$stamp"
mkdir -p "$run_dir"
for sid in $ids; do
  printf 'started %s\nrun %s\n' "$(date '+%Y-%m-%d %H:%M %Z')" "$stamp" >"$BMU_HOME/active/$sid"
done

echo "BURN_HOME=$(native_path "$BMU_HOME")"
echo "RUN_DIR=$(native_path "$run_dir")"
echo "SESSION=$(echo $ids)"
case "$ids" in
  *"
"*) echo "SESSION_IDS_DIFFER: the skill's session id and CLAUDE_CODE_SESSION_ID differ; both are marked." ;;
esac
echo "LOCAL_TIME=$(date '+%Y-%m-%d %H:%M %Z')"
report_files
if [ -n "$others" ]; then
  echo "OTHER_RUN_ACTIVE=$others"
  echo "  Another session started a run in the last 12 hours. It may still be working, or it"
  echo "  may have died without stopping. Two live runs on the same repos collide."
fi
echo "NEXT: run  echo burn-guard-selftest  . A denial that says 'self-test OK' means the guard is on."
