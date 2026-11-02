# Shared by the burn-my-usage scripts. Source it; don't run it.
# Works on bash 3.2 (macOS), Linux and Git Bash on Windows.

BMU_HOME=${BURN_MY_USAGE_HOME:-$HOME/.burn-my-usage}

# A path that Claude's Read and Write tools accept. On Windows that is C:/Users/x, not the
# /c/Users/x that Git Bash prints.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

# The first "key: value" line in config.md (a leading "- " is allowed), without any trailing
# "# comment". Prints the default when the key is missing.
config_value() {
  local v=""
  if [ -f "$BMU_HOME/config.md" ]; then
    v=$(sed -n "s/^[[:space:]]*[-*]\{0,1\}[[:space:]]*$1:[[:space:]]*//p" "$BMU_HOME/config.md" |
      head -n 1 | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//; s/^`//; s/`$//')
  fi
  printf '%s\n' "${v:-${2:-}}"
}

valid_session() {
  case "$1" in
    "" | *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# The session ids to mark, one per line: the one passed in (the skill's ${CLAUDE_SESSION_ID})
# and CLAUDE_CODE_SESSION_ID, which Claude Code sets for the Bash tool. They are normally the
# same. If they ever differ, both are marked, so the guard can't miss the session. An id that
# was passed but is malformed is an error, not a reason to fall back.
session_ids() {
  local a=${1:-} b=${CLAUDE_CODE_SESSION_ID:-}
  if [ -n "$a" ] && ! valid_session "$a"; then
    return 1
  fi
  valid_session "$b" || b=""
  [ -n "$a" ] && echo "$a"
  [ -n "$b" ] && [ "$b" != "$a" ] && echo "$b"
  [ -n "$a$b" ]
}
