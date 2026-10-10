#!/bin/sh
# Usage: vote.sh <note> +|-
# Prepends today's vote to the note's votes line and keeps the 5 newest, as the tk pre-commit hook requires.
set -eu

[ $# -eq 2 ] && { [ "$2" = + ] || [ "$2" = - ]; } || { echo "usage: vote.sh <note> +|-" >&2; exit 2; }
f=$1
case $f in *-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) echo "$f: dated records take no votes" >&2; exit 1 ;; esac
sed -n 4p "$f" | grep -q '^votes: \[.*\]$' || { echo "$f: line 4 is not a votes line" >&2; exit 1; }

awk -v v="$2$(date +%F)" '
  FNR == 4 {
    s = $0; sub(/^votes: \[/, "", s); sub(/\]$/, "", s)
    n = (s == "") ? 0 : split(s, a, ", ")
    out = v
    for (i = 1; i <= n && i < 5; i++) out = out ", " a[i]
    $0 = "votes: [" out "]"
  }
  { print }
' "$f" > "$f.tmp"
mv "$f.tmp" "$f"
sed -n 4p "$f"
