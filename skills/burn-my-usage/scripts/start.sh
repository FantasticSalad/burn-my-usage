#!/usr/bin/env bash
# Starts a burn run: marks this session active (which switches the guard on for it), makes a
# run folder, and prints what the run needs to know.
#   bash start.sh <session id>
#   bash start.sh --until-limit <session id>
#        no stop line: the run works until Claude Code's usage limit stops it, then wraps up
#        on the next turn (until-limit.sh). For clients whose status line doesn't refresh.
#   bash start.sh --paths      print the paths and what exists; change nothing (plan, status)
set -eu
. "$(dirname "$0")/lib.sh"

until_limit=0
if [ "${1:-}" = --until-limit ]; then
  until_limit=1
  shift
  if [ "$BMU_HOST" != claude-code ]; then
    echo 'ERROR: --until-limit needs Claude Code, whose StopFailure hook reports the usage limit' >&2
    exit 2
  fi
fi

report_files() {
  for f in config.md INBOX.md wishlist.md recurring.md lessons.md roots.txt usage.json guard.log; do
    if [ -f "$BMU_HOME/$f" ]; then echo "HAS_${f%%.*}=yes"; else echo "HAS_${f%%.*}=no"; fi
  done
}

# Local time with its UTC offset. Not the zone name: Git Bash on Windows derives it from the
# Windows zone and can get it wrong (a daylight-time zone under its standard-time name); the offset is right.
local_time() { date '+%Y-%m-%d %H:%M (UTC%z)'; }

# Which code is running: the plugin version, and the commit when these scripts run from a git
# checkout. The same version number can cover different code between releases.
report_version() {
  local root v c
  root=$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd) || root=""
  v=""
  [ -n "$root" ] && [ -f "$root/.claude-plugin/plugin.json" ] &&
    v=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -n 1)
  echo "VERSION=${v:-unknown}"
  # Only the plugin's own checkout: .git right at its root (a folder, or a file in a linked
  # worktree). Comparing paths fails where one folder has two spellings (/tmp and C:/...).
  if [ -n "$root" ] && [ -e "$root/.git" ] && c=$(git -C "$(native_path "$root")" rev-parse --short HEAD 2>/dev/null); then
    echo "COMMIT=$c"
  fi
}

if [ "${1:-}" = --paths ]; then
  if ! valid_host; then echo 'ERROR: invalid BMU_HOST' >&2; exit 2; fi
  echo "BURN_HOME=$(native_path "$BMU_HOME")"
  report_version
  echo "LOCAL_TIME=$(local_time)"
  report_files
  exit 0
fi

if ! ids=$(session_ids "${1:-}"); then
  echo "ERROR: pass the session id (letters, digits, - and _ only)" >&2
  exit 2
fi

# No config means setup hasn't run. Start nothing: no burn home, no run folder, no guard marker.
if [ ! -f "$BMU_HOME/config.md" ]; then
  echo "BURN_HOME=$(native_path "$BMU_HOME")"
  report_files
  echo "NO_CONFIG: nothing was started. Tell the user to run /burn-my-usage setup."
  exit 3
fi

