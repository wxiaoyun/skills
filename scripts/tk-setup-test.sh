#!/bin/sh
# Runs tk-setup.sh in a throwaway HOME and checks the hook accepts good notes and rejects bad ones.
set -eu

vote="$(cd "$(dirname "$0")/../skills/tribal-knowledge" && pwd)/vote.sh"
find="$(dirname "$vote")/find.sh"
setup="$(cd "$(dirname "$0")" && pwd)/tk-setup.sh"
export HOME="$(mktemp -d)" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
trap 'rm -rf "$HOME"' EXIT
sh "$setup" >/dev/null
cd "$HOME/tk"
hook=.git/hooks/pre-commit

note() { mkdir -p "$(dirname "$1")"; printf -- '---\nkeywords: [k]\nindex: i\nvotes: %s\n---\n%s\n' "$2" "${3:-body}" > "$1"; }
pass() { git add -A; "$hook" 2>/dev/null || { echo "FAIL: expected pass: $1"; exit 1; }; }
reject() { git add -A; ! "$hook" 2>/dev/null || { echo "FAIL: expected reject: $1"; exit 1; }; }

pass "fresh setup"
note tools/kubectl.md '[]'
note tools/rtk.md '[+2026-10-03, -2026-09-20]'
pass "valid notes"

note tools/rtk.md '[+2026-10-03, +2026-10-02, +2026-10-01, +2026-09-30, +2026-09-29, +2026-09-28]'
reject "6 votes"
note tools/rtk.md '[2026-10-03]'
reject "unsigned vote"
note tools/rtk.md '[+2026-09-20, +2026-10-03]'
reject "votes oldest first"
note tools/rtk.md '[+2026-10-03, -2026-10-03]'
pass "same-day votes"
note tools/rtk.md '[+2026-10-03, +2026-10-02, +2026-10-01, +2026-09-30, +2026-09-29]'
sh "$vote" tools/rtk.md - >/dev/null
[ "$(sed -n 4p tools/rtk.md)" = "votes: [-$(date +%F), +2026-10-03, +2026-10-02, +2026-10-01, +2026-09-30]" ] || { echo "FAIL: vote.sh on a full list"; exit 1; }
pass "vote.sh on a full list"
sh "$vote" tools/kubectl.md + >/dev/null
[ "$(sed -n 4p tools/kubectl.md)" = "votes: [+$(date +%F)]" ] || { echo "FAIL: vote.sh on an empty list"; exit 1; }
note tools/rtk.md '[+2026-10-03]'
printf -- '---\nkeywords: [k]\n' > tools/short.md
reject "truncated frontmatter"
: > tools/short.md
reject "empty note"
rm tools/short.md
printf -- '---\nindex: i\nkeywords: [k]\nvotes: []\n---\n' > tools/order.md
reject "wrong field order"
rm tools/order.md

note history/outage-2026-09-21.md '[+2026-09-21]'
reject "votes on a dated record"
note history/outage-2026-09-21.md '[]' 'see [rtk](../tools/rtk.md#flags), [docs](https://x.y/z), [top](#top)'
pass "dated record without votes, valid links"
note history/outage-2026-09-21.md '[]' 'see [gone](../tools/gone.md)'
reject "broken link"
note history/outage-2026-09-21.md '[]'
pass "back to valid"
git commit -qm base

body() { printf "%$1s" | tr ' ' x | fold -w 100; }
note tools/big.md '[]' "$(body 13000)"
git add -A
"$hook" 2>&1 | grep -q 'tools/big.md: body grew to 13 KB' || { echo "FAIL: size message"; exit 1; }
reject "new note past 12 KB"
git commit -qm big --no-verify
sh "$vote" tools/big.md + >/dev/null
pass "vote on a note already past 12 KB"
note tools/big.md '[]' "$(body 12500)"
pass "shrinking a note still past 12 KB"
note tools/big.md '[]' "$(body 13500)"
reject "growing a note past 12 KB"
git rm -qf tools/big.md && git commit -qm unbig

note tools/long.md '[]' "- $(printf '%700s' | tr ' ' x)"
git add -A
"$hook" 2>&1 | grep -q 'tools/long.md: line 6 is 702 characters' || { echo "FAIL: long line message"; exit 1; }
reject "new long line"
git commit -qm long --no-verify
printf -- 'short\n' >> tools/long.md
pass "existing long line untouched"
note tools/long.md '[]' "| $(printf '%700s' | tr ' ' x) |"
pass "long table row"

