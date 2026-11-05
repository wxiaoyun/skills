# Sleep v1

Sleep v0 (`skills/sleep/`) merges overlapping notes and compresses and sharpens the most-read ones. This document records the rest of the design agreed on 2026-11-05, held back until v0 shows it moves the metric below. Terms follow [GLOSSARY.md](../GLOSSARY.md).

## Why v0 came first

Measured on 2026-11-05 over `~/tk` and 30 days of session logs:

| Signal | Value |
|---|---|
| Notes | 676, about 4 MB, 81 of them records |
| Growth | about 85 new notes a week, 206 in 2026-W44 |
| Hot notes | the top 8 hold 18% of read output, all near the old 12 KB cap |
| Never read in 30 days | 146 notes (22%) |

Reading cost sits in a few hot notes, so v0 attacks that. A cold note costs little, since it only surfaces when its keywords match, and tk's value lies in the rare pitfall a cold note may still hold. Forgetting is the riskiest operation for the smallest gain, so it waits for evidence that note count itself hurts.

v0 also lowered the pre-commit size cap from 12 KB to 6 KB, since every hot note sat at the cap, so notes split when written instead of waiting for sleep.

## Success metric

Bytes of note text read per session that reads `~/tk`, from `python3 skills/sleep/tk-usage.py --days 30` (the "KB per session" figure on its first line).

| Date | Window | Sessions | KB per session |
|---|---|---|---|
| 2026-11-05 (baseline, before v0) | 30 days | 645 | 25.8 |

Re-measure after two weeks of nightly runs. v1 is worth building only if v0 brought this down.

## Deferred operations

**Forget**: remove a note from the live set with `git rm`, git history being the archive. A note is forgotten when it had no reads in 45 days and its newest vote is older than 45 days, or when it has held an open `DISPUTED` line for more than 45 days. A note other notes link to is merged into the linking note instead.

**Distill**: once a record is 45 days old, lift its lasting facts into regular notes and forget the record in the same commit. No marker is needed, since a record is processed once. Open question raised during the v0 review: records exist only because the user asked for them, so forgetting them may undo the user's intent. Decide before building whether distill also forgets.

**Split**: split a hot note past 8 KB. The 6 KB cap may make this redundant.

**Strengthen by co-reads**: link notes that sessions often read together. Needs new log parsing, and was left out from the start.

Order within one run: forget, distill, merge, compress, strengthen. Cheap removals go first so later stages read less.

## Known limits

- Read counts come from session logs on the machine sleep runs on. Before forget ships, decide whether a machine with partial logs may forget at all, or whether forget relies on votes alone there.
- Votes on a merged or compressed note vouched for its earlier text. Sleep keeps them, since it re-checks no evidence.
- Sleep keeps no memory of merge pairs it rejected, so it re-judges them each run from their index lines.
- A push that fails for a reason other than a rebase race, lost evidence or a hook block ends the run, and its unpushed commit is lost when the next run resets the `sleep` branch.

## Decisions kept from the grilling

- Sleep is independent of `retro`. Retro fixes the tooling, and sleep fixes note content. Sleep reports recurring patterns for a later retro and changes no skill text itself.
- Sleep is user-invoked. The user schedules it with their own cron.
- No argument means the whole tree. Merge pairs are ranked over the whole tree but listed only when both notes are in scope, so parallel runs on disjoint subtrees never edit the same note. Pairs that span two subtrees surface only in a run covering both.
- Sleep edits in its own worktree at `~/tk/.sleep` (`~/tk/.sleep-<name>` for a named parallel run) and pushes each operation without review, one commit per operation. A save that loses a rebase race drops that operation and the run continues.
- Notes with unsaved edits in `~/tk`, or committed in the last 24 hours, are off limits.
- A save that drops any evidence citation, `DISPUTED` line or `Hypothesis (unverified)` line is refused.
