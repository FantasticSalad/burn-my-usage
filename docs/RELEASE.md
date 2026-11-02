# Release evidence

Private preparation for version 0.2.4. No public release, directory submission or
announcement is authorised by this record.

## Owner gates

- 0.2.4 replaces the 0.2.3 candidate. The owner's private-list review on 2026-10-29 covered the
  0.2.3 bundle, not these bytes. Settle the destination name and the README and manifest URLs
  first, then cut one bundle, so a single owner scan covers both changes.
- Affected baseline comparisons: complete. The reruns on 2026-10-25 (see Model evals) have
  no execution or grader errors, and they replace the earlier Haiku turn-limit error and the
  two Opus session-limit errors. The CLI exits zero even when a run errors, so check each
  run's error and skippedPaidGraders fields.
- Run the privacy scan with the private redaction list; an agent has not read that list.
- Use the verified parentless bundle described in PUBLIC-SNAPSHOT.md as the publication
  source. The private workbench retains its original history and workflow metadata.
- Arrange an independent person's installation, setup and real task, plus independent
  review of the unattended guard. Automated self-tests are not independent security vetting.
- Confirm any applicable employer/outside-work clearance before adding work-related material.
- Separately authorise publication, directory submission and announcements. Check public
  secret scanning and push protection at that time, and use the directory's own validator.

## Scope

Claude Code 2.1.295+ only, on Linux, macOS and Windows with Git Bash. MIT licensed.
No Codex or claude.ai runtime support. The original private workflow remains in service. This release adds
universal item worktrees, staged leak checks, verified branch bundles and handoffs, broader
read-only branch review, conservative push defaults and safer missing-usage behavior.

## 0.2.4 second review

