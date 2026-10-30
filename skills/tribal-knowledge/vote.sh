#!/bin/sh
# Usage: vote.sh <note> +|-|reset
# + or - prepends today's vote to the note's votes line, keeps one vote per date (the newest) and the 5 newest dates, as the tk pre-commit hook requires.
# One vote per date stops a same-day burst of sessions from pushing older verdicts out.
# reset replaces every vote with [+today], for a note just corrected.
set -eu

[ $# -eq 2 ] && case $2 in +|-|reset) true ;; *) false ;; esac || { echo "usage: vote.sh <note> +|-|reset" >&2; exit 2; }
f=$1
[ -f "$f" ] || f="$HOME/tk/$f"
case $f in *-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) echo "$f: dated records take no votes" >&2; exit 1 ;; esac
sed -n 4p "$f" | grep -q '^votes: \[.*\]$' || { echo "$f: line 4 is not a votes line" >&2; exit 1; }
if [ "$2" = + ] && grep -q '^[[:space:]]*> DISPUTED' "$f"; then
  echo "$f: has an open DISPUTED line. Re-check that claim: if it is wrong, fix the note, drop the line and run vote.sh reset; if unclear, vote -" >&2
  exit 1
fi

awk -v m="$2" -v d="$(date +%F)" '
  FNR == 4 && m == "reset" { $0 = "votes: [+" d "]" }
  FNR == 4 && m != "reset" {
    v = m d
    s = $0; sub(/^votes: \[/, "", s); sub(/\]$/, "", s)
    n = (s == "") ? 0 : split(s, a, ", ")
    out = v; seen[d] = 1; k = 1
    for (i = 1; i <= n && k < 5; i++) if (!seen[substr(a[i], 2)]++) { out = out ", " a[i]; k++ }
    $0 = "votes: [" out "]"
  }
  { print }
' "$f" > "$f.tmp"
mv "$f.tmp" "$f"
sed -n 4p "$f"
