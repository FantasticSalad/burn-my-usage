# Security decisions

The runtime and guard decision log remains in [SECURITY.md](SECURITY.md).

## 2026-11-15: the public identity is the GitHub handle

Problem: the licence, the three manifests and the release scanner each carried the owner's
personal name. The scanner listed it as a marker to catch, split into pieces, and its tests
spelled it the same way, so the check that was meant to keep the name out of the repository
published it.
Options: keep the name as an allowed author credit; hash the marker; or carry no personal
name in the tree and take name terms only from the owner's private redaction list.
Decision: credit the handle `FantasticSalad` in the licence and manifests, remove the name
from the scanner's built-in markers, and use an existing workflow marker as the test fixture.
The scanner's exemption for copyright and author fields stays, so a credit is still not
scanned against built-in markers; private-list terms are still checked everywhere else.
Consequence: a scan without the private list no longer catches the owner's name. That check
now depends on the private list and on the publishing procedure, both kept outside this tree.
Verification: no personal name remains in any tracked file outside the internal release
record; the 11 scanner tests, all 41 Node tests and every shell suite pass; both Claude
manifests pass strict validation.

## 2026-11-13: supervise Windows guard startup outside Node

Problem: the Node-based bootstrap cannot emit a denial when Node itself fails to start.
Options: accept the native host's error behavior, change machine controls, or run a bounded
supervisor independently of Node and explicitly deny when the bridge cannot complete.
Decision: on Windows, register a complete literal PowerShell command that supervises Node.
It reads bounded input, waits at most 18 seconds internally, bounds child output, requires
one positive completion token, and emits a fixed valid denial after any other outcome.
The native timeout is 40 seconds. Keep the existing non-Windows command experimental.
PowerShell policy blocks script files here; the template is used at authoring time only.
The registered command contains the complete reviewed code; no runtime file evaluation,
script policy override, native trust bypass or settings change is used. Package preflight
requires the exact template-generated command. The installed candidate needs native review.
Verification: synthetic inline PowerShell tests cover normal allow/deny, missing runtime,
Node preload crash, empty/extra/nonzero output, excessive input/output and internal timeout.
Outer-shell startup, disabled/untrusted hooks, host-level timeout and detached process
containment remain separate native limits; this fix does not establish unattended support.
Integrated verification: 41 Node tests and all shell suites pass. Older path/recovery fixtures
now provide synthetic fresh quota and matching ownership instead of assuming cached quota
or markers suffice; the odd-path fixture cannot contact the real quota client. The installed
v8's 48 files match its inventory. After the initial rejection for exact-v7-only authority,
the owner explicitly approved the two v8 hooks and their exact hash. Native /hooks trusted only
those two definitions; fresh metadata confirms enabled/trusted with zero errors. Inactive
native use succeeds. The startup crash and missing-lock cases emit explicit denial and no
command item; the crash reports protectedFailureObserved=true and failedHook=false.
Denied-call input is still unverified. The observed Windows startup bug is closed for private
integration while broader native acceptance and public release gates remain open.

## 2026-11-12: retain the native acceptance block after an interpreter crash

Problem: native discovery and trusted explicit denials do not establish behavior when
the hook interpreter fails before the denial bootstrap runs.
Options: infer safety from happy-path denials, add another JavaScript catch, or test the
failure with a harmless native command and retain the independent enforcement gate.
Decision: preserve the installed definitions and native controls; inject a synthetic Node
startup crash only in a disposable read-only client. Keep unattended Codex unavailable
when the host proceeds after hook failure. A wrapper inside the failed interpreter cannot
enforce the missing boundary; native mandatory enforcement or an independent constrained
execution environment must be evaluated before further unattended acceptance.
Verification: both approved hooks are enabled/trusted; native context and inactive behavior
work, and four guard blocks are observed. Denied calls lack command execution metadata,
so exact intercepted-call coverage is unverified. The crash causes failed SessionStart/PreToolUse
events and the harmless command exits 0. The regression is an acceptance failure, not a
passing test. See docs/NATIVE-ACCEPTANCE.md and opt-in tests/native-runtime.mjs. No settings,
threshold, credit operation, public release or unrelated hook change was made.
The package allowlist includes the acceptance document so the installation guide's new
link resolves in future prepared payloads. The currently installed v7 payload stays intact.

## 2026-11-12: give git Windows paths, so items stay inside the burn home