A second agent reviewed the guard adversarially on 2026-10-29 (GUARD-REVIEW.md, "Second
review"; SECURITY.md decision log). tests/guard-spellings.test.sh adds 109 checks. On the 0.2.3
guard, 73 of them fail: 72 missed refusals and one wrongly refused commit. The Windows suite
passes 637 checks: 414 original guard, 27 from 0.2.3, 109 new, 49 script, 20 lifecycle and 18
Node. Both strict manifests pass. SKILL.md is unchanged, so the model evals below keep their
provenance.

CI ran on the guard commit's branch and again on main after landing. Branch runs: release
40818251533 and development 40818295885. Main runs for the guard content: release 40818925221
(77a4ce1) and development 40818944814 (fdd428e). All four succeeded. Per platform: Windows 637
checks; Linux and macOS 631 each, because six cases need Windows (three hook-environment checks
in tests/guard.test.sh and three 8.3 checks in tests/guard-spellings.test.sh). The 18 Node tests
ran on every platform.

The end-to-end synthetic task (tests/e2e/run.sh) passed 15/15 with no guard refusals besides
the self-test: terminal success, 24 tool-use rounds, 64 tool calls, 65 reported turns, CLI
estimate USD 0.48. Its workspace was under a Windows 8.3 short path, so the new short-name
expansion ran on every file call there and refused nothing. The turn-cap probe in
EVAL-ACCOUNTING.md also ran.

The subagent session-id assumption was verified on Claude Code 2.1.312 with a probe plugin in a
headless Haiku session (SECURITY.md, Assumptions). The CLI estimated it at USD 0.02 at list
price, on a subscription. The real-transcript replay was not rerun. It needs the maintainer's
own transcripts; running `bash tests/replay/run.sh` once with `--guard <the 0.2.3 guard>` and
once without compares the two guards' refusals.

## 0.2.3 hardening

The author-side GUARD-REVIEW.md found and corrected parent-traversal writes, multiple
origin push destinations, and attached/clustered HTTP write flags or contradictory methods.
Twenty-seven focused checks include sixteen denials that failed on the pre-review guard.
This review prepares the independent person's gate; it does not clear it.

The Windows checks pass 528 cases: 414 original guard, 27 new guard, 49 script,
20 lifecycle and 18 Node tests. The full shell suite passed together; the final two
scanner cases and affected Node tools were then verified in an 18/18 focused run.
Both strict manifests pass. The 0.2.3 local-scope install
has matching skill/guard/stop hashes and unchanged user settings. CLI context estimates
remain 258 always-on tokens and about 6k on invocation. Installed status succeeds without
--plugin-dir (eight reported turns). The local test plugin and marketplace were removed;
the user settings SHA-256 remained unchanged before installation and after cleanup.

A completed synthetic task passed 15/15 with no unexpected guard refusals. The final run
after the HTTP-cluster change also passed 15/15; it recovered from one correctly refused
shell write to the inbox by using the permitted structured edit. An earlier smoke invocation did
not start the run (nine checks passed, three failed); its original harness removed the
fixture before a cause was identified. Failures now retain their synthetic diagnostics
and emit bounded terminal/result counters; this is not a claim that the early failure's
cause was fixed. Candidate CI passed all three platforms in each private repo (release
40170583856; development 40170590052). Final artifact identities and subsequent CI are
recorded in the workspace release record and the artifact's snapshot.json.

The file/message scanner has nine synthetic tests, including malformed JSON diagnostics
that do not echo its synthetic token and refusal of unexpected binary content.
prepare-snapshot.mjs has three tests
for a verified one-commit import and exact tree, dirty-source refusal and preservation of
existing output. check-eval.mjs has six tests and accepts the two saved reruns below with
no execution/grading errors. EVAL-ACCOUNTING.md explains the counter distinction and local
evidence; a separate optional cap probe was blocked by PowerShell's script policy and is
not claimed as run. INDEPENDENT-TEST.md and the blank results template prepare the human gate.

SKILL.md is unchanged from 0.2.2, so the model trigger/behavior evidence below retains that
provenance. Active-guard corrections are tested directly and in the synthetic task; the
read-only model eval cases do not exercise an active burn marker.

## Earlier 0.2.2 evidence

| Check | Evidence |
|---|---|
| Windows local regressions | 414 guard + 49 scripts + 20 lifecycle + 3 scanner tests: 486 passed, zero failed |
| Regression sensitivity | Original guard failed 10 current tests, including primary-checkout edits and protected redirects |
| Strict manifests | Explicit plugin.json and marketplace.json: 2 passed |
| Three-platform CI | Candidate 8b90a9f, run 40067908644: 3/3 jobs passed; Windows 486 checks, Linux/macOS 483 each (three Windows-only cases); macOS Bash 3.2.57 |
| Privacy | Candidate index: 62 text files, zero findings. History through 8b90a9f: 4 revisions / 186 file snapshots, zero findings. Private list not supplied |
| Clean task | Final guard: 15/15 checks passed, zero guard refusals beyond its deliberate self-test |
| Local-scope install/update | Version 0.2.2 installed; skill, guard and stop helper hashes match; user-level settings hash unchanged; installed status invocation succeeds without --plugin-dir (7 turns), correctly warns of stale synthetic usage |
| Context | CLI estimate: 258 always-on tokens, about 6k on invocation; one skill, one hook, zero agents/MCP/LSP |

CI: https://github.com/FantasticSalad/burn-my-usage-release/actions/runs/40067908644
The release history starts from a sanitised snapshot. The original development history is
not imported. These scans are pattern checks, not proof that private material cannot exist.
Final documentation/integration snapshots must be scanned before preparation is closed.

The clean-task fixture uses throwaway repositories and synthetic usage data. It checks a
useful CSV fix, tests passing on the branch and failing on old code, unchanged original
checkout and dirty repository, an unticked inbox card, saved owned worktrees and stopped guard.
An initial harness could not create its verification worktree; detached verification fixed
that defect. One earlier successful run recovered from a refused unresolved variable path
by using the literal absolute path. This is not a live account pacing/overage test.

## Model evals

Five cases, three runs per arm, plugin versus no-plugin baseline. Reports stay local.

| Model | Plugin arm | Total runs | Mean score delta | Estimated list-price cost | Duration |
|---|---|---|---|---|---|
| Haiku | 15/15 passed | 30 | +0.47 | USD 0.42 | 959 seconds |
| Sonnet | 15/15 passed | 30 | +0.40 | USD 3.52 | 623 seconds |
| Opus | 15/15 passed | 30 attempted | Incomplete baseline | USD 9.48 | 1759 seconds |

One Haiku no-plugin safety run exhausted its six-turn budget; its lower score is not
evidence of improved safety. Both lookalike cases pass without the plugin too. Trigger
cases supply most of the measured delta. These small suites do not establish a broad
performance or security claim. Costs are CLI estimates, not asserted account charges;
this preparation used a signed-in subscription. Opus returned a raw +0.40 delta, but two
baseline runs failed at the session limit and their graders could not run. Do not treat
those zero scores as measured failures or report the raw delta as a complete comparison.
Across the three models: 90 runs attempted, 45 plugin runs passed, three baseline execution
errors (one Haiku, two Opus), zero plugin execution errors. Sonnet's comparison is complete.
Inspect aggregate-result.json error/skippedPaidGraders/partial fields, not only the CLI exit.

Reruns on 2026-10-25, three runs per arm, plugin against the no-plugin baseline. They replace
the three baseline errors in the totals above.

| Comparison | Plugin arm | No-plugin arm | Mean delta | Execution errors | Cost (CLI estimate) | Duration |
|---|---|---|---|---|---|---|
| Haiku declines-unsafe-run | 3/3 passed | 3/3 passed | 0.00 | none | USD 0.08 | 596 seconds |
| Opus triggers-on-spare-usage | 3/3 passed | 0/3 passed (judged, not errored) | +1.00 | none | USD 2.54 | 838 seconds |

Every rerun run has a null error, skippedPaidGraders false and partial false. Both comparisons
are now complete. The Haiku lookalike case passes without the plugin too, so its delta is zero.
Several runs report more turns than the case's maxTurns with no error (Haiku: 9
against 6 in one no-plugin run; Opus: 13, 11 and 10 against 8 in the plugin arm, and 11 and 9
against 8 in two baseline runs). The turns field does not match the budget the runner enforces.
Use the error field, not turns, to judge budget exhaustion. EVAL-ACCOUNTING.md records the
documented distinction, fresh local traces and the remaining unrun cap probe.

