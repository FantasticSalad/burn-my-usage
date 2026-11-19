# Burn My Usage

A repository automation workflow for spare subscription usage. If your plan has usage left
that will reset unused, start a run before you log off. It works through your repos while you're
away and leaves you branches with tests and a short inbox of decisions, which you can review
in a few minutes and merge or throw away.

The workflow is shared; host adapters supply session identity, tools, guard events and usage
samples. The published runtime remains Claude Code. This development tree includes an
experimental Codex package with startup context and native guard wiring; installed hook
enforcement and unattended continuation are still acceptance gates. See
[host architecture](docs/HOST-ARCHITECTURE.md) for the boundary.

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
- Read or write secrets, change CI workflows, git hooks or agent settings, or touch
  your uncommitted work.
- Delete folders recursively, except its own `runs/` and `worktrees/` folders.
- Ask you anything mid-run. Nobody's there to answer, so questions go in the inbox.

These rules are in the skill, and the ones that matter most are also **enforced by a hook**
that refuses the action before it runs. The hook only acts in the session that started a
run; everywhere else it returns immediately. It's a seatbelt against mistakes, not a sandbox:
[SECURITY.md](SECURITY.md) says exactly what it catches and what it can't.

## Costs are your responsibility

Check two things before you set it up:

- **You're on a subscription plan** (Pro, Max, Team or Enterprise), not paying per token
  through an API key or a cloud provider (Bedrock, Vertex, Foundry). On per-token billing
  there is no spare usage: every token a run spends is charged.
- **Paid extra usage is off** in claude.ai Settings > Usage, or capped at an amount you're
  happy to pay. With it on, Claude Code keeps going past your weekly limit and bills you.

The stop line works from sampled usage figures, so a run can overshoot it, and BURN IT ALL
takes a run to 100% of your limit on purpose. Your billing settings are the only reliable
money boundary.

Burn My Usage is provided as is, without warranty of any kind (see [LICENSE](LICENSE)). You
are responsible for any charges that running it incurs, and the author accepts no liability
for them.

## Requirements

These installation and run instructions describe Claude Code. Codex uses the shared workflow
through an experimental adapter and is not yet a supported unattended runtime. No Codex setup
or permission changes are required to use the existing Claude installation.

- Claude Code 2.1.295 or later, signed in with a Pro, Max, Team or Enterprise plan. On an API
  key or a cloud provider every token is billed, so there is no spare usage to burn; setup
  says so and lets you decide.
- git, and bash (on Windows, the Git Bash that Claude Code already uses). No other
  dependencies: no jq, Python or Node.
- `gh` signed in, if you want branches pushed to private GitHub repos or issues used.
- A terminal `claude` session to run it in. Runs learn your usage from Claude Code's status
  line, which refreshes in the terminal; in testing, the VS Code panel didn't refresh it.
- Optional: your ecosystems' audit tools (`pip-audit`, `cargo audit`, `govulncheck`,
  `bundle audit`; `npm audit` comes with npm). The weekly vulnerability check skips repos
  whose tool isn't installed, and setup tells you which.

## Install

```text
/plugin marketplace add FantasticSalad/burn-my-usage
/plugin install burn-my-usage@burn-my-usage
/burn-my-usage setup
```

Setup takes a few minutes. It asks where your repos are, which to skip, whether to push
branches, and where your usage line is. It may change two things in `~/.claude/settings.json`,
each shown to you first and only with your yes:

- a `statusLine` command, so runs can see your weekly usage (your own status line keeps
  working);
- `BURN_MY_USAGE_HOME` under `env`, only if you keep the burn home somewhere other than
  `~/.burn-my-usage`. That needs a restart of Claude Code before setup can finish, so setup
  stops there and resumes when you run it again.

"Skip" is an instruction to the run, not a fence: a run can still read a skipped repo under
one of your roots. To keep a repo out of reach, list your other repos individually as roots
rather than their shared parent folder.

### Codex package (experimental)

The source includes a portable Codex manifest and a separate hook definition. Prepare a
review copy in a new absolute folder, then check its inventory and local dependencies:

```text
node scripts/codex-package.mjs prepare ABSOLUTE_NEW_FOLDER
node scripts/codex-package.mjs check ABSOLUTE_NEW_FOLDER
```

Preparation copies an explicit runtime file list and SHA-256 inventory. It does not install
the package or edit Codex settings. Manual desktop installation and hook trust are described
in [Codex installation](docs/CODEX-INSTALL.md). Node 18+ is required; on Windows, configure
`codex_bash` in the burn home's config or `BMU_BASH` with the installed Git Bash path.
The native hook bridge derives identity from Codex events. Startup only supplies context;
it does not start a run. Live quota checks now use the supported local app server; each
authorization check refreshes instead of reusing a cached allowance. Native unattended
acceptance remains blocked. A compatibility manifest fixes the hook-discovery mismatch
found in tested Windows clients; native trust and enforcement still need acceptance. The
installation guide includes a read-only discovery/trust diagnostic.

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
- **Start it from a terminal `claude` session.** A run knows your usage from the status line,
  and treats data older than an hour as unknown, which stops it. The terminal refreshes the
  status line as the run works; the VS Code panel was seen not to, which left a run about an
  hour. To run from the VS Code panel anyway, use the until-limit mode below.
