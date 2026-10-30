#!/bin/sh
# Runs tk-setup.sh in a throwaway HOME and checks the hook accepts good notes and rejects bad ones.
set -eu

vote="$(cd "$(dirname "$0")/../skills/tribal-knowledge" && pwd)/vote.sh"
find="$(dirname "$vote")/find.sh"
setup="$(cd "$(dirname "$0")" && pwd)/tk-setup.sh"
# A symlinked HOME, as on hosts where /home/<user> points at a data disk.
real="$(mktemp -d)"
ln -s "$real" "$real.home"
export HOME="$real.home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
trap 'rm -rf "$real" "$real.home"' EXIT
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
note tools/rtk.md "[-$(date +%F), +2026-10-03, +2026-10-03, +2026-10-02, +2026-10-01]"
sh "$vote" tools/rtk.md + >/dev/null
[ "$(sed -n 4p tools/rtk.md)" = "votes: [+$(date +%F), +2026-10-03, +2026-10-02, +2026-10-01]" ] || { echo "FAIL: vote.sh keeps one vote per date"; exit 1; }
pass "vote.sh keeps one vote per date"
(cd / && sh "$vote" tools/kubectl.md - >/dev/null) || { echo "FAIL: vote.sh takes a path inside ~/tk"; exit 1; }
note tools/disputed.md '[+2026-10-01]' "$(printf -- '- claim\n> DISPUTED 2026-10-02: no evidence')"
! sh "$vote" tools/disputed.md + 2>/dev/null || { echo "FAIL: vote.sh + on a DISPUTED note"; exit 1; }
sh "$vote" tools/disputed.md reset >/dev/null
[ "$(sed -n 4p tools/disputed.md)" = "votes: [+$(date +%F)]" ] || { echo "FAIL: vote.sh reset"; exit 1; }
rm tools/disputed.md
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
pass "index of 300 characters, the prefix not counted"
printf -- '---\nkeywords: [k]\nindex: %s\nvotes: []\n---\nbody\n' "$(printf '%301s' | tr ' ' x)" > tools/kw.md
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
sh "$save" 'add saved' tools/saved.md >/dev/null || { echo "FAIL: save.sh"; exit 1; }
[ "$(git --git-dir="$HOME/remote.git" log -1 --format=%s)" = 'tk: add saved' ] || { echo "FAIL: save.sh pushed commit"; exit 1; }
[ -f tools/other.md ] || { echo "FAIL: save.sh rebased onto upstream"; exit 1; }
[ "$(git status --porcelain tools/rtk.md tools/old.md)" = "$(printf ' M tools/rtk.md\n?? tools/old.md')" ] || { echo "FAIL: save.sh kept other edits"; exit 1; }
sh "$save" noop tools/saved.md | grep -q 'nothing changed' || { echo "FAIL: save.sh with no change"; exit 1; }
note tools/bad.md '[]' 'see [gone](gone.md)'
out=$(sh "$save" bad tools/bad.md 2>&1) && { echo "FAIL: save.sh pushed past the hook"; exit 1; }
printf '%s\n' "$out" | tail -1 | grep -q 'broken link gone.md' || { echo "FAIL: a blocked save names the reason last: $out"; exit 1; }
[ "$(git --git-dir="$HOME/remote.git" log -1 --format=%s)" = 'tk: add saved' ] || { echo "FAIL: save.sh pushed a blocked note"; exit 1; }
git rm -q --cached tools/bad.md && rm tools/bad.md
git mv tools/saved.md tools/moved.md
sh "$save" 'move saved' tools/saved.md tools/moved.md >/dev/null || { echo "FAIL: save.sh after git mv"; exit 1; }
git --git-dir="$HOME/remote.git" cat-file -e HEAD:tools/moved.md && ! git --git-dir="$HOME/remote.git" cat-file -e HEAD:tools/saved.md 2>/dev/null || { echo "FAIL: save.sh pushed the rename"; exit 1; }
! sh "$save" typo tools/nope.md 2>/dev/null || { echo "FAIL: save.sh with a missing note"; exit 1; }

