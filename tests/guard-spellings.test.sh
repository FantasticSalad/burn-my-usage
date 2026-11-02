#!/usr/bin/env bash
# Other spellings of actions the guard refuses: quoted strings with spaces, option values given
# as the next word, settings from the environment, aliases, prefixes in front of a shell, and
# other routes to a protected file. Found by the second review (2026-10-29). Hook decisions only:
# nothing here pushes, deletes, sends mail or calls GitHub.
#   bash tests/guard-spellings.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
guard=${GUARD:-"$here/../skills/burn-my-usage/scripts/guard.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home"
home=$BURN_MY_USAGE_HOME
mkdir -p "$home/active" "$tmp/code"
sid=spellings

g() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }
repo() { # path: a repository on main with a CI workflow and a GitHub-looking origin
  mkdir -p "$1/.github/workflows"
  g -C "$1" init -q
  printf 'x\n' >"$1/README.md"
  printf 'name: ci\n' >"$1/.github/workflows/ci.yml"
  g -C "$1" add README.md .github/workflows/ci.yml
  g -C "$1" commit -q -m init
  g -C "$1" remote add origin https://github.com/example/app.git
}
app="$tmp/code/app"
spaced="$tmp/code/two words/app"
repo "$app"
repo "$spaced"
lib="$tmp/code/app-linked"
spaced_lib="$tmp/code/two words/linked"
g -C "$app" worktree add -q -b burn/2026-10-29-x "$lib"
g -C "$spaced" worktree add -q -b burn/2026-10-29-y "$spaced_lib"
mkdir -p "$lib/.claude"
touch "$home/active/$sid"
printf 'push_branches: all\n' >"$home/config.md"
printf '%s\n' "$tmp/code" >"$home/roots.txt"
now=$(date +%s)
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}' "$now" "$((now + 86400))" >"$home/usage.json"

pass=0
fail=0
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'NR>1{printf "\\n"} {printf "%s", $0}'; }
shell_json() { # tool command cwd
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"}}' \
    "$sid" "$(esc "$3")" "$1" "$(esc "$2")"
}
write_json() { # path
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' \
    "$sid" "$(esc "$lib")" "$(esc "$1")"
}
check() { # expect(deny|allow) label json
  local out
  out=$(printf '%s' "$3" | bash "$guard")
  case "$1:$out" in
    deny:*'"permissionDecision":"deny"'* | allow:) pass=$((pass + 1)) ;;
    *)
      fail=$((fail + 1))
      printf 'FAIL [%s] %s\n  output: %s\n' "$1" "$2" "${out:-<none>}"
      ;;
  esac
}
deny() { check deny "$1" "$(shell_json Bash "$1" "${2:-$app}")"; }
allow() { check allow "$1" "$(shell_json Bash "$1" "${2:-$app}")"; }
ps_deny() { check deny "[PowerShell] $1" "$(shell_json PowerShell "$1" "${2:-$app}")"; }
ps_allow() { check allow "[PowerShell] $1" "$(shell_json PowerShell "$1" "${2:-$app}")"; }

# --- a quoted string with a space in it is one word ----------------------------------------------
# Split at its space, the string's second half was read as the command or the subcommand.
deny 'GIT_COMMITTER_NAME="Burn Bot" git commit -m fix'
allow 'GIT_COMMITTER_NAME="Burn Bot" git commit -m fix' "$lib"
deny 'MSG="two words" git push origin main'
deny "MSG='two words' git push origin main"
deny 'git -c user.name="Burn Bot" push origin main'
deny 'git -c user.name="Burn Bot" commit -m fix'
allow 'git -c user.name="Burn Bot" commit -m fix' "$lib"
deny "git -C \"$spaced\" push origin main" "$lib"
deny "git -C \"$spaced\" commit -m fix" "$lib"
allow "git -C \"$spaced_lib\" commit -m fix" "$lib"
allow "git -C \"$spaced\" status" "$lib"
deny "cd \"$spaced\" && git commit -m fix" "$lib"
allow "cd \"$spaced_lib\" && git commit -m fix" "$lib"
# Quotes that don't balance leave the words as they were, so nothing new is hidden.
ps_deny 'git -C "C:\" push origin main'

# --- git options whose value is the next word ------------------------------------------------------
deny "git --git-dir $app/.git push origin main" "$lib"
deny "git --git-dir \"$app/.git\" commit -m fix" "$lib"
deny "git --git-dir=$app/.git commit -m fix" "$lib"
deny "git --work-tree $app push origin main" "$lib"
allow "git --git-dir $app/.git log --oneline -1" "$lib"
deny 'git --namespace x push origin main'
deny 'git --attr-source HEAD push origin main'

# --- settings that change what git runs, where it pushes or what it commits ------------------------
deny "git -c 'alias.ship=push origin HEAD:main' ship"
deny 'git -c "remote.origin.pushurl=https://github.com/other/public.git" push origin burn/2026-10-29-x' "$lib"
deny 'git -c url.https://github.com/other/.pushInsteadOf=https://github.com/example/ push origin burn/2026-10-29-x' "$lib"
deny 'git -c include.path=extra.cfg status'
deny 'SHIP=push git --config-env=alias.ship=SHIP ship origin main'
deny 'git --config-env alias.ship=SHIP ship origin main'
deny 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ship GIT_CONFIG_VALUE_0=push git ship origin main'
deny 'export GIT_CONFIG_PARAMETERS=x'
deny 'GIT_DIR=/elsewhere/.git git commit -m fix' "$lib"
deny 'GIT_INDEX_FILE=other.idx git commit -m fix' "$lib"
deny 'export GIT_SSH_COMMAND="ssh -i key"'
ps_deny '$env:GIT_DIR = "C:/elsewhere/.git"; git log'
allow 'GIT_TERMINAL_PROMPT=0 git fetch origin'
allow 'git_dir=build; echo $git_dir'
allow 'git -c color.ui=always log --oneline -1'
g -C "$app" config alias.st status
deny 'git st'
allow 'git status'

