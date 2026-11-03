# Burn My Usage

A Claude Code plugin for the end of the week. If your Pro or Max plan has usage left that
will reset unused, start a run before you log off. It works through your repos while you're
away and leaves you branches with tests and a short inbox of decisions, which you can review
in a few minutes and merge or throw away.

```text
/burn-my-usage
```

## What a run does

- **Works out what to do.** In order: answers you gave in the inbox, your wishlist (things
  you jotted down during the week), each repo's own TODO and roadmap docs, issues you've
  labelled (optional), then health checks: failing tests, lint and type errors, known
  vulnerabilities, docs that no longer match the code.
- **One branch per item,** named `burn/<date>-<item>`, in the repo's own style. New tests are
  checked to fail on the old code and pass on the new. Each change gets a hostile review
  before it's committed.
- **Asks instead of guessing.** Anything touching security trade-offs, auth, money, public
  copy, APIs other code depends on, or production becomes a card in your inbox, with options,
  a recommendation, and what happens if you never answer.
- **Paces itself against your weekly limit** and stops at a line you choose (90% by
  default), to leave headroom for the rest of
  the week.
- **Learns.** Each run writes down what went wrong in its own process, and the next run
  reads it.

## What it never does

- Commit to, push or merge your default branch. Merges happen only for branches you ticked
  Merge on, and stay local until you push.
- Deploy, publish a package, open or comment on PRs and issues, send messages, or reach other
  machines over ssh.
- Read or write secrets, change CI workflows, git hooks or Claude Code settings, or touch
  your uncommitted work.
- Delete folders recursively, except its own `runs/` and `worktrees/` folders.
- Ask you anything mid-run. Nobody's there to answer, so questions go in the inbox.

These rules are in the skill, and the ones that matter most are also **enforced by a hook**
that refuses the action before it runs. The hook only acts in the session that started a
run; everywhere else it returns immediately. It's a seatbelt against mistakes, not a sandbox:
[SECURITY.md](SECURITY.md) says exactly what it catches and what it can't.

## Requirements

- Claude Code 2.1.295 or later, signed in with a Pro, Max, Team or Enterprise plan. On an API
  key or a cloud provider every token is billed, so there is no spare usage to burn; setup
  says so and lets you decide.
- git, and bash (on Windows, the Git Bash that Claude Code already uses). No other
  dependencies: no jq, Python or Node.
- `gh` signed in, if you want branches pushed to private GitHub repos or issues used.

## Install

```text
/plugin marketplace add FantasticSalad/burn-my-usage
/plugin install burn-my-usage@burn-my-usage
/burn-my-usage setup
```

Setup takes a few minutes. It asks where your repos are, which to skip, whether to push
branches, and where your usage line is. It also offers to add a status line hook so runs can
see your weekly usage (your own status line keeps working). Nothing in your settings changes
without you seeing the change and saying yes.

## Running it

See what a run would do, without changing anything:

```text
/burn-my-usage plan
```

Start a real run before you walk away:

```bash
cd ~/code
claude --permission-mode auto --add-dir ~/.burn-my-usage
```

```text
/goal Run /burn-my-usage to the end. Done when its final report is written and stop.sh has printed STOPPED.
```

- **Auto mode** lets it work without permission prompts, with Claude Code's classifier
  checking each action. In manual mode it stops at the first prompt and waits all weekend.
- **`/goal`** keeps it working turn after turn until the run reports it's finished.
- **Leave the session open and the machine awake.** When the 5-hour limit hits, Claude Code
  waits and continues by itself after the reset, but only in an open session.
- **Stop it** with Esc, then `/burn-my-usage stop`.

## Your week with it

1. **During the week**, jot things in `~/.burn-my-usage/wishlist.md`: "api: add tests for the
   rate limiter", "webapp: CSV export breaks on commas in names". A "done when" helps.
2. **Friday**, start a run.
3. **Over the weekend or Monday**, open `~/.burn-my-usage/INBOX.md` and tick boxes:

   ```markdown
   ### webapp · `burn/2026-10-10-csv-escaping`
   **What it does.** Quotes CSV fields that contain commas or newlines on export.
   **Verified.** 4 new tests fail on main and pass here; full suite green.
   - [x] **Merge**
   - [ ] Needs changes (say what in the note)
   - [ ] Bin
   ```

4. **The next run** merges what you approved (locally), fixes what you sent back, builds what
   your decisions unblocked, and carries on. `/burn-my-usage inbox` processes your answers
   without starting a run.

Put the burn home in a synced folder or a private git repo and you can answer from your
phone.

## Commands

| Command | What it does |
|---|---|
| `/burn-my-usage` | A full run |
| `/burn-my-usage setup` | First-time setup, or fill in what's missing |
| `/burn-my-usage plan` | Build and show the queue; change nothing |
| `/burn-my-usage inbox` | Process your answers only |
| `/burn-my-usage status` | Usage left, open branches, inbox counts |
| `/burn-my-usage stop` | End the run in this session |

## Files

Everything lives in `~/.burn-my-usage` (or `$BURN_MY_USAGE_HOME`):

