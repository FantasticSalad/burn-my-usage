# Shared workflow and host adapters

Contents: boundary, contracts, safety, verification and remaining runtime gates.

## Boundary

One workflow owns task selection, the queue, item worktrees, tests, review, inbox decisions,
backups and handoffs. Host adapters supply invocation, script paths, session identity, tool
events, usage samples and continuation. A host adapter cannot relax the shared safety policy
or a repository's own instructions.

| Component | Shared responsibility | Host responsibility |
|---|---|---|
| Skill | Modes, work selection and review | Invocation and resolving installed resources |
| Run state | One owner per burn home, queue and recovery | Validated host and session identity |
| Guard | Branches, protected paths, approvals and outward actions | Translate actual tool inputs before checking policy |
| Usage | Freshness, stop line and conservative stopping | Collect only supported quota data for that provider |
| Inbox | Local records and owner answers | Available file editing tools |
| Continuation | Read saved queue and handoff | Supported host launch, interrupt and resume behavior |

The existing Claude plugin manifest and Bash hook remain the supported integration. The
experimental Codex package selects its own hook definition, supplies startup context and
translates documented native events to the shared policy. These are exercised with
synthetic events and prepared packages. Installation is an explicit user action, separate
from preparation. Native checks on Windows found that the tested clients ignored the
inline OpenAI hook extension; the compatibility manifest makes hooks discoverable in
controlled native fixtures. This does not establish that a particular client calls the
adapter, trusts its hook, blocks host hook failures or continues after quota resets.

## Contracts

`BMU_HOST` identifies `claude-code` or `codex`; omitted values retain the existing Claude
behavior. `BMU_SESSION_ID` supplies host-neutral identity where an explicit session argument
is not supplied. Host adapters resolve script locations rather than assuming another host
expands Claude variables. Runtime state stays under `BURN_MY_USAGE_HOME`, never inside the
installed package. Existing Claude config and inbox files remain usable.

Both hosts share the user's config, wishlist, queue conventions and inbox. Active session
markers and quota snapshots distinguish providers. A shared atomic run lock prevents two
owners from using the same burn home at once; marker age is not proof that a run can be
adopted. Only the owning host and session may release its lock. Separate burn homes do not
isolate Git repositories or other shared resources: configure them to avoid overlapping
concurrent work.

Before upgrading an active older installation, finish its run with that installed
version. An older marker without a new-format lock blocks a new run; the new stop command
does not claim ownership of it. If the old process is unavailable, the user must verify
it has ended, preserve unfinished work and review its state before manually clearing an
abandoned marker. No age-based cleanup or automatic takeover is performed.

If stop reports a filesystem cleanup error, preserve the lock and recovery records and
inspect the reported state before retrying. Stop retains external backups of the lock owner
and markers until lock removal succeeds; a failed removal restores them where the filesystem
permits it and retains recovery evidence otherwise. It is not a successful normal finish.
Item operations require both a matching marker and a valid provider/session run lock. New
items and adoption of retained branches require a fresh `go` verdict. A verified existing
owner can recover and save its current item at `wrap`, `stop` or `unknown`.

Usage percentages are meaningful only within their provider and quota window. A Codex
sample cannot authorize Claude work, or the reverse. Existing untagged `usage.json` samples
belong to Claude only. Codex `usage.sh` authorization checks launch the supported local
`codex app-server`, initialize it and call only `account/rateLimits/read`. The approved
client handles authentication internally; the collector never opens authentication or
session stores. It selects the `codex` bucket, requires both five-hour and weekly windows,
honors a service-reported reached limit and saves only validated quota fields. Other quota
window shapes are currently unsupported and return `unknown`.

`BMU_CODEX_BIN` optionally names an absolute native client executable; otherwise `codex`
is resolved through PATH. Each authorization check fetches again, with bounded time/output
and confirmed client termination. Failure returns `unknown`, even if an older snapshot
cannot be removed. `usage-codex.mjs read` is snapshot inspection only; it never authorizes
new work. Live checks add startup/network latency and may make several requests per action.
They do not redeem resets or purchase credits. Sampling is not a hard spending cap.

The optional Codex adapter uses Node 18 or later for structured JSON and patch parsing. The
existing Claude runtime retains its Bash 3.2 and Git requirements. This dependency is local;
the adapter installs nothing and downloads no code.

The offline guard input is a normalized envelope containing `session_id`, absolute `cwd`,
`tool_name` and object `tool_input`. Its process also receives `BMU_HOST=codex` and matching
`BMU_SESSION_ID`. On Windows, `BMU_BASH` must name the installed Git Bash executable by
absolute path; the adapter does not assume a `bash` on PATH is Git Bash. These are fixture
and adapter contracts, not evidence that a native hook emits the same envelope.

## Codex package and native bridge

