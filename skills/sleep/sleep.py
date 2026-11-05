#!/usr/bin/env python3
"""Consolidates ~/tk notes in a private worktree at ~/tk/.sleep, pushing each change to ~/tk's upstream.

Usage:
  sleep.py start                                    create the worktree, or fail while another run holds it
  sleep.py candidates [path...]                     merge pairs and hot notes, only those under the paths if given
  sleep.py save '<what>' [--rm <note>]... <note>... check no evidence was lost, then commit and push via save.sh
  sleep.py end [--force]                            remove the worktree, --force discards unsaved edits
  sleep.py selftest

Note paths are relative to the worktree root. --name <name>, given before the command, runs in
~/tk/.sleep-<name> on branch sleep-<name>, so runs on disjoint subtrees can go in parallel.
"""
import argparse
import importlib.util
import math
import os
import re
import subprocess
import sys
import time
from collections import defaultdict

HOME = os.path.expanduser('~')
TK = os.path.join(HOME, 'tk')
WT = os.path.join(TK, '.sleep')    # main() moves it for --name
ME = f'python3 {os.path.abspath(__file__)}'
HERE = os.path.dirname(os.path.abspath(__file__))
SAVE = os.path.join(os.path.dirname(HERE), 'tribal-knowledge', 'save.sh')
DAYS = 30          # read window for hot notes
HOT_SHARE = 0.2    # hot = the top 20% of notes by bytes read
PAIR_MIN = 0.15    # weighted keyword overlap a pair needs. On ~/tk in 2026-11, true duplicates scored about 0.2
PAIR_TOP = 20
FRESH = 86400      # notes committed this recently are still in use, so sleep leaves them alone
CAP = 6000         # the pre-commit hook's body size cap
OP = re.compile(r'(merge|compress|split) \S')

URL = re.compile(r'https?://[^\s)>`\]]+')
CODE = re.compile(r'`([^`]+)`')
# A code span citing evidence: repo:path, a path or file name with an extension (and maybe :line),
# a command ending in a path, or any command with a flag, whose arguments are facts too.
CITE = re.compile(r'^[\w.-]+:[\w.-]*[/.][\w./-]*|^[\w.-]+/[\w./-]+\.\w+|\s[\w./-]+/[\w.-]+\.\w+$'
                  r'|^[\w.-]+\.[a-z]{1,5}(:\d+)?$|^[\w./-]+ .*\s--?[a-zA-Z]')
DISPUTED = re.compile(r'DISPUTED \d{4}-\d\d-\d\d')
HYPOTHESIS = 'Hypothesis (unverified)'


def log(stage, **kw):
    print(f'sleep: stage={stage} ' + ' '.join(f'{k}={v}' for k, v in kw.items()), file=sys.stderr)


def git(*args, cwd=TK, check=True):
    r = subprocess.run(['git', '-C', cwd, *args], capture_output=True, text=True)
    if check and r.returncode:
        log('git', target=cwd, cmd=args[0], status=r.returncode, error=repr(r.stderr.strip()[-300:]))
        sys.exit(1)
    return r


def is_record(note, votes):
    """Records live under history/ and never take votes. One filed elsewhere still has votes: []."""
    return note.startswith('history/') or '/history/' in note or votes == 'votes: []'


def evidence(text):
    """Returns (citation tokens, count of unverified hypotheses) in a note's text."""
    toks = {u.rstrip('.,;:') for u in URL.findall(text)}
    for c in CODE.findall(text.replace('```', '')):
        c = ' '.join(c.split())
        if CITE.search(c):
            toks.add(c)
    toks |= set(DISPUTED.findall(text))
    return toks, text.count(HYPOTHESIS)


def pairs(kws):
    """Ranks note pairs by keyword overlap, each keyword weighted by its rarity. Skips a note and its own parts."""
    n = len(kws)
    by_kw = defaultdict(list)
    for note, ks in kws.items():
        for k in ks:
            by_kw[k].append(note)
    w = {k: math.log(n / len(ns)) for k, ns in by_kw.items()}
    total = {note: sum(w[k] for k in ks) for note, ks in kws.items()}
    shared = defaultdict(float)
    for k, ns in by_kw.items():
        # ponytail: keywords on 50+ notes weigh almost nothing and blow up the pair count, so they are skipped.
        if len(ns) > 50:
            continue
        ns = sorted(ns)
        for i, a in enumerate(ns):
            for b in ns[i + 1:]:
                shared[a, b] += w[k]
    out = []
    for (a, b), s in shared.items():
        if b.startswith(a[:-3] + '/') or a.startswith(b[:-3] + '/'):
            continue
        union = total[a] + total[b] - s
        if union > 0:
            out.append((s / union, a, b))
    return sorted(out, reverse=True)