# No usable roots.txt means the guard would refuse every repository edit (it fails closed),
# so the run could do nothing. Usually a hand-copied template or a sync conflict: refuse.
has_root=0
if [ -f "$BMU_HOME/roots.txt" ]; then
  while IFS= read -r r || [ -n "$r" ]; do
    r=${r%%#*}
    r=${r%$'\r'}
    r=${r#"${r%%[![:space:]]*}"}
    case "$r" in /* | [A-Za-z]:[\\/]* | "~"/*) has_root=1 ;; esac
  done <"$BMU_HOME/roots.txt"
fi
if [ "$has_root" = 0 ]; then
  echo "BURN_HOME=$(native_path "$BMU_HOME")"
  report_files
  echo "NO_ROOTS: nothing was started. roots.txt in the burn home needs at least one absolute"
  echo "repository folder, one per line. Tell the user to run /burn-my-usage setup."
  exit 3
fi

primary=${ids%%
*}
# The cross-provider claim is creating run.lock/owner with noclobber, which opens the file
# with O_EXCL: of two starts at the same moment, exactly one creates it. mkdir alone is not a
# claim: uutils mkdir, Ubuntu's default from 26.04, can report success to both of two
# simultaneous calls. Never infer that an old claim is abandoned.
other_run() {
  owner=$(sed -n '2p' "$BMU_HOME/run.lock/owner" 2>/dev/null || true)
  echo "OTHER_RUN_ACTIVE= ${owner:-unknown}"
  exit 4
}
mkdir "$BMU_HOME/run.lock" 2>/dev/null || other_run
if ! (set -C; printf '%s\n%s\n%s\n' "$BMU_HOST" "$primary" "$ids" >"$BMU_HOME/run.lock/owner") 2>/dev/null; then
  [ ! -f "$BMU_HOME/run.lock/owner" ] || other_run
  # Not a lost claim: the file couldn't be written. rmdir removes the folder only while it is
  # empty, so it never takes away a claim another start has made.
  rmdir "$BMU_HOME/run.lock" 2>/dev/null || true
  echo "ERROR: could not write $(native_path "$BMU_HOME")/run.lock/owner; nothing was started" >&2
  exit 1
fi
claimed=1
markers=""
run_dir=""
cleanup_failed_start() {
  [ "$claimed" = 1 ] || return 0
  if [ -n "$markers" ]; then
    for sid in $ids; do rm -f "$markers/$sid"; done
  fi
  [ -z "$run_dir" ] || rmdir "$run_dir" 2>/dev/null || true
  rm -f "$BMU_HOME/run.lock/owner"
  rmdir "$BMU_HOME/run.lock" 2>/dev/null || true
}
trap cleanup_failed_start EXIT
# Existing legacy markers also block a new run; they may belong to an older version.
existing=$(find "$BMU_HOME/active" -type f -print 2>/dev/null | head -n 1 || true)
if [ -n "$existing" ]; then
  rm -f "$BMU_HOME/run.lock/owner"
  rmdir "$BMU_HOME/run.lock"
  claimed=0
  echo "OTHER_RUN_ACTIVE= $(basename "$existing")"
  exit 4
fi
markers=$(marker_dir)
mkdir -p "$markers" "$BMU_HOME/runs"
# Answers saved from the inbox page by an earlier run are stale: the user may have changed or
# withdrawn them since, and a resumed session keeps its id. Only what this run saves counts
# as an approval (guard.sh, page_merge_approved), so a run never starts with any on disk.
if [ -e "$BMU_HOME/page-answers" ] && ! rm -rf "$BMU_HOME/page-answers"; then
  echo "ERROR: could not clear $BMU_HOME/page-answers (old inbox page answers); nothing was started" >&2
  exit 1
fi

stamp=$(date +%Y-%m-%d-%H%M%S)-$BMU_HOST-$primary-$$
candidate="$BMU_HOME/runs/$stamp"
mkdir "$candidate"
run_dir=$candidate
for sid in $ids; do
  # A limit an earlier run in this session hit doesn't end this one.
  rm -f "$BMU_HOME/limit-hit/$sid" "$BMU_HOME/limit-hit/$sid.told"
  printf 'started %s\nrun %s\n' "$(local_time)" "$stamp" >"$markers/$sid"
  [ "$until_limit" = 0 ] || echo 'mode until-limit' >>"$markers/$sid"
done
claimed=0
# BURN IT ALL typed in this session before the run started counts if it was within the hour;
# an older arm is dropped, so it can't carry into a much later run.
burn_all=0
for sid in $ids; do
  arm="$BMU_HOME/burn-it-all/$sid"
  [ -f "$arm" ] || continue
  if [ -n "$(find "$arm" -mmin +60 2>/dev/null)" ]; then rm -f "$arm"; else burn_all=1; fi
done

echo "BURN_HOME=$(native_path "$BMU_HOME")"
echo "RUN_DIR=$(native_path "$run_dir")"
echo "SESSION=$(echo $ids)"
case "$ids" in
  *"
"*)
    # Marking the calling session too means the guard can't miss it, but it also switches the
    # guard on in the session that ran this, even when the id passed was a test id.
    echo "SESSION_IDS_DIFFER: passed ${ids%%
*}, this session ${ids#*
}. Both are marked, so the guard is on in this session too; stop.sh with the passed id ends both."
    ;;
esac
report_version
echo "LOCAL_TIME=$(local_time)"
report_files
[ "$burn_all" = 0 ] || echo "BURN_IT_ALL=on: the user typed BURN IT ALL; this run's stop line is 100%."
if [ "$until_limit" = 1 ]; then
  echo "UNTIL_LIMIT=on: no stop line and no usage checks. The run works until Claude Code's usage"
  echo "limit stops it, then wraps up on the next turn. Extra usage must be off (claude.ai Settings >"
  echo "Usage): with it on, the limit never stops the run and the work past it is billed."
fi
echo "NEXT: run  echo burn-guard-selftest  . A denial that says 'self-test OK' means the guard is on."