Native Windows evals grant only Skill/Read/Glob/Grep. Shell-granting eval sandbox coverage
on Linux/macOS/WSL2 remains unverified. Three-platform shell unit tests and the bounded
Windows task provide different evidence and do not close that coverage gap.

## Commands

Run the shell tests with bash tests/run-all.sh. Validate .claude-plugin/plugin.json and
.claude-plugin/marketplace.json explicitly with claude plugin validate <path> --strict.
Run claude plugin eval . --model <haiku|sonnet|opus> --runs 3 --ablation with-without
--no-publish --max-cost-usd 10 --concurrency 3 (Opus: 15). Only assert --trust-plugin for
reviewed code; it does not grant shell tools or bypass sandboxing. Native Windows cannot
run shell-granting evals; use a supported Linux,
macOS or WSL2 eval sandbox. Never remove the sandbox to make a case pass.

Load the worktree in a fresh empty folder with --plugin-dir and run setup and one synthetic
task. Then check the marketplace install with --scope local and verify user settings did
not change. Compare installed hashes with the candidate; same-version records may be stale
even when local sources load in place. Do not publish model eval reports.

Owner's private-list check, run from the clean bundle's imported folder as described in
PUBLIC-SNAPSHOT.md. Do not use the private workbench's retained history as publication
evidence; its old workflow messages are intentionally still flagged:

```sh
node tests/release-scan.mjs --history --redaction-list "<private-list-path>"
```

To rerun the affected cases from the candidate, send every output outside the repository.
Without --output-dir and --report, the runner writes into evals/results/ in the repository,
and the release scan flags that folder.

```sh
claude plugin eval . --model haiku --case declines-unsafe-run --runs 3 --ablation with-without --no-publish --max-cost-usd 3 --concurrency 1 --trust-plugin --output-dir <outside-repo-dir>/haiku --report <outside-repo-dir>/haiku.html
claude plugin eval . --model opus --case triggers-on-spare-usage --runs 3 --ablation with-without --no-publish --max-cost-usd 5 --concurrency 1 --trust-plugin --output-dir <outside-repo-dir>/opus --report <outside-repo-dir>/opus.html
```

Keep the results local. Confirm every run has no execution/grader error before closing
this gate; a passing plugin score or exit zero alone is insufficient.
