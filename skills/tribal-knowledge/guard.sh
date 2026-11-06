#!/bin/sh
# Agent hooks for ~/tk, wired up by tk-setup.sh. Every session shares one ~/tk checkout.
#   guard.sh               Claude Code PreToolUse on Bash, JSON on stdin. Blocks shell writes to notes,
#                          which force a re-read before the next edit, and git commands that discard
#                          other sessions' unsaved edits. Each simple command is judged by the paths
#                          and directory it acts on, so a command that only mentions ~/tk passes.
#   guard.sh stop          Claude Code Stop and SubagentStop, JSON on stdin. Blocks the end of a turn
#                          once while a note this agent edited is unsaved. Each agent answers for its
#                          own edits, so a parent never trips on a background subagent mid-edit.
#   guard.sh lint          Claude Code PostToolUse on Edit and Write, JSON on stdin (pi passes the
#                          same shape). Reports the size and frontmatter limits a just-written note
#                          breaks, so the agent fixes them now instead of at a blocked save.
#   guard.sh dirty <path>  Prints the given ~/tk paths that have unsaved changes (used by tk-guard.ts).
# Exit 2 hands stderr back to the agent.
set -u
tk="$HOME/tk"

dirty() { [ $# -gt 0 ] && git -C "$tk" status --porcelain -- "$@" 2>/dev/null | cut -c4-; }

case ${1:-} in
dirty) shift; dirty "$@"; exit 0 ;;
stop)
  in=$(cat)
  [ "$(printf '%s' "$in" | jq -r '.stop_hook_active // false')" = true ] && exit 0
  t=$(printf '%s' "$in" | jq -r '.agent_transcript_path // .transcript_path // empty')
  [ -f "$t" ] || exit 0
  real=$(cd "$tk" 2>/dev/null && pwd -P) || exit 0
  # Notes this agent changed with the file-edit tools, as paths inside ~/tk.
  # shellcheck disable=SC2046 # note paths hold no spaces
  left=$(dirty $(grep -F '"tool_use"' "$t" |
    jq -r '.message.content[]? | select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit")) | .input.file_path // empty' 2>/dev/null |
    sed -n -e "s#^$tk/##p" -e "s#^$real/##p" | sort -u))
  [ -n "$left" ] || exit 0
  echo "tk notes you edited are not saved: $(printf '%s\n' "$left" | paste -sd ' ' -). Save them with save.sh, or undo your edit with the Edit tool if it was a mistake." >&2
  exit 2 ;;
