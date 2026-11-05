#!/bin/sh
# Usage: save.sh '<what changed>' <path>...
# Commits only the given ~/tk paths as "tk: <what changed>", then rebases onto the
# upstream and pushes, retrying when another session pushed first. Other sessions' uncommitted
# edits in the shared checkout are neither committed nor lost. TK overrides the checkout, such as
# the sleep skill's worktree.
set -u

[ $# -ge 2 ] || { echo "usage: save.sh '<what changed>' <path>..." >&2; exit 2; }
msg=$1; shift
g() { git -C "${TK:-$HOME/tk}" "$@"; }
fail() { echo "save.sh: $*" >&2; exit 1; }

# The old side of a `git mv` is gone from disk and index, so git add rejects it. The commit still takes it.
for p; do
  if g ls-files -co --error-unmatch -- "$p" >/dev/null 2>&1; then g add -- "$p" || fail "git add $p failed, nothing committed"
  elif [ -z "$(g ls-tree --name-only HEAD -- "$p")" ]; then fail "no such note $p, nothing committed"; fi
done
if g diff --cached --quiet -- "$@"; then echo "save.sh: nothing changed in $*"; exit 0; fi
# The hook's reasons go into the last line, which is all an agent sees after `| tail -1`.
out=$(g commit -q -m "tk: $msg" -- "$@" 2>&1) ||
  fail "commit blocked: $(printf '%s\n' "$out" | grep -v '^tk: commit blocked' | paste -sd ';' -). Fix that and save again"
head=$(g rev-parse --short HEAD)
g rev-parse -q --verify '@{u}' >/dev/null || { echo "saved $head locally, no upstream to push to"; exit 0; }

# Rebase onto the fetched upstream ref, not FETCH_HEAD, which concurrent fetches overwrite.
# ponytail: --autostash pops other sessions' edits back after the rebase; if upstream changed
# the same file, git keeps their edit in the stash and says so.
# A push that loses a race prints scary rejections, so its output shows only when every try failed.
# Backs off longer each try, since several sessions saving at once keep beating each other to the push.
out=''
for try in 1 2 3 4 5; do
  g fetch -q || { sleep "$try"; continue; }
  g rebase -q --autostash '@{u}' || { g rebase --abort 2>/dev/null; fail "rebase onto upstream failed, $head is committed locally but not pushed"; }
  out=$(g push -q 2>&1) && { echo "saved $(g rev-parse --short HEAD), pushed"; exit 0; }
  sleep "$try"
done
fail "push failed 5 times, $(g rev-parse --short HEAD) is committed locally but not pushed: $(printf '%s\n' "$out" | tail -1)"
