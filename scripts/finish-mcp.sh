#!/bin/bash
# One-shot: register the running brain + personal MCP daemons with Claude Code.
# Use when setup.sh's MCP-register step failed but the daemons are healthy.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TB=$(grep '^BRAIN_MCP_TOKEN=' "$SCRIPT_DIR/brain/.env" | cut -d= -f2-)
TP=$(grep '^PERSONAL_MCP_TOKEN=' "$SCRIPT_DIR/personal/.env" | cut -d= -f2-)
[ -z "$TB" ] && { echo "BRAIN_MCP_TOKEN not found in brain/.env"; exit 1; }
[ -z "$TP" ] && { echo "PERSONAL_MCP_TOKEN not found in personal/.env"; exit 1; }
claude mcp remove brain -s user 2>/dev/null || true
claude mcp remove personal -s user 2>/dev/null || true
claude mcp add --transport http -s user brain http://127.0.0.1:5050/mcp -H "Authorization: Bearer $TB"
claude mcp add --transport http -s user personal http://127.0.0.1:5051/mcp -H "Authorization: Bearer $TP"
echo
claude mcp list