lint)
  f=$(jq -r '.tool_input.file_path // .tool_input.path // empty' | sed "s#^~/#$HOME/#")
  real=$(cd "$tk" 2>/dev/null && pwd -P) || exit 0
  case $f in "$tk"/*.md) r=${f#"$tk"/} ;; "$real"/*.md) r=${f#"$real"/} ;; *) exit 0 ;; esac
  case /$r in */.*) exit 0 ;; esac
  [ -f "$f" ] || exit 0
  # ponytail: repeats the pre-commit hook's limits (tk-setup.sh), keep the two in step.
  # Like the hook, it flags only what this edit adds past a limit, measured against HEAD.
  msg=$(git -C "$tk" show "HEAD:$r" 2>/dev/null | awk '
    FILENAME == "-" { if (FNR > 5) seen[$0]; if (FNR <= 3) head[FNR] = $0; if (FNR > 5) ob += length($0) + 1; next }
    FNR == 1 && $0 != "---" { print "line 1 must be ---" }
    FNR == 2 && $0 !~ /^keywords: \[.+\]$/ { print "line 2 must be keywords: [a, b]" }
    FNR == 2 && $0 != head[2] && (n = split($0, k, ", ")) > 30 { print "keywords holds " n " entries, keep the 30 most searched" }
    FNR == 3 && $0 !~ /^index: [^ ]/ { print "line 3 must be index: <one line>" }
    FNR == 3 && $0 != head[3] && length($0) - 7 > 300 { print "index is " length($0) - 7 " characters after \"index: \", keep it under 300" }
    FNR == 4 && $0 !~ /^votes: \[.*\]$/ { print "line 4 must be votes: [...]" }
    FNR == 5 && $0 != "---" { print "line 5 must be ---" }
    FNR > 5 { nb += length($0) + 1; if (!($0 in seen) && $0 !~ /^[ \t]*[|]/ && length($0) > 600) print "line " FNR " is " length($0) " characters, break it into one fact per bullet" }
    END { if (nb > 6000 && nb > ob) print "body is " int(nb / 1000) " KB, past 6 KB, move the section you edited into its own note" }
  ' - "$f")
  [ -n "$msg" ] || exit 0
  printf 'tk note %s breaks the limits save.sh enforces, fix it now:\n%s\n' "$r" "$msg" >&2
  exit 2 ;;
esac

in=$(cat)
cmd=$(printf '%s' "$in" | jq -r '.tool_input.command // empty')
dir=$(printf '%s' "$in" | jq -r '.cwd // empty')
[ -n "$dir" ] || dir=$PWD
real=$(cd "$tk" 2>/dev/null && pwd -P) || real=$tk

# A path as the shell would see it: ~ and a leading $HOME or variable set earlier in the command
# filled in, relative paths taken from the directory the last cd moved to. Anything it cannot
# fill in keeps its $.
abs() {
  p=$1 n=
  case $p in
  '${'*'}'*) n=${p#'${'} n=${n%%'}'*} ;;
  '$'[A-Za-z_]*) n=$(printf '%s' "${p#'$'}" | sed 's/[^A-Za-z0-9_].*//') ;;
  esac
  case $n in
  '' | *[!A-Za-z0-9_]*) ;;
  *)
    case $n in HOME) v=$HOME ;; *) eval "v=\${v_$n-}" ;; esac
    if [ -n "$v" ]; then case $p in '${'*) p=$v${p#*'}'} ;; *) p=$v${p#'$'"$n"} ;; esac; fi ;;
  esac
  case $p in '~') p=$HOME ;; '~/'*) p=$HOME/${p#'~/'} ;; /* | '$'*) ;; *) p=$dir/$p ;; esac
  printf '%s\n' "$p"
}
# Whether a path is in ~/tk. One still holding a variable counts when the part before the
# variable could lead into ~/tk and the command names ~/tk at all.
in_tk() {
  p=$(abs "$1")
  case $p in "$tk" | "$tk"/* | "$real" | "$real"/*) return 0 ;; *'$'*) ;; *) return 1 ;; esac
  pre=${p%%'$'*}
  case $pre in '' | */) ;; *) pre=${pre%/*}/ ;; esac
  case $tk/ in "$pre"*) [ -n "$named" ]; return ;; esac
  case $real/ in "$pre"*) [ -n "$named" ]; return ;; esac
  return 1
}
block() {
  case $1 in
  git) echo "tk guard: every session shares the ~/tk checkout, so git checkout, restore, reset, stash or clean there can discard other sessions' unsaved notes. Undo your own change with the Edit tool. save.sh commits only the paths you pass." >&2 ;;
  *) echo "tk guard: change notes in ~/tk with the Edit or Write tool, and votes with vote.sh. A shell write forces a re-read before your next edit and skips the permission rules scoped to ~/tk." >&2 ;;
  esac
  exit 2
}
# git [-C <dir>] checkout|restore|reset|stash|clean, judged by the directory it acts on.
git_check() {
  while [ $# -gt 0 ] && [ "$1" != git ]; do shift; done
  [ $# -gt 0 ] || return 0
  shift
  target=$dir
  [ "${1:-}" = -C ] && { target=${2:-}; shift 2; }
  case ${1:-} in checkout | restore | reset | stash | clean) in_tk "$target" && block git ;; esac
  return 0
}

named=
printf '%s\n' "$cmd" | grep -Fq -e '~/tk' -e '$HOME/tk' -e '${HOME}/tk' -e "$tk" -e "$real" && named=1
case $dir/ in "$tk"/* | "$real"/*) ;; *) [ -n "$named" ] || exit 0 ;; esac

# Python writes live in heredocs and quoted code, so they are matched on the raw text.
[ -n "$named" ] && printf '%s\n' "$cmd" | grep -Eq "write_text\(|open\([^)]*['\"][wax]\+?['\"]" && block write

# Everything else is judged one simple command at a time. A quoted word keeps its text, while
# quoted text with spaces or separators, such as a commit message or a search pattern, becomes Q.
set -f
segs=$(printf '%s\n' "$cmd" |
  sed -e "s/'\([^' ;|&()<>]*\)'/\1/g" -e 's/"\([^" ;|&()<>]*\)"/\1/g' -e "s/'[^']*'/Q/g" -e 's/"[^"]*"/Q/g' -e 's/&&/;/g' -e 's/||/;/g' |
  tr ';|&()' '\n\n\n  ')
while IFS= read -r s; do
  # shellcheck disable=SC2086 # word splitting is the point, globbing is off
  set -- $s
  [ $# -gt 0 ] || continue
  case $1 in
  cd) dir=$(abs "${2:-$HOME}"); continue ;;
  [A-Za-z_]*=*)
    n=${1%%=*}
    if [ $# -eq 1 ]; then
      case $n in *[!A-Za-z0-9_]*) ;; *) v=$(abs "${1#*=}"); eval "v_$n=\$v" ;; esac
      continue
    fi ;;
  esac
  git_check "$@"
  case " $s " in
  *' sed -i'* | *' perl -i'* | *' perl -pi'*)
    for w; do case $w in -* | sed | perl | Q) ;; *) in_tk "$w" && block write ;; esac; done ;;
  esac
  # Redirections and tee into a note. Targets outside ~/tk, such as /tmp, are fine.
  for w in $(printf '%s\n' "$s" | grep -Eo '(>>?|tee( -a)?)[[:space:]]*[^[:space:]>]+\.md' | sed -E 's/^(>>?|tee( -a)?)[[:space:]]*//'); do
    in_tk "$w" && block write
  done
done <<EOF
$segs
EOF
exit 0