def frontmatter(path):
    """Returns (keywords, index, votes line, body bytes) of a note, the body measured as the pre-commit hook does."""
    with open(path, 'rb') as f:
        lines = f.read().split(b'\n')
    head = [x.decode(errors='replace') for x in lines[:4]] + [''] * 4
    body = len(b'\n'.join(lines[5:]))
    kw = head[1]
    if not (kw.startswith('keywords: [') and kw.endswith(']')):
        log('frontmatter', target=path, error='no keywords line')
        return set(), '', head[3], body
    return {k.strip().lower() for k in kw[11:-1].split(', ') if k.strip()}, head[2][7:], head[3], body


def last_commits():
    """Returns {path: subject of its newest commit} and {path: unix time of its newest commit not made by sleep}."""
    out = git('log', '--format=\x01%ct %s', '--name-only', cwd=WT).stdout
    subject, human, cur = {}, {}, None
    for line in out.splitlines():
        if line.startswith('\x01'):
            t, _, s = line[1:].partition(' ')
            cur = (int(t), s)
        elif line:
            subject.setdefault(line, cur[1])
            if not cur[1].startswith('tk: sleep '):
                human.setdefault(line, cur[0])
    return subject, human


def dirty():
    """Notes with uncommitted edits in the shared ~/tk checkout."""
    out = set()
    for line in git('status', '--porcelain').stdout.splitlines():
        out.update(p.strip('"') for p in line[3:].split(' -> '))
    return out


def scope_filter(paths):
    """A path ending in .md matches that note only. Any other path matches the note of that name and its parts."""
    scope = [p.removeprefix('./').removeprefix('~/tk/').rstrip('/') for p in paths]
    return lambda n: not scope or any(
        n == s if s.endswith('.md') else n == s + '.md' or n.startswith(s + '/') for s in scope)


def candidates(paths):
    if not os.path.isdir(WT):
        log('candidates', target=WT, error='no worktree, run sleep.py start first')
        sys.exit(1)
    spec = importlib.util.spec_from_file_location('tk_usage', os.path.join(HERE, 'tk-usage.py'))
    tk_usage = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tk_usage)
    log('candidates', target=WT, days=DAYS)
    notes, st, logs = tk_usage.collect(DAYS, WT)
    kws, index, body = {}, {}, {}
    for n in list(notes):
        kws[n], index[n], votes, body[n] = frontmatter(os.path.join(WT, n))
        if is_record(n, votes):
            notes.discard(n)
    kws = {n: kws[n] for n in notes}
    in_scope = scope_filter(paths)
    busy, (subject, human), now = dirty(), last_commits(), time.time()
    # Only other sessions' commits make a note fresh, so sleep can return to its own work.
    fresh = {n for n, t in human.items() if now - t < FRESH}
    slept = {n for n, s in subject.items() if s.startswith('tk: sleep ')}
    usable = lambda n: n not in busy and n not in fresh
    read = lambda n: st[n]['chars'] / 1e3 if n in st else 0

    # Both notes in scope, so parallel runs on disjoint subtrees never edit the same note.
    merge = [p for p in pairs(kws) if p[0] >= PAIR_MIN and in_scope(p[1]) and in_scope(p[2])
             and usable(p[1]) and usable(p[2])][:PAIR_TOP]

    ranked = sorted(((x['chars'], n) for n, x in st.items() if n in notes and x['reads']), reverse=True)
    hot = [(c, n) for c, n in ranked[:math.ceil(HOT_SHARE * len(notes))]
           if in_scope(n) and usable(n) and (n not in slept or body[n] > CAP)]

    print(f'{len(notes)} notes, reads from {len(logs)} session logs over {DAYS} days. Off limits: '
          f'{len(busy & notes)} with unsaved edits in ~/tk, {len(fresh & notes)} committed by sessions in the last 24h.')
    print(f'\nMERGE: {len(merge)} pairs by keyword overlap. Merge only pairs that describe the same thing.')
    for s, a, b in merge:
        print(f'{s:.2f}  {a}  {b}')
        for n in (a, b):
            print(f'      {n} ({read(n):.0f} KB read, body {body[n] / 1e3:.1f} KB): {index[n]}')
    print(f'\nHOT: {len(hot)} notes to compress, sharpen and split. A note sleep already did returns while its body '
          f'is over {CAP // 1000} KB.')
    print(f"{'read_kb':>8} {'body_kb':>8}  note")
    for c, n in hot:
        print(f'{c / 1e3:8.0f} {body[n] / 1e3:8.1f}  {n}' + ('  (compressed before, split only)' if n in slept else ''))