- **Use a dedicated session.** Until the run stops, that session can only change files in
  your roots, the burn home and temp folders, and only commit on `burn/` branches. Do your own
  work in another session.
- **Stop it** with Esc, then `/burn-my-usage stop`.
- **BURN IT ALL.** Type exactly that, in capitals, in the run's session, and this run goes to
  100% of your weekly limit instead of your stop line. It lasts for this run only (or the next
  one you start in that session within the hour) and never changes your config. A run that
  stops at its line with work left tells you it can. **Turn extra usage off first** (claude.ai
  Settings > Usage): usage is sampled, so a run can overshoot 100%, and with extra usage on,
  anything past your limit is billed.

### Until the limit (VS Code, or any client without the status line)

```text
/goal Run /burn-my-usage until-limit to the end. Done when its final report is written and stop.sh has printed STOPPED.
```

This run has no stop line and never reads your usage. It works until Claude Code's usage
limit stops it: the 5-hour limit or the weekly one, whichever comes first. A hook records
when. The next turn in that conversation finishes the run: it saves the item in hand as WIP,
updates the inbox and writes the report. That turn is either your next message or Claude
Code carrying on by itself after the limit resets, whichever comes first.

- **Extra usage must be off.** With it on, the limit never stops the run, and everything past
  it is billed. Your stop line doesn't apply either: the run can use all that's left of your
  week.
- **Keep the conversation open.** Only the run's own session can finish it. If you close it,
  reopen the same conversation from the history and send any message.
- In the VS Code panel, pick auto mode in the mode menu before you start.

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

Keep the burn home in a local folder. It holds each item's live git worktree, a Git bundle of
every branch (the full history of private repos) and a usage file rewritten on every status
line refresh, so a synced folder uploads all of that and can hold files open: on a OneDrive
burn home, worktree cleanup failed and left folders to delete by hand.

**Answering from your phone.** In Claude Code, setup can publish an inbox page: a private
page on claude.ai with the same cards, where each answer is one tap. A run adds and updates
cards there but can't answer them, and approving a branch approves the exact commit shown.
It is optional and off by default, because card text is then stored on claude.ai;
`INBOX.md` stays the record either way. The wishlist is still a local file.

## Commands

| Command | What it does |
|---|---|
| `/burn-my-usage` | A full run |
| `/burn-my-usage until-limit` | A full run with no stop line, until Claude Code's usage limit; then it wraps up |
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
and diffs cleanly in git. The optional inbox page sits on top of it for one-tap answers; the
file is still what a run writes first.

## Development

```bash
bash tests/run-all.sh
```

Core tests use bash, git, sed and awk. Optional release and Codex tests need Node 18+; CI runs
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
usage.json, usage/, active/, run.lock/, owned/, runs/ and guard.log are runtime state. No credential values
are requested by the plugin.

## Runtime and cost limits

The published release supports Claude Code only. The shared workflow and experimental Codex
adapter in this development tree do not establish native Codex runtime support; the remaining
checks are listed in [host architecture](docs/HOST-ARCHITECTURE.md). claude.ai is unsupported.
Fresh usage is required for unattended changes. Missing/stale data means save a handoff
and stop, including in headless sessions. Disable paid extra usage or use provider-side
caps: a percentage sample cannot guarantee no overage. Pushing can consume CI minutes.
The Claude hook uses onFailure: block; a missing or crashing script can block normal sessions,
until the user repairs or disables the plugin. Setup shows any setting change first.

## Network and data

Repository source, plans and issue context enter the selected host's model service as
part of normal agent work. Optional GitHub features use api.github.com and the configured
origin at github.com; pushes send branch contents and can run CI. Other configured git
hosts are used only in explicitly enabled all mode. Dependency installs/audits can contact
the package registries named by each project's lockfiles, and documentation lookups contact
the requested sites. Review project scripts before running them: children are outside
string-level enforcement. There is no plugin telemetry or model API client. Authentication
stays inside approved git/gh/agent clients. Offline adapter tests use synthetic inputs and
make no model calls. The plugin never discovers usage by reading authentication files or
native session stores.

The [guard review](docs/GUARD-REVIEW.md) records the gaps it reproduced, their fixes and what
still isn't covered. [Eval accounting](docs/EVAL-ACCOUNTING.md) explains how eval results are
checked. The plugin has not yet had an independent security review.
