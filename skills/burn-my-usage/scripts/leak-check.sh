#!/usr/bin/env bash
# Staged added text only. Findings print location/category, never matching text.
# Exit 0: clear, 1: possible secret, 2: unable to check. Requires bash 3.2 and git.
set -uo pipefail
[ "$#" = 1 ] || { echo "usage: leak-check.sh <worktree>" >&2; exit 2; }
repo=$1
diff=$(git -C "$repo" diff --cached --no-ext-diff --no-textconv --no-color -U0 --) || exit 2
printf '%s\n' "$diff" | LC_ALL=C awk '
  /^\+\+\+ b\// { path=substr($0,7); next }
  /^@@ / { n=$0; sub(/^.*\+/, "", n); sub(/[, ].*$/, "", n); line=n+0; next }
  /^Binary files / { print path ": binary staged content needs manual review"; found=1; next }
  /^\+/ {
    s=substr($0,2); kind=""
    if (s ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) kind="private key"
    else if (s ~ /sk-(ant-|proj-)?[A-Za-z0-9_-]{20,}/) kind="API token"
    else if (s ~ /(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,})/) kind="GitHub token"
    else if (s ~ /(AKIA|ASIA)[0-9A-Z]{16}/) kind="cloud key"
    else if (s ~ /AIza[0-9A-Za-z_-]{35}/) kind="API key"
    else if (s ~ /xox[abprs]-[0-9A-Za-z-]{10,}/) kind="chat token"
    else if (s ~ /eyJ[0-9A-Za-z_-]{10,}\.eyJ[0-9A-Za-z_-]{10,}\./) kind="JWT"
    else if (s ~ /Bearer[ \t]+[A-Za-z0-9._~+\/-]{20,}/) kind="bearer token"
    else {
      low=tolower(s)
      if (low ~ /(password|passwd|api_key|api-key|client_secret|access_token)[ \t]*[:=][ \t]*["\047][^"\047$<>{} \t]{12,}["\047]/) kind="assigned credential"
    }
    if (kind != "") { printf "%s:%d: %s\n", path, line, kind; found=1 }
    line++
  }
  END { exit found ? 1 : 0 }
'
rc=$?
[ "$rc" -le 1 ] || exit 2
exit "$rc"
