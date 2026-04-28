#!/bin/bash
# brain/hooks/user-prompt-inject.sh
# UserPromptSubmit hook for Claude Code.
# Fires on every user prompt. Searches the brain for relevant context
# and injects the top matches into the conversation automatically.
#
# Install in ~/.claude/settings.json:
#   "hooks": {
#     "UserPromptSubmit": [{
#       "type": "command",
#       "command": "/path/to/brain/hooks/user-prompt-inject.sh"
#     }]
#   }
#
# Reads: $PROMPT (set by Claude Code's hook system)
# Writes: context block to stdout (injected into conversation)
# Exit 0 = inject, Exit 0 with no output = skip

set -euo pipefail

BRAIN_URL="${BRAIN_MCP_URL:-http://127.0.0.1:5050}"
BRAIN_TOKEN="${BRAIN_MCP_TOKEN:?BRAIN_MCP_TOKEN not set}"

PROMPT="${PROMPT:-}"
if [ -z "$PROMPT" ] || [ ${#PROMPT} -lt 5 ]; then
    exit 0
fi

# Truncate prompt to first 500 chars for the search query
QUERY=$(printf '%s' "$PROMPT" | head -c 500)

# Build JSON body safely via python (avoids shell quoting issues)
JSON_BODY=$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1], "limit": 3}))' "$QUERY")

# Call /context-inject with 3-second timeout. Fail silently on error.
RESPONSE=$(curl -s --max-time 3 \
    -X POST "${BRAIN_URL}/context-inject" \
    -H "Authorization: Bearer ${BRAIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY" 2>/dev/null) || exit 0

# Parse response, check threshold, format output — all in one python call
printf '%s' "$RESPONSE" | python3 -c '
import sys, json

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

results = d.get("results", [])
if not results:
    sys.exit(0)

# Skip if best match is too distant (>0.45 = not relevant enough)
distances = [r.get("distance", 1.0) for r in results]
if min(distances) > 0.55:
    sys.exit(0)

lines = []
lines.append(f"--- Brain Context (auto-injected, {len(results)} matches) ---")
for r in results:
    table = r.get("source_table", "?")
    slug = r.get("slug", "?")
    dist = r.get("distance", 1.0)
    title = r.get("title") or r.get("display_name") or slug
    preview = r.get("body_preview", "")
    lines.append(f"**[{table}/{slug}]** (relevance: {1-dist:.0%}) -- {title}")
    if preview:
        lines.append(preview[:600])
    lines.append("")
lines.append("---")
print("\n".join(lines))
'