# --- commands git runs for itself ----------------------------------------------------------------
deny "git submodule foreach 'git push origin main'"
allow 'git submodule foreach git status'
deny 'git rebase -x "git push origin main" main' "$lib"
allow 'git rebase -x "npm test" main' "$lib"
allow 'git rebase -X ours main' "$lib"
deny 'git bisect run git push origin main'
deny 'git send-pack https://github.com/example/app.git main'
deny 'git send-email --to=x@example.com HEAD~1'
deny 'git am fix.patch' "$lib"
allow 'git am --abort' "$lib"

# --- prefixes in front of the command ----------------------------------------------------------------
deny 'FOO=1 bash -c "git push origin main"'
deny 'timeout 600 bash -c "git push origin main"'
deny 'ionice -c 3 bash -c "git push origin main"'
allow 'timeout 600 bash -c "npm test"'
deny 'env -i git push origin main'
deny 'env -u HOME git push origin main'
deny 'env -C /elsewhere git status'
deny 'env -S "git push origin main"'
deny 'env -i'
allow 'env FOO=1 npm test'
deny 'echo main | xargs -n1 git push origin'
deny 'xargs -I {} git push origin {}'
allow 'ls | xargs -n1 echo'
deny 'wsl git push origin main'
deny 'wsl --cd /mnt/c/x git status'
allow 'wsl ls'
deny 'exec -a name git push origin main'
deny 'command -p git push origin main'
deny 'g\it push origin main'

# --- shells reached another way ---------------------------------------------------------------------
ps_deny 'pwsh -COMMAND "git push origin main"'
ps_deny 'powershell -NoProfile -Comm "git push origin main"'
ps_deny 'powershell -enc ZwBpAHQA'
deny 'echo "git push origin main" | sh'
deny 'printf "git push origin main" | bash -s'
deny 'cat steps.txt | bash -s -- --yes'
ps_deny 'Get-Content steps.txt | iex'
allow "git diff --stat | sh -c 'wc -l'"
allow 'git log --oneline | sha256sum'
deny 'find . -name x -exec git push origin main \;'
deny "find . -name x -exec sh -c 'git push origin main' \\;"
allow 'find . -name "*.py" -exec grep -l TODO {} +'

# --- gh api: values after "=", attached, or a second method -----------------------------------------
deny 'gh api --method=POST repos/o/r/issues'
deny 'gh api -XPATCH repos/o/r'
deny 'gh api -X GET -X POST repos/o/r/issues'
deny 'gh api repos/o/r/issues --field=title=x'
deny 'gh api repos/o/r/issues --raw-field=title=x'
deny 'gh api graphql -fquery=mutation'
deny 'gh api repos/o/r/issues -Ftitle=x'
deny 'gh api repos/o/r/contents/x --input=body.json'
allow 'gh api -X GET search/issues -f q=repo:o/r'
allow 'gh api --method=GET repos/o/r'
allow 'gh api repos/o/r/pulls --paginate -q ".[].number"'
deny "gh alias set ship 'pr merge 1'"
deny 'gh config set editor vim'
allow 'gh alias list'

# --- PowerShell parameter prefixes and -Name:Value ----------------------------------------------------
ps_deny 'Invoke-WebRequest -Uri https://example.com -Meth Post -Bod x'
ps_deny 'Invoke-RestMethod -Method:Delete -Uri https://example.com/x'
ps_deny 'iwr https://example.com -InFile out.json -Method Put'
ps_deny 'irm https://example.com -Body:$data'
ps_allow 'Invoke-RestMethod -Method:Get -Uri https://example.com/x'
ps_allow 'Invoke-WebRequest -Uri https://example.com -OutFile page.html'
ps_allow 'curl -I https://example.com'

# --- a glob that names env files --------------------------------------------------------------------
deny 'cat .env*'
deny 'grep -n KEY config/*.env*'

# --- a protected file changed by any route is refused at commit ---------------------------------------
# sed -i, cp, tee or a script can change a workflow without Write, Edit or a redirect. Pushed, a
# burn/ branch runs that workflow with the repository's secrets.
allow "sed -i 's/ci/x/' .github/workflows/ci.yml" "$lib"
printf 'name: changed\n' >"$lib/.github/workflows/ci.yml"
g -C "$lib" add .github/workflows/ci.yml
deny 'git commit -m "tidy CI"' "$lib"
g -C "$lib" reset -q
g -C "$lib" checkout -q -- .github/workflows/ci.yml
printf 'y\n' >>"$lib/README.md"
g -C "$lib" add README.md
allow 'git commit -m "update readme"' "$lib"
g -C "$lib" mv .github/workflows/ci.yml ci.yml.off
deny 'git commit -m "turn CI off"' "$lib"

# --- Windows: an 8.3 short name is the same folder ------------------------------------------------------
if command -v cygpath >/dev/null 2>&1; then
  short=$(cygpath -d "$lib/.claude" 2>/dev/null)
  case "$short" in
    *'~'*)
      check deny "Write through a short name of .claude" "$(write_json "$(cygpath -m "$short")/settings.json")"
      g -C "$lib" reset -q --hard
      wf=$(cygpath -m "$(cygpath -d "$lib/.github/workflows")")
      check deny "Write through short names of .github/workflows" "$(write_json "$wf/ci.yml")"
      deny "echo x > \"$wf/ci.yml\"" "$lib"
      ;;
    *) echo "SKIP 8.3 short names: this volume doesn't make them" ;;
  esac
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
