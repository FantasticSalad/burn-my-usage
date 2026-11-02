# Recurring checks

Checks worth doing every week. setup copies this file to the burn home, where you switch
checks on or off and add your own. Each run does every check marked `on` whose **Last run** is
more than 7 days ago (or blank), before the main queue, then updates **Last run** and **Last
result**. A check that finds work turns it into queue items like anything else; findings go in
the owning repo's docs or the inbox, not here.

To add a check, copy a section and change it. Keep each one read-only unless it says what it
may change, and say what it must never do.

---

## 1. Known vulnerabilities in dependencies

**Status:** on · **Last run:** · **Last result:**

For each repo, run the audit its ecosystem has, read-only: `npm audit --omit=dev` (and with
dev), an already-installed `pip-audit`, `cargo audit`, `govulncheck ./...`,
`bundle audit`. Skip a tool that isn't installed; don't install global tools.

A fix within the same major version is Build work: bump it on a branch, run the suites, and
say on the card which advisory it closes. A fix that needs a major version is a question.
Note anything with no fix available on the card for the repo's next branch, or as a job.

## 2. Secrets in tracked files

**Status:** on · **Last run:** · **Last result:**

Search tracked files only (`git ls-files`, then `git grep`) for things that look like live
credentials: private key blocks, `AKIA[0-9A-Z]{16}`, `ghp_`/`github_pat_`, `sk-` keys,
`xox[abp]-` tokens, `-----BEGIN`, passwords in connection strings. Use `gitleaks detect
--no-git` or `trufflehog filesystem` if installed.

**Never print a value**, not even part of it. Report the file and line only. A likely live
secret is a hard stop for that repo and a job card at the top of the inbox: the user rotates
it first, then decides whether history needs cleaning (which a run never does).

## 3. Loose ends

**Status:** on · **Last run:** · **Last result:**

Across every repo: uncommitted work, commits on a default branch that were never pushed,
stashes, stray worktrees, repos left off their default branch, and `burn/` branches older than
three weeks with no answer. Never commit, stash or discard any of it; list it.

Usually the outcome is one job card: "these repos have work that isn't pushed", with the
exact commands, and a nudge on old branches ("merge, bin or defer?").

## 4. CI health on default branches

**Status:** on · **Last run:** · **Last result:**

For repos with a GitHub remote and `gh` signed in: `gh run list --branch <default> --limit 5`.
A red default branch is the first Build item for that repo if the cause is clear from the log
(`gh run view <id> --log-failed`); otherwise a card with the failing step and your best guess.

## 5. Docs that contradict the code

**Status:** off · **Last run:** · **Last result:**

For the README of each active repo: do the install and run commands still work, do the
documented options, flags and environment variables still exist, do the examples still run?
Fix what is clearly stale on a branch; ask about anything that changes what the project
claims to do.
