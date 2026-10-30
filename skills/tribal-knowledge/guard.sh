#!/bin/sh
# Agent hooks for ~/tk, wired up by tk-setup.sh. Every session shares one ~/tk checkout.
#   guard.sh               Claude Code PreToolUse on Bash, JSON on stdin. Blocks shell writes to notes,
#                          which force a re-read before the next edit, and git commands that discard
#                          other sessions' unsaved edits.
#   guard.sh stop          Claude Code Stop and SubagentStop, JSON on stdin. Blocks the end of a turn
#                          once while a note this agent edited is unsaved. Each agent answers for its
#                          own edits, so a parent never trips on a background subagent mid-edit.
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
esac

cmd=$(jq -r '.tool_input.command // empty')
real=$(cd "$tk" 2>/dev/null && pwd -P) || real=$tk
printf '%s\n' "$cmd" | grep -Fq -e '~/tk' -e '$HOME/tk' -e '${HOME}/tk' -e "$tk" -e "$real" || exit 0
# Quoted text, such as a commit message, cannot be a git subcommand.
bare=$(printf '%s\n' "$cmd" | sed -e "s/'[^']*'/Q/g" -e 's/"[^"]*"/Q/g')
if printf '%s\n' "$bare" | grep -Eq '(^|[^[:alnum:]_-])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(checkout|restore|reset|stash|clean)([[:space:]]|$)'; then
  echo "tk guard: every session shares the ~/tk checkout, so git checkout, restore, reset, stash or clean there can discard other sessions' unsaved notes. Undo your own change with the Edit tool. save.sh commits only the paths you pass." >&2
  exit 2
fi
if printf '%s\n' "$cmd" | grep -Eq "sed -i|perl -i|write_text\(|open\([^)]*['\"][wax]\+?['\"]" ||
  printf '%s\n' "$cmd" | grep -Eo '(>>?|tee( -a)?)[[:space:]]*[^[:space:]&|;]+\.md' | grep -Evq '[[:space:]>](/tmp/|/dev/)'; then
  echo "tk guard: change notes in ~/tk with the Edit or Write tool, and votes with vote.sh. A shell write forces a re-read before your next edit and skips the permission rules scoped to ~/tk." >&2
  exit 2
fi
exit 0
