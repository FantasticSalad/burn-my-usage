# Native Codex acceptance

## 13 November: Windows startup repair

The Windows hook now runs an independent PowerShell supervisor before Node. Its complete
literal command is registered in `commandWindows`; the `.ps1` file is an authoring template
and is never loaded or evaluated at runtime. Exact registration equality is checked by
synthetic tests and package preflight. No execution-policy override is used.

Focused bridge/package/supervisor checks pass 10/10, zero skips. They cover positive normal
allow, inconsistent-state denial, missing Node/root, the observed NODE_OPTIONS startup
crash, silence/extra/nonzero output, input/output limits and an 18-second internal deadline.
The native hook timeout is 40 seconds. Default non-Windows startup supervision, outer-shell
failure, detached descendants and the broader unattended acceptance gates remain open.

Candidate v8 is prepared with 48 files. Inventory SHA-256:
`26376416e4875c5851e03d60200077f80d6334ccdc25434f28f7f9866aadb9f3`.
Hook definition SHA-256:
`5fa78e43dbc98f0b072dd0729359dae2b7099283460332a2b3da323f6fedaee9`.
Only the existing local review marketplace/plugin was refreshed through supported native
commands. Automatic approval review initially rejected trust because the earlier grant
covered exact v7. The owner then explicitly approved both exact v8 hooks and the hash above.
Both were trusted individually through native /hooks. Fresh metadata confirms both enabled
and trusted, the skill enabled and zero errors. All 48 installed files still match.

Native regression on desktop CLI 0.167.0-alpha.4.1:

| Fixture | Observed result | Probe exit |
|---|---|---|
| Inactive | SessionStart context and PreToolUse complete; exact harmless sentinel executes once with exit 0 | 0 |
| Node startup crash | SessionStart fails as expected; Windows PreToolUse returns explicit deny, not failure; no command item | 3, block observed |
| Active marker with no lock | Context completes; PreToolUse returns explicit deny; no command item | 3, block observed |

The crash case reports `protectedFailureObserved:true`, `failedHook:false` and
`commandRan:false`. This closes the observed Windows startup-failure regression. Exit 3
preserves the protocol limit: denied calls expose no command input, so exact intercepted
sentinel input is unverified. No probe equates this result with full unattended acceptance.
Fresh live quota was go before each run: 49%, 51%, then 52% five-hour, 32% weekly, stop90.
The probe now uses the schema's `effort:'high'` field; the prior `reasoningEffort` field did
not establish an effort override, so earlier effort claims should be treated as unverified.
The native repair is integrated. The broader native gates below remain open, and unattended
Codex runs are not supported until they close.

Integrated checks: all 41 Node tests pass, zero skips, and both Claude manifests pass strict
validation with the existing icon warning. Every shell suite passes, including three reruns
after repairing older fixtures to supply fresh synthetic quota and matching run ownership.
The initial combined run failed those fixtures; it did not expose a runtime launcher failure.
The odd-path fixture now uses a synthetic supported quota client instead of contacting a real
account. Current-main native Windows path conversion and fresh Codex authorization checks
are both retained. The installed v8 bytes remain the reviewed immutable 48-file candidate.

## 12 November: original failure evidence

Status: **unattended Codex builds remain blocked**. This is development
evidence from one Windows machine, not acceptance for other hosts.

The installed v7 payload contains 45 runtime/catalog files. Its inventory SHA-256 is
`51434aeeed80a6c9d501b24c4f910ac54a31996d3c405d622115859f8906e8bf`;
`hooks/codex.json` SHA-256 is
`37666021f3c47392b1e78365a44f9c911513df765bfdb0d22f8f454d4d6b16f7`.
The owner explicitly approved native review for this review folder and these two hooks.
Both were trusted through the native hook browser. A fresh desktop CLI
`0.167.0-alpha.4.1` reports the skill enabled, both hooks enabled/trusted, zero
metadata errors, and `ready-for-enforcement-tests`. That status does not accept enforcement.
The previous bundled executable was replaced during an app update; paths must be
resolved from the actual installed client rather than assuming its old directory exists.

The initial supported live quota read returned `go`: 16% five-hour, 14% weekly,
stop line 90%. A later refresh before probe validation remained `go` at 74% five-hour
and 23% weekly. The final go-gated crash regression started at 79% five-hour and 24%
weekly. These are observations at test time, not continuing authorization.
No credits, resets, thresholds, unrelated hooks or security defaults were changed.

## Observed native results

Each supervised fixture used an ephemeral read-only thread with Terra 6.1/high,
isolated synthetic BMU state and a request for one harmless `Write-Output` command.
Execution is verified only when the native event exposes the command. Only this
probe's live protocol events were inspected. No raw native stores or credentials
were opened. Idle `thread/start` alone emitted no hook completion; the first turn
invoked SessionStart and PreToolUse.

