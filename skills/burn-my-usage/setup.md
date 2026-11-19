# Setup

Contents: requirements, burn home, repos, pushes, usage, status line, guard, optional checks, run.

First-time setup, with the user present. Resolve `<skill>` and `<scripts>` as literal paths using the host binding. Ask the user where it says so, offer
sensible defaults, and keep it to a few minutes. Never edit a settings file without showing
the change and getting a yes. Re-running setup is safe: it keeps existing files and only
fills gaps, unless the user asks to start over. If `config.md` and `roots.txt` already exist
and `start.sh --paths` shows the expected burn home, setup was stopped for a restart: show
the saved answers in a few lines and continue at step 6.

## 1. Check this is the right tool for them

**Costs first, before anything else.** Ask the user to confirm both, plainly:

1. They're on a subscription plan, not per-token billing (an API key, Bedrock, Vertex or
   Foundry). On per-token billing every token a run spends is charged and there is no spare
   usage; continue only if they still want to, with provider-side spending caps.
2. Paid extra usage is off in their account's usage settings, or capped at an amount they're
   happy to pay. With it on, the host keeps going past the weekly limit and bills them.

Then show this, word for word, and continue only once they've acknowledged it:

> Burn My Usage is provided as is, without warranty of any kind (see LICENSE). The stop line
> works from sampled usage and a run can overshoot it; BURN IT ALL takes a run to 100% on
> purpose. Your billing settings are the only reliable money boundary. You are responsible
> for any charges that running it incurs, and the author accepts no liability for them.

Explain in two or three sentences what a run does and what it never does (workflow.md section 0).
Recommend a stop line of 90% or lower; a sampled usage line is not a spending guarantee.

## 2. Burn home

Default `~/.burn-my-usage`. Recommend a local folder. If the user wants to answer the inbox
from their phone and asks about a synced folder (Dropbox, OneDrive, iCloud Drive, Syncthing)
or a private git repo, tell them first what the whole burn home holds, because all of it would
sync:

- every item's live git worktree (`worktrees/`). Sync clients hold files open, and on the
  first real run OneDrive made `git worktree remove` fail, leaving folders to delete by hand.
- a Git bundle of every branch (`backups/`), holding the full history of private repos,
  which would then be uploaded to the sync provider.
- `usage.json`, rewritten on every status line refresh, and the status line script in
  `bin/`, which runs on every refresh. A synced copy from another machine would be run.

A burn home that is itself a git repo would contain nested worktrees and bundles. Let them
choose; a local folder is the recommendation until only the files they edit can be synced.

A different location needs `BURN_MY_USAGE_HOME` available to the host's scripts and
guard. Follow the host binding, and show and obtain approval for any settings change.

Create the folder, then copy in from `<skill>/templates/`: `config.md`,
`INBOX.md`, `wishlist.md`, `lessons.md`, and `<skill>/recurring.md`. Don't
overwrite files that exist.

## 3. Repos

Ask where their repos live (offer folders that exist among `~/code`, `~/src`,
`~/dev`, `~/projects`, `~/repos`, `~/git`, `~/github`, `~/Documents/GitHub`, and on Windows
also `C:/src`, `C:/dev`, `C:/repos` and `C:/git`, plus Other). If none of them
exist, say so before asking for a path, so an empty list doesn't look broken.
Several folders are fine. Run `bash "<scripts>/repo-check.sh" --no-fetch --summary
<folders>` and show its table and open-work lines, idle days included. The full scan, with
raw worktree and branch lists, is for runs.

