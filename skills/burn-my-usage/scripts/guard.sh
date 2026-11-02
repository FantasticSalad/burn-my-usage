#!/usr/bin/env bash
# burn-my-usage guard: a PreToolUse hook.
#
# Enforces a burn run's hard rules in the one session that started the run, and does nothing
# anywhere else. A run marks itself active by writing <burn home>/active/<session id>. The
# guard pulls the session id out of the hook input with a bash regex and exits when there is
# no marker, so an ordinary session pays for one bash start per tool call and nothing more.
#
# It refuses an action by printing a PreToolUse "deny" decision with a reason Claude can act
# on, and exits 0 otherwise so the normal permission flow applies.
#
# It is a seatbelt against mistakes, not a sandbox. A model that writes a script and then
# runs it can route around any string match. SECURITY.md lists what it covers and what it
# cannot.
#
# Written for bash 3.2 (macOS) and Git Bash, with no jq and as few child processes as
# possible: on Windows each one costs tens of milliseconds, and this runs on every tool call.
# JSON string values are matched with a regex, which works because a JSON string cannot hold
# a raw newline or an unescaped quote. Matching is case-insensitive (nocasematch) except where
# a flag's case changes its meaning; those places use [ = ], which nocasematch doesn't touch.
set -u
set -f
shopt -s nocasematch

IFS= read -r -d '' input || true

home=${BURN_MY_USAGE_HOME:-$HOME/.burn-my-usage}
[ -d "$home/active" ] || exit 0
re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
[[ $input =~ $re ]] || exit 0
session=${BASH_REMATCH[1]}
[ -f "$home/active/$session" ] || exit 0

# --- from here on, a run is active in this session ---------------------------------------

case "${OSTYPE:-}" in
  msys* | cygwin* | win*) windows=1 ;;
  *) windows=0 ;;
esac

# The splitter writes this control byte where a command substitution was, so 'git -C "$(...)" push'
# stays one command (split_commands). A folder written with it is unknown until the command runs.
# It has to be a byte no command can contain. A word such as @subst@ can be typed into a path, and
# a path that held it skipped the redirect check. Claude Code escapes control bytes in its JSON,
# and json_str keeps the escape as text, so check_shell refuses a raw byte if one gets through.
subst=$'\002'

# Functions return strings in REPLY to avoid a subshell per call.

