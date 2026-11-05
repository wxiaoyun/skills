---
name: sleep
description: Consolidate ~/tk notes, merging overlapping notes and compressing the most-read ones. Use when the user runs /sleep, optionally with note paths or directories to limit it.
disable-model-invocation: true
---

# Sleep

Sleep consolidates the notes the `tribal-knowledge` skill writes, the way sleep consolidates a day's memories: overlapping notes merge, and the most-read notes get cheaper to find and to read. It works in a private git worktree at `~/tk/.sleep` and pushes each operation as its own commit, so `git revert <sha>` undoes exactly one. `<dir>` below is this skill's directory.

## Steps

1. Load the `tribal-knowledge` skill. Its note format and layout rules bind every note you write here.
2. Run `python3 <dir>/sleep.py start`. If it fails because the worktree exists, stop and report that line: another run is live or a crashed one needs the user. When told to run as a named parallel run, put `--name <name>` before every `sleep.py` command: the worktree is then `~/tk/.sleep-<name>`.
3. Run `python3 <dir>/sleep.py candidates [path...]`, passing the user's paths if any. It prints MERGE pairs and HOT notes, already filtered to notes nobody is editing.
4. Split the candidates into batches: group by directory, about 150 KB of note text per batch, and put each MERGE pair whose notes sit in different directories in a batch of its own. Dispatch one subagent per batch. Brief each with the batch, the worktree path, and an instruction to read the Operations section of `<dir>/SKILL.md` and return one line per save. Without a subagent tool, work the batches yourself in order. Done when every batch has reported.
5. Run `python3 <dir>/sleep.py end`. If it lists unsaved edits, save or undo each, then run it again.
6. Report one line per commit, then any pattern that kept recurring across notes (for example agents writing event timelines), phrased as a fix for the user's next retro.

## Operations

Edit notes only under the run's worktree, with your file-edit tool. Save each operation on its own:

```sh
python3 <dir>/sleep.py [--name <name>] save '<op> <note>, <reason>' <note>... [--rm <note>]
```

- A save that prints `Dropped` lost a race with another session. Move on to the next operation.
- A save that lists lost evidence means a citation, `DISPUTED` line or `Hypothesis (unverified)` line went missing. Put each back beside its claim and save again.
- A save the pre-commit hook blocks names what to fix. Fix it and save once more, or drop the operation by undoing your edits.
- Any other failed save: stop, run `sleep.py end --force`, and report the failing save.

**Merge** a MERGE pair only when both notes describe the same thing. Judge by the two index lines first and open the bodies only when they look like one subject.
- The survivor is the note with more reads (higher `read_kb`, else the larger note). Fold the other's facts into it, rewrite its `keywords` (union, at most 30) and `index`, and keep the 5 newest votes from both, one per date.
- Repoint every link to the removed note (`rg -l '<name>.md' ~/tk/.sleep`) to the survivor, and pass those notes in the same save with `--rm <removed note>`.
- Keep the survivor under 6 KB by compressing it in the same operation. If it still cannot fit, leave the pair.

**Compress** each HOT note to its live facts.
- Keep every evidence citation, `DISPUTED` line and `Hypothesis (unverified)` line beside its claim.
- Cut narration, event timelines, verdicts, facts a newer line in the same note supersedes, and text a linked note already holds.
- Change no fact and add none.

**Sharpen** each HOT note's frontmatter in the same save as its compress: `keywords` lead with the exact identifiers a searcher would type, and `index` reads "when to open it. what it holds."

Sleep leaves votes as they are and leaves `history/` records alone, since it re-checks no evidence and records are true for their date only.
