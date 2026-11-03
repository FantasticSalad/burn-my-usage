# Design

Contents: origin, components, compatibility, decisions and what's still open.

## Origin

This plugin generalises an earlier private unattended workflow. The original remains useful
for its owner's operational integrations; this package is a configurable sibling.

| Private predecessor | Public plugin | Reason |
|---|---|---|
| Fixed repository priorities and central work board | User config, wishlist and repo plans | No workstation infrastructure required |
| Interactive private inbox | INBOX.md cards | Works in a local editor |
| Private branch/worktree scripts | Bundled work-item.sh, handoffs and verified bundles | Preserve concurrent work without external tooling |
| Mandatory workstation leak check | Bundled staged scanner and pre-commit guard check | Portable location-only reporting |
| Operational server/personal checks | Generic recurring checks | Local repository scope |
| User-specific rules and approvals | Conservative defaults and explicit opt-in | New users choose their own risk |
| Rules supplied by the workstation | Plugin hook plus skill instructions | State coverage and limitations explicitly |

## Components

SKILL.md defines setup, plan, run, inbox, status and stop. worktrees.md documents item
lifecycle. The scripts use bash 3.2, git and ordinary shell utilities. Optional GitHub
features use gh; development replay/E2E utilities use Node 18+. Runtime state belongs in
the user-selected burn home, never the install folder. A status-line copy there samples
only usage data and can chain the user's previous status line.

The session-keyed guard enforces branch restrictions, staged leak checks, push policy,
secret paths, protected configuration and selected outward commands. It is command-string
mediation, not an adversarial sandbox. SECURITY.md documents indirection and other gaps.
The manifest uses onFailure: block: a failed hook blocks ordinary sessions too.

## Compatibility

Claude Code 2.1.295+ on Linux, macOS or Windows with Git Bash. No Codex or claude.ai runtime
support in this release. The skill's general wording does not establish equivalent hooks,
usage pacing or continuation behavior on another host.

## Decisions

New installs never push by default. Private mode verifies origin on GitHub at each push.
No secrets are requested: approved clients authenticate internally. Missing usage data
ends unattended work after saving a handoff. Existing user configuration is retained.

All item changes occur in linked worktrees. Staged added text is scanned before each
commit; failures block it. Every finished item has a verified local bundle and a handoff.
Read-only review can cover all unmerged branches, while other sessions' branches are
never adopted or changed without explicit approval.

## Still open

Nobody independent of development has installed the plugin, run a real task with it or reviewed
the guard. A clean history, a privacy review, model evals with a baseline, a clean installation
and an independent user's run are separate evidence, and a passing unit suite establishes none
of them. Cross-repository agent fan-out and scheduling are future work.
