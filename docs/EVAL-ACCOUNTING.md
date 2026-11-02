# Eval accounting

## What the counters mean

The official agent-loop documentation defines max_turns/maxTurns as a limit on tool-use
round trips and documents error_max_turns and error_max_budget_usd as terminal result
subtypes. A reported message count is not a substitute for that enforced budget.

An upstream claude-code-action issue reproduces num_turns counting the initial prompt and
tool-result messages, while the CLI cap counts agentic rounds. Several parallel tool calls
therefore increase that result count faster than the capped loop count. The reporter's
positive and negative controls show both successful runs above the numeric cap and an
error_max_turns result when the actual cap is reached.

Sources:

- https://code.claude.com/docs/en/agent-sdk/agent-loop#turns-and-budget
- https://github.com/anthropics/claude-code-action/issues/1795
- https://code.claude.com/docs/en/plugin-evals

## What was verified here

The saved rerun aggregates report 9 against 6 in one safety baseline and 13, 11 and 10
against 8 in the spare-usage plugin arm, with null errors and completed graders. This is
consistent with the documented distinction. The exact internal assignment to the plugin
runner's turns field was not inspected; treat the upstream explanation as supporting
evidence, not proof obtained from this build's implementation.

A fresh 2.1.296 synthetic task export completed successfully with 27 distinct assistant
messages, 26 tool-use rounds and 55 tool results; the terminal result reported 56 turns.
That locally confirms the reported count differs from loop rounds and matches the initial
prompt plus tool results in this trace. It does not prove every future run's cap behavior.
The final task after the last guard correction independently reported 59 turns with
30 assistant messages, 29 tool-use rounds and 58 tool results, again completing successfully.

An optional local two-budget probe on three synthetic Read calls was prepared, but this
machine's PowerShell script policy refused its .ps1 launcher before a model call. The
policy was left unchanged.

It ran on 2026-10-29 from Git Bash instead: Claude Code 2.1.312, Haiku, `--max-turns 2`, three
synthetic files, read with the Read tool only. Asked to read all three in one message, the run
made one tool-use round with three results, finished with success and reported 4 turns. Asked
to read them one message at a time, it stopped with `error_max_turns` after two rounds, before
the third read, and reported 3 turns. So the CLI cap counts tool-use rounds, and the reported
number counts the prompt plus each tool result, as the documented distinction says. The plugin
eval runner's own `turns` field wasn't part of this probe.

## Release gate

Run the native eval with --no-publish and explicit output/report paths outside the repo,
then check its native aggregate export:

```sh
node tests/check-eval.mjs "<output-directory>/aggregate-result.json"
```

The checker requires both arms and the declared run counts, partial=false, null run errors,
no skipped paid graders, real grader records and passed plugin runs. A judged baseline
failure is valid comparison evidence. A baseline execution error is not a security win.
It prints counters and locations, not raw error text. It deliberately does not compare
turns to maxTurns. Keep timeout, budget and native permission controls in place.
