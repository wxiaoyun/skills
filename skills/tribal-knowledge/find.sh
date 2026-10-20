#!/bin/sh
# Usage: find.sh [-n N] <term>...   rank ~/tk notes for the terms, print the top N (default 10)
#        find.sh -o <note>           outline a note by line number before reading part of it
# Terms are plain strings matched in any case; `a|b` counts as two terms. Notes rank by how many
# terms their keywords line holds as whole words, then by how many appear anywhere, then by newest vote.
set -eu

tk="$HOME/tk"
usage() { echo "usage: find.sh [-n N] <term>... | find.sh -o <note>" >&2; exit 2; }

if [ "${1:-}" = -o ]; then
  [ $# -eq 2 ] || usage
  f=$2
  [ -f "$f" ] || f="$tk/$f"
  echo "$2: $(wc -l < "$f" | tr -d ' ') lines, $(($(wc -c < "$f") / 1000)) KB. Read a range with sed -n 'A,Bp'."
  awk 'NR > 5 && NF { s = $0; if (s !~ /^#/ && length(s) > 72) s = substr(s, 1, 72) "..."; print NR ": " s }' "$f"
  exit
fi

n=10
[ "${1:-}" = -n ] && { [ $# -ge 3 ] || usage; n=$2; shift 2; }
[ $# -ge 1 ] || usage
TERMS=$(printf '%s\n' "$@" | tr '|' '\n' | sed '/^$/d')
export TERMS
cd "$tk"

ranked=$(printf '%s\n' "$TERMS" | rg -l -0 -i -F -f - -g '*.md' | xargs -0 -r awk '
  function word(s, w,   o, p) {  # w occurs in s with no letter, digit or _ on either side
    while ((p = index(substr(s, o + 1), w)) > 0) {
      o += p
      if (substr(s, o - 1, 1) !~ /[a-z0-9_]/ && substr(s, o + length(w), 1) !~ /[a-z0-9_]/) return 1
    }
    return 0
  }
  function flush(   i, kw, tx, d) {
    if (file == "") return
    kw = tx = 0
    for (i = 1; i <= nt; i++) { kw += word(keys, t[i]); tx += (i in hit) }
    d = match(votes, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) ? substr(votes, RSTART, 10) : "0000-00-00"
    print kw "\t" tx "\t" d "\t" file "\t" index_line "\t" votes
  }
  BEGIN { nt = split(tolower(ENVIRON["TERMS"]), t, "\n") }
  FNR == 1 { flush(); file = FILENAME; split("", hit); keys = index_line = votes = "" }
  FNR == 2 { keys = tolower(substr($0, 11)) }
  FNR == 3 { index_line = $0 }
  FNR == 4 { votes = $0 }
  { l = tolower($0); for (i = 1; i <= nt; i++) if (!(i in hit) && index(l, t[i])) hit[i] = 1 }
  END { flush() }
' | sort -t "$(printf '\t')" -k1,1nr -k2,2nr -k3,3r)

total=$(printf '%s' "$ranked" | grep -c . || true)
bykw=$(printf '%s' "$ranked" | grep -c '^[1-9]' || true)
nt=$(printf '%s\n' "$TERMS" | wc -l | tr -d ' ')
if [ "$total" -eq 0 ]; then echo "0 notes match: try other terms, or fewer"; exit; fi
echo "$total notes match ($bykw by keyword). Top $n:"
printf '%s\n' "$ranked" | head -n "$n" | awk -F '\t' -v nt="$nt" '{ print $4 "  [keywords " $1 "/" nt ", text " $2 "/" nt "]  " $6; print "  " $5 }'
[ "$total" -le "$n" ] || echo "$((total - n)) more rank lower. Pass -n to see more."
