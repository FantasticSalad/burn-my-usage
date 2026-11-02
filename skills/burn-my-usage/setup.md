# Setup

Contents: requirements, burn home, repos, pushes, usage, status line, guard, optional checks, run.

First-time setup, with the user present. Ask the user where it says so, offer
sensible defaults, and keep it to a few minutes. Never edit a settings file without showing
the change and getting a yes. Re-running setup is safe: it keeps existing files and only
fills gaps, unless the user asks to start over.

## 1. Check this is the right tool for them

Explain in two or three sentences what a run does and what it never does (SKILL.md section 0).

Then ask how they pay for Claude Code:
- **Pro or Max (or Team/Enterprise seat):** go on. Spare weekly usage is what this is for.
- **API key, Bedrock, Vertex or Foundry:** every token is billed. There is no "spare" usage,
  only spend. Say so plainly; continue only if they still want it, and then set `stop_at`
  aside: they should cap spend in their provider's console instead.

Ask whether **usage credits** (extra usage) are on in claude.ai Settings > Usage. If they are,
a run that went past the weekly limit could draw on paid credits. `stop_at` exists to prevent
that; recommend they keep it at 90 or lower.

## 2. Burn home

Default `~/.burn-my-usage`. If the user wants to answer the inbox from their phone, suggest a
folder their phone can see (Dropbox, OneDrive, iCloud Drive, Syncthing), or making the burn
home a private git repo. A different location needs `BURN_MY_USAGE_HOME` set for Claude Code:
in `~/.claude/settings.json` under `"env"`, so hooks and scripts see it too. Show the change
and ask before writing it.

Create the folder, then copy in from `${CLAUDE_SKILL_DIR}/templates/`: `config.md`,
`INBOX.md`, `wishlist.md`, `lessons.md`, and `${CLAUDE_SKILL_DIR}/recurring.md`. Don't
overwrite files that exist.

## 3. Repos

Ask where their repos live (AskUserQuestion; offer folders that exist among `~/code`, `~/src`,
`~/dev`, `~/projects`, `~/repos`, `~/git`, `~/github`, `~/Documents/GitHub`, plus Other).
Several folders are fine. Run `bash "${CLAUDE_SKILL_DIR}/scripts/repo-check.sh" --no-fetch
<folders>` and show what it found, idle days included.

Ask which repos to **skip** entirely (client work under NDA, anything they don't want touched),
and whether any deserve **high** priority. Everything else is tiered by recent activity.

Write the folders to `roots:` in `config.md` and, one absolute path per line, to `roots.txt`
in the burn home. The guard reads `roots.txt` and refuses edits outside those folders, the
burn home and temp directories.

## 4. Pushing branches

Ask (AskUserQuestion):
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
(AskUserQuestion: 80, 90 (recommended), 95). Write `stop_at:`.

## 6. Status line tap (how a run knows how much is left)

Claude Code gives a status line command the plan's usage, and nothing else does. So:

1. Copy `${CLAUDE_SKILL_DIR}/scripts/usage-tap.sh` to `<burn home>/bin/usage-tap.sh`. (The
   plugin's own folder moves on every update, so settings must point at a copy.)
2. Read `~/.claude/settings.json`. If it already has a `statusLine` command, save that command
   string to `<burn home>/statusline-next`: the tap runs it afterwards with the same input, so
   their status line looks exactly as before.
3. Show the change, ask, then set:
   ```json
   "statusLine": { "type": "command", "command": "bash \"<burn home>/bin/usage-tap.sh\"" }
   ```
   using the absolute burn home path (forward slashes on Windows).
4. After the next reply, `<burn home>/usage.json` should exist.
   `bash "${CLAUDE_SKILL_DIR}/scripts/usage.sh"` reads it.

If they decline or usage data is missing/stale, planning works but an unattended run must
save current work and stop. Disable paid extra usage or set provider billing caps for a
money boundary: sampled percentages cannot guarantee zero overage.

## 7. Guard

If this skill came from the plugin, the guard is already registered as a hook. Otherwise
(a skill copied into `~/.claude/skills/`), offer to install it: copy
the entire `${CLAUDE_SKILL_DIR}/scripts/` folder into `<burn home>/bin/` so guard.sh,
lib.sh, usage.sh and leak-check.sh stay together; show the change, ask,
and add to `~/.claude/settings.json`:

```json
"hooks": {
  "PreToolUse": [
    { "hooks": [ { "type": "command", "command": "bash \"<burn home>/bin/guard.sh\"", "onFailure": "block" } ] }
  ]
}
```

merging with any `hooks` already there. The hook must use onFailure: block (Claude Code 2.1.295+). A missing or broken hook then
blocks ordinary tool calls too, until the user repairs or disables the plugin. It costs one
bash start per tool call and does
nothing outside a burn run.

Then test it: `bash "${CLAUDE_SKILL_DIR}/scripts/start.sh" ${CLAUDE_SESSION_ID}`, then
`echo burn-guard-selftest` (a refusal that says "self-test OK" means it works), then
`bash "${CLAUDE_SKILL_DIR}/scripts/stop.sh" ${CLAUDE_SESSION_ID}`, and delete the empty run
folder start.sh made. A hook added to settings mid-session may need a restart before it fires; if the
echo just runs, ask them to restart Claude Code and run `/burn-my-usage setup` again to test.

## 8. Optional

- **Issues:** offer `issues: on` with a label (default `burn-ok`). Only issues they or
  `trusted_issue_authors` wrote are used, because anyone can file an issue on a public repo.
- **Extra deny patterns:** `guard-deny.txt` in the burn home, one regular expression per line,
  for their own deploy scripts and the like (`deploy\.sh`, `make (release|ship)`).
- **Wishlist:** show them `wishlist.md`. Jotting things there during the week is what makes
  the runs useful.

## 9. How to start a run

Show this, adjusted to their folders, and suggest `/burn-my-usage plan` first to see the
queue without changing anything:

```bash
cd ~/code
claude --permission-mode auto --add-dir ~/.burn-my-usage
```

then, inside Claude Code:

```text
/goal Run /burn-my-usage to the end. Done when its final report is written and stop.sh has printed STOPPED.
```

- **Auto mode** lets it work without prompts, with a classifier checking each action. In
  manual mode it would stop at the first prompt and wait all weekend.
- **`/goal`** keeps it going turn after turn until the run says it is finished.
- **Keep the session open and the computer awake.** When the 5-hour limit hits, Claude Code
  waits and carries on by itself after the reset, but only in an open session. macOS:
  `caffeinate -i claude ...`. Windows: set sleep to Never while plugged in. Linux:
  `systemd-inhibit claude ...`.
- **Stop it** any time with Esc, then `/burn-my-usage stop`.

Finish with a summary: where the burn home is, what was written, what to do next.
