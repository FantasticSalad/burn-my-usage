---
name: burn-my-usage
description: Turns spare weekly usage into review-ready work across local repositories while the user is away. Uses isolated branches, tests, review and an inbox of decisions; never deploys or publishes and stops when usage is unavailable. Use for "burn my usage", "burn my tokens", "use up my usage", "spend my spare usage", "end of week run", or "work on my repos while I'm away". Supports setup, plan, inbox, status and stop modes. Not for checking usage numbers.
license: MIT
compatibility: Claude Code 2.1.295 or later with bash 3.2 and git; Codex native unattended runtime acceptance remains blocked.
---

# Burn my usage

Read the [shared workflow](workflow.md) and the applicable host binding:
[Claude Code](hosts/claude-code.md) or [Codex](hosts/codex.md). The host binding
defines session identity, command arguments and runtime gates; it does not grant authority
beyond the user's instructions or the shared workflow. If the host is unknown, stop.

Codex mutation is blocked until its native guard and usage tests are accepted. Do not
install or change host settings as part of selecting this skill.