printf -- '---\nkeywords: [%s]\nindex: i\nvotes: []\n---\nbody\n' "$(seq -s ', ' 31)" > tools/kw.md
reject "31 keywords"
printf -- '---\nkeywords: [k]\nindex: %s\nvotes: []\n---\nbody\n' "$(printf '%300s' | tr ' ' x)" > tools/kw.md
reject "index over 300 characters"
git commit -qm kw --no-verify
printf -- 'more\n' >> tools/kw.md
pass "unchanged long index"
git rm -qf tools/kw.md tools/long.md && git commit -qm clean

printf -- '---\nkeywords: [rtk, proxy]\nindex: rtk note\nvotes: [+2026-10-01]\n---\nrtk proxy body\n' > tools/rtk.md
printf -- '---\nkeywords: [legacy]\nindex: old note\nvotes: [+2026-10-09]\n---\nmentions RTK\n' > tools/old.md
out=$(sh "$find" rtk proxy)
printf '%s\n' "$out" | grep -q '^2 notes match (1 by keyword)' || { echo "FAIL: find.sh counts: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | sed -n 2p | cut -d' ' -f1)" = tools/rtk.md ] || { echo "FAIL: find.sh ranks keyword hits first: $out"; exit 1; }
sh "$find" -n 1 rtk | grep -q '^1 more rank lower' || { echo "FAIL: find.sh -n"; exit 1; }
sh "$find" nothing-here | grep -q '^0 notes match' || { echo "FAIL: find.sh no match"; exit 1; }
sh "$find" -o tools/rtk.md | grep -q '^6: rtk proxy body' || { echo "FAIL: find.sh -o"; exit 1; }

save="$(dirname "$vote")/save.sh"
git init -q --bare "$HOME/remote.git" && git remote add origin "$HOME/remote.git" && git push -qu origin HEAD 2>/dev/null
git clone -q "$HOME/remote.git" "$HOME/other"
printf -- '---\nkeywords: [o]\nindex: o\nvotes: []\n---\nbody\n' > "$HOME/other/tools/other.md"
git -C "$HOME/other" add -A && git -C "$HOME/other" commit -qm other && git -C "$HOME/other" push -q 2>/dev/null
note tools/saved.md '[]'
CLAUDE_CODE_SESSION_ID=abcdefgh123 sh "$save" 'add saved' tools/saved.md >/dev/null || { echo "FAIL: save.sh"; exit 1; }
[ "$(git --git-dir="$HOME/remote.git" log -1 --format=%s)" = 'tk: add saved (abcdefgh)' ] || { echo "FAIL: save.sh pushed commit"; exit 1; }
[ -f tools/other.md ] || { echo "FAIL: save.sh rebased onto upstream"; exit 1; }
[ "$(git status --porcelain tools/rtk.md tools/old.md)" = "$(printf ' M tools/rtk.md\n?? tools/old.md')" ] || { echo "FAIL: save.sh kept other edits"; exit 1; }
sh "$save" noop tools/saved.md | grep -q 'nothing changed' || { echo "FAIL: save.sh with no change"; exit 1; }
note tools/bad.md '[]' 'see [gone](gone.md)'
! sh "$save" bad tools/bad.md 2>/dev/null || { echo "FAIL: save.sh pushed past the hook"; exit 1; }
[ "$(git --git-dir="$HOME/remote.git" log -1 --format=%s)" = 'tk: add saved (abcdefgh)' ] || { echo "FAIL: save.sh pushed a blocked note"; exit 1; }
git rm -q --cached tools/bad.md && rm tools/bad.md

# The settings merge keeps existing rules and adds each tk rule once.
if command -v jq >/dev/null; then
  mkdir -p "$HOME/.claude"
  printf '{"permissions":{"allow":["Bash(ls)"]},"theme":"dark"}\n' > "$HOME/.claude/settings.json"
  sh "$setup" >/dev/null && sh "$setup" >/dev/null
  jq -e '.theme == "dark" and (.permissions.allow | index("Bash(ls)") and index("Edit(~/tk/**)") and length == 14)' "$HOME/.claude/settings.json" >/dev/null || { echo "FAIL: settings merge"; exit 1; }
fi
echo ok
