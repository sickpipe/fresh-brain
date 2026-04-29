#!/usr/bin/env bash
# scripts/reset.sh — clean teardown of a Fresh Brain install
#
# Stops daemons, drops databases, removes Claude Code MCP entries, and
# deletes generated files (.venv, .env, mcp.pid/log). Each step is safe
# to re-run.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }

echo ""
echo "========================================="
echo "  Fresh Brain — Reset"
echo "========================================="
echo ""

# 1. Stop daemons
info "Stopping MCP daemons..."
for name in brain personal; do
    pid_file="$SCRIPT_DIR/$name/mcp.pid"
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            ok "killed $name (pid $pid)"
        fi
    fi
done
# Backup sweep for orphan processes
pkill -f 'fresh-brain.*mcp_server.py' 2>/dev/null || true
ok "daemons stopped"

# 2. Drop databases
info "Dropping databases..."
dropdb brain 2>/dev/null && ok "dropped brain" || ok "brain db absent"
dropdb personal 2>/dev/null && ok "dropped personal" || ok "personal db absent"

# 3. Remove MCP entries from Claude Code at all scopes
info "Removing Claude Code MCP entries..."
if command -v claude >/dev/null 2>&1; then
    for scope in user project local; do
        claude mcp remove brain    -s "$scope" 2>/dev/null || true
        claude mcp remove personal -s "$scope" 2>/dev/null || true
    done
    ok "MCP entries removed (all scopes)"
else
    warn "claude CLI not installed — skipping MCP entry removal"
fi

# 4. Delete venv and generated files
info "Removing generated files..."
rm -rf "$SCRIPT_DIR/.venv"
rm -f  "$SCRIPT_DIR/brain/.env"     "$SCRIPT_DIR/personal/.env"
rm -f  "$SCRIPT_DIR/brain/mcp.log"  "$SCRIPT_DIR/brain/mcp.pid"
rm -f  "$SCRIPT_DIR/personal/mcp.log" "$SCRIPT_DIR/personal/mcp.pid"
ok ".venv, .env files, and mcp.{log,pid} removed"

echo ""
echo "Reset complete. Run ./setup.sh to reinstall."
echo ""
