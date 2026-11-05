#!/bin/sh
# Runs sleep.py start, save and end against a throwaway ~/tk with a bare upstream, and checks that
# sleep commits reach the upstream, lost evidence blocks a save, and a live run locks out a second.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
py="$here/sleep.py"
export HOME="$(mktemp -d)" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
trap 'rm -rf "$HOME"' EXIT
sh "$here/../../scripts/tk-setup.sh" >/dev/null
git init -q --bare "$HOME/up.git"
cd "$HOME/tk"
note() { printf -- '---\nkeywords: [k]\nindex: i\nvotes: [+2026-10-01]\n---\n%s\n' "$2" > "$1"; }
note a.md 'Cited in `repo:src/a.go`.'
note b.md 'Same as a, see `repo:src/b.go`.'
git add -A && git commit -qm base
git remote add origin "$HOME/up.git" && git push -qu origin HEAD 2>/dev/null

fail() { echo "FAIL: $1"; exit 1; }
python3 "$py" start >/dev/null 2>&1 || fail "start"
! python3 "$py" start >/dev/null 2>&1 || fail "second start should be locked out"
wt="$HOME/tk/.sleep"
[ -z "$(git status --porcelain)" ] || fail "worktree shows up in ~/tk status"

note "$wt/a.md" 'Cited nowhere now.'
! python3 "$py" save 'compress a.md' a.md >/dev/null 2>&1 || fail "save dropped evidence"
note "$wt/a.md" 'Cited in `repo:src/a.go`. Also `repo:src/b.go`.'
python3 "$py" save 'merge b.md into a.md' a.md --rm b.md >/dev/null 2>&1 || fail "merge save"
[ "$(git -C "$HOME/up.git" log -1 --format=%s)" = 'tk: sleep merge b.md into a.md' ] || fail "commit not on upstream"
[ -z "$(git -C "$HOME/up.git" ls-tree HEAD b.md)" ] || fail "b.md still on upstream"

# A parallel run on its own worktree, racing the first run on the same note: the loser drops its operation.
python3 "$py" --name x start >/dev/null 2>&1 || fail "parallel start"
wx="$HOME/tk/.sleep-x"
note "$wt/a.md" 'First: `repo:src/a.go` and `repo:src/b.go`.'
note "$wx/a.md" 'Second: `repo:src/a.go` and `repo:src/b.go`.'
python3 "$py" save 'compress a.md' a.md >/dev/null 2>&1 || fail "first save"
out=$(python3 "$py" --name x save 'compress a.md' a.md 2>&1) && fail "conflicting save should fail"
echo "$out" | grep -q '^Dropped' || fail "conflict not dropped: $out"
[ -z "$(git -C "$wx" status --porcelain)" ] && [ "$(git -C "$wx" rev-parse HEAD)" = "$(git -C "$wx" rev-parse '@{u}')" ] ||
  fail "dropped operation left the worktree off upstream"
[ -z "$(git status --porcelain)" ] || fail "parallel worktree shows up in ~/tk status"

python3 "$py" end >/dev/null 2>&1 || fail "end"
python3 "$py" --name x end >/dev/null 2>&1 || fail "parallel end"
[ ! -e "$wt" ] && [ ! -e "$wx" ] || fail "worktree left behind"
echo ok
