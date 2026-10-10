#!/bin/sh
# Runs tk-setup.sh in a throwaway HOME and checks the hook accepts good notes and rejects bad ones.
set -eu

vote="$(cd "$(dirname "$0")/../skills/tribal-knowledge" && pwd)/vote.sh"
export HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
sh "$(dirname "$0")/tk-setup.sh" >/dev/null
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
note tools/big.md '[]' "$(printf '%13000s' | tr ' ' x)"
git add -A
"$hook" 2>&1 | grep -q 'tools/big.md is 13 KB' || { echo "FAIL: size warning"; exit 1; }
pass "size warning does not block"
echo ok
