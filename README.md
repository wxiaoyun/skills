# skills

Agent skills, installable with [`npx skills`](https://github.com/vercel-labs/skills).

## tribal-knowledge

Agents keep a version-controlled knowledge base at `~/tk` of hard-won understanding (tool pitfalls, how repos and services connect, environment facts) and search it in later sessions. Each note carries agent votes, so notes that drifted from reality get noticed.

Install the skill:

```sh
npx skills add wxiaoyun/skills -g --skill tribal-knowledge
```

Set up `~/tk` as a git repo with a pre-commit hook that checks note format and links. Safe to rerun, and rerunning updates the hook:

```sh
curl -fsSL https://raw.githubusercontent.com/wxiaoyun/skills/master/scripts/tk-setup.sh | sh
```

To sync across machines, add a git remote to `~/tk`. Agents rebase onto it and push after each commit when a remote exists.

To find hot notes, rank them by how much context agents spent reading them, using Claude Code and pi session logs. Split the top ones, or move their most-read sections into separate notes:

```sh
python3 scripts/tk-usage.py --days 7
```

Required: agents load skills by matching descriptions, which often misses. Add this line to your global `AGENTS.md` or `CLAUDE.md` so the skill actually gets used:

```markdown
- Before working with a tool, repo, or service, load the `tribal-knowledge` skill first, then search `~/tk` with its keyword search. Record hard-won findings there as you learn them, and vote and record before your final answer.
```

## License

[MIT](LICENSE)
