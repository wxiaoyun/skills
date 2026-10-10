#!/bin/sh
# Runs tk-usage.py on fake Claude Code and pi session logs and checks the per-note counts.
set -eu

py="$(cd "$(dirname "$0")" && pwd)/tk-usage.py"
export HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/tk/tools" "$HOME/.claude/projects/p" "$HOME/.pi/agent/sessions/s"
seq 10 > "$HOME/tk/tools/hot.md"
seq 3 > "$HOME/tk/tools/listed.md"
seq 3 > "$HOME/tk/tools/cold.md"

cat > "$HOME/.claude/projects/p/a.jsonl" <<EOF
{"type":"assistant","timestamp":"2026-10-10T00:00:00Z","message":{"content":[{"type":"tool_use","id":"1","name":"Read","input":{"file_path":"$HOME/tk/tools/hot.md"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"1","content":"xxxxxxxxxx"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"2","name":"Bash","input":{"command":"rg -il '^keywords:.*x' ~/tk | xargs -r rg -H -m2 '^(index|votes):'"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"2","content":"$HOME/tk/tools/listed.md:index: i"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"3","name":"Edit","input":{"file_path":"$HOME/tk/tools/hot.md","old_string":"1","new_string":"one"}}]}}
EOF
cat > "$HOME/.pi/agent/sessions/s/b.jsonl" <<EOF
{"type":"message","timestamp":"2026-10-10T00:00:00Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"4","name":"bash","arguments":{"command":"cd ~/tk && sed -n 1,5p tools/hot.md"}}]}}
{"type":"message","message":{"role":"toolResult","toolCallId":"4","content":[{"type":"text","text":"yyyyy"}]}}
EOF

out=$(python3 "$py")
row() { echo "$out" | awk -v n="$1" '$NF == n { print $3, $4, $5, $6, $7 }'; }
check() { [ "$(row "$1")" = "$2" ] || { echo "FAIL: $1: got '$(row "$1")', want '$2'"; echo "$out"; exit 1; }; }
check tools/hot.md '2 2 1 0 1'
check tools/listed.md '0 0 0 1 0'
echo "$out" | grep -q '^2 of 3 notes were never read' || { echo "FAIL: cold count"; echo "$out"; exit 1; }
echo ok