| File | Who writes it | What it is |
|---|---|---|
| `config.md` | you | roots, usage line, push policy, repo tiers, notes |
| `wishlist.md` | you | things to do when there's usage to spare |
| `INBOX.md` | both | cards from the run; your ticks and notes |
| `recurring.md` | both | weekly checks you switch on or off; runs update their dates |
| `lessons.md` | runs | what your runs learned |
| `ideas.md` | runs | ideas for later, never built without you |
| `runs/<date>/` | runs | each run's queue and log |
| `guard-deny.txt` | you | extra command patterns to refuse, such as your deploy script |
| `usage.json` | status line | your plan's usage, for pacing |

## Questions

**Will it cost me money?** Not on a subscription, with extra usage disabled. Sampled usage is not a hard spend cap. On API billing, yes; setup warns you.

**Will it push to main?** No. The hook checks push policy and refuses any push that isn't a `burn/` branch, and any
force push.

**What about public repos?** New installations keep branches local. Opted-in private mode pushes only to verified private origins. On a
public repo a pushed branch is visible to everyone, so they stay local.

**What if I'm using the machine when it runs?** Don't start a run in repos you're actively
editing. It won't touch uncommitted work, but two people on one branch is still a bad idea.

**Why markdown for the inbox and not an app?** It works in any editor, syncs with anything,
and diffs cleanly in git.

## Development

```bash
bash tests/run-all.sh
```

Core tests use bash, git, sed and awk. Optional release-scanner tests need Node 18+; CI runs
both on Linux, Windows (Git Bash) and macOS with the system bash 3.2.

`claude plugin validate . --strict` checks the manifests. `evals/` holds `claude plugin
eval` cases for whether the skill triggers when it should.

`bash tests/e2e/run.sh` does a real headless run on two throwaway repos and checks what it
left: a `burn/` branch whose tests fail on the old code, an untouched default branch and
untouched uncommitted work, an inbox card with no boxes ticked, and the guard switched off at
the end. It uses about 40 turns of your plan, so it's run by hand, not in CI.

Replay accepts only explicitly supplied synthetic or sanitised exported fixtures.
It makes no model calls, needs Node 18+, and never searches a native history store by default.
[docs/guard-replay.md](docs/guard-replay.md) explains its limitations.

[SECURITY.md](SECURITY.md) has the threat model and the decision log. [docs/DESIGN.md](docs/DESIGN.md)
explains how the pieces fit and why.

MIT licence: see [LICENSE](LICENSE).

## Isolation, recovery and commit checks

Every item uses a linked worktree, including clean repositories. The original checkout
stays on its existing branch. A staged text scanner blocks commits on possible credentials
or scanner errors, and reports only location/category. A commit is also refused when its
staged changes include agent, CI or git configuration, however the file was changed, because
a pushed branch runs its CI workflow with the repository's secrets. Finished items have
verified local Git bundles in the burn home's backups/ and task notes in handoffs/. Unmerged
branches, worktrees and stashes from all sessions are reported; other sessions' work is left
alone.

## Configuration defaults

Config lives at ~/.burn-my-usage/config.md, moved by BURN_MY_USAGE_HOME. Setup must confirm
roots and write matching absolute roots.txt; there is no implicit repository permission.
New defaults: stop_at 90 (strictly between 0 and 100), push_branches never, max_open_branches 3,
require_guard yes, ideas yes, issues off, burn_label burn-ok, trusted_issue_authors empty.
High/low/skip lists and run notes start empty. Existing values are never overwritten.
Push choices are never, private and all; only origin is supported. Private mode verifies
the single effective push URL with gh and refuses public or unknown visibility. Multiple
push destinations are refused. File-tool writes and literal redirects use canonical paths;
paths containing parent traversal are refused.

recurring.md holds enabled checks and dates (dependency/secrets/loose-ends/CI on; docs off).
Optional guard-deny.txt adds command patterns; guard-allow-mcp.txt contains exact
user-reviewed tool names. statusline-next preserves the previous status-line command.
usage.json, active/, owned/, runs/ and guard.log are runtime state. No credential values
are requested by the plugin.

## Runtime and cost limits

This release supports Claude Code only; Codex and claude.ai are future work.
Fresh usage is required for unattended changes. Missing/stale data means save a handoff
and stop, including in headless sessions. Disable paid extra usage or use provider-side
caps: a percentage sample cannot guarantee no overage. Pushing can consume CI minutes.
The hook uses onFailure: block; a missing or crashing script can block normal sessions,
until the user repairs or disables the plugin. Setup shows any setting change first.

## Network and data

Repository source, plans and issue context enter the selected Claude model service as
part of normal agent work. Optional GitHub features use api.github.com and the configured
origin at github.com; pushes send branch contents and can run CI. Other configured git
hosts are used only in explicitly enabled all mode. Dependency installs/audits can contact
the package registries named by each project's lockfiles, and documentation lookups contact
the requested sites. Review project scripts before running them: children are outside
string-level enforcement. There is no plugin telemetry or model API client. Authentication
stays inside approved git/gh/Claude clients.

The [guard review](docs/GUARD-REVIEW.md) records the gaps it reproduced, their fixes and what
still isn't covered. [Eval accounting](docs/EVAL-ACCOUNTING.md) explains how eval results are
checked. The plugin has not yet had an independent security review.