Problem: Git Bash doesn't convert a `/c/Users/...` path containing an apostrophe when it
starts a native program, and git and Node then read it as `C:\c\Users\...` or, for `/tmp`,
`C:\tmp\...`. With the default burn home (`~/.burn-my-usage`) under a profile folder such as
`O'Brien Desktop`, `work-item.sh` created item worktrees under `C:\tmp\...`: outside the burn
home, where the guard's folder rules don't expect them. `repo-check.sh` failed on a root
like `~/code`, and `start.sh` couldn't read its commit. Found by the new CI step that runs
the suite from a folder with a space and an apostrophe, after the F1 change landed.

Options: tell users not to have apostrophes in their profile (they can't easily change it);
convert at each git call; normalise the inputs once.

Decision: `lib.sh` converts the burn home to `C:/...` form once (`cygpath -m`, Windows only),
which covers every script that sources it. `work-item.sh` converts a repository argument in
Git Bash form, `repo-check.sh` each root, and `start.sh` the plugin root it hands to git.
The guard and the status line script are unchanged: they compare paths and write files in
bash, which handles either form.

Verification: tests/odd-path.test.sh gains four checks (repo-check under a root with an
apostrophe; the item worktree created inside a default burn home under such a profile, and
git agreeing where it is; start.sh's commit from such a checkout). All four fail on the
previous code and pass now; the full suite passes from the normal path and from a folder
with a space and an apostrophe.

## 2026-11-12: BURN IT ALL raises one run's stop line, armed only by the user

Problem: users asked to let a run go past `stop_at` to 100% when they choose (new-user review
F11). The stop line is the product's cost control: the guard refuses writes once `usage.sh`
says stop, and `stop_at` is capped below 100 so headroom is the default. A run must never be
able to raise it for itself, and a raise must not become a standing default.

Options: (a) an inbox card that raises the line for the next run; (b) the run asks at the
line and waits; (c) the user types a phrase that a UserPromptSubmit hook sees, arming the
current run.

Decision: (c). (a) is a run late; (b) leaves an unattended run waiting, the stuck state the
question-tool block exists to prevent. A UserPromptSubmit hook only ever sees the user's own
message, so the run can't forge it by claiming consent. The message must be exactly `BURN IT
ALL` (capitals, optional ! or .), so mentioning it doesn't arm it. The hook writes
`<burn home>/burn-it-all/<session>`; `usage.sh` uses 100 (wrap at 99) only while that session
holds the run lock; `stop.sh` deletes it; `start.sh` drops an arm older than an hour, so
one typed between runs applies only to the next run in that session. The guard treats the
folder as a run control (no file-tool or shell writes) and refuses any shell command naming
`burn-it-all`, so the run can't feed the hook a made-up message. `config.md` is untouched.
The hook warns that extra usage must be off: sampled usage can overshoot 100%, and the hook
can't see billing settings.

Limits: like the other run controls, a script the run writes elsewhere and executes could
create the file; the guard is a seatbelt, not a sandbox. A run working on this repository
can't name `tests/burn-it-all.test.sh` in a command (run-all.sh still runs it). Every
message in every session now starts one bash for the hook (about 40 ms on Windows) and
exits after a substring check. Codex runs get their own mechanism, built separately; this
hook arms Claude Code runs only. Setup now opens with an explicit cost check (subscription,
not per-token billing; paid extra usage off or capped) and a no-liability disclaimer the
user must acknowledge, repeated in the README.

Verification: tests/burn-it-all.test.sh, 31 synthetic checks covering the exact phrase,
other sessions, the 100% line and wrap window, guard refusals (file tool, touch, redirect,
piping into the hook), removal at stop, the pending arm and its one-hour expiry, and
malformed input. The hook's JSON output has not yet been checked in a live Claude Code session.

## 2026-11-12: refuse to start a run without a usable roots.txt

Problem: a new-user review (new-user review F6) read `[ -s roots.txt ] || return 0` in the
guard as "allow everywhere when roots.txt is missing". Testing showed the opposite:
`outside_roots` returning 0 means "outside", so the guard refuses every write outside the
burn home and temp. It fails closed. But `start.sh` still started a run in that state, which
could then change nothing in any repository, and the comment above the function implied
the check only applied "when setup wrote roots.txt".

Options: leave it (safe but a wasted run); make the guard treat a missing file as an error
of its own; refuse at start.

Decision: `start.sh` refuses with `NO_ROOTS` and creates nothing (no marker, lock or run
folder) unless roots.txt has at least one absolute path, matching the existing `NO_CONFIG`
refusal. The guard is unchanged; its comment now says it fails closed.

Verification: scripts.test.sh adds six checks that fail on the previous `start.sh` and pass
now; guard-paths.test.sh pins the fail-closed behaviour for a missing and an empty roots.txt
(Write and redirect), against a listed root outside temp as the control.

## 2026-11-12: read quoted paths with spaces and apostrophes as the shell does

Problem: on the first real run, with the burn home under a Windows profile folder whose name
has a space and an apostrophe, the guard refused the run's own cleanup and a redirect into
the burn home (new-user review F15). Reproducing it found three defects, two of which
refused too little:

1. Every path was unquoted twice (`check_delete`, the file-mutator check, `--git-dir=` and
   redirect targets unquoted a word and then passed it to `resolve_dir`, which unquoted
   again). The second pass dropped an apostrophe that the first had correctly kept, so a
   path in the burn home no longer matched it. Over-refusal: `rm -rf` inside the run's own
   `worktrees/`. Under-refusal: `rm "<home>/config.md"` skipped the run-control check.
2. The old unquote dropped every quote character, including one inside the other kind of
   quote (`"O'Brien"`).
3. A redirect target was only its first space-separated word, so
   `> "C:/x/my dir/.github/workflows/ci.yml"` was checked as `C:/x/my`. Over-refusal for a
   good path under a spaced root; under-refusal for CI workflows, agent settings or other
   protected files below any folder with a space.

Options: (a) tell users not to put the burn home or roots under paths with spaces or
apostrophes; (b) fix the parsing.

Decision: (b), since (a) leaves the under-refusals for anyone whose repos sit under such a
path. `unquote` now keeps a quote that sits inside the other kind, with the previous
behaviour unchanged for words holding only one kind of quote and for backslashes.
`resolve_path` resolves an already-unquoted word, and the four callers that had unquoted use
it. The redirect scanner joins a quoted target across the words it spans before checking
it; if the quotes never close, it checks the first word as well, as before, so a malformed
command is judged at least as strictly as it was.

Verification: tests/guard-quoting.test.sh, 13 synthetic cases with a home and a root whose
names have spaces and apostrophes; 9 fail on the previous guard (four of them
under-refusals) and all pass now. The full suite and replayed trace cases pass.

## 2026-11-12: a failed worktree removal must not leave a run unable to stop

Problem: on a first real run with a OneDrive burn home, `git worktree remove` failed with
"Permission denied" after git had already deleted the worktree's admin folder. `work-item.sh
finish` exited under `set -e` before releasing the ownership record, `stop.sh` refused while
any record existed, and the guard (correctly) refused the run's own edits to `owned/`. No
documented command ended the run; its guard stayed on until the user deleted state by hand
(new-user review F18).

Options: (a) force-remove the worktree; (b) have `stop.sh` silently drop any record it can't
match; (c) release ownership as soon as the backup verifies, report a leftover folder, and
give `stop.sh` an explicit, narrow `--release-orphans`.

Decision: (c). Force removal could delete files the user's tools are holding, and silent
dropping would weaken the "save before stop" rule. `finish` now records "State: saved" and
releases the record once the bundle verifies, then tries the removal and prints
`LEFTOVER=<path>` for a user job if it fails. `--release-orphans` releases only records whose
path is no longer the top of a git worktree, checks every record before changing any, and
still refuses while a live owned worktree exists. It deletes no folders. Commits live in the
repository, not the worktree folder, so no saved work can be lost; uncommitted files in a
leftover folder stay on disk.

Verification: tests/recovery.test.sh uses a git shim that reproduces the OneDrive failure.
16 of its 23 checks fail on the previous code and all pass now; the full suite passes.

## 2026-11-11: select the compatibility manifest for native hook discovery

Problem: the installed skill was visible but native metadata omitted both hooks when the
portable manifest selected them through its inline OpenAI extension.
Options: copy hooks into shared user configuration, rely on the default hook filename, or
use the documented compatibility fallback and keep host definitions separate.
Decision: retain source portable identity unchanged, but prepare a compatibility-only Codex
payload selecting hooks/codex.json from .codex-plugin/plugin.json. Preserve the canonical
portable manifest at docs/portable-plugin.json in that payload, where native loading does
not select it. Enforce matching name, version and description during package checks.
Preserve Claude's manifest and hook file.
Verification: model-free native probes first compare six layouts on both clients, then
isolate the schema-bearing portable root selector using additional controlled variants.
It suppresses hooks even with compatibility/default-file declarations. The compatibility-only
payload exposes both hooks as untrusted in the normal profile. Temporary uniquely named
fixture registrations in the normal profile are removed by the probe. No trust bypass,
security-default change or authentication-store access is used. Discovery does not establish
trust, native enforcement or unattended acceptance.

## 2026-11-11: refresh Codex quota and preserve verified recovery ownership

Problem: reusing a saved quota sample can miss exhaustion, failed deletion can leave an
old go sample readable, and a marker alone does not establish ownership of an interrupted
run. Failed lock removal can also lose its owner after guard markers have been removed.

Options: shorten cache age and best-effort deletion, or require a fresh supported quota
response for every authorization check and verify recovery ownership independently.

Decision: call only initialization and the supported quota-read method through a bounded
native client subprocess. Use only its new validated result, require both five-hour and
weekly windows and honor service-reported reached limits. Do not redeem resets or retain
account identities or raw diagnostics. Snapshot inspection never authorizes work. Require
matching lock/provider/session for item operations, go for new work, and preserve owner
and marker backups until stop releases the lock. Existing owners may still save work at
stop or unknown. Keep native sandbox, approval and trust controls unchanged.

Verification: synthetic tests cover transport/protocol/output/timeout/termination failures,
missing windows, reached states, failed storage/invalidation, exhausted/unknown quota and
interrupted lock removal. A native quota read succeeded and returned stop. Installed native
skill discovery succeeded but package hook discovery failed on the tested clients; native
enforcement and unattended acceptance remain blocked. A read-only diagnostic makes that
boundary explicit. The private release record retains exact results and remaining gates.

## 2026-11-11: bind native Codex hooks without changing installed controls

Problem: the offline guard expects a normalized envelope and explicit provider identity,
while native Codex events use their own shell/patch fields and supply session identity.
An installer that silently edits existing controls or copies the development repository
could expose private history or create a false impression of native enforcement.

Options: rely on shell-expanded host variables and the Claude hook definition, or package
a separate native bridge and prepare a review copy with explicit runtime contents.

Decision: the portable manifest selects only the Codex hook definition. Startup returns
validated resource/recovery context without creating a run. The tool bridge validates native
session and ownership state, binds provider identity itself, preserves directory semantics
and refuses unsupported overrides. Invalid partial locks and orphaned matching markers
refuse calls. Child-process failures produce denial feedback, never permission grants.
An environment-reading Node bootstrap resolves package paths without shell interpolation.
Preparation creates a new allowlisted copy, local marketplace catalog and checksum inventory;
it never edits existing client settings, installs a plugin or trusts a hook.

Verification: synthetic native events, startup side effects, exact registered shell commands,
prepared-copy contents and refusal paths are tested locally. Package checksums are not an
authenticity signature. Native discovery/trust, host errors/timeouts and unhooked interactive
or hosted tool paths remain acceptance gates; the bridge cannot assert host fail-closed
behavior. Exact results are retained in the private development release record.

## 2026-11-11: separate the shared workflow from host enforcement

Problem: the task workflow is reusable, but its Claude variables, tool vocabulary, session
markers and usage feed cannot establish safe operation in another agent host. Reusing a
Claude quota sample for Codex or accepting only the first target of a multi-file patch
would silently weaken controls.

Options: copy the skill for each host, rename Claude references without changing runtime
contracts, or share the workflow and policy while translating host inputs explicitly.

Decision: keep one shared workflow and small host adapters. Preserve the Claude integration;
add experimental Codex event translation and explicit quota ingestion without installing a
native hook or collector. Scope identity and quota data to the provider and serialize runs
with one burn-home lock. Refuse malformed or unsupported adapter events, validate every patch
target and retain the existing sandbox and approval controls. Native integration acceptance
is deferred; no unattended Codex support claim follows from this implementation.

Verification: synthetic lifecycle, usage and guard tests exercise the shared contracts;
the exact results and remaining runtime gates are recorded in the development release
record. No native session stores or credentials are test inputs. Native discovery, installed
tasks, live quota refresh, continuation and host hook-failure behavior remain separate gates.

## 2026-11-05: review metadata in public deliverables

Problem: a history-free snapshot preserves file contents, and a snapshot helper
can still inherit dates from its source commit. Text scanners do not inspect
binary metadata or archive headers. Options: rely on source scans, or review
the final distributed files and their container metadata as a separate gate.
Decision: require the separate review, descriptive screenshot names, documented
constant archive dates and public-only source ancestry. Keep internal evidence
and development provenance out of public deliverables. Preserve actual Git
event dates and required source attribution. Internal preparation steps remain
in the private release records.
Verification: source review identified inherited dates in the legacy preparation
helper. Its outputs remain private pending a corrected date policy and review.
No packaging implementation or publication occurred in this documentation task.
