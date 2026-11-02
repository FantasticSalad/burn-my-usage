#!/usr/bin/env bash
# Replays Claude Code transcripts through the guard and reports what it would have refused.
# No model calls, so no plan usage. Needs node 18 or later. Options are in replay.mjs.
#
#   bash tests/replay/run.sh --roots ~/code --run-skill burn-my-usage
#   bash tests/replay/run.sh --help
set -eu
here=$(cd "$(dirname "$0")" && pwd)
command -v node >/dev/null 2>&1 || { echo "replay: needs node 18 or later" >&2; exit 1; }
script="$here/replay.mjs"
bash_path=$(command -v bash)
# node on Windows can't run /usr/bin/bash, and a bare "bash" may find WSL's instead of Git Bash.
if command -v cygpath >/dev/null 2>&1; then
  script=$(cygpath -m "$script")
  bash_path=$(cygpath -m "$bash_path")
fi
exec node "$script" --bash "$bash_path" "$@"
