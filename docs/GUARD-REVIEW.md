# Guard review

This is the author's own review of version 0.2.3, not an independent security review. Review
scope: the registered hook, session markers, path and shell dispatch, push checks, usage and
staged-commit checks, plus the owned-worktree lifecycle. Only synthetic hook inputs and
disposable repositories were used. Requested dangerous commands were never executed.

## Findings and corrections

| Finding | Risk | Correction | Regression evidence |
|---|---|---|---|
| Parent segments in write paths | A path under an allowed prefix could resolve into run controls or outside the prefix | File-tool writes and literal redirects refuse parent traversal; callers must use canonical absolute paths | guard-paths.test.sh: six checks, four reproduced denials failed before the fix; canonical writes and permitted reads remain allowed |
| Multiple origin push URLs | Checking only the first URL could permit a private-policy push that also reaches another destination | Enumerate all effective push URLs and require exactly one before checking visibility | guard-push.test.sh: six checks, two fan-out denials failed before the fix; private/public/never controls use a mock visibility service |
| Attached/clustered HTTP flags and contradictory methods | Attached or clustered write options passed; an earlier GET could override a later POST or payload in the guard's decision | Inspect short-option clusters and explicit method/data flags; each method must be GET and payload options remain refused | guard-network.test.sh: fifteen checks, ten denials failed before the fix; GET/proxy/header-output forms remain allowed |

The finding locations are reject_parent_write/check_file_tool/scan_redirects, check_push,
and the HTTP-client branch of check_segment in skills/burn-my-usage/scripts/guard.sh.
Tests run the hook only, with local fixture state. The push tests perform no pushes and
make no GitHub calls. The network tests perform no HTTP requests.

## Other controls reviewed

- Native hook errors block through onFailure: block. The self-test and supported CLI
  version remain required; this review does not establish coverage of a changed host schema.
- Branch destinations, force flags, automatic commit staging and staged leak-check errors
  are guarded. Private push visibility must be verifiable; new installs never push.
- The helper records an owned linked worktree and verifies a complete local bundle before
  removing a clean worktree. Dirty or unowned cleanup is refused. Repository basenames
  must be unique across configured roots, as the current helper keys ownership by name.
- Fresh usage is checked before selected mutations. This is pacing, not provider billing
  enforcement. Configure provider-side limits when a hard spend boundary is required.
- Inbox checks prevent adding approval ticks; moving an existing tick remains a documented
  weakness. Approval and exact-revision review remain the user's responsibility.

## Coverage limits

The guard examines selected strings, not arbitrary program behavior. Interpreter calls,
project scripts, aliases, dynamically built commands, symlinks, unrecognized CLI syntax,
GET-based exfiltration and tools with misleading names remain outside complete mediation.
Some ordinary commands that write files internally are not covered like Write/Edit or
literal redirects. Normal processes and other sessions do not enter this hook's boundary.
Do not use this review as proof of sandboxing or complete unattended security. See
SECURITY.md for the accepted limits.

An independent reviewer should repeat the synthetic regressions, examine the fixed branches
and decide whether these limits fit the intended use.

## Second review (2026-10-29, 0.2.4)

A second agent, not the one that wrote 0.2.3, read the whole guard and tried other spellings
of each refused action, then confirmed each one with synthetic hook input and, where it
depended on git or Windows, against real git 2.55 and NTFS. The author ran this agent too, so
it isn't an independent review either.

| Finding | Example the 0.2.3 guard allowed | Correction |
|---|---|---|
| A quoted string with a space split into two words, so the rules read the wrong word as the command or subcommand | `GIT_COMMITTER_NAME="Burn Bot" git commit -m x` on main; `git -C "C:/Users/Jane Doe/app" push origin main`; `git -c user.name="Burn Bot" push origin main` | join_quoted keeps a quoted string whole before any rule walks the words; unbalanced quotes leave the words as they were |
| git options whose value is the next word | `git --git-dir /repo/.git push origin main`; `--work-tree`, `--namespace`, `--attr-source` | Values are read; `--git-dir` and `--work-tree` name the folder the branch rules judge |
| Settings through quotes, other keys or the environment | `git -c "remote.origin.pushurl=..."`; `-c url.<x>.pushInsteadOf=...`; `-c include.path=...`; `--config-env`; `GIT_CONFIG_COUNT`/`KEY_n`/`VALUE_n`; `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_SSH_COMMAND` | `-c` values are unquoted before matching, `url.*` and `include.*` join the list, `--config-env` and those variables are refused |
| git aliases | `git ship` after `alias.ship = push origin HEAD:main` | An unknown subcommand that is an alias is refused (git ignores aliases that shadow built-ins) |
| Prefixes in front of a nested shell or command | `timeout 600 bash -c "git push origin main"`; `ionice -c 3 bash -c ...`; `env -i git push`; `xargs -n1 git push origin`; `wsl git push` | skip_prefix serves both the nested-shell check and the command check; env, xargs, exec and wsl options are read; `env -C`/`-S` and `wsl --cd` are refused |
| Shells reached another way | `pwsh -COMMAND "..."` (only `-Command` was matched); `powershell -enc ...`; `echo "git push origin main" \| sh` | The script after `-c`/`-Command` prefixes is found case-insensitively; encoded commands and text piped into a shell are refused |
| Commands that git and find start | `git submodule foreach 'git push origin main'`; `git rebase -x ...`; `git bisect run ...`; `find . -exec git push origin main \;` | Checked as shell text |
| Commits and pushes without the usual checks | `git am fix.patch` (no staged scan); `git send-pack`, `git http-push`; `git send-email`, `imap-send`, `daemon`, `instaweb` | Refused |
| gh api forms | `--method=POST`, `-X GET -X POST`, `--field=`, `--raw-field=`, `-fquery=...`, `-Ftitle=x`, `--input=`; `gh alias set`, `gh config set` | Arguments are read one by one; every method must be GET and a body needs an explicit GET |
| PowerShell parameter spellings | `Invoke-WebRequest -Meth Post -Bod x`; `Invoke-RestMethod -Method:Delete` | ps_web reads prefixes and `-Name:Value` |
| A glob naming env files | `cat .env*` | Treated as a secret path |
| Windows 8.3 short names | Write to `<repo>/GITHUB~1/WORKFL~1/ci.yml` or `CLAUDE~1/settings.json` (`CLAUDE~1` verified to land in `.claude` on NTFS; the workflow path is covered by the same expansion and tested as a refusal only) | long_name expands them before the protected and secret checks; it only adds refusals, since %TEMP% is often a short path |
| Protected files changed by other commands | `sed -i ... .github/workflows/ci.yml`, `cp`, `tee`, `Set-Content`, then `git commit` and push, which runs the workflow with the repository's secrets | A commit whose staged changes include a protected path is refused, renames and deletions included |
| Backslash in a bare command name | `g\it push origin main` | Outside PowerShell the backslash is an escape |

One correction removed a false refusal: `cd "<burn worktree with a space in its path>" && git
commit` was refused, because the folder was cut at the space.

A trailing dot (`.claude./settings.json`) was tested and is not a bypass. With `.claude` present,
a Node write to `.claude./` failed with ENOENT, so the path doesn't reach `.claude`. The Write
tool's own path handling wasn't tested.

Evidence: tests/guard-spellings.test.sh, 109 checks; 73 of them fail on the 0.2.3 guard (72
missed refusals and the false refusal above). The subagent assumption in SECURITY.md was
verified the same day. The real-transcript replay wasn't rerun, because it needs the
maintainer's own transcripts. That would measure any new refusals in ordinary use.
