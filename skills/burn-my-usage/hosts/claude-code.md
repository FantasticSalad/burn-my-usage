# Claude Code host binding

Set the conceptual `BMU_HOST` to `claude-code`, `BMU_SKILL_DIR` to
`${CLAUDE_SKILL_DIR}`, and `BMU_SESSION_ID` to `${CLAUDE_SESSION_ID}`.
Resolve these in skill text, not as assumed shell variables. Substitute literal paths and
session identifier as separately quoted arguments. Scripts default to this host; explicitly
select `claude-code` if another host was set. Read the mode from `$ARGUMENTS`.
The guard must receive the same session identifier; an old marker does not grant ownership.

## Setup only

The following setup instructions apply only in `setup` mode with the user present.
Reading this binding during another mode does not authorise these changes.

Start with the cost check and disclaimer in setup.md step 1. For Claude Code: a Pro, Max,
Team or Enterprise seat may have spare weekly usage; API key, Bedrock, Vertex or Foundry
usage is billed per token. Paid extra usage is under claude.ai Settings > Usage; with it on,
usage past the weekly limit is charged. Recommend a stop line of 90% or lower.

For a non-default burn home, show and obtain approval for setting
`BURN_MY_USAGE_HOME` under `env` in `~/.claude/settings.json`, so hooks and scripts
receive the same location. The setting only reaches sessions started afterwards: in this
one, the scripts, the guard and the status line still use `~/.burn-my-usage`, so the guard
self-test would fail and the status line could create a stray default burn home. After
writing it (and the status line change below, if they want it), stop setup there: tell the
user to restart Claude Code and run `/burn-my-usage setup` again, which resumes at step 6.

### Status line tap (how a run knows how much is left)

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
   `bash "${CLAUDE_SKILL_DIR}/scripts/usage.sh"` reads it. If it doesn't appear, the status
   line isn't running where setup runs (seen in the VS Code panel): ask the user to open a
   terminal `claude` session, send one message, and check again. Say runs should start from
   a terminal session for the same reason.

If they decline or usage data is missing/stale, planning works but an unattended run must
save current work and stop. Disable paid extra usage or set provider billing caps for a
money boundary: sampled percentages cannot guarantee zero overage.

### Guard

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

### Explain how to start a run

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

Finish setup with a summary: where the burn home is, what was written, what to do next.

## During a run

During an unattended run, do not use AskUserQuestion or ExitPlanMode. Three consecutive
refusals in auto mode pause for a human and end the unattended run. A notification is an
outward message and requires the user's explicit authorisation.

If the auto-mode classifier returns no verdict, it is transient: retry once, then do
read-only work for a while. Smaller edits may help. Ten consecutive no-verdict responses
end the turn; after about six, work read-only until it recovers. A refusal is different:
never retry a refused action.
