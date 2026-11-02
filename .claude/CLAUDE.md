# Repository work

Use an isolated branch and worktree. Read SECURITY.md and docs/RELEASE.md before changing
safety controls. Run bash tests/run-all.sh and strict manifest validation.
Do not push to the default branch manually, rewrite published history, alter another
session's work, change user settings or publish a release. Cloud sessions use only their
assigned branch and leave a final commit note: Branch, State, Checks, Next and Handoff.
Use synthetic fixtures only. Never consume raw session stores or credentials.
