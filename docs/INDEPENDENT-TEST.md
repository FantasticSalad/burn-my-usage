# Independent installation and review

This gate is completed by a person independent of development. Author-side agent tests
and GUARD-REVIEW.md are preparation. The owner arranges the person and supplies the exact
snapshot bundle plus manifest; this package does not contact anyone.

## Installation and real task

1. Verify the artifact hash and import as PUBLIC-SNAPSHOT.md describes. Record the bundle
   hash, plugin version, OS, Git/Bash and Claude Code versions. Do not record account emails,
   credentials, personal paths or private repository details in feedback intended for Git.
2. Use an empty folder and install locally:

   ```sh
   claude plugin marketplace add "<absolute-candidate-folder>" --scope local
   claude plugin install burn-my-usage@burn-my-usage --scope local
   claude plugin details burn-my-usage@burn-my-usage
   ```

3. Start an interactive session there. Use a fresh BURN_MY_USAGE_HOME and run
   /burn-my-usage:burn-my-usage setup. Review any proposed status-line settings change
   before approving it. Keep branches local, confirm the selected test root and record
   whether setup is understandable without help from the author. Use the user's normal
   native approvals and deny rules.
4. Select a small real task in a disposable local repository the tester understands.
   Keep a separate dirty repository beside it to check preservation. Record initial branch
   tips/status. Put the task in wishlist.md; after the interactive usage sample refreshes,
   invoke /burn-my-usage:burn-my-usage. A plan-only run does not close the real-task gate.
5. Verify the guard's deliberate self-test denial, one linked item worktree, a useful
   branch change and meaningful tests. Confirm the tests pass on the branch and fail on
   old code in a separate detached verification worktree. Check original branches and dirty
   work, an unticked inbox card, the verified bundle/handoff and stopped active marker.
6. Invoke the installed status mode without --plugin-dir to check installed discovery.
   Record confusion, refusals and failures as well as passes. Check settings changes against
   the approved setup diff. Remove the local plugin/marketplace when testing is finished,
   and review restoration of the temporary status-line setup.

The bundled tests/e2e/run.sh is an additional synthetic smoke test, not a substitute for
this person's own setup and task. It consumes plan usage; start only with available
allowance and an understood budget. No paid-overage guarantee is claimed.

## Independent guard review

Read SECURITY.md and GUARD-REVIEW.md, then inspect the actual hook and its registration.
Repeat the script tests and examine both permitted and denied cases, including parent
traversal, multiple origin push URLs, attached HTTP flags, commit staging, protected files,
usage failure, owned-worktree cleanup and approval handling, plus the second review's spellings
(tests/guard-spellings.test.sh): quoted strings with spaces, git options and settings given
other ways, prefixes in front of a shell, commands that git and find start, and protected files
changed by other commands and then committed. The fixtures feed requests to the hook without
performing forbidden network, delete or push actions. Try spellings of your own: both reviews
so far found most of their problems that way.

Assess the documented indirection, symlink, GET exfiltration, MCP naming and approval-tick
limitations, and recheck the subagent-identity assumption on your Claude Code version.
Record whether they are acceptable for the intended use, what remains unverified and any
required changes. No checkmark should imply sandboxing.

## Result record

Use INDEPENDENT-RESULTS.template.md. Include the exact candidate identity and who performed
each role, using a public-safe identifier if the record will be shared. A failure or an
unavailable step stays open. The owner reviews the record before clearing the gate.
