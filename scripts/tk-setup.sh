#!/bin/sh
# Sets up ~/tk for the tribal-knowledge skill: a git repo with a pre-commit hook
# that checks note format and links. Safe to rerun. Rerunning updates the hook.
set -eu

TK="$HOME/tk"
mkdir -p "$TK"
cd "$TK"
[ -d .git ] || git init -q

mkdir -p .git/hooks
cat > .git/hooks/pre-commit <<'HOOK'
#!/bin/sh
# Checks every tk note and its links. Installed by tk-setup.sh from github.com/wxiaoyun/skills.
cd "$(git rev-parse --show-toplevel)" || exit 1
tab=$(printf '\t')

errors=$(
  find . -type f -name '*.md' ! -path '*/.*' -empty -exec echo "{}: empty note" \;
  find . -type f -name '*.md' ! -path '*/.*' -exec awk '
    function bad(msg) { print FILENAME ": " msg }
    function done_file() { if (file != "" && lines < 5) print file ": frontmatter must be lines 1-5 (---, keywords, index, votes, ---)" }
    FNR == 1 { done_file(); file = FILENAME }
    { lines = FNR }
    FNR == 1 && $0 != "---" { bad("line 1 must be ---") }
    FNR == 2 && $0 !~ /^keywords: \[.+\]$/ { bad("line 2 must be keywords: [a, b]") }
    FNR == 3 && $0 !~ /^index: [^ ]/ { bad("line 3 must be index: <one line>") }
    FNR == 4 {
      if ($0 !~ /^votes: \[.*\]$/) { bad("line 4 must be votes: [+YYYY-MM-DD, -YYYY-MM-DD]"); next }
      s = $0; sub(/^votes: \[/, "", s); sub(/\]$/, "", s)
      n = (s == "") ? 0 : split(s, v, ", ")
      if (n > 5) bad("votes keeps at most 5 entries")
      for (i = 1; i <= n; i++) {
        if (v[i] !~ /^[-+][0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) bad("bad vote " v[i])
        else if (i > 1 && substr(v[i], 2) > substr(v[i - 1], 2)) bad("votes must be newest first")
      }
      if (n > 0 && FILENAME ~ /-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.md$/) bad("dated records take no votes")
    }
    FNR == 5 && $0 != "---" { bad("line 5 must be ---") }
    END { done_file() }
  ' {} +
  # Relative links must resolve. Anything with a scheme (https:, mailto:) is skipped.
  find . -type f -name '*.md' ! -path '*/.*' -exec awk '
    { s = $0
      while (match(s, /[]][(][^) ]+[)]/)) {
        t = substr(s, RSTART + 2, RLENGTH - 3); s = substr(s, RSTART + RLENGTH)
        sub(/#.*/, "", t)
        if (t != "" && t !~ /^[a-z]+:/) print FILENAME "\t" t
      }
    }
  ' {} + | while IFS="$tab" read -r f t; do
    case $t in /*) p=$t ;; *) p=${f%/*}/$t ;; esac
    [ -e "$p" ] || echo "$f: broken link $t"
  done
)

[ -z "$errors" ] && exit 0
printf '%s\n' "$errors" >&2
echo "tk: commit blocked, fix the notes above (format in the tribal-knowledge skill)" >&2
exit 1
HOOK
chmod +x .git/hooks/pre-commit

# ponytail: a hooksPath (often global) makes git skip .git/hooks, warn instead of overriding it
if hp=$(git config core.hooksPath); then
  echo "warning: core.hooksPath is $hp, so git will not run $TK/.git/hooks/pre-commit" >&2
fi
echo "tk ready at $TK"