def save(what, paths, rm):
    if not OP.match(what):
        log('save', target=WT, error=f'bad subject {what!r}')
        print("Start the subject with merge, compress or split, then the note: 'compress tools/rtk.md, cut timeline'")
        sys.exit(2)
    if what.startswith('split '):
        parent = what.split()[1].rstrip(',')
        if os.path.exists(os.path.join(WT, parent)) and frontmatter(os.path.join(WT, parent))[3] > CAP:
            log('save', target=parent, error='split leaves parent over cap')
            print(f'{parent} is still over {CAP} bytes after this split. Move another section out and save again.')
            sys.exit(1)
    old, new = [], []
    for p in paths + rm:
        old.append(git('show', f'HEAD:{p}', cwd=WT, check=False).stdout)
        if p in paths and os.path.exists(os.path.join(WT, p)):
            with open(os.path.join(WT, p), errors='replace') as f:
                new.append(f.read())
    (old_e, old_h), (new_e, new_h) = evidence('\n'.join(old)), evidence('\n'.join(new))
    lost = sorted(old_e - new_e)
    if lost or new_h < old_h:
        log('evidence_check', target=' '.join(paths + rm), lost=len(lost), hypotheses=f'{old_h}->{new_h}')
        print('Evidence these notes held is gone. Put each back next to its claim, then save again:')
        print('\n'.join('  ' + t for t in lost) or f'  {old_h - new_h} "{HYPOTHESIS}" lines')
        sys.exit(1)
    for p in rm:
        # A retry after the hook blocked the commit finds the note already removed.
        git('rm', '-q', '--ignore-unmatch', '--', p, cwd=WT)
    log('save', target=WT, paths=len(paths + rm), what=repr(what))
    env = dict(os.environ, TK=WT, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='push.default', GIT_CONFIG_VALUE_0='upstream')
    r = subprocess.run(['sh', SAVE, 'sleep ' + what, *paths, *rm], env=env, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if 'rebase onto upstream failed' in r.stderr:
        # Another session changed these notes upstream. Drop this operation and keep the run going.
        # --keep refuses to touch files with unsaved edits, so other operations in flight survive.
        log('save', target=WT, status='conflict', error='dropped, upstream changed the same notes')
        git('reset', '-q', '--keep', '@{u}', cwd=WT)
        print('Dropped: upstream changed the same notes. Move on to the next operation.')
    sys.exit(r.returncode)


def start():
    up = git('rev-parse', '--abbrev-ref', '@{u}', check=False).stdout.strip()
    if not up:
        log('start', target=TK, error='~/tk has no upstream branch for sleep to push to')
        sys.exit(1)
    if os.path.exists(WT):
        log('start', target=WT, error='exists, so another sleep run is live or one crashed. '
            f'If none is running: {ME} end --force')
        sys.exit(1)
    exclude = git('rev-parse', '--git-path', 'info/exclude').stdout.strip()
    exclude = os.path.join(TK, exclude)
    if '/.sleep*/' not in (open(exclude).read() if os.path.exists(exclude) else ''):
        os.makedirs(os.path.dirname(exclude), exist_ok=True)
        with open(exclude, 'a') as f:
            f.write('/.sleep*/\n')
    log('start', target=WT, upstream=up)
    git('fetch', '-q')
    git('worktree', 'add', '-q', '-B', os.path.basename(WT)[1:], WT, up)
    git('branch', '-q', f'--set-upstream-to={up}', cwd=WT)
    print(WT)


def push_left():
    """Pushes commits a failed save left on the branch. Returns True once nothing is left unpushed."""
    for i in range(5):
        git('fetch', '-q', cwd=WT, check=False)
        if git('rev-list', '--count', '@{u}..HEAD', cwd=WT).stdout.strip() == '0':
            return True
        log('push_left', target=WT, attempt=i + 1)
        if git('rebase', '-q', '--autostash', '@{u}', cwd=WT, check=False).returncode:
            git('rebase', '--abort', cwd=WT, check=False)
            return False
        if git('-c', 'push.default=upstream', 'push', '-q', cwd=WT, check=False).returncode == 0:
            return True
        time.sleep(i + 1)
    return False


def end(force):
    if not os.path.exists(WT):
        print('no sleep worktree')
        return
    # Removing the worktree deletes its branch, so unpushed commits must reach upstream first, even with --force.
    if not push_left():
        log('end', target=WT, error='commits still unpushed, worktree kept')
        print('These commits did not reach upstream, so the worktree stays. Report them to the user:')
        print(git('log', '--oneline', '@{u}..HEAD', cwd=WT, check=False).stdout)
        sys.exit(1)
    r = git('worktree', 'remove', *(['--force'] if force else []), WT, check=False)
    if r.returncode:
        log('end', target=WT, status=r.returncode, error=repr(r.stderr.strip()[-300:]))
        print(f'Unsaved edits in the worktree. Save or undo each, or run {ME} end --force to discard them:')
        print(git('status', '--short', cwd=WT, check=False).stdout)
        sys.exit(1)
    git('branch', '-q', '-D', os.path.basename(WT)[1:], check=False)
    print('removed', WT)


def selftest():
    toks, hyp = evidence('See `wallet-ml:src/a.go` and https://x.y/z. Run `rg -n foo src/b.py`, '
                         'not `plain` or `a:b`.\n> DISPUTED 2026-10-01: why\nHypothesis (unverified): c')
    assert toks == {'wallet-ml:src/a.go', 'https://x.y/z', 'rg -n foo src/b.py', 'DISPUTED 2026-10-01'}, toks
    assert hyp == 1
    assert evidence('```sh\nrg x\n```\n`repo:\n  a/b.go`')[0] == {'repo: a/b.go'}
    toks = evidence('`main.py`, `pltv.rs:88`, `bytedcli libra get --app-id 1180`, `1.2.3`, `a.dws_wallet_eval_di`')[0]
    assert toks == {'main.py', 'pltv.rs:88', 'bytedcli libra get --app-id 1180'}, toks
    kws = {'a.md': {'rtk', 'proxy', 'x'}, 'b.md': {'rtk', 'proxy', 'y'}, 'a/part.md': {'rtk', 'proxy', 'x'},
           'c.md': {'z'}, 'd.md': {'w'}}
    got = pairs(kws)
    assert [(a, b) for _, a, b in got] == [('a/part.md', 'b.md'), ('a.md', 'b.md')], got
    assert scope_filter(['tools/'])('tools/a.md') and not scope_filter(['tools'])('toolsx/a.md')
    assert scope_filter(['~/tk/tools/rtk.md'])('tools/rtk.md') and scope_filter([])('any.md')
    assert scope_filter(['tools'])('tools.md') and scope_filter(['tools'])('tools/a/b.md')
    assert scope_filter(['wallet-ml.md'])('wallet-ml.md') and not scope_filter(['wallet-ml.md'])('wallet-ml/a.md')
    assert is_record('a/history/x.md', 'votes: [+2026-10-01]') and is_record('tools/triage.md', 'votes: []')
    assert not is_record('tools/rtk.md', 'votes: [+2026-10-01]')
    assert OP.match('compress tools/rtk.md, cut') and not OP.match('COMPRESS x') and not OP.match('compress+sharpen x')
    print('ok')


def name_arg(s):
    if not re.fullmatch(r'[\w-]+', s):
        raise argparse.ArgumentTypeError('use letters, digits, _ and - only')
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--name', type=name_arg, help='parallel run name')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('start')
    sub.add_parser('candidates').add_argument('paths', nargs='*')
    s = sub.add_parser('save')
    s.add_argument('what')
    s.add_argument('paths', nargs='*')
    s.add_argument('--rm', action='append', default=[])
    sub.add_parser('end').add_argument('--force', action='store_true')
    sub.add_parser('selftest')
    a = ap.parse_args()
    global WT, ME
    if a.name:
        WT, ME = os.path.join(TK, '.sleep-' + a.name), f'{ME} --name {a.name}'
    if a.cmd == 'save' and not a.paths + a.rm:
        ap.error('save needs at least one note')
    {'start': start, 'selftest': selftest, 'end': lambda: end(a.force),
     'candidates': lambda: candidates(a.paths), 'save': lambda: save(a.what, a.paths, a.rm)}[a.cmd]()


if __name__ == '__main__':
    main()
