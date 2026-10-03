---
name: tribal-knowledge
description: Search and maintain ~/tk, a personal knowledge base of hard-won understanding reused across sessions, such as tool behavior and pitfalls, how repos and services in a workspace connect, and environment facts. Use before working with a tool, repo, or service, when hitting an unexpected error, or when cross-service context is needed. Also use right after figuring out something non-obvious, after a wrong assumption gets corrected, or when the user explains how an internal system works.
---

# Tribal Knowledge

`~/tk` is a version-controlled tree of markdown notes. It holds understanding that took real effort to gain, so later sessions can reuse it instead of rediscovering it.

## What belongs here

- Tool behavior and pitfalls: misleading flags, version quirks, confusing output.
- How repos and services connect: who calls whom, where config lives, shared contracts.
- Environment facts: how to reach logs, clusters, CI, dashboards.
- Repo internals learned by tracing code.

Not here: user preferences, anything a quick read of the code or README answers, and secrets of any kind.

## Layout

```
~/tk/
  INDEX.md
  tools/
    INDEX.md
    rtk.md
  workspace1/
    INDEX.md
    repo1.md
```

- One note per thing (a tool, repo, or service), named in kebab-case after it.
- Every directory has an `INDEX.md` in the same format. It states the directory's scope and holds knowledge spanning the whole directory, such as a workspace's service map. It never lists or summarizes its children.
- Create directories as needed, reusing existing ones first. Split, merge, or move notes whenever the tree stops fitting the knowledge.

## Note format

```markdown
---
keywords: [rtk, proxy, token-saving, truncated-output]
index: RTK output condensing, when output is truncated, recovering raw output via rtk proxy
votes: [+2026-10-03, -2026-09-20]
---
Free-form body. Terse, pitfalls first.
```

- Frontmatter is exactly these three single-line fields in this order, so search stays line-based.
- `keywords`: lowercase, kebab-case, including aliases and exact identifiers (binary names, service names, env vars, error strings).
- `index`: one line telling a reader whether the note has what they need.
- Point claims at evidence where you can (file path and symbol, command, tool version) so the next reader can check for drift.

## Searching

Narrow by keywords, then judge candidates by their `index` and `votes` lines before opening any note:

```sh
rg -i -A2 '^keywords:.*\b(rtk|proxy)\b' ~/tk
```

## Votes

`votes` keeps the 5 most recent verdicts, newest first. `+YYYY-MM-DD` confirms and `-YYYY-MM-DD` contradicts. Vote at most once per note per session.

- Your own check agrees with the note: prepend `+today`.
- The note is wrong and you know the truth: fix it, drop any related `DISPUTED` line, and reset votes to `[+today]`.
- The note looks wrong but the truth is unclear: prepend `-today` and add `> DISPUTED YYYY-MM-DD: <reason>` next to the claim.
- A new note starts at `[+today]`.
- Any `-` in a note's votes means verify before relying on it.

## Writing

- Write as soon as you learn something, not at the end of the task.
- Search first and update an existing note rather than adding a duplicate.
- When a search missed a note that turned out relevant, add the missed terms to its `keywords`.
- After each change, commit in `~/tk` with git (or the user's preferred version control) as `tk: <what changed>`, then push if a remote exists.
- If `~/tk` does not exist, ask the user to run the setup script from https://github.com/wxiaoyun/skills.