# guard.sh: the Claude Code hooks (and, through tk-guard.ts, pi) for the shared checkout.
if command -v jq >/dev/null; then
  guard="$(dirname "$vote")/guard.sh"
  bash_hook() { printf '%s' "$1" | jq -Rs '{tool_input: {command: .}}' | sh "$guard" 2>/dev/null; }
  for c in 'cd ~/tk && git checkout -- tools/rtk.md' 'git -C ~/tk stash' "git -C \"\$HOME/tk\" reset --hard" \
    "sed -i 's/a/b/' ~/tk/tools/rtk.md" 'cd ~/tk && printf x >> tools/rtk.md' \
    "$(printf "cd ~/tk && python3 - <<'EOF'\nopen('tools/rtk.md', 'w').write('x')\nEOF")"; do
    ! bash_hook "$c" || { echo "FAIL: guard should block: $c"; exit 1; }
  done
  for c in "cd ~/tk && sh x/save.sh 'note the git reset trap' tools/rtk.md" 'cd ~/tk && rg -n proxy tools > /tmp/out.md' \
    'git -C ~/tk status && sh x/vote.sh tools/rtk.md + >/dev/null' 'git checkout main' "sed -i 's/a/b/' src/main.go"; do
    bash_hook "$c" || { echo "FAIL: guard should allow: $c"; exit 1; }
  done
  # Stop blocks once while a note this session edited is unsaved. tools/rtk.md is still modified here.
  edit() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$1" > "$HOME/t.jsonl"; }
  stop() { printf '{"transcript_path":"%s/t.jsonl"%s}' "$HOME" "${1:-}" | sh "$guard" stop 2>/dev/null; }
  edit "$HOME/tk/tools/rtk.md"; ! stop || { echo "FAIL: stop with an unsaved note"; exit 1; }
  edit "$(cd "$HOME/tk" && pwd -P)/tools/rtk.md"; ! stop || { echo "FAIL: stop with an unsaved note by real path"; exit 1; }
  stop ',"stop_hook_active":true' || { echo "FAIL: stop blocks only once"; exit 1; }
  mv "$HOME/t.jsonl" "$HOME/sub.jsonl"; edit "$HOME/tk/tools/moved.md"
  printf '{"transcript_path":"%s/t.jsonl","agent_transcript_path":"%s/sub.jsonl"}' "$HOME" "$HOME" | sh "$guard" stop 2>/dev/null &&
    { echo "FAIL: SubagentStop reads the subagent's own transcript"; exit 1; }
  rm "$HOME/sub.jsonl"
  edit "$HOME/tk/tools/moved.md"; stop || { echo "FAIL: stop with every note saved"; exit 1; }
  [ "$(sh "$guard" dirty tools/rtk.md tools/moved.md)" = tools/rtk.md ] || { echo "FAIL: guard.sh dirty"; exit 1; }
fi

# The settings merge keeps existing rules and adds each tk rule once.
if command -v jq >/dev/null; then
  mkdir -p "$HOME/.claude"
  printf '{"permissions":{"allow":["Bash(ls)"]},"theme":"dark","hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"x"}]}]}}\n' > "$HOME/.claude/settings.json"
  # An installed skill, so setup links the pi extension.
  mkdir -p "$HOME/.agents/skills" "$HOME/.pi/agent" && ln -s "$(dirname "$vote")" "$HOME/.agents/skills/tribal-knowledge"
  sh "$setup" >/dev/null && sh "$setup" >/dev/null
  jq -e --arg real "$(cd "$HOME/tk" && pwd -P)" '.theme == "dark" and (.permissions.allow | index("Bash(ls)") and index("Edit(~/tk/**)") and index("Edit(/\($real)/**)") and length == 16)' "$HOME/.claude/settings.json" >/dev/null || { echo "FAIL: settings merge"; exit 1; }
  jq -e '(.hooks.PreToolUse | length == 2 and .[0].hooks[0].command == "x" and .[1].matcher == "Bash") and (.hooks.Stop | length == 1 and (.[0].hooks[0].command | endswith("guard.sh stop"))) and (.hooks.SubagentStop | length == 1)' "$HOME/.claude/settings.json" >/dev/null || { echo "FAIL: hooks merge"; exit 1; }
  [ -f "$HOME/.pi/agent/extensions/tk-guard.ts" ] || { echo "FAIL: pi extension link"; exit 1; }
fi
echo ok
