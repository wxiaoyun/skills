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
# Checks the staged snapshot, not the working tree, so another agent's unstaged
# half-written note cannot block an unrelated commit.
cd "$(git rev-parse --show-toplevel)" || exit 1
# Blocks only what this commit adds past the size limits, so a note already over them still
# takes votes and fixes: a body line over 600 characters (table rows excepted), a body grown
# past 12 KB, and a changed keywords line over 30 entries or index line over 300 characters.
grown=$(git diff --cached --name-only --diff-filter=AM -- '*.md' | while read -r f; do
  new=$(git show ":$f" | tail -n +6 | wc -c)
  old=$(git show "HEAD:$f" 2>/dev/null | tail -n +6 | wc -c)
  [ "$new" -le 12000 ] || [ "$new" -le "$old" ] || echo "$f: body grew to $((new / 1000)) KB, past 12 KB, move the section you edited into its own note"
  git diff --cached -U0 -- "$f" | awk -v f="$f" '
    /^@@/ { split($3, a, ","); n = substr(a[1], 2) - 1; h = 1; next }
    h && /^\+/ { n++; s = substr($0, 2)
      if (n > 5 && s !~ /^[ \t]*[|]/ && length(s) > 600) print f ": line " n " is " length(s) " characters, break it into one fact per bullet" }'
  for i in 2 3; do
    l=$(git show ":$f" | sed -n "${i}p")
    [ "$l" = "$(git show "HEAD:$f" 2>/dev/null | sed -n "${i}p")" ] && continue
    printf '%s\n' "$l" | awk -v f="$f" '
      /^keywords:/ && (n = split($0, k, ", ")) > 30 { print f ": keywords holds " n " entries, keep the 30 most searched" }
      /^index:/ && length($0) > 300 { print f ": index is " length($0) " characters, keep it under 300" }'
  done
done)
snap=$(mktemp -d) || exit 1
trap 'rm -rf "$snap"' EXIT
git checkout-index -a --prefix="$snap/" || exit 1
cd "$snap" || exit 1
tab=$(printf '\t')

errors=$(
  [ -z "$grown" ] || printf '%s\n' "$grown"
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

# Lets Claude Code read, edit and save notes without a prompt or an auto mode denial.
# Scoped to ~/tk and the skill's own scripts.
s="$HOME/.claude/settings.json"
if [ -d "$HOME/.claude" ] && command -v jq >/dev/null; then
  [ -s "$s" ] || echo '{}' > "$s"
  jq --arg h "$HOME" '
    (["Read(~/tk/**)", "Edit(~/tk/**)"]
      + (["add", "commit", "pull", "push", "status", "log", "diff", "show", "mv"] | map("Bash(git -C ~/tk \(.) *)"))
      + (["~", $h] | map("Bash(sh \(.)/.claude/skills/tribal-knowledge/*)"))) as $r
    | .permissions.allow = ((.permissions.allow // []) + ($r - (.permissions.allow // [])))
  ' "$s" > "$s.tmp"
  # Rewrite in place so the file keeps its mode.
  cmp -s "$s" "$s.tmp" || { cat "$s.tmp" > "$s"; echo "added ~/tk allow rules to $s"; }
  rm -f "$s.tmp"
fi
echo "tk ready at $TK"
