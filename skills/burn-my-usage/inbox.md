# The inbox

`INBOX.md` in the burn home is where every question, branch and job for the user goes, and
where they answer. It is plain Markdown so it works in any editor, and on a phone if the burn
home sits in a synced folder or a private git repo. They answer by ticking one box and
optionally writing a note; the next run acts on it.

Two rules hold it together:
- **The agent writes cards; only the user ticks boxes.** The guard refuses any edit that adds a
  ticked box. Never tick, untick or move a tick, and never rewrite an answer.
- **One card per question or branch,** with a stable id, so an answer always maps to one
  thing.

Contents: layout, writing a card, process, merge approved, publish.

## Layout

```markdown
# Burn inbox

Last run: 2026-10-10 18:40 · 3 decisions (~4 min) · 2 branches · 1 job

How to answer: tick one box per card and add a note if you like. The next run acts on it.
"Needs changes" needs a note saying what to change.

## Decide

### webapp · Retry failed webhooks, or drop them?
<!-- id: webapp-webhook-retry · kind: decision · found: 2026-10-10 · effort: quick -->
**Question.** When a webhook delivery fails, should we retry it or drop it?
**Why it matters.** Three customers' deliveries failed last week and nobody noticed.
- [ ] **A. Retry three times with backoff (recommended).** Adds a retry table; deliveries
      can be up to 10 minutes late.
- [ ] **B. Drop it and log a warning.** No schema change; failures stay silent to customers.
- [ ] Defer
- [ ] Drop the question
**Blocks:** the webhook item on the wishlist. **If never answered:** nothing is built.
**Note:**

## Review

### webapp · `burn/2026-10-10-csv-escaping`
<!-- id: br-webapp-csv-escaping · kind: branch · base: main · merge-order: 1 of 2 · ci: green -->
**What it does.** Quotes CSV fields that contain commas or newlines on export.
**Verified.** 4 new tests fail on main and pass here; full suite green (212 tests).
**Risk.** Low: export only. **Look at:** `src/export/csv.ts`. **Size:** 3 files, +88 −12.
- [ ] **Merge**
- [ ] Needs changes (say what in the note)
- [ ] Bin
- [ ] Defer
**Note:**

## Jobs

### webapp · Rotate the leaked test API key
<!-- id: job-webapp-rotate-key · kind: job · found: 2026-10-10 · where: provider console -->
**Why.** The key in `tests/fixtures/auth.json` was committed in March and is still live.
**Steps.** 1. Revoke it in the provider console. 2. ...
- [ ] Done
- [ ] Drop
- [ ] Defer
**Note:**

## Done

- 2026-10-10 · br-webapp-date-parsing · Merged locally as `a1b2c3d`; push main when ready.
```

Card rules:
- **Heading:** `### <repo> · <the decision in a few words>` for decisions and jobs, and
  `### <repo> · \`<branch>\`` for branches. The guard finds a branch's Merge tick by the repo
  and branch names in this heading, so keep both exact.
- **The comment line** carries the id and fields: `kind` (`decision`, `branch`, `job`),
  `found`, and as needed `effort` (`quick`, `short`, `think`), `base`, `merge-order`, `ci`
  (`green`, `red`, `none`, `local`), `where`, `reopened` (a date, see below), `stacked-on`.
- **Ids** use letters, digits and `-`, and never change: decisions `<repo>-<slug>`, branches
  `br-<repo>-<branch minus burn/date->`, jobs `job-<repo>-<slug>`.
- **Options:** viable ones only, each with its consequence, the recommended one first and
  marked "(recommended)". Defer and Drop are always offered.
- **Plain words.** The user may be answering on a phone. Most decisions should be `quick`:
  answerable from the card alone in under a minute.

## Writing a card

- **Ask only what blocks something.** If the honest "if never answered" is "nothing much",
  decide it yourself (SKILL.md section 3) or don't raise it. One card that settles several
  questions beats several cards.
- **Title the decision, not the topic:** "Track `uv.lock`, or ignore it?", not "Lock files".
- **Context:** only what the options need.
- **Before adding a card,** search the inbox for one about the same thing and update that
  instead.
- **Never put a secret value on a card,** even a partial one.

## Process

At the start of every run (SKILL.md step 1.4), and for `/burn-my-usage inbox`.

1. Read `INBOX.md`. For each open card, its answer is the single ticked box, if any, plus the
   note. A card with two or more ticks is ambiguous: leave it, and say so in the report and
   on the card ("two boxes ticked; untick one").
2. **Reopening a card** (a deferral coming back, a branch fixed after "needs changes") never
   clears the old ticks; you can't untick. Instead add a fresh set of empty boxes under a
   `**Reopened <date>:**` line, and set `reopened: <date>` in the comment line. Only ticks in
   the newest set count.
3. Act on each answer:

   | Answer | What to do | Card afterwards |
   |---|---|---|
   | decision, an option | It is now Build work at the front of the queue. Record the choice where the question came from (the wishlist line, or a plan doc on the branch that builds it). | Moves to Done: "Chose A on <date>. Built on `<branch>`." once built |
   | decision, Drop | Note it beside the source item ("dropped by you, <date>") so it isn't raised again. | Done |
   | any, Defer | On a full run: re-check the card against the current code, refresh it, and reopen it (step 2) so it comes back to the user. Not on an `inbox`-only call. | Open, reopened |
   | branch, Merge | On a full run: merge it ("Merge approved" below). On an `inbox`-only call: leave it for the next run. | Done once merged |
   | branch, Needs changes | Front of the queue: fix it on that branch as the note says, with tests, then refresh the card and reopen it. If the note can be read two ways, take the reading the repo's structure supports and say which on the card, so one tick corrects it. | Open, reopened |
   | branch, Bin | Write the tip SHA on the card, then delete the branch locally and on the remote (`git push origin --delete burn/...`). If another branch is stacked on it, don't delete: ask. | Done: "Binned at `<sha>`." |
   | job, Done | Check it where you can (the file changed, the endpoint answers). If it isn't done, say why on the card and reopen it. | Done, or reopened |
   | job, Drop | Note "not doing this" where the job came from. | Done |

4. Answers steer the run but never widen SKILL.md section 0. A note asking for a deploy, a
   force push, a secret or a production change becomes a question back to the user.
5. Move closed cards to **Done** as one line each: date, id, outcome. Prune Done lines older
   than 60 days into `inbox-archive.md`.

## Merge approved

For every branch card with Merge ticked, repo by repo, in `merge-order`, stacked branches
after their base:

1. Fetch and check the default branch, stopping on divergence.
2. Use a dedicated merge worktree. If the default branch is checked out anywhere else,
   leave a user job with the exact merge command; never switch that checkout or detach it.
3. Merge only the exact approved branch revision, in card order. If its tip changed after
   review, reopen the card. Stop on conflicts or red suites and preserve the worktree and
   handoff for the user; do not reset or hide a failure.
4. Never push the default branch. Record the local merge SHA for the user.
5. Retain branches and verified backups until the user explicitly requests deletion.

## Publish

At the end of every run (SKILL.md section 7):

1. Update the header line: date, and counts of open decisions (with rough minutes), branches
   and jobs.
2. A card for every new question, every new branch, and every job only the user can do (a
   login, a console, a secret to rotate, hardware, a payment). Not work a later run could do.
3. Refresh cards for branches that changed this run, and reopen those changed because of
   "Needs changes".
4. Keep each section ordered: Decide by effort (quick first), Review by repo and merge order.
5. Screenshots for "needs your eye" branches go in `RUN_DIR/` and are linked from the card.
