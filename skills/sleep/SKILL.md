---
name: sleep
description: Consolidate ~/tk notes, merging overlapping notes and compressing and splitting the most-read ones. Use when the user runs /sleep, optionally with note paths or directories to limit it.
disable-model-invocation: true
---

# Sleep

Sleep consolidates the notes the `tribal-knowledge` skill writes, the way sleep consolidates a day's memories: overlapping notes merge, and the most-read notes get cheaper to find and to read. It works in a private git worktree at `~/tk/.sleep` and pushes each operation as its own commit, so `git revert <sha>` undoes exactly one. `<dir>` below is this skill's directory.

## Steps

1. Load the `tribal-knowledge` skill. Its note format and layout rules bind every note you write here.
2. Run `python3 <dir>/sleep.py start`. If it fails because the worktree exists, stop and report that line: another run is live or a crashed one needs the user. When told to run as a named parallel run, put `--name <name>` before every `sleep.py` command: the worktree is then `~/tk/.sleep-<name>`.
3. Run `python3 <dir>/sleep.py candidates [path...]`, passing the user's paths if any. It prints MERGE pairs and HOT notes, already filtered to notes nobody is editing.
4. Split the candidates into batches: group by directory, about 150 KB of note text per batch, and put each MERGE pair whose notes sit in different directories in a batch of its own. Work the batches one at a time, since they share the worktree: dispatch a subagent for a batch and wait for its report before the next, or work it yourself. Brief each subagent with the batch, the worktree path, and an instruction to read the Operations section of `<dir>/SKILL.md` and return one line per save. Done when every batch has reported.
5. Run `python3 <dir>/sleep.py end`. If it lists unsaved edits, save or undo each, then run it again.
6. Report one line per commit, then any pattern that kept recurring across notes (for example agents writing event timelines), phrased as a fix for the user's next retro.

## Operations

Edit notes only under the run's worktree, with your file-edit tool (the tk guard blocks shell writes to notes). Save each operation on its own, the subject starting with its operation and note:

```sh
python3 <dir>/sleep.py [--name <name>] save '<merge|compress|split> <note>, <reason>' <note>... [--rm <note>]
```

Every note you write passes the pre-commit hook: at most 30 `keywords`, an `index` under 300 characters, body lines under 600 characters (tables excepted), and a body of at most 6000 bytes (`tail -n +6 <note> | wc -c`) unless the save shrinks it. "6 KB" below means those 6000 bytes.

- A save that prints `Dropped` lost a race with another session. Move on to the next operation.
- A save that lists lost evidence means a citation, `DISPUTED` line or `Hypothesis (unverified)` line went missing. The check matches each citation verbatim, so put each back exactly as it was, beside its claim, and save again.
- A save the pre-commit hook blocks names what to fix. Fix it and save once more, or drop the operation by undoing your edits.
- Any other failed save: stop and run `sleep.py end --force`. It pushes commits the save left behind first, and keeps the worktree when it cannot. Report its output.

**Merge** a MERGE pair only when both notes describe the same thing. Judge by the two index lines first and open the bodies only when they look like one subject.
- The survivor is the note with more reads (higher `KB read`, else the larger body). Fold the other's facts into it, rewrite its `keywords` (union, at most 30) and `index`, and keep the 5 newest votes from both, one per date.
- Repoint every link to the removed note (`rg -l '<name>.md' <worktree>`) to the survivor, and pass those notes in the same save with `--rm <removed note>`.
- A survivor over 6 KB gets compressed and split right after, in their own saves.

**Compress** each HOT note to its live facts. A HOT note marked `split only` was compressed by an earlier run, so go straight to Split.
- Keep every evidence citation, `DISPUTED` line and `Hypothesis (unverified)` line beside its claim.
- Cut narration, event timelines, verdicts, facts a newer line in the same note supersedes, and text a linked note already holds.
- Change no fact and add none.

**Sharpen** each HOT note's frontmatter in the same save as its compress: `keywords` lead with the exact identifiers a searcher would type, and `index` reads "when to open it. what it holds."

**Split** a note whose body is still over 6 KB after compress, following the tribal-knowledge layout: move whole sections into child notes in the directory named after it (`tools/herdr.md` into `tools/herdr/<section>.md`) until the parent body fits.
- Each child gets its own `keywords` and `index` for the section it holds, and the parent's `votes`, since the moved text carries the same evidence.
- Leave a one-line link to each child where its section was, and trim the parent's `keywords` and `index` to what it still holds.
- Save the parent and its children together.
- `save` refuses a split that leaves the parent over 6 KB, so move sections out until it fits. When one table or section cannot divide, save what you moved under a `compress` subject and name the note in your report.

Sleep leaves votes as they are and leaves records alone (notes under `history/` or with `votes: []`), since it re-checks no evidence and records are true for their date only.
