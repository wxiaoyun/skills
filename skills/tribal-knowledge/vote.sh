#!/bin/sh
# Usage: vote.sh <note> +|-
# Prepends today's vote to the note's votes line, keeps one vote per date (the newest) and the 5 newest dates, as the tk pre-commit hook requires.
# One vote per date stops a same-day burst of sessions from pushing older verdicts out.
set -eu

[ $# -eq 2 ] && { [ "$2" = + ] || [ "$2" = - ]; } || { echo "usage: vote.sh <note> +|-" >&2; exit 2; }
f=$1
case $f in *-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) echo "$f: dated records take no votes" >&2; exit 1 ;; esac
sed -n 4p "$f" | grep -q '^votes: \[.*\]$' || { echo "$f: line 4 is not a votes line" >&2; exit 1; }

awk -v v="$2$(date +%F)" '
  FNR == 4 {
    s = $0; sub(/^votes: \[/, "", s); sub(/\]$/, "", s)
    n = (s == "") ? 0 : split(s, a, ", ")
    out = v; seen[substr(v, 2)] = 1; k = 1
    for (i = 1; i <= n && k < 5; i++) if (!seen[substr(a[i], 2)]++) { out = out ", " a[i]; k++ }
    $0 = "votes: [" out "]"
  }
  { print }
' "$f" > "$f.tmp"
mv "$f.tmp" "$f"
sed -n 4p "$f"
