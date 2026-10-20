#!/bin/sh
# Usage: save.sh '<what changed>' <path>...
# Commits only the given ~/tk paths as "tk: <what changed> (<run-id>)", then rebases onto the
# upstream and pushes, retrying when another session pushed first. Other sessions' uncommitted
# edits in the shared checkout are neither committed nor lost.
set -u

[ $# -ge 2 ] || { echo "usage: save.sh '<what changed>' <path>..." >&2; exit 2; }
msg=$1; shift
id=${CLAUDE_CODE_SESSION_ID:-${PI_SESSION_ID:-${CODEX_THREAD_ID:-manual}}}
g() { git -C "$HOME/tk" "$@"; }
fail() { echo "save.sh: $*" >&2; exit 1; }

g add -- "$@" || fail "git add failed, nothing committed"
if g diff --cached --quiet -- "$@"; then echo "save.sh: nothing changed in $*"; exit 0; fi
g commit -q -m "tk: $msg ($(printf '%.8s' "$id"))" -- "$@" || fail "commit blocked, fix what the hook reported and save again"
head=$(g rev-parse --short HEAD)
g rev-parse -q --verify '@{u}' >/dev/null || { echo "saved $head locally, no upstream to push to"; exit 0; }

# Rebase onto the fetched upstream ref, not FETCH_HEAD, which concurrent fetches overwrite.
# ponytail: --autostash pops other sessions' edits back after the rebase; if upstream changed
# the same file, git keeps their edit in the stash and says so.
for try in 1 2 3; do
  g fetch -q || { sleep 1; continue; }
  g rebase -q --autostash '@{u}' || { g rebase --abort 2>/dev/null; fail "rebase onto upstream failed, $head is committed locally but not pushed"; }
  g push -q && { echo "saved $(g rev-parse --short HEAD), pushed"; exit 0; }
  sleep 1
done
fail "push failed 3 times, $(g rev-parse --short HEAD) is committed locally but not pushed"
