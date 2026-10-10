#!/usr/bin/env python3
"""Ranks ~/tk notes by how much agents read them, from Claude Code and pi session logs.

Usage: tk-usage.py [--days N] [--top N] [--cold]

A hot note costs the most context: split it, or move its most-read section into its own note.
Columns: read_kb is tool output returned by reads of the note, split evenly across notes read
in one call. kb/read is its average per read, size_kb the note's current size. whole counts reads
of the entire note. listed counts appearances in search output.
"""
import argparse
import glob
import json
import os
import re
import time
from collections import defaultdict

HOME = os.path.expanduser('~')
TK = os.path.join(HOME, 'tk')
TK_REF = re.compile(r'(~/tk\b|\$HOME/tk\b|/tk/)')
MD = re.compile(r'[\w.~/$-]+\.md\b')
WRITE_TOOLS = {'Write', 'Edit', 'MultiEdit', 'write', 'edit'}
READ_TOOLS = {'Read', 'read'}
WRITE_CMD = re.compile(r'sed -i|perl -i|vote\.sh|\bgit\b[^|;&]*\bcommit|>\s*[\w./~$-]+\.md|python3?\s+-')
SEARCH_CMD = re.compile(r'\brg\b[^|]*\s-\w*l|\bxargs\b|\^(keywords|index):|\bgrep\b[^|]*\s-\w*l|\bfind\b|\bfd\b|\bls\b')
PARTIAL_CMD = re.compile(r'sed -n|\bhead\b|\btail\b|\brg\b|\bgrep\b|\bawk\b|\bcut\b')


def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for c in content or []:
        if isinstance(c, dict):
            if c.get('type') == 'text':
                out.append(c.get('text', ''))
            elif c.get('type') == 'tool_result':
                out.append(text_of(c.get('content')))
    return '\n'.join(out)


def tool_calls(path):
    """Yields (tool name, input dict, output text, timestamp) for each tool call in a session log."""
    pi = '/.pi/' in path
    calls, results = [], {}
    for line in open(path, errors='replace'):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        m = e.get('message') or {}
        role = m.get('role') if pi else e.get('type')
        if pi and e.get('type') != 'message':
            continue
        if role == 'assistant':
            for c in m.get('content') or []:
                if c.get('type') in ('tool_use', 'toolCall'):
                    calls.append((c['id'], c['name'], c.get('input') or c.get('arguments') or {}, e.get('timestamp', '')))
        elif role == 'toolResult':
            results[m.get('toolCallId')] = text_of(m.get('content'))
        elif role == 'user' and isinstance(m.get('content'), list):
            for c in m['content']:
                if isinstance(c, dict) and c.get('type') == 'tool_result':
                    results[c.get('tool_use_id')] = text_of(c.get('content'))
    for cid, name, inp, ts in calls:
        yield name, inp if isinstance(inp, dict) else {}, results.get(cid, ''), ts


def resolve(token, notes, by_tail):
    """Maps a path token from a command to a note path relative to ~/tk, or None."""
    rel = token.split('/tk/', 1)[1] if '/tk/' in token else token.lstrip('./')
    if rel in notes:
        return rel
    hits = by_tail.get(rel.rsplit('/', 1)[-1], [])
    hits = [n for n in hits if n.endswith('/' + rel) or n == rel]
    return hits[0] if len(hits) == 1 else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--days', type=float, default=7)
    ap.add_argument('--top', type=int, default=25)
    ap.add_argument('--cold', action='store_true', help='also list notes nobody read')
    a = ap.parse_args()

    notes = {os.path.relpath(p, TK) for p in glob.glob(os.path.join(TK, '**', '*.md'), recursive=True)}
    by_tail = defaultdict(list)
    for n in notes:
        by_tail[n.rsplit('/', 1)[-1]].append(n)

    cutoff = time.time() - a.days * 86400
    logs = glob.glob(os.path.join(HOME, '.claude/projects/**/*.jsonl'), recursive=True)
    logs += glob.glob(os.path.join(HOME, '.pi/agent/sessions/**/*.jsonl'), recursive=True)
    logs = [p for p in logs if os.path.getmtime(p) >= cutoff]

    st = defaultdict(lambda: dict(sessions=set(), reads=0, whole=0, chars=0, listed=0, writes=0, last=''))
    for log in logs:
        for name, inp, out, ts in tool_calls(log):
            target = inp.get('file_path') or inp.get('path') or ''
            cmd = inp.get('command') or ''
            s = json.dumps(inp, ensure_ascii=False)
            if not TK_REF.search(s) and '/tk/' not in target:
                continue
            mentioned = {r for r in (resolve(t, notes, by_tail) for t in MD.findall(target or cmd or s)) if r}
            if name in WRITE_TOOLS or WRITE_CMD.search(cmd):
                for n in mentioned:
                    st[n]['writes'] += 1
                continue
            if name in READ_TOOLS:
                kind = 'partial' if inp.get('limit') or inp.get('offset') else 'whole'
            elif mentioned and not SEARCH_CMD.search(cmd):
                kind = 'partial' if PARTIAL_CMD.search(cmd) else 'whole'
            else:
                kind = 'search'
            if kind == 'search':
                for t in set(MD.findall(out)):
                    n = resolve(t, notes, by_tail)
                    if n:
                        st[n]['listed'] += 1
                continue
            for n in mentioned:
                x = st[n]
                x['sessions'].add(log)
                x['reads'] += 1
                x['whole'] += kind == 'whole'
                x['chars'] += len(out) // len(mentioned)
                x['last'] = max(x['last'], ts[:10])

    total = sum(x['chars'] for x in st.values()) or 1
    ranked = sorted(((x['chars'], n) for n, x in st.items() if n in notes), reverse=True)
    print(f'{len(logs)} session logs, last {a.days:g} days, {total / 1e3:.0f} KB read from {len(ranked)} notes')
    print(f"{'read_kb':>8} {'share':>6} {'sess':>5} {'reads':>6} {'whole':>6} {'listed':>7} {'writes':>7} {'kb/read':>8} {'size_kb':>8}  note")
    cum = 0
    for chars, n in ranked[:a.top]:
        x = st[n]
        cum += chars
        size = os.path.getsize(os.path.join(TK, n))
        print(f"{chars / 1e3:8.0f} {chars / total:6.0%} {len(x['sessions']):5} {x['reads']:6} {x['whole']:6} "
              f"{x['listed']:7} {x['writes']:7} {chars / max(x['reads'], 1) / 1e3:8.1f} {size / 1e3:8.1f}  {n}")
    print(f'top {min(a.top, len(ranked))} notes = {cum / total:.0%} of read output')
    cold = sorted(n for n in notes if n not in st or not st[n]['reads'])
    print(f'{len(cold)} of {len(notes)} notes were never read in the window')
    if a.cold:
        print('\n'.join('  ' + n for n in cold))


if __name__ == '__main__':
    main()
