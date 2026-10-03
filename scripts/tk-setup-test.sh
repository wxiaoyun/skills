#!/bin/sh
# Runs tk-setup.sh in a throwaway HOME and checks the hook accepts good notes and rejects bad ones.
set -eu

export HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
sh "$(dirname "$0")/tk-setup.sh" >/dev/null
cd "$HOME/tk"
hook=.git/hooks/pre-commit

note() { mkdir -p "$(dirname "$1")"; printf -- '---\nkeywords: [k]\nindex: i\nvotes: %s\n---\nbody\n' "$2" > "$1"; }
pass() { "$hook" 2>/dev/null || { echo "FAIL: expected pass: $1"; exit 1; }; }
reject() { ! "$hook" 2>/dev/null || { echo "FAIL: expected reject: $1"; exit 1; }; }

pass "fresh setup"
note tools/kubectl.md '[]'
note tools/rtk.md '[+2026-10-03, -2026-09-20]'
pass "valid notes"

note tools/rtk.md '[+2026-10-03, +2026-10-02, +2026-10-01, +2026-09-30, +2026-09-29, +2026-09-28]'
reject "6 votes"
note tools/rtk.md '[2026-10-03]'
reject "unsigned vote"
note tools/rtk.md '[+2026-10-03]'
printf -- '---\nkeywords: [k]\n' > tools/short.md
reject "truncated frontmatter"
: > tools/short.md
reject "empty note"
rm tools/short.md
printf -- '---\nindex: i\nkeywords: [k]\nvotes: []\n---\n' > tools/order.md
reject "wrong field order"
rm tools/order.md
pass "back to valid"
echo ok