Ask which repos to **skip** entirely (client work under NDA, anything they don't want touched),
and whether any deserve **high** priority. Everything else is tiered by recent activity.

Say plainly that `skip:` is an instruction to the run, not an enforced boundary: the scanner
still fetches and inspects every repository under a root, and the guard doesn't stop the run
reading a skipped repo's files. If a repo must not be read, don't list its parent folder as a
root: list each other repository's own path as a root instead, and leave that one out.

Write the folders to `roots:` in `config.md` and, one absolute path per line, to `roots.txt`
in the burn home. The guard reads `roots.txt` and refuses edits outside those folders, the
burn home and temp directories.

## 4. Pushing branches

Ask:
- **never (recommended):** keep every branch local, with a verified backup bundle.
- **private:** push `burn/` branches only to private GitHub repos, so CI runs
  on them and they're backed up. Public repos keep their branches local, because a pushed
  branch on a public repo is visible to everyone. Needs `gh` signed in to check visibility.
- **all:** push to every repo with a remote.


Write `push_branches:`. Only the origin remote is supported. Private mode rechecks the
origin push destination with gh before every push and refuses unknown visibility.
Existing config is preserved; never silently change an existing push choice.

## 5. Usage line

Ask what share of the weekly limit a run may take, counting what they used themselves
(80, 90 (recommended), 95). Write `stop_at:`.

## 6. Usage and guard

Follow the selected host binding for usage and guard verification. Show any proposed
settings change and obtain the user's approval before applying it. Missing or stale usage
means an unattended run saves its work and stops. Sampled percentages cannot guarantee
zero paid usage; use provider billing controls for a money boundary.

## 7. Inbox page (optional, Claude Code only)

Offer it if this session has the `Artifact` and `ArtifactData` tools; otherwise say the inbox
is `INBOX.md` and move on. Explain it plainly before asking:

- It is a private page on claude.ai where they answer cards with one tap, from a phone too.
  Only they can open it, and its data is readable and writable only by its owner.
- Every card a run writes to `INBOX.md` is also sent there, so card text (repo and branch
  names, what a change does, questions) is stored on claude.ai. Secrets never go on a card.
- A run can add and update cards but can't answer them, and can't publish or share pages.
  Approving a branch there approves the exact commit shown, and the merge stays local.

If they want it:

1. Publish `<skill>/templates/inbox.html` with the `Artifact` tool, icon `inbox`, and
   `capabilities` set to
   `{"db": {"rules": [{"path": "items", "read": "owner", "write": "owner"}, {"path": "answers", "read": "owner", "write": "owner"}]}, "user": {}}`.
   Confirm the result says only they can read it.
2. Check the rules: `ArtifactData` `list` of `items` with `as_level: "admin"` must return
   nothing.
3. Show the URL and, with their yes, write it to `inbox_page:` in `config.md`.
4. Mirror the open cards in `INBOX.md` to the page ([inbox.md](inbox.md), "Publish, with a
   page"). Tell them not to share the page or change its access rules: an answer there
   approves merges on their machine.

To update the page after a plugin update, publish the template again to the same URL,
leaving `capabilities` out so the rules stay as they are. To stop using it, clear
`inbox_page:`; runs go back to `INBOX.md` alone.

## 8. Optional

- **Issues:** offer `issues: on` with a label (default `burn-ok`). Only issues they or
  `trusted_issue_authors` wrote are used, because anyone can file an issue on a public repo.
- **Extra deny patterns:** `guard-deny.txt` in the burn home, one regular expression per line,
  for their own deploy scripts and the like (`deploy\.sh`, `make (release|ship)`).
- **Wishlist:** show them `wishlist.md`. Jotting things there during the week is what makes
  the runs useful. Most repo plans are prose rather than `- [ ]` checklists, which a run
  can read but often finds held for the user; the wishlist is the reliable way to queue work.
- **Audit tools:** from the scan, note which ecosystems their repos use (package.json,
  pyproject.toml or requirements.txt, Cargo.toml, go.mod, Gemfile) and check which audit
  tools are installed (`npm`, `pip-audit`, `cargo audit`, `govulncheck`, `bundle audit`).
  Tell them which repos the weekly vulnerability check will skip, and what to install if
  they want it. Don't install anything yourself.

## 9. Start

Follow the selected host binding's launch instructions and recommend plan mode first.
Finish with a summary of the burn home, what was written and the next step.