The source root portable `plugin.json` owns package identity. Prepared Codex payloads use
only `.codex-plugin/plugin.json` at the installed manifest location; the portable manifest
is preserved as `docs/portable-plugin.json`. Its name, version and description must match
the compatibility manifest; package checks enforce this. On the tested native clients,
a schema-bearing portable root manifest prevents hook discovery even with a compatibility
overlay or a default hook file. Keeping it as documentation avoids that selector while
retaining canonical identity. The compatibility manifest selects only `hooks/codex.json`,
avoiding default discovery of the existing Claude `hooks/hooks.json`.
The Codex definition registers `context-codex.mjs` for `SessionStart` and `hook-codex.mjs`
for `PreToolUse`. Its Node bootstrap reads `PLUGIN_ROOT` as an environment variable and
resolves handler paths without depending on shell variable expansion. The existing Claude
manifest and hook definition are retained.

Startup validates native session metadata and returns resource and recovery pointers only;
it never creates a marker or changes ownership. The native bridge binds `BMU_HOST` and
`BMU_SESSION_ID` from its validated event and checks them against the product's run lock and
matching marker. An orphaned matching marker or inconsistent owned state is refused.
Ordinary unmarked sessions remain unaffected.

Native `Bash` and `apply_patch` events carry their payload in `tool_input.command`.
The bridge translates those into the common adapter's command and patch schema, preserving
explicit execution directories and refusing unsupported overrides. Native child events use
the parent session identity in the documented contract; actual child coverage is unverified.
Shell reads pass the common policy; unsupported tool forms
are refused while the run is active. The bridge does not read `transcript_path` or native
auth/history files. On Windows, it resolves Bash from `BMU_BASH` or the product config's
`codex_bash` key, with the same explicit dependency documented by package preflight.

Preparation and manual installation are described in [CODEX-INSTALL.md](CODEX-INSTALL.md).
Preparation copies an allowlisted set of runtime resources to a new destination and writes
checksums. Checking a copy verifies its inventory and dependencies; it neither trusts hooks
nor demonstrates native enforcement. No private source ancestry or internal release records
belong in that copy. Public distribution still requires the normal release review.

The native host does not run another `PreToolUse` for later `write_stdin` input, and some
hosted or specialized paths have no tool hook coverage. Refusing a synthetic `write_stdin`
envelope does not fix that host behavior. Acceptance must resolve the effective writable
tool surface and interactive/background execution before an unattended support claim.
Likewise a bridge denial on a child-process error does not prove the host blocks a missing
Node executable, skipped or untrusted hook, or host-level timeout.

## Safety

Every Codex patch target must pass the same path policy as an ordinary file edit before
the patch is permitted. Moves include both source and destination. A patch with one unsafe
target is refused as a whole. Malformed input, unsupported tools and failures of the policy
process are refusals in the offline adapter, not permission to proceed. Later input to an
existing shell process needs its own mediation; it must not inherit permission from an
earlier checked command.

These adapter decisions do not prove native host failure handling. Existing string-level
guard limitations still apply, including code executed indirectly by project scripts. Keep
the host sandbox, normal approval review and user trust requirements. Never bypass those
controls to make an acceptance test pass.

## Verification and remaining runtime gates

Run `bash tests/run-all.sh` for shared scripts, guard fixtures, usage and lifecycle tests.
Node tests are included when Node is installed. Strict Claude manifest validation checks
packaging separately. Synthetic adapter tests neither invoke a model nor prove installation.

Before claiming unattended Codex support, verify all of these against a named client
version and operating system:

1. Native skill discovery, installation and resource path resolution.
2. Actual session identity on start, resume, compaction and child-agent events.
3. Shell, patch, nested tool and MCP coverage; interactive stdin and background processes.
4. Refusals before side effects, including missing scripts, crashes, timeouts and untrusted
   or disabled hooks. Resolve any host behavior that continues without the required guard.
5. Fresh supported subscription quota collection and correct window/bucket selection.
6. Unattended launch, interruption, quota exhaustion and safe recovery without changing
   host security defaults.
7. A real task from an installed copy, preserving original checkouts and dirty work and
   leaving a tested branch, unticked inbox card, backup and handoff.

The native integration proof remains blocked. On Windows, tested clients
`0.162.0-alpha.17.2` and `0.167.0-alpha.3.2` exposed the installed skill but ignored the
inline hook extension. Controlled native profile tests isolate the schema-bearing root
manifest as an additional selector: it suppresses even compatibility/default-file hooks.
The compatibility-only prepared payload exposes both hooks as untrusted in the normal
profile. This fixes discovery; trust, denials, hook
failure behavior, child coverage and continuation still require acceptance. The
supported live quota path returned a stop verdict; no model-driven mutating task followed.
Use `node scripts/codex-native-check.mjs ABSOLUTE_CWD` to recheck discovery and trust.
Even a ready result means only that enforcement tests can begin, not that they passed.
Until native proof is completed, use Codex
adapter code only for development and read-only workflow guidance. Claude end-to-end/model
eval evidence from an older revision does not validate this refactor; repeat the applicable
installed task and discovery checks before distributing a new runtime version.
