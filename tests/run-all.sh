#!/usr/bin/env bash
# Runs every test suite and exits non-zero if any failed.
#   bash tests/run-all.sh
here=$(cd "$(dirname "$0")" && pwd)
status=0
for t in "$here"/*.test.sh; do
  printf '== %s\n' "$(basename "$t")"
  bash "$t" || status=1
done
if command -v node >/dev/null 2>&1; then
  # Node is a native program: on Windows, give it Windows paths. Git Bash doesn't convert a
  # path with an apostrophe in it, and Node would read /c/Users/... as C:\c\Users\...
  mjs=()
  for f in "$here"/*.test.mjs; do
    if command -v cygpath >/dev/null 2>&1; then mjs+=("$(cygpath -m "$f")"); else mjs+=("$f"); fi
  done
  node --test "${mjs[@]}" || status=1
else
  echo "SKIP optional release-scanner tests: Node 18+ is not installed"
fi
exit $status