# REPLY = the first string value for key $1, unescaped. Escaped newlines become real ones, so
# the command splitter can tell a new command from a line inside a quoted string.
json_str() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  REPLY=""
  [[ $input =~ $re ]] || return 0
  local s=${BASH_REMATCH[1]}
  s=${s//\\\\/$'\001'}
  s=${s//\\\"/\"}
  s=${s//\\n/$'\n'}
  s=${s//\\r/ }
  s=${s//\\t/ }
  s=${s//\\\//\/}
  s=${s//$'\001'/\\}
  REPLY=$s
}

# REPLY = a path in one comparable form: forward slashes, no doubled or trailing slash, and on
# Windows /c/x becomes c:/x. Case is left alone; comparisons ignore it.
norm() {
  local p=${1//\\//}
  if [ "$windows" = 1 ] && [[ $p =~ ^/([a-z])(/.*)?$ ]]; then
    p="${BASH_REMATCH[1]}:${BASH_REMATCH[2]:-/}"
  fi
  while [[ $p == *//* ]]; do p=${p//\/\//\/}; done
  [ "$p" = / ] || p=${p%/}
  REPLY=$p
}

unquote() {
  REPLY=${1//\"/}
  REPLY=${REPLY//\'/}
}

json_str tool_name
tool=$REPLY
json_str cwd
cwd=${REPLY:-$PWD}
norm "$home"
home_n=$REPLY

# Refuse the call, and append one line to guard.log so the run's report (and the user) can see
# what was refused. Logging failures never block the refusal itself.
deny() {
  local why=${1//\"/}
  why=${why//\\/\/}
  why=${why//$'\n'/ }
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$session" "$tool" "$why" >>"$home/guard.log" 2>/dev/null
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"burn-my-usage guard: %s (a burn run is active in this session; /burn-my-usage stop ends it)"}}\n' "$why"
  exit 0
}

# --- paths --------------------------------------------------------------------------------

secret_path() {
  norm "$1"
  local p=$REPLY base=${REPLY##*/}
  case "$base" in
    .env.example | .env.sample | .env.template | .env.dist | .env.defaults | .env.test.example) return 1 ;;
    .env | .env.* | *.env) return 0 ;;
    # A glob such as .env* names every env file, and the shell expands it after this check.
    .env[*?[]* | *.env[*?[]*) return 0 ;;
    *.pem | *.key | *.p12 | *.pfx | *.keystore | *.jks | *.kdbx | *.ovpn | *.gpg | *.asc) return 0 ;;
    id_rsa* | id_dsa* | id_ecdsa* | id_ed25519* | .netrc | _netrc | .npmrc | .pypirc | .git-credentials) return 0 ;;
    credentials | credentials.json | token.json | tokens.json | *.tfstate | *.tfstate.backup) return 0 ;;
    secret.json | secrets.json | secret.yaml | secrets.yaml | secret.yml | secrets.yml | secrets.toml) return 0 ;;
    service-account*.json | service_account*.json) return 0 ;;
  esac
  case "/$p/" in
    */.ssh/* | */.aws/* | */.gnupg/* | */.kube/* | */.docker/config.json/* | */.config/gh/*) return 0 ;;
  esac
  return 1
}

# Files the run may read but never change: agent and CI configuration, git internals, and the
# run's own controls.
protected_path() {
  norm "$1"
  local p=$REPLY
  case "/$p/" in
    */.claude/* | */.agents/* | */.codex/* | */.git/* | */.github/workflows/* | */.circleci/* | */.buildkite/* | */.gitlab/ci/*) return 0 ;;
    */.gitlab-ci.yml/* | */azure-pipelines.yml/* | */jenkinsfile/* | */bitbucket-pipelines.yml/*) return 0 ;;
  esac
  case "$p" in
    "$home_n"/config.md | "$home_n"/guard-deny.txt | "$home_n"/guard-allow-mcp.txt | "$home_n"/roots.txt | "$home_n"/bin/* | "$home_n"/active/* | "$home_n"/owned/* | "$home_n"/usage.json | "$home_n"/guard.log) return 0 ;;
  esac
  return 1
}

under() { # path, dir: is path inside dir (both normalised)?
  case "$1/" in "$2"/*) return 0 ;; esac
  return 1
}

# Prefix checks are lexical. A parent segment can cross a root or hide a control file.
# Reject it for writes rather than guessing the eventual filesystem destination.
reject_parent_write() {
  norm "$1"
  case "/$REPLY/" in
    */../*) deny "write paths containing a parent traversal are refused; use the canonical absolute path" ;;
  esac
}

# REPLY = the Windows folder /tmp is mounted on, or "" elsewhere. On Windows a hook gets
# TEMP=/tmp (Git Bash's runtime rewrites the variable when Claude Code starts bash), while
# Claude Code names files with Windows paths, its session scratchpad in %TEMP% among them. One
# child process, and only when a write is checked.
win_tmp() {
  if [ -z "${wintmp_set:-}" ]; then
    wintmp=""
    if [ "$windows" = 1 ]; then
      wintmp=$(cygpath -m /tmp 2>/dev/null)
      [ -n "$wintmp" ] || wintmp=${LOCALAPPDATA:+$LOCALAPPDATA/Temp}
    fi
    wintmp_set=1
  fi
  REPLY=$wintmp
}

# REPLY = the path with its Windows 8.3 short names (GITHUB~1) expanded, or "" when it has none.
# Windows resolves them, so GITHUB~1/WORKFL~1/ci.yml is .github/workflows/ci.yml, while the checks
# here compare names. Callers use the long form only to refuse more, never less: %TEMP% is often a
# short path too. One child process, and only for a path with a ~digit in it.
long_name() {
  REPLY=""
  [ "$windows" = 1 ] || return 0
  case "$1" in *~[0-9]*) ;; *) return 0 ;; esac
  norm "$1"
  local p=$REPLY rest="" long
  REPLY=""
  while [ ! -e "$p" ]; do
    case "$p" in */*) ;; *) return 0 ;; esac
    rest="/${p##*/}$rest"
    p=${p%/*}
    [ -n "$p" ] || return 0
  done
  long=$(cygpath -m -l "$p" 2>/dev/null) || return 0
  REPLY=$long$rest
}

# When setup wrote roots.txt, edits must land under a root, the burn home or a temp dir.
outside_roots() {
  norm "$1"
  local p=$REPLY r
  under "$p" "$home_n" && return 1
  win_tmp
  for r in "${TMPDIR:-}" "${TEMP:-}" "${TMP:-}" /tmp /private/tmp /var/folders "$REPLY"; do
    [ -n "$r" ] || continue
    norm "$r"
    under "$p" "$REPLY" && return 1
  done
  [ -s "$home/roots.txt" ] || return 0
  while IFS= read -r r || [ -n "$r" ]; do
    r=${r%%#*}
    r=${r%$'\r'}
    r=${r#"${r%%[![:space:]]*}"}
    r=${r%"${r##*[![:space:]]}"}
    [ -n "$r" ] || continue
    case "$r" in "~"/*) r="$HOME/${r#\~/}" ;; esac
    norm "$r"
    under "$p" "$REPLY" && return 1
  done <"$home/roots.txt"
  return 0
}

count_ticks() { grep -oE '\[[xX]\]' | wc -l | tr -d ' '; }

# Every value for a key, still escaped (for MultiEdit, which has many old/new strings).
json_all() {
  printf '%s' "$input" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\""
}

check_inbox_edit() {
  local before after
  if [ "$tool" = Write ]; then
    before=0
    [ -f "$home/INBOX.md" ] && before=$(count_ticks <"$home/INBOX.md")
    after=$(json_all content | count_ticks)
  else
    before=$(json_all old_string | count_ticks)
    after=$(json_all new_string | count_ticks)
  fi
  if [ "${after:-0}" -gt "${before:-0}" ]; then
    deny "this edit adds a ticked box to INBOX.md. Only the user answers inbox cards; write the question and leave every box empty"
  fi
}

check_file_tool() {
  local key=file_path p lp
  case "$tool" in
    NotebookEdit) key=notebook_path ;;
    Grep | Glob) key=path ;;
  esac
  json_str "$key"
  p=$REPLY
  [ -n "$p" ] || return 0
  long_name "$p"
  lp=$REPLY
  if secret_path "$p" || { [ -n "$lp" ] && secret_path "$lp"; }; then
    deny "$p looks like a secret or credential file. A burn run never reads or writes secrets; if the work needs one, write it up as a job for the user"
  fi
  case "$tool" in Read | Grep | Glob) return 0 ;; esac
  reject_parent_write "$p"
  case "$p" in "$home"/*) ;; *) cost_gate ;; esac
  if protected_path "$p" || { [ -n "$lp" ] && protected_path "$lp"; }; then
    deny "$p is agent, CI or git configuration, or one of the run's own controls. Changing it changes what runs with the user's credentials, so it needs the user: write it up as a question in the inbox"
  fi
  if outside_roots "$p"; then
    deny "$p is outside the folders this run may change (roots.txt in the burn home)"
  fi
  protect_checkout "$p"
  norm "$p"
  case "$REPLY" in "$home_n"/inbox.md) check_inbox_edit ;; esac
}

# --- shell commands -----------------------------------------------------------------------

# REPLY = the folder a word names, or "" when it can't be known before the command runs: a
# command substitution, or a relative path from a folder that is itself unknown.
resolve_dir() { # word, current dir
  unquote "$1"
  local d=$REPLY
  case "$d" in *"$subst"*) REPLY=""; return 0 ;; esac
  # The home folder written out, or $USERPROFILE, would otherwise resolve under the current folder.
  case "$d" in
    '$HOME' | '$HOME'/*) d=$HOME${d#'$HOME'} ;;
    '${HOME}' | '${HOME}'/*) d=$HOME${d#'${HOME}'} ;;
    '$USERPROFILE' | '$USERPROFILE'/*) d=${USERPROFILE:-$HOME}${d#'$USERPROFILE'} ;;
    '${USERPROFILE}' | '${USERPROFILE}'/*) d=${USERPROFILE:-$HOME}${d#'${USERPROFILE}'} ;;
  esac
  case "$d" in
    "~") d=$HOME ;;
    "~"/*) d="$HOME/${d#\~/}" ;;
  esac
  case "$d" in
    /* | [A-Za-z]:* | \\*) REPLY=$d ;;
    *) if [ -n "$2" ]; then REPLY="$2/$d"; else REPLY=""; fi ;;
  esac
}

# Rules that depend on the branch can't be checked in an unknown folder (resolve_dir), so they
# refuse there. Reads in that folder are fine.
known_dir() { # dir, what
  [ -n "$1" ] && return 0
  deny "$2 runs in a folder named by a command substitution, so the guard can't tell which branch it is on. Use the repository's path instead: cd <path> && git ..."
}

current_branch() { git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null; }
repo_top() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# The burn home's own repository (if it is one), not a worktree that happens to live inside it.
is_home_repo() {
  local top
  top=$(repo_top "$1")
  [ -n "$top" ] || return 1
  norm "$top"
  [[ $REPLY == "$home_n" ]]
}

# A branch card in INBOX.md whose heading names this repo and branch, with Merge ticked after
# the card's last "Reopened" line (a reopened card's earlier answers no longer count).
merge_approved() {
  [ -f "$home/INBOX.md" ] || return 1
  awk -v b="$1" -v r="$2" '
    BEGIN { b = tolower(b); r = tolower(r) }
    /^#+ / {
      if (card && ticked) found = 1
      h = " " tolower($0) " "
      gsub(/[`*|:]/, " ", h)
      gsub(/\302\267/, " ", h)
      card = (index(h, " " b " ") > 0 && index(h, " " r " ") > 0)
      ticked = 0
      next
    }
    card && tolower($0) ~ /^[[:space:]]*\*\*reopened/ { ticked = 0 }
    card && tolower($0) ~ /^[[:space:]]*[-*][[:space:]]+\[x\][[:space:]]+(\*\*)?merge/ { ticked = 1 }
    END { if (card && ticked) found = 1; exit found ? 0 : 1 }' "$home/INBOX.md"
}

# A git switch or checkout earlier in the same command changes the branch later parts of the
# command run on, but the repository won't show it until the command runs. So the guard
# remembers it: switched_top is the repository, switched_branch the branch ("" if unknown).
switched_top=""
switched_branch=""
branch_in() { # the branch $1 will be on when this part of the command runs
  local top
  if [ -n "$switched_top" ]; then
    top=$(repo_top "$1")
    if [ -n "$top" ] && [ "$top" = "$switched_top" ]; then
      printf '%s\n' "$switched_branch"
      return 0
    fi
  fi
  current_branch "$1"
}

# Records the branch a git switch/checkout moves to. $1 = dir, $2 = switch|checkout, then args.
# A checkout of files (git checkout -- f, git checkout f) moves nothing. Anything unclear
# (git checkout -, a commit) counts as an unknown branch, which no rule treats as a burn/ one.
note_switch() {
  local dir=$1 sub=$2 a target="" known=0 grab=0 cand=""
  shift 2
  [ -n "$dir" ] || return 0
  for a in "$@"; do
    unquote "$a"
    a=$REPLY
    if [ "$grab" = 1 ]; then target=$a; known=1; grab=0; continue; fi
    case "$a" in
      --) return 0 ;;
      -b | -B | --create | --force-create) grab=1 ;;
      -d | --detach) target=""; known=1 ;;
      -*)
        # switch -c and -C create; for checkout they don't exist.
        if [ "$sub" = switch ] && { [ "$a" = -c ] || [ "$a" = -C ]; }; then grab=1; fi
        ;;
      *) [ -z "$cand" ] && cand=$a ;;
    esac
  done
  if [ "$known" = 0 ] && [ -n "$cand" ]; then
    if [ "$cand" = - ]; then
      known=1
    elif [ "$sub" = switch ] ||
      git -C "$dir" rev-parse -q --verify "refs/heads/$cand" >/dev/null 2>&1 ||
      git -C "$dir" rev-parse -q --verify "refs/remotes/origin/$cand" >/dev/null 2>&1; then
      target=$cand
      known=1
    elif git -C "$dir" rev-parse -q --verify "$cand^{commit}" >/dev/null 2>&1; then
      known=1
    fi
  fi
  if [ "$known" = 1 ]; then
    switched_top=$(repo_top "$dir")
    switched_branch=$target
  fi
  return 0
}

# Refuse ordinary file edits in primary/default checkouts. Non-repo scratch stays allowed.
protect_checkout() {
  local path=$1 parent top
  case "$path" in /* | [A-Za-z]:* | \\*) ;; *) path="$cwd/$path" ;; esac
  parent=$(dirname "$path")
  while [ ! -d "$parent" ] && [ "$parent" != . ] && [ "$parent" != / ]; do
    parent=$(dirname "$parent")
  done
  top=$(repo_top "$parent")
  [ -n "$top" ] || return 0
  is_home_repo "$top" && return 0
  [ -f "$top/.git" ] || deny "file edits require a linked item worktree; leave the original checkout untouched"
  require_burn_branch "$top" "file edit"
}

require_burn_branch() {
  local dir=$1 what=$2 br
  known_dir "$dir" "$what"
  is_home_repo "$dir" && return 0
  br=$(branch_in "$dir")
  case "$br" in burn/*) return 0 ;; esac
  deny "$what is only allowed on a burn/ branch, and $dir is on ${br:-a detached HEAD or no repository}. Create a burn/<date>-<item> branch first"
}

has_arg() { # case-sensitive: is $1 one of the remaining words?
  local want=$1 a
  shift
  for a in "$@"; do
    unquote "$a"
    [ "$REPLY" = "$want" ] && return 0
  done
  return 1
}

cost_gate() {
  local state
  state=$(bash "$(dirname "$0")/usage.sh") || deny "usage check failed; save a handoff and stop"
  case "$state" in *"verdict=go"* | *"verdict=wrap"*) return 0 ;; esac
  deny "fresh usage below the stop line is required; save a handoff and stop"
}

check_push() {
  local dir=$1 remote="" refs=0 a dst
  shift
  cost_gate
  local policy url github_repo
  . "$(dirname "$0")/lib.sh"
  policy=$(config_value push_branches never)
  case "$policy" in never) deny "push_branches is never; keep the branch and verified backup local" ;; private | all) ;; *) deny "invalid push policy" ;; esac
  for a in "$@"; do
    unquote "$a"
    a=$REPLY
    case "$a" in
      --force | --force-with-lease* | --force-if-includes | --mirror | --all | --tags | --prune | --follow-tags)
        deny "git push $a is not allowed. Push one burn/ branch at a time, without force" ;;
      -o | --push-option* | --repo* | --receive-pack* | --exec*)
        deny "git push $a is not allowed in a burn run" ;;
      --*) continue ;;
      -*)
        # Short flags can be clustered: -uf is -u -f.
        case "${a#-}" in *f*) deny "git push $a includes -f, a force push" ;; esac
        continue
        ;;
    esac
    if [ -z "$remote" ]; then
      remote=$a
      [ "$remote" = origin ] || deny "pushes must name the configured origin remote"
      known_dir "$dir" "git push"
      url=$(git -C "$dir" remote get-url --push --all origin 2>/dev/null) || deny "origin push URL cannot be verified"
      [ -n "$url" ] || deny "origin has no effective push destination"
      case "$url" in *$'\n'*) deny "origin has multiple push destinations; configure one reviewed destination before an unattended run" ;; esac
      if [ "$policy" = private ]; then
        case "$url" in
          https://github.com/*) github_repo=${url#https://github.com/} ;;
          git@github.com:*) github_repo=${url#git@github.com:} ;;
          *) deny "private pushes require a verifiable GitHub origin" ;;
        esac
        github_repo=${github_repo%.git}
        [[ $github_repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || deny "invalid GitHub push destination"
        [ "$(gh repo view "$github_repo" --json isPrivate --jq .isPrivate 2>/dev/null)" = true ] ||
          deny "origin is public or its private visibility cannot be verified"
      fi
      continue
    fi
    refs=$((refs + 1))
    case "$a" in +*) deny "git push $a is a force push" ;; esac
    dst=$a
    case "$a" in *:*) dst=${a#*:} ;; esac
    # HEAD (or @) means the current branch.
    case "$dst" in HEAD | @) known_dir "$dir" "git push $a"; dst=$(branch_in "$dir") ;; esac
    case "$dst" in
      burn/* | refs/heads/burn/*) ;;
      *) deny "git push may only push to burn/ branches, and $a is not one" ;;
    esac
  done
  [ "$refs" = 0 ] && deny "name the branch when pushing (git push -u origin burn/...), so nothing else can go up by accident"
  return 0
}

check_git() {
  # $1 = directory the command runs in, then the words after "git"
  local dir=$1 sub="" a br ref top
  shift
  while [ $# -gt 0 ]; do
    unquote "$1"
    a=$REPLY
    # An option's value can be missing (a truncated command), and shift 2 with one word left
    # shifts nothing, which would loop here for ever, so shift what is there.
    if [ "$a" = -C ]; then
      resolve_dir "${2:-.}" "$dir"
      dir=$REPLY
      shift $(($# > 1 ? 2 : 1))
      continue
    fi
    if [ "$a" = -c ]; then
      # Without its quotes: git -c "remote.origin.pushurl=..." is the same setting.
      unquote "${2:-}"
      case "$REPLY" in
        remote.* | url.* | include.* | includeif.* | *hookspath* | *credential* | *sshcommand* | *askpass* | *extraheader*)
          deny "git -c $REPLY changes hooks, credentials, where git pushes or which settings it loads" ;;
        alias.*) deny "git -c alias.* hides which git command runs" ;;
        *"$subst"*) deny "git -c with a command substitution hides which setting it changes" ;;
      esac
      shift $(($# > 1 ? 2 : 1))
      continue
    fi
    case "$a" in
      --no-verify) deny "--no-verify skips the repository's hooks; never skip them" ;;
      --config-env | --config-env=*) deny "git --config-env takes a setting from the environment, which hides its value" ;;
      # These take a value, and it can be the next word: read as the subcommand, the path in
      # git --git-dir <path> push let the push through unchecked. The repository or work tree
      # they name is the folder the branch rules judge.
      --git-dir | --work-tree)
        resolve_dir "${2:-.}" "$dir"
        dir=$REPLY
        shift $(($# > 1 ? 2 : 1))
        continue
        ;;
      --git-dir=* | --work-tree=*)
        resolve_dir "${a#*=}" "$dir"
        dir=$REPLY
        shift
        continue
        ;;
      --namespace | --attr-source) shift $(($# > 1 ? 2 : 1)) ;;
      -*) shift ;;
      *) sub=$a; shift; break ;;
    esac
  done
  # Redirections aren't arguments: git push origin burn/x 2>/dev/null pushes one branch, not
  # two. One glued to an argument stays in it, and the rules still read the name in front:
  # burn/x>log as a burn/ branch, main>log as not one.
  # An array, so a quoted string stays one word (join_quoted): git rebase -x "npm test" main.
  local -a kept
  local skip=0
  kept=()
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in
      ">" | ">>" | [0-9]">" | [0-9]">>" | "&>" | "&>>" | "<" | [0-9]"<" | "<<<") skip=1; continue ;;
      ">"* | [0-9]">"* | "&>"* | "<"* | [0-9]"<"*) continue ;;
    esac
    kept[${#kept[@]}]=$a
  done
  set -- ${kept[@]+"${kept[@]}"}
  local args=" $* "
  case "$args" in *" --no-verify "*) deny "--no-verify skips the repository's hooks; never skip them" ;; esac

  case "$sub" in
    push) check_push "$dir" "$@" ;;
    am)
      case "$args" in *" --abort "* | *" --quit "* | *" --skip "* | *" --show-current-patch"*) return 0 ;; esac
      deny "git am commits a patch without the staged checks. Apply it with git apply, review it, then commit"
      ;;
    commit | cherry-pick | revert | rebase)
      if [ "$sub" = rebase ]; then
        local exec_next=0
        for a in "$@"; do
          if [ "$exec_next" = 1 ]; then nested_command "$dir" "$a"; exec_next=0; continue; fi
          # Case matters: -X is a merge strategy option.
          if [ "$a" = -x ] || [ "$a" = --exec ]; then exec_next=1; fi
          case "$a" in --exec=*) nested_command "$dir" "${a#--exec=}" ;; esac
        done
      fi
      if [ "$sub" = commit ]; then
        local skip_value=0 quote=""
        for a in "$@"; do
          if [ -n "$quote" ]; then
            odd_quote "$a" "$quote"; [ -n "$REPLY" ] && quote=""
            continue
          fi
          if [ "$skip_value" = 1 ]; then
            odd_quote "$a" ""; quote=$REPLY; skip_value=0; continue
          fi
          case "$a" in
            -m | --message | -F | --file | -C | --reuse-message) skip_value=1 ;;
            --message=* | --file=* | --allow-empty | --allow-empty-message | --amend | --no-edit | -s | --signoff | -v | --verbose | -q | --quiet | --dry-run) ;;
            *) deny "commit only the staged index with -m or -F; automatic staging, path arguments and unknown flags bypass the staged scan" ;;
          esac
        done
        for a in "$@"; do
          unquote "$a"
          case "$REPLY" in --*) ;; -*n*) deny "git commit $REPLY includes -n, which skips the repository's hooks; never skip them" ;; esac
        done
      fi
      case "$args" in *" --abort "* | *" --quit "* | *" --skip "*) return 0 ;; esac
      require_burn_branch "$dir" "git $sub"
      if [ "$sub" = commit ]; then
        is_home_repo "$dir" || check_staged_paths "$dir"
        bash "$(dirname "$0")/leak-check.sh" "$dir" >/dev/null 2>&1 ||
          deny "staged leak check found a possible secret or could not run; run leak-check.sh for locations only"
      fi
      ;;
    pull | merge)
      case "$args" in *" --abort "* | *" --quit "*) return 0 ;; esac
      known_dir "$dir" "git $sub"
      is_home_repo "$dir" && return 0
      br=$(branch_in "$dir")
      case "$br" in burn/*) return 0 ;; esac
      # Everything named that isn't an option or an option's value. For pull, the first is the
      # remote.
      local refs="" skip=0 remote_seen=0 inq=""
      for a in "$@"; do
        # Words were split on spaces, so a quoted message ("Merge it") spans several. Skip
        # from a word that opens a quote to the one that closes it: that's never a ref.
        if [ -n "$inq" ]; then
          case "$a" in *"$inq") inq="" ;; esac
          continue
        fi
        case "$a" in
          \"*\" | \'*\') ;;
          \"*) inq='"'; skip=0; continue ;;
          \'*) inq="'"; skip=0; continue ;;
        esac
        unquote "$a"
        a=$REPLY
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$a" in
          -m | -F | -s | -X | --message | --file | --strategy | --strategy-option | --log | --cleanup) skip=1; continue ;;
          -*) continue ;;
        esac
        if [ "$sub" = pull ] && [ "$remote_seen" = 0 ]; then remote_seen=1; continue; fi
        refs="$refs ${a#origin/}"
      done
      # With no ref, or only the branch's own upstream, and --ff-only, the branch can only move
      # to where origin already has it.
      case "$args" in
        *" --ff-only "*)
          case "$refs" in "" | " $br" | " @{u}" | " @{upstream}") return 0 ;; esac
          ;;
      esac
      [ -n "$refs" ] || deny "git $sub on ${br:-this branch} without --ff-only can create commits that aren't on a burn/ branch"
      top=$(repo_top "$dir")
      for ref in $refs; do
        case "$ref" in
          burn/*)
            merge_approved "$ref" "$(basename "${top:-$dir}")" ||
              deny "merging $ref into ${br:-this branch} needs a ticked Merge on its card in INBOX.md, and there isn't one"
            ;;
          *) deny "the only merges allowed onto a non-burn branch are burn/ branches the user approved in INBOX.md, and fast-forwards from the branch's own upstream" ;;
        esac
      done
      return 0
      ;;
    reset)
      case "$args" in *" --hard "*) deny "git reset --hard throws away work. Use a new branch or git stash instead" ;; esac
      require_burn_branch "$dir" "git reset"
      ;;
    clean)
      for a in "$@"; do
        unquote "$a"
        case "$REPLY" in
          --force) deny "git clean --force deletes untracked files, which may be the user's work" ;;
          --*) ;;
          -*f*) deny "git clean -f deletes untracked files, which may be the user's work" ;;
        esac
      done
      ;;
    checkout | switch)
      cost_gate
      for a in "$@"; do
        unquote "$a"
        a=$REPLY
        case "$a" in
          -f | --force | --discard-changes) deny "git $sub $a discards uncommitted work" ;;
          . | :/ | "*") deny "git $sub $a discards every uncommitted change in the tree" ;;
        esac
        if [ "$a" = -B ] || { [ "$sub" = switch ] && [ "$a" = -C ]; }; then
          case "$args" in *" $a burn/"*) ;; *) deny "git $sub $a resets an existing branch; only burn/ branches may be reset" ;; esac
        fi
      done
      note_switch "$dir" "$sub" "$@"
      ;;
    restore)
      if has_arg --staged "$@" || has_arg -S "$@"; then
        has_arg --worktree "$@" || has_arg -W "$@" || return 0
      fi
      for a in "$@"; do
        unquote "$a"
        case "$REPLY" in . | :/ | "*") deny "git restore $REPLY discards every uncommitted change in the tree" ;; esac
      done
      ;;
    stash)
      case "$args" in *" drop "* | *" clear "*) deny "git stash drop/clear deletes stashed work" ;; esac
      ;;
    branch)
      local destructive=0
      for a in "$@"; do
        unquote "$a"
        case "$REPLY" in -d | --delete | -m | --move | -f | --force | -c | --copy) destructive=1 ;; esac
      done
      if [ "$destructive" = 1 ]; then
        for a in "$@"; do
          unquote "$a"
          case "$REPLY" in -* | burn/*) ;; *) deny "git branch with delete, move or force only applies to burn/ branches, not $REPLY" ;; esac
        done
      fi
      ;;
    tag)
      case "$args" in *" -d "* | *" --delete "* | *" -f "* | *" --force "*) deny "deleting or moving tags is not part of a burn run" ;; esac
      ;;
    update-ref | filter-branch | filter-repo | replace | gc | prune)
      deny "git $sub rewrites or prunes history" ;;
    reflog)
      case "$args" in *" expire "* | *" delete "*) deny "git reflog expire/delete removes recovery points" ;; esac ;;
    config)
      case "$args" in *" --get"* | *" -l "* | *" --list "* | *" --show-origin "* | *" --show-scope "*) return 0 ;; esac
      # Newer git: "git config get <key>" and "git config list". Older: one bare key reads it.
      unquote "${1:-}"
      case "$REPLY" in get | list) return 0 ;; esac
      local words=0
      for a in "$@"; do
        unquote "$a"
        case "$REPLY" in
          --global | --local | --system | --worktree | --show-origin | --show-scope | --includes | --null | -z | --type=* | --bool | --int | --path) ;;
          -*) words=99 ;;
          *) words=$((words + 1)) ;;
        esac
      done
      [ "$words" = 1 ] && return 0
      deny "git config changes are out of scope for a burn run; reading a key (git config <key>, --get, --list) is fine"
      ;;
    remote)
      unquote "${1:-}"
      case "$REPLY" in add | remove | rm | rename | set-url | set-branches) deny "git remote $REPLY changes where the repository pushes" ;; esac
      ;;
    worktree)
      case "$args" in *" add "*) cost_gate ;; esac
      # Removing a worktree is allowed; --force also throws away its uncommitted work.
      unquote "${1:-}"
      if [ "$REPLY" = remove ]; then
        case "$args" in *" --force "* | *" -f "* | *" -ff "*) deny "git worktree remove --force throws away the uncommitted work in a worktree. Commit or stash it first" ;; esac
      fi
      ;;
    credential | credential-*) deny "git credential reads stored credentials" ;;
    send-pack | http-push) deny "git $sub pushes without the push checks; use git push -u origin burn/..." ;;
    send-email | imap-send) deny "git $sub sends the work out by mail" ;;
    daemon | instaweb) deny "git $sub serves the repository on the network" ;;
    # Commands git starts for itself are shell text of their own.
    submodule)
      unquote "${1:-}"
      if [ "$REPLY" = foreach ]; then
        shift
        while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
        nested_command "$dir" "$@"
      fi
      ;;
    bisect)
      unquote "${1:-}"
      [ "$REPLY" = run ] && { shift; nested_command "$dir" "$@"; }
      ;;
    "" | add | apply | archive | blame | bundle | cat-file | check-ignore | clone | count-objects | describe | diff | difftool | fetch | for-each-ref | format-patch | fsck | grep | help | init | lfs | log | ls-files | ls-remote | ls-tree | merge-base | merge-tree | mv | name-rev | notes | range-diff | rev-list | rev-parse | rm | shortlog | show | show-ref | sparse-checkout | status | symbolic-ref | var | version | whatchanged) ;;
    *)
      # Any other name may be an alias, which runs anything (alias.ship = push origin HEAD:main)
      # under a name the rules above don't know. Git ignores an alias that shadows a built-in,
      # so the common built-ins listed above skip the lookup.
      git -C "${dir:-.}" config --get "alias.$sub" >/dev/null 2>&1 &&
        deny "git $sub is a git alias, so the guard can't see the command it runs. Use the git command itself"
      ;;
  esac
  return 0
}

# A command git starts for itself (submodule foreach, rebase --exec, bisect run) is checked as
# shell text. $1 = the folder, then its words; a quoted script loses its outer quotes.
nested_command() {
  local dir=$1 text
  shift
  text="$*"
  case "$text" in
    \"*\") text=${text#\"}; text=${text%\"} ;;
    \'*\') text=${text#\'}; text=${text%\'} ;;
  esac
  [ -n "$text" ] && check_text "$dir" "$text" 1
  return 0
}

# Protected files can change by routes the guard doesn't parse (sed -i, cp, tee, a script), so a
# commit that would include one is refused however it was edited: CI runs a pushed workflow with
# the repository's secrets. Renames count as a delete and an add, so moving one away is seen too.
check_staged_paths() {
  local f
  while IFS= read -r -d '' f; do
    protected_path "$1/$f" &&
      deny "the commit would include $f, which is agent, CI or git configuration. Unstage it (git restore --staged) and write the change up for the user"
  done < <(git -C "$1" diff --cached --name-only --no-renames -z 2>/dev/null)
  return 0
}

check_gh() {
  unquote "${1:-}"
  local sub=$REPLY act args=" $* "
  unquote "${2:-}"
  act=$REPLY
  case "$sub" in
    pr) case "$act" in create | merge | close | comment | review | edit | ready | reopen | lock | unlock | update-branch) deny "gh pr $act acts on GitHub in the user's name; list it as a job for them instead" ;; esac ;;
    issue) case "$act" in create | close | comment | edit | delete | reopen | transfer | lock | unlock | pin | unpin | develop) deny "gh issue $act acts on GitHub in the user's name" ;; esac ;;
    release) case "$act" in create | upload | delete | delete-asset | edit) deny "gh release $act publishes" ;; esac ;;
    repo) case "$act" in create | delete | edit | fork | rename | archive | unarchive | sync | set-default | deploy-key) deny "gh repo $act changes a repository on GitHub" ;; esac ;;
    secret | variable | auth | ssh-key | gpg-key | codespace | extension | cache | ruleset | attestation)
      deny "gh $sub is out of scope for a burn run" ;;
    workflow) case "$act" in run | enable | disable) deny "gh workflow $act starts or changes CI" ;; esac ;;
    run) case "$act" in rerun | cancel | delete) deny "gh run $act changes CI runs" ;; esac ;;
    gist | label | project) case "$act" in list | view | "") ;; *) deny "gh $sub $act writes to GitHub" ;; esac ;;
    alias) case "$act" in set | import | delete) deny "gh alias $act changes what a gh command name runs" ;; esac ;;
    config) case "$act" in set) deny "gh config set changes gh's own settings" ;; esac ;;
    api)
      # Every method given must be GET, and fields or an input body need an explicit GET, since
      # gh sends them as a POST otherwise. A value follows its option as the next word, after
      # "=", or attached (-XPOST, -ftitle=x): matching only " -f " let the other forms through.
      local a nxt="" get=0 body=0
      shift
      for a in "$@"; do
        unquote "$a"
        a=$REPLY
        if [ "$nxt" = method ]; then
          [[ $a == GET ]] || deny "gh api -X $a writes to GitHub; only GET is allowed"
          get=1
          nxt=""
          continue
        fi
        if [ "$nxt" = value ]; then nxt=""; continue; fi
        case "$a" in
          -X | --method) nxt=method ;;
          --method=* | -X?*)
            a=${a#--method=}
            a=${a#-X}
            [[ $a == GET ]] || deny "gh api with method $a writes to GitHub; only GET is allowed"
            get=1
            ;;
          -f | -F | --field | --raw-field | --input) body=1; nxt=value ;;
          -f?* | -F?* | --field=* | --raw-field=* | --input=*) body=1 ;;
        esac
      done
      [ "$nxt" = method ] && deny "gh api -X without a method can't be checked"
      [ "$body" = 1 ] && [ "$get" = 0 ] && deny "gh api with fields or an input body sends a POST to GitHub; only GET is allowed"
      ;;
  esac
  return 0
}

# A recursive delete is refused in a run, except inside the run's own runs/ and worktrees/
# folders, which the run makes and clears itself. $1 = the command, $2 = the folder it runs in,
# then its words. find's -delete and -exec rm -r are refused too.
check_delete() {
  local w=$1 dir=$2 a t rec=0 targets=0 outside=0 exec_next=0 in_exec=0 exec_rm=0 execw=""
  shift 2
  if [ "$w" = find ]; then
    for a in "$@"; do
      unquote "$a"
      t=$REPLY
      [ "$t" = -delete ] && deny "find -delete removes files and whole folder trees in one step. A burn run doesn't delete recursively: write it up for the user"
      if [ "$exec_next" = 1 ]; then
        exec_next=0
        execw=$a
        case "$t" in rm | rimraf | rmdir) exec_rm=1 ;; esac
        continue
      fi
      case "$t" in
        -exec | -execdir | -ok | -okdir) exec_next=1; in_exec=1; exec_rm=0 ;;
        ';' | '\;' | '+')
          # The command find runs for each file is checked like any other command.
          [ -n "$execw" ] && nested_command "$dir" "$execw"
          execw=""
          in_exec=0
          exec_rm=0
          ;;
        *)
          [ "$in_exec" = 1 ] && execw="$execw $a"
          [ "$in_exec" = 1 ] && [ "$exec_rm" = 1 ] || continue
          case "$t" in
            rimraf) deny "find -exec rimraf deletes folder trees. A burn run doesn't do that: write it up for the user" ;;
            --recursive) deny "find -exec rm --recursive deletes folder trees. A burn run doesn't do that: write it up for the user" ;;
            --*) ;;
            -*[rR]*) deny "find -exec rm with -r deletes folder trees. A burn run doesn't do that: write it up for the user" ;;
          esac
          ;;
      esac
    done
    [ -n "$execw" ] && nested_command "$dir" "$execw"
    return 0
  fi
  case "$w" in rimraf) deny "rimraf deletes folder trees. A burn run doesn't do that: write it up for the user" ;; esac
  for a in "$@"; do
    unquote "$a"
    t=$REPLY
    case "$t" in
      --recursive | /s) rec=1; continue ;;
      --*) continue ;;
      /[a-zA-Z]) continue ;;
      -*)
        # Short flags, possibly clustered (rm -rf). PowerShell's -Force has an r in it, so there
        # only -Recurse and its prefixes count.
        if [ "$tool" = PowerShell ]; then
          case "$t" in -r | -re | -rec | -recu | -recur | -recurs | -recurse) rec=1 ;; esac
        else
          case "$t" in *[rR]*) rec=1 ;; esac
        fi
        continue
        ;;
    esac
    targets=$((targets + 1))
    resolve_dir "$t" "$dir"
    norm "$REPLY"
    case "$REPLY" in
      */../* | */..) outside=1 ;;
      "$home_n"/runs/* | "$home_n"/worktrees/*) ;;
      *) outside=1 ;;
    esac
  done
  [ "$rec" = 1 ] || return 0
  [ "$targets" -gt 0 ] && [ "$outside" = 0 ] && return 0
  deny "$w deletes a folder tree. A burn run only deletes inside its own runs/ and worktrees/ folders; write it up for the user, or remove a worktree with git worktree remove"
}

# words = the words of one simple command, with each quoted string whole. The split was on
# spaces, so "Burn Bot" or "C:/Users/Jane Doe/app" came out as two words, and every rule that
# walks the words lost its place: in GIT_COMMITTER_NAME="Burn Bot" git commit, Bot" was read as
# the command, and the commit went unchecked. If the quotes don't balance (a PowerShell "C:\"
# ends in a backslash), the words stay as they were.
join_quoted() {
  local a q=""
  words=()
  for a in "$@"; do
    if [ -n "$q" ]; then
      words[${#words[@]} - 1]="${words[${#words[@]} - 1]} $a"
      odd_quote "$a" "$q"
      [ -n "$REPLY" ] && q=""
      continue
    fi
    words[${#words[@]}]=$a
    odd_quote "$a" ""
    q=$REPLY
  done
  [ -z "$q" ] || words=("$@")
}

# REPLY = the command a word runs, without its folder or .exe. Outside PowerShell a backslash in
# a bare name is an escape, not a folder separator: g\it runs git.
command_name() {
  unquote "$1"
  local w=$REPLY
  case "$tool:$w" in PowerShell:* | *:*/* | *:*:*) ;; *) w=${w//\\/} ;; esac
  w=${w##*/}
  w=${w##*\\}
  REPLY=${w%.[Ee][Xx][Ee]}
}

# PowerShell takes any unambiguous prefix of a parameter's name (-Meth for -Method) and a value
# after a colon in the same word (-Method:Delete). Sets out, the caller's, to 1 for a body, an
# input file, a form or a method other than GET. $1 = 1 when -b counts as -Body: for curl and wget
# under PowerShell it is also curl's cookie option.
ps_web() {
  local single=$1 a name val method=0
  shift
  for a in "$@"; do
    unquote "$a"
    a=$REPLY
    if [ "$method" = 1 ]; then
      [[ $a == GET ]] || out=1
      method=0
      continue
    fi
    case "$a" in -?*) ;; *) continue ;; esac
    name=${a%%:*}
    val=""
    case "$a" in *:*) val=${a#*:} ;; esac
    case "$name" in
      -me* | -cu*) if [ -n "$val" ]; then [[ $val == GET ]] || out=1; else method=1; fi ;;
      -bo* | -infi* | -fo | -for*) out=1 ;;
      -b) [ "$single" = 1 ] && out=1 ;;
    esac
  done
  [ "$method" = 1 ] && out=1
  return 0
}

# REPLY = how many words come before the command itself: assignments (FOO=1) and commands that
# start another one (env, timeout, xargs, npx ...). check_text uses it as well as check_segment:
# when only the first word was read there, a nested shell behind a prefix went unchecked
# (timeout 600 bash -c "git push origin main").
skip_prefix() {
  local n=$#
  while [ $# -gt 0 ]; do
    unquote "$1"
    case "$REPLY" in
      *=*) shift ;;
      env)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -C* | --chdir* | -S* | --split-string*) deny "env $1 moves the command to another folder or builds it from a string, which the guard can't follow" ;;
            -u | --unset) shift $(($# > 1 ? 2 : 1)) ;;
            --) shift; break ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] || deny "env with no command prints every variable, tokens included"
        ;;
      xargs)
        shift
        # Case matters: -E, -I and -L take the next word, while -e, -i and -l take theirs attached.
        shopt -u nocasematch
        while [ $# -gt 0 ]; do
          case "$1" in
            -a | -d | -E | -I | -L | -n | -P | -s | --arg-file | --delimiter | --eof | --max-args | --max-chars | --max-lines | --max-procs | --replace) shift $(($# > 1 ? 2 : 1)) ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        shopt -s nocasematch
        ;;
      command | builtin | exec | time | nohup)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in -a) shift $(($# > 1 ? 2 : 1)) ;; -*) shift ;; *) break ;; esac
        done
        ;;
      then | do | else | if | while | until | !) shift ;;
      wsl | wsl.exe)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            --cd*) deny "wsl --cd runs the command in a folder the guard doesn't follow; cd there first" ;;
            -d | --distribution | -u | --user | --shell-type) shift $(($# > 1 ? 2 : 1)) ;;
            -e | --exec | --) shift; break ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      # Runners that start another command: look at the command they start.
      # Options with a value shift two words, or one if the value is missing (check_git).
      npx | bunx | pnpx | uvx | stdbuf | caffeinate | systemd-inhibit)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -p | --package | --from | --with) shift $(($# > 1 ? 2 : 1)) ;;
            --) shift; break ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      timeout | nice | ionice)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -k | -s | -n | -c | --kill-after | --signal | --adjustment) shift $(($# > 1 ? 2 : 1)) ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        [ "$REPLY" = timeout ] && [ $# -gt 0 ] && shift
        ;;
      npm | pnpm | yarn | bun)
        unquote "${2:-}"
        case "$REPLY" in
          exec | x | dlx)
            shift 2
            while [ $# -gt 0 ]; do
              case "$1" in
                -p | --package) shift $(($# > 1 ? 2 : 1)) ;;
                --) shift; break ;;
                -*) shift ;;
                *) break ;;
              esac
            done
            ;;
          *) break ;;
        esac
        ;;
      *) break ;;
    esac
  done
  REPLY=$((n - $#))
}

check_segment() {
  # $1 = directory, $2 = one simple command
  local dir=$1 w largs
  set -- $2
  join_quoted "$@"
  set -- ${words[@]+"${words[@]}"}
  skip_prefix "$@"
  shift "$REPLY"
  [ $# -gt 0 ] || return 0
  command_name "$1"
  w=$REPLY
  shift
  largs=" $* "
  case "$w" in
    sudo | doas | su | runas) deny "$w runs as another user" ;;
    git) check_git "$dir" "$@" ;;
    rm | rimraf | rmdir | rd | del | erase | ri | remove-item | find) check_delete "$w" "$dir" "$@" ;;
    gh) check_gh "$@" ;;
    ssh | scp | sftp | rsync | mosh | telnet) deny "$w reaches another machine; a burn run stays on this one" ;;
    vercel | netlify | flyctl | fly | heroku | wrangler | firebase | railway | surge | serverless | sls | eb | amplify | cdk | sam | gcloud | az | doctl | aws)
      deny "$w deploys or changes cloud resources" ;;
    kubectl | helm | terraform | tofu | pulumi | ansible-playbook | nomad | docker-compose)
      case "$w$largs" in
        "kubectl get "* | "kubectl describe "* | "kubectl logs "* | "helm list "* | "helm template "* | "terraform validate "* | "terraform fmt "* | "tofu validate "* | "tofu fmt "*) ;;
        *) deny "$w can change live infrastructure" ;;
      esac
      ;;
    docker | podman)
      case "$largs" in " push "* | " login "* | " logout "*) deny "$w ${1:-} publishes or handles credentials" ;; esac ;;
    npm | pnpm | yarn | bun)
      case "$largs" in
        *" publish "* | *" unpublish "* | *" deprecate "* | *" dist-tag "* | *" owner "* | *" adduser "* | *" login "* | *" token "*)
          deny "$w publishes or handles registry credentials" ;;
        *" -g "* | *" --global "*) deny "installing global packages changes the machine, not the repo" ;;
      esac
      ;;
    cargo)
      case "$largs" in " publish "* | " yank "* | " owner "* | " login "* | " install "*) deny "cargo ${1:-} publishes or changes the machine" ;; esac ;;
    dotnet)
      case "$largs" in *" nuget push "*) deny "dotnet nuget push publishes a package" ;; esac ;;
    twine | flit | hatch | poetry | uv | pdm | gem | mvn | mvnw | gradle | gradlew)
      case "$largs" in
        *" publish "* | *" upload "* | *" push "* | *" deploy "* | *" release "*) deny "$w publishes a package" ;;
        *" tool install "*) deny "uv tool install changes the machine, not the repo" ;;
      esac
      ;;
    pipx | brew | apt | apt-get | dnf | yum | pacman | winget | choco | scoop | snap | port)
      case "$largs" in
        *" install "* | *" upgrade "* | *" remove "* | *" uninstall "* | *" update "*) deny "$w changes the machine, not the repo" ;;
      esac
      ;;
    crontab | schtasks | launchctl | at | systemctl | service | reg | setx)
      case "$w$largs" in
        "systemctl status"* | "systemctl list"* | "systemctl is-"* | "service --status-all"* | "reg query"*) ;;
        *) deny "$w schedules jobs or changes the machine" ;;
      esac
      ;;
    curl | wget | invoke-webrequest | iwr | invoke-restmethod | irm | http | https)
      # Case matters here: curl -X sets the method but -x is a proxy, -F is a form but -f is
      # --fail, -d is data but -D only saves headers.
      local out=0 method_next=0 value_next=0 a opts flag takes_value
      for a in "$@"; do
        unquote "$a"; a=$REPLY
        if [ "$value_next" = 1 ]; then value_next=0; continue; fi
        if [ "$method_next" = 1 ]; then
          [ "$a" = GET ] || out=1
          method_next=0
          continue
        fi
        if [ "${a:0:1}" = - ] && [ "${a:1:1}" != - ]; then
          opts=${a#-}
          while [ -n "$opts" ]; do
            flag=${opts:0:1}; opts=${opts:1}
            if [ "$flag" = X ]; then
              if [ -n "$opts" ]; then [ "$opts" = GET ] || out=1; else method_next=1; fi
              break
            fi
            if [ "$flag" = d ] || [ "$flag" = F ] || [ "$flag" = T ]; then out=1; break; fi
            # These short options consume a value; its letters are not further options.
            takes_value=0
            shopt -u nocasematch
            case "$flag" in a|A|b|c|C|D|e|E|H|K|m|o|P|Q|r|t|u|U|w|x|y|Y|z) takes_value=1 ;; esac
            shopt -s nocasematch
            if [ "$takes_value" = 1 ]; then [ -n "$opts" ] || value_next=1; break; fi
          done
          # PowerShell parameter names are not curl short-option clusters.
          case "$a" in -method | -method=* | -body* | -infile*) ;; *) continue ;; esac
        fi
        case "$a" in
          --request | --method | -method) method_next=1 ;;
          --request=* | --method=* | -method=*) [ "${a#*=}" = GET ] || out=1 ;;
          --data* | --form* | --upload-file* | --json* | --post-data* | --post-file* | -body* | -infile*) out=1 ;;
        esac
      done
      [ "$method_next" = 1 ] && out=1
      # Windows PowerShell 5.1 runs curl and wget as Invoke-WebRequest, so they are read both ways.
      case "$tool:$w" in
        *:invoke-webrequest | *:iwr | *:invoke-restmethod | *:irm) ps_web 1 "$@" ;;
        PowerShell:curl | PowerShell:wget) ps_web 0 "$@" ;;
      esac
      [ "$out" = 1 ] && deny "$w sending data out (POST, PUT, uploads, forms) is not allowed; plain GETs are fine"
      ;;
    printenv) deny "printenv can print tokens" ;;
    set | export | declare | typeset)
      [ $# -eq 0 ] && deny "$w with no arguments prints every variable, tokens included" ;;
    get-childitem | gci | dir | ls | get-item | gi | cat | type | get-content | gc)
      case "$largs" in *" env:"* | *" \$env:"*) deny "listing environment variables can print tokens" ;; esac ;;
    security | cmdkey | keyring | op | bw | pass | gopass | vault)
      deny "$w reads stored secrets" ;;
  esac
  return 0
}