| Fixture | Native result | Acceptance |
|---|---|---|
| Inactive BMU | Context supplied; hook completed; command exited 0 | Pass for inactive behavior |
| Active marker, missing lock | BMU PreToolUse blocked; no command execution item | Block observed; exact intercepted call unverified |
| Matching owner, missing marker | BMU PreToolUse blocked; no command execution item | Block observed; exact intercepted call unverified |
| Invalid owner | BMU PreToolUse blocked; no command execution item | Block observed; exact intercepted call unverified |
| Missing Bash configuration | BMU PreToolUse blocked; no command execution item | Block observed; exact intercepted call unverified |
| Node startup crash | SessionStart and PreToolUse failed; command still exited 0 | **Fail: host continues after hook failure** |

The crash fixture sets `NODE_OPTIONS` only in the disposable client process to load
a synthetic module that throws before the hook bootstrap executes. It leaves the
installed hook definitions and trust hashes unchanged. The command has no side effects.
This tests hook interpreter failure, distinct from a child guard failure that the
running bootstrap can catch and convert into an explicit deny.

The native protocol omits command execution items for denied calls and its hook summary
does not expose tool input. Those four block observations therefore do not independently
establish which exact call was intercepted. The preserved probe correlates events to its
own thread/turn, requires exactly one BMU PreToolUse event, and reports exit 3 for that
limited observation. It only verifies the sentinel when a command execution event exposes
the fixed command. No model reply is treated as proof of tool interception.

Codex documents that PreToolUse errors, timeouts and malformed responses can let
tools run. The observed startup-crash behavior confirms that limitation on this
client. [Official hook contracts](https://learn.chatgpt.com/docs/hooks#managed-hooks-from-requirementstoml).
Adding another JavaScript catch cannot handle a failure before JavaScript starts.

## Repeatable probe

`tests/native-runtime.mjs` is explicitly opt-in and excluded from offline test globs.
It uses the existing native profile, makes one model turn, preserves synthetic
fixtures in the system temporary directory, and never trusts or disables hooks.
First check live quota through the installed collector and require `go`. Review the
exact installed hooks using the native interface before running it.

Set `BMU_CODEX_BIN` to the absolute installed executable, then run:

```text
node tests/native-runtime.mjs --supervised --cwd=ABSOLUTE_REVIEW_FOLDER --case=missing-lock
node tests/native-runtime.mjs --supervised --cwd=ABSOLUTE_REVIEW_FOLDER --case=node-crash
```

Cases also include `inactive`, `missing-marker`, `invalid-owner`, and `missing-bash`.
Exit 0 requires the inactive case's exact command and hook expectations; exit 1 is an
acceptance failure; exit 2 indicates invalid invocation, unavailable protocol or cleanup
failure; exit 3 means one guard block was observed but its exact call is unverified.
The crash case is expected to return 1 on the tested client. A reproduced failure
is useful evidence, not a passing safety gate. Even a passing case always reports
`enforcementAccepted:false`. The probe rejects interactive approval requests rather
than accepting them. It uses bounded output and a 90-second deadline. Cleanup targets only
its own client process tree (Windows taskkill /T, or the newly created POSIX process group),
checks the termination result and reports cleanup failure instead of passing. Parent exit
before tree termination is also a cleanup failure. This covers attached descendants;
already detached or reparented processes require stronger launch-time containment such as
a Windows job object. Pipe handles are closed even on failure. The probe does not establish
process containment. It prints metadata only, excluding prompts, model replies and tool output.

## Next implementation boundary

Keep unattended Codex support unavailable until a control outside the hook process
prevents tools running after hook failure. Evaluate native host support for mandatory
enforcement, or a separately constrained execution environment whose permissions
enforce the required boundary independently of hooks. Do not weaken sandbox or approval
defaults or claim another hook wrapper fixes interpreter startup failure.

Timeout/missing/disabled-hook behavior, actual spawned-child coverage, patch coverage,
interruption/resume and supervised mutating work remain unaccepted. Complete them only
after resolving the failed prerequisite. Claude's published support is unchanged;
no public publication, release or default-branch merge is part of this test.

Offline verification: every shell suite passes. The first combined run exposed a broken
package documentation link; including this acceptance record in the preparation allowlist
fixes it. The final Node suite passes 37/37 with zero skips. Both Claude manifests pass
strict validation, with the existing listing-icon warning. All 45 installed v7 file hashes
still match, and fresh native metadata still reports the two approved hooks trusted.
Future prepared packages include this extra document; the installed v7 is unchanged.
