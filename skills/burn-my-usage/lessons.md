# Lessons

What unattended runs have learned the hard way. Read it at the start of every run. Your own
runs add theirs to `lessons.md` in the burn home, not here.

## Proving the work

- **Prove behavior changes on old source in a separate worktree.** Never stash or replace
  the implementation worktree to do it. Tests already passing are not regression evidence.
- **The hostile review finds real defects nearly every time.** Do it before every commit,
  ideally with a fresh subagent that sees only the diff and the spec. Typical finds: a log line
  that reports success on the failure path, a cleanup that runs before the thing it cleans up,
  a fix applied to one of two identical call sites.
- **Check every factual claim before writing it,** in code comments, commit messages and
  cards alike. "X sits behind Y" and "the roadmap already fixes this" are the kind of
  sentence that is confidently wrong. Grep or read the source first.
- **External API shapes come from the docs, not memory.** Fetch the page.
- **Linux CI catches what Windows and macOS can't** (file locking, case-sensitive paths,
  dotfiles in directory listings). For platform-sensitive work, push and read CI before
  calling it done.
- **Test data with checksums or formats is generated, never typed.** Build it with the
  repo's own validators in a scratch script. Fake secrets should look fake
  (`sk-EXAMPLE-...`) so a host's push protection doesn't trip on them.
- **A bulk replace rewrites the helper you just added.** Add a wrapper after the bulk replace,
  or exclude its line, or it ends up calling itself.
- **Check the premise, not just the code.** Code can match its own docs while both
  contradict the primary source they claim to implement (a spec, a standard, a law). Read the
  source.

## Deciding

- **Adapt a spec to code that changed after it was written, and say so** on the card.
- **Close the obvious adjacent hole.** If the spec fixes one input type and a second is the
  same bug, fix both and say why.
- **A later decision beats an earlier spec.** Note which one won.
- **A terse "needs changes" note is an instruction, not a puzzle.** Take the reading the
  repo's structure supports, keep any safeguard the old code had, and state your reading on
  the card so a wrong guess costs the user one tick.
- **Count the branch cap before every new branch,** not once per repo. A stack of two plus a
  reopened branch is already three.
- **The user's own material is theirs.** Notes, drafts and practice work they wrote are not a
  queue; anything there becomes a question.

## Repos and machines

- **Put every repo back on the branch you found it on.** Other tools and scripts expect it.
- **A big uncommitted-changes count can be a damaged index, not anyone's work.** Folders
  synced by Dropbox, OneDrive or iCloud sometimes replace `.git/index` with a stale copy, and
  `git status` then shows staged deletions of files that are still on disk. Committing that
  would delete them. Check first: `GIT_INDEX_FILE=<scratch file> git read-tree HEAD`, then
  `git diff --stat` and `git ls-files --others --exclude-standard` with the same variable. If
  both are empty, the tree is exactly HEAD and the user should run `git reset` (it touches
  only the index). Either way, leave it for them and say so.
- **Synced folders can roll back history too.** If the local default branch is behind and
  also has commits origin lacks (DIVERGED), don't build there.
- **Windows:** heredocs, `sed -i` and `echo >` break on CRLF line endings and quoting. Write
  files with the Write and Edit tools. Git Bash `date` may not know your time zone; trust
  `start.sh`'s `LOCAL_TIME` line.
- **Python projects with `uv`:** if pytest lives in an extra (`[project.optional-dependencies]
  dev`), run `uv run --extra dev pytest`, or it runs in a throwaway environment that can't see
  the project's dependencies, and every test fails with ModuleNotFoundError.
- **Headless browsers won't render narrower than about 500 px.** For phone-width
  screenshots, put the page in an iframe at the width you need.

## Tooling

- **Auto mode's classifier sometimes returns no verdict.** It's transient: retry once, then
  do read-only work for a while. Smaller Edit payloads go through more often. Ten no-verdict
  responses in a row end the turn, so after about six, work read-only until it recovers.
- **Three refusals in a row pause auto mode** for a human. Never retry a refused action;
  change course instead.
- **Another session may be working at the same time,** even in the same repo. Re-read a file
  just before editing it, and stage by path, never `git add -A` in a repo you didn't start
  clean.
- **After a branch switch** the editor reports "changed on disk" for every file that differs
  between branches. That's expected; don't revert anything because of it.
- **Editing Markdown tables:** count the `|` separators against a neighbouring row afterwards.
- **Inserting into a paragraph:** re-read the paragraph afterwards to check you didn't split a
  sentence away from it.