check_shell() {
  local cmd dir seg p re s
  json_str command
  cmd=$REPLY
  [ -n "$cmd" ] || deny "could not read the command, so it cannot be checked"
  case "$cmd" in *"$subst"*) deny "the command contains a control byte the guard uses internally, so it can't be checked" ;; esac

  case "$cmd" in *burn-guard-selftest*) deny "self-test OK, the guard is active for this session" ;; esac

  # Whole-command checks: the run's own controls, settings, stored credentials.
  # Reading the inbox or the guard's files from the shell is harmless; writing them is not.
  # Anything that names one of them and could write (a redirect into it, a file-moving tool,
  # an interpreter, or a git command that rewrites files) is refused.
  case "$cmd" in
    *inbox.md* | *burn-my-usage/active* | *burn-my-usage\\active* | *"$home"/active* | *"$home_n"/active* | *guard.log* | *guard-deny.txt* | *guard-allow-mcp.txt* | *roots.txt*)
      re='>[[:space:]]*["'"'"']?[^[:space:]]*(inbox\.md|/active|\\active|guard\.log|guard-deny\.txt|guard-allow-mcp\.txt|roots\.txt)'
      [[ $cmd =~ $re ]] && deny "INBOX.md, the run markers and the guard's files are never written from the shell. Edit the inbox with the Edit tool; the run ends with stop.sh"
      re='(^|[^a-z0-9_.-])(tee|mv|cp|rm|rmdir|del|erase|truncate|dd|ln|touch|install|chmod|unlink|shred|set-content|add-content|out-file|clear-content|remove-item|move-item|copy-item|rename-item|new-item|python3?|py|node|deno|bun|ruby|perl|php|awk|gawk)([^a-z0-9_-]|$)|sed[^|;&]*[[:space:]]-[a-z]*i|git[[:space:]][^|;&]*(checkout|restore|reset|stash|rm|mv|clean|apply)'
      [[ $cmd =~ $re ]] && deny "INBOX.md, the run markers and the guard's files are never changed from the shell. Read them with Read, edit the inbox with Edit; the run ends with stop.sh"
      ;;
  esac
  case "$cmd" in
    *.claude/settings* | *.claude\\settings* | *.git/hooks* | *.git\\hooks* | *core.hookspath*)
      deny "the command touches Claude Code settings or git hooks" ;;
    *"gh auth token"* | *"git credential"* | *"auth print-access-token"* | *"configure get"* | *.git-credentials*)
      deny "the command reads stored credentials" ;;
  esac
  re='(curl|wget|iwr|invoke-webrequest|irm|invoke-restmethod)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?((ba|z|da|k)?sh|iex|invoke-expression|python3?|node|perl|ruby)([[:space:]]|$)'
  [[ $cmd =~ $re ]] && deny "piping a download into a shell runs code nobody has read"
  # Expanding an environment variable that looks like a secret prints it. Environment variables
  # are ALL CAPS by convention ($GITHUB_TOKEN), so lower-case names ($max_tokens, a PowerShell
  # $apiKey) and anything inside single quotes (a grep pattern, which nothing expands) pass.
  s=$cmd
  re="'[^']*'"
  while [[ $s =~ $re ]]; do s=${s/"${BASH_REMATCH[0]}"/ }; done
  re='\$env:[A-Za-z0-9_]*(token|secret|passw|api_?key|private_key|credential|access_key)'
  [[ $s =~ $re ]] && deny "the command expands an environment variable that looks like a secret"
  shopt -u nocasematch
  re='\$\{?[A-Z0-9_]*(TOKEN|SECRET|PASSW|API_?KEY|PRIVATE_KEY|CREDENTIAL|ACCESS_KEY)'
  if [[ $s =~ $re ]]; then
    shopt -s nocasematch
    deny "the command expands a variable that looks like a secret"
  fi
  # Git takes settings from the environment as well as from -c (aliases, push URLs, hooks,
  # credential helpers), and another repository, work tree or index, which the branch rules and
  # the staged scan wouldn't see. A burn run sets none of them. Shell names are case-sensitive;
  # PowerShell's $env: names are not.
  local gitenv='GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+|PARAMETERS|GLOBAL|SYSTEM)|GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_SSH|GIT_SSH_COMMAND|GIT_ASKPASS|SSH_ASKPASS'
  re="(^|[^A-Za-z0-9_])($gitenv)="
  if [[ $s =~ $re ]]; then
    shopt -s nocasematch
    deny "the command sets git configuration, a repository or an index through the environment, which hides what git will do"
  fi
  shopt -s nocasematch
  re="\\\$env:($gitenv)[[:space:]]*="
  [[ $s =~ $re ]] && deny "the command sets git configuration, a repository or an index through the environment, which hides what git will do"
  # Text piped into a shell is commands nobody here can read: echo "git push ..." | sh. A shell
  # with only options after the pipe (or -s) reads them from the pipe; one given a -c script
  # doesn't. The full text is matched, so a quoted -c script still counts as one.
  local nl=$'\n'
  re='\|[[:space:]]*(sudo[[:space:]]+)?((ba|z|da|k|c|tc|fi)?sh|pwsh|powershell)(\.exe)?([[:blank:]]+-[A-Za-z-]*)*[[:blank:]]*($|[;&|)]|'"$nl"')'
  [[ $cmd =~ $re ]] && deny "piping text into a shell runs commands the guard can't read"
  re='\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k|c|tc|fi)?sh(\.exe)?[[:blank:]]+(-[A-Za-z]+[[:blank:]]+)*-[A-Za-z]*s'
  [[ $cmd =~ $re ]] && deny "piping text into a shell runs commands the guard can't read"
  re='\|[[:space:]]*(iex|invoke-expression)([[:space:]]|$)'
  [[ $cmd =~ $re ]] && deny "piping text into Invoke-Expression runs commands the guard can't read"
  for p in $cmd; do
    unquote "$p"
    p=$REPLY
    case "$p" in -* | *://*) continue ;; esac
    case "$p" in
      *.env* | *.pem | *.key | *id_rsa* | *id_ed25519* | *id_ecdsa* | *.ssh/* | *.aws/* | *credentials* | *token.json | *.tfstate* | *secrets.* | *.netrc | *.npmrc | *.pypirc | *.p12 | *.pfx)
        secret_path "$p" && deny "$p looks like a secret or credential file" ;;
    esac
  done

  if [ -f "$home/guard-deny.txt" ]; then
    while IFS= read -r p || [ -n "$p" ]; do
      p=${p%$'\r'}
      case "$p" in "" | "#"*) continue ;; esac
      [[ $cmd =~ $p ]] && deny "the command matches '$p' in guard-deny.txt"
    done <"$home/guard-deny.txt"
  fi

  check_text "$cwd" "$cmd" 0
}

# Splits shell text into simple commands, one per line, the way a shell would: separators
# (; & && || | and newlines) and subshells start a new command, but only outside quotes, so a
# commit message or a quoted grep pattern stays one argument.
#
# A command substitution ($( ), backticks, <( ) and >( ), and in PowerShell any ( )) runs as
# commands of its own, so its text becomes lines of its own, even inside double quotes. It is
# also an argument of the command around it, which keeps its other words with $subst in the
# substitution's place. Splitting that command apart instead left 'push origin main' from
# 'git -C "$(...)" push origin main' with no command name, so nothing checked it.
#
# A heredoc's body is data and is dropped, unless the heredoc feeds a shell (bash <<EOF),
# whose body is commands and is kept. In PowerShell ($2 = 1) a backtick escapes the next
# character instead of starting a command.
split_commands() {
  printf '%s' "$1" | LC_ALL=C awk -v ps="${2:-0}" -v ph="$subst" '
    function segword(   cur, n, i, w, a) {
      cur = substr(out, segstart)
      n = split(cur, a, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        w = a[i]
        if (w == "" || w ~ /=/) continue
        gsub(/["\047]/, "", w)
        sub(/.*[\/\\]/, "", w)
        return tolower(w)
      }
      return ""
    }
    function sep() { out = out "\n"; segstart = length(out) + 1 }
    # Each open ( or substitution is a frame: ft = its closer, rq = the quote to restore after
    # it, ty = "sub" or "group". A substitution puts ph in the command around it, saves that
    # command (ob, os) and collects its own text in a fresh out, which joins extra on close.
    function open_sub(closer, quote) {
      out = out ph
      sp++; ft[sp] = closer; rq[sp] = quote; ty[sp] = "sub"; ob[sp] = out; os[sp] = segstart
      out = ""; segstart = 1; q = ""
    }
    function open_group() { sp++; ft[sp] = ")"; rq[sp] = ""; ty[sp] = "group"; sep() }
    function close_frame() {
      if (ty[sp] == "sub") { extra = extra out "\n"; out = ob[sp]; segstart = os[sp]; q = rq[sp]; sp-- }
      else { q = rq[sp]; sp--; sep() }
    }
    BEGIN { RS = "\001" }
    {
      s = $0; n = length(s); out = ""; extra = ""; segstart = 1; q = ""; sp = 0; hd = ""; hdtabs = 0
      i = 1
      while (i <= n) {
        c = substr(s, i, 1)
        if (ps == 1 && c == "`" && q != "\047") { out = out substr(s, i, 2); i += 2; continue }
        if (q == "\047") {
          out = out (c == "\n" ? " " : c)
          if (c == "\047") q = ""
          i++; continue
        }
        if (q == "\"") {
          if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
          if (substr(s, i, 2) == "$(") { open_sub(")", "\""); i += 2; continue }
          if (c == "`") { open_sub("`", "\""); i++; continue }
          if (c == "\"") q = ""
          out = out (c == "\n" ? " " : c)
          i++; continue
        }
        if (c == "\\") {
          nx = substr(s, i + 1, 1)
          out = out (nx == "\n" ? " " : c nx)
          i += 2; continue
        }
        if (c == "\047" || c == "\"") { q = c; out = out c; i++; continue }
        if (c == "`") {
          if (sp > 0 && ft[sp] == "`") close_frame()
          else open_sub("`", "")
          i++; continue
        }
        if (substr(s, i, 2) == "$(") { open_sub(")", ""); i += 2; continue }
        if (c == "(") {
          pc = substr(s, i - 1, 1)
          if (ps == 1 || pc == "<" || pc == ">") open_sub(")", "")
          else open_group()
          i++; continue
        }
        if (c == ")") {
          if (sp > 0 && ft[sp] == ")") close_frame()
          else sep()
          i++; continue
        }
        if (substr(s, i, 3) == "<<<") { out = out "<<<"; i += 3; continue }
        if (substr(s, i, 2) == "<<") {
          j = i + 2; tabs = 0
          if (substr(s, j, 1) == "-") { tabs = 1; j++ }
          while (substr(s, j, 1) == " ") j++
          d = ""; qc = substr(s, j, 1)
          if (qc == "\047" || qc == "\"") {
            k = index(substr(s, j + 1), qc)
            if (k > 0) { d = substr(s, j + 1, k - 1); j = j + k + 1 }
          } else {
            while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_.-]/) { d = d substr(s, j, 1); j++ }
          }
          w = segword()
          if (d != "" && w !~ /^(bash|sh|zsh|dash|ksh|pwsh|powershell|eval|source|\.)$/) { hd = d; hdtabs = tabs }
          out = out "<<"; i = j; continue
        }
        two = substr(s, i, 2)
        if (two == "&&" || two == "||") { sep(); i += 2; continue }
        # An & inside a redirection (2>&1, >&2, &>file) is part of it, not a separator.
        if (c == "&" && (two == "&>" || substr(s, i - 1, 1) ~ /[<>]/)) { out = out c; i++; continue }
        # ${NAME} is one word, not a group: keep it whole, so ${HOME}/x is a single redirect target.
        # Only a plain name qualifies. ${x:-$(cmd)} must keep its substitution visible to the checks.
        if (substr(s, i, 2) == "${") { k = index(substr(s, i + 2), "}"); if (k > 1 && substr(s, i + 2, k - 1) ~ /^[A-Za-z_][A-Za-z0-9_]*$/) { out = out substr(s, i, k + 2); i += k + 2; continue } }
        if (c == ";" || c == "|" || c == "&" || c == "{" || c == "}") { sep(); i++; continue }
        if (c == "\n") {
          sep(); i++
          if (hd != "") {
            while (i <= n) {
              k = index(substr(s, i), "\n")
              line = (k > 0) ? substr(s, i, k - 1) : substr(s, i)
              i = (k > 0) ? i + k : n + 1
              if (hdtabs) sub(/^\t+/, "", line)
              sub(/\r$/, "", line)
              if (line == hd) break
            }
            hd = ""
          }
          continue
        }
        out = out c; i++
      }
      # An unclosed substitution still gets checked.
      while (sp > 0) {
        if (ty[sp] == "sub") { extra = extra out "\n"; out = ob[sp]; segstart = os[sp] }
        sp--
      }
      print out
      printf "%s", extra
    }'
}

# REPLY = the quote character a word opens or closes, if it holds an odd number of them, else "".
# $1 = the word, $2 = the quote to count ("" for whichever comes first). Escaped quotes don't count.
odd_quote() {
  local s=${1//\\\\/} c=$2 n
  s=${s//\\\"/}
  case "$c:$1" in "':"* | ":'"*) ;; *) s=${s//\\\'/} ;; esac
  if [ -z "$c" ]; then
    case "$s" in *[\'\"]*) c=${s#"${s%%[\'\"]*}"}; c=${c:0:1} ;; esac
  fi
  case "$c" in
    "'") n=${s//[!\']/} ;;
    '"') n=${s//[!\"]/} ;;
    *) n="" ;;
  esac
  REPLY=""
  [ $((${#n} % 2)) = 1 ] && REPLY=$c
  return 0
}

# Refuses redirects that write outside the allowed folders. $1 = directory, then the words.
# The words were split on spaces, so a quoted string spans several of them, and a > inside it
# (an awk or sed program, a commit message, a command for ssh or bash -c) is text, not a
# redirection: follow the quote across words and skip what's inside. The splitter keeps quoted
# strings whole, so quotes balance in a well-formed command. If they don't, the count went
# wrong ('C:\' ends in a backslash, say) and skipping could hide a real redirection, so every
# word is checked as if nothing were quoted.
check_redirects() {
  local dir=$1
  shift
  scan_redirects "$dir" 1 "$@"
  [ -n "$REPLY" ] && scan_redirects "$dir" 0 "$@"
  return 0
}

# $1 = directory, $2 = 1 to skip quoted text, then the words. REPLY = a quote left open, if any.
scan_redirects() {
  local dir=$1 quoted=$2 a t target next=0 q=""
  shift 2
  for a in "$@"; do
    if [ -n "$q" ]; then
      odd_quote "$a" "$q"
      [ -n "$REPLY" ] && q=""
      continue
    fi
    t=""
    if [ "$next" = 1 ]; then
      t=$a
      next=0
    else
      case "$quoted$a" in
        1\"* | 1\'*) ;;
        ?">" | ?">>" | ?[0-9]">" | ?[0-9]">>" | ?"&>" | ?"&>>") next=1 ;;
        ?*">&") next=1 ;;
        ?*">&"*)
          # >&file sends both streams to a file. 2>&1 and >&2 duplicate a descriptor, so they're fine.
          t=${a#*>&}
          case "$t" in [0-9-]*) t= ;; esac
          ;;
        ?*">"?*) t=${a#*>}; t=${t#>} ;;
      esac
    fi
    if [ "$quoted" = 1 ]; then
      odd_quote "$a" ""
      q=$REPLY
    fi
    [ -n "$t" ] || continue
    unquote "$t"
    t=$REPLY
    case "$t" in "&"* | /dev/null | /dev/stdout | /dev/stderr | nul | NUL | '$null') continue ;; esac
    resolve_dir "$t" "$dir"
    # A target named by a command substitution can't be known in advance, like one in a variable.
    [ -n "$REPLY" ] || continue
    target=$REPLY
    reject_parent_write "$target"
    cost_gate
    protect_checkout "$target"
    outside_roots "$target" && deny "the redirect writes $t, outside the folders this run may change (roots.txt in the burn home)"
    protected_path "$target" && deny "the redirect writes $t, which is agent, CI or git configuration or one of the run's own controls"
    long_name "$target"
    [ -n "$REPLY" ] && protected_path "$REPLY" && deny "the redirect writes $t, which is agent, CI or git configuration or one of the run's own controls"
  done
  REPLY=$q
  return 0
}

# Checks shell text: each simple command in it, following cd so git knows which repo it is
# in. $1 = starting directory, $2 = text, $3 = nesting depth (bash -c inside bash -c ...).
check_text() {
  local dir=$1 depth=$3 seg s first rest
  [ "$depth" -gt 3 ] && deny "commands nested more than three shells deep cannot be checked"
  if [ "$tool" = PowerShell ]; then s=$(split_commands "$2" 1); else s=$(split_commands "$2" 0); fi
  local IFS=$'\n'
  for seg in $s; do
    IFS=$' \t\n'
    set -- $seg
    if [ $# -gt 0 ]; then
      check_redirects "$dir" "$@"
      join_quoted "$@"
      set -- ${words[@]+"${words[@]}"}
      skip_prefix "$@"
      shift "$REPLY"
      command_name "${1:-}"
      first=$REPLY
      case "$first" in
        cd | pushd | set-location | sl | chdir)
          if [ $# -ge 2 ]; then
            resolve_dir "$2" "$dir"
            dir=$REPLY
          fi
          ;;
        bash | sh | zsh | dash | ksh | pwsh | powershell | cmd | eval)
          # A shell given a script on its command line: check the script too. It is the words
          # after the shell's own -c (-Command or a prefix of it, /c, a cluster such as -lc), or
          # every word after eval. Reading the words after the shell, not the first " -c " in
          # the text, keeps ionice -c 3 or -COMMAND from hiding the script.
          rest=""
          shift
          if [ "$first" = eval ]; then
            rest="$*"
          else
            while [ $# -gt 0 ]; do
              unquote "$1"
              shift
              case "$first" in
                cmd) case "$REPLY" in /c | /k) rest="$*"; break ;; esac ;;
                pwsh | powershell)
                  case "$REPLY" in
                    -e | -ec | -en*) deny "$first $REPLY runs an encoded command, which can't be read before it runs" ;;
                    -c | -co | -com | -comm | -comma | -comman | -command) rest="$*"; break ;;
                  esac
                  ;;
                *) case "$REPLY" in -c | -[a-z]*c) rest="$*"; break ;; esac ;;
              esac
            done
          fi
          rest=${rest#"${rest%%[![:space:]]*}"}
          rest=${rest%"${rest##*[![:space:]]}"}
          case "$rest" in
            \"*\") rest=${rest#\"}; rest=${rest%\"} ;;
            \'*\') rest=${rest#\'}; rest=${rest%\'} ;;
          esac
          [ -n "$rest" ] && check_text "$dir" "$rest" $((depth + 1))
          check_segment "$dir" "$seg"
          ;;
        *) check_segment "$dir" "$seg" ;;
      esac
    fi
    IFS=$'\n'
  done
}

# --- dispatch -----------------------------------------------------------------------------

case "$tool" in
  Bash | PowerShell) check_shell ;;
  Read | Edit | Write | MultiEdit | NotebookEdit | Grep | Glob) check_file_tool ;;
  AskUserQuestion | ExitPlanMode)
    deny "the user is away. Write the question into INBOX.md as a card with options and a recommendation, then carry on with other work" ;;
  SendMessage | RemoteTrigger | CronCreate | CronDelete | Artifact | ArtifactData | ArtifactComments | DesignSync)
    deny "$tool acts outside this machine or schedules more work; a burn run only changes local repos and pushes burn/ branches" ;;
  mcp__*)
    if [ -f "$home/guard-allow-mcp.txt" ]; then
      while IFS= read -r p || [ -n "$p" ]; do
        [ "${p%$'\r'}" = "$tool" ] && exit 0
      done <"$home/guard-allow-mcp.txt"
    fi
    re='(^|_)(send|create|update|delete|remove|merge|push|post|write|publish|trash|archive|label|share|comment|reply|forward|upload|move|rename|edit|insert|set|add|modify|execute|run|invoke|transfer|pay|book|draft|apply|approve|close|cancel|spam|unspam|untrash|respond|batch)(_|$)'
    [[ ${tool##*__} =~ $re ]] && deny "$tool looks like it changes something outside this machine. Allow it by name in guard-allow-mcp.txt if it is safe"
    ;;
esac
exit 0
