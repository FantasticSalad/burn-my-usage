# burn-my-usage config

Every run reads this. Edit it freely; a run never changes it (the guard refuses).

## Settings

- roots:                 # folders that hold your repos, comma-separated
- stop_at: 90                   # stop at this % of the weekly limit, your own use included
- push_branches: never        # private (only to private GitHub repos), all, or never
- max_open_branches: 3          # per repo: no new branch while this many await your answer
- require_guard: yes            # yes: if the guard isn't running, a run only writes briefs
- ideas: yes                    # finish an emptied queue with a batch of ideas in ideas.md
- issues: off                   # on: also work open issues with burn_label, by you or trusted authors
- burn_label: burn-ok
- trusted_issue_authors:        # GitHub logins besides your own, comma-separated

## Repos

Tiers decide where usage goes first. A repo not listed counts as `normal` if it has had a
commit in the last 60 days, else `low`. `skip` repos are never touched.

- high:
- low:
- skip:

## Notes for the run

Anything else a run should know: how to run a repo's tests, things to leave alone, your
conventions.
