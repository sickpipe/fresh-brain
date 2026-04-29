#!/usr/bin/env bash
# scripts/start-mcp.sh — idempotent launcher for brain + personal MCP daemons
#
# Starts each Flask MCP server as a background daemon if it isn't already
# running, writing PID + log files into the server's own directory and
# polling /health until the process answers.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VENV_PY="$SCRIPT_DIR/.venv/bin/python"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    fail ".venv not found at $SCRIPT_DIR/.venv — run ./setup.sh first"
fi
if [ ! -x "$VENV_PY" ]; then
    fail "Python interpreter missing at $VENV_PY — venv looks broken, try ./scripts/reset.sh"
fi

start_server() {
    local name="$1" port="$2"
    local dir="$SCRIPT_DIR/$name"
    local pid_file="$dir/mcp.pid"
    local log_file="$dir/mcp.log"
    local script="$dir/mcp_server.py"

    if [ ! -f "$script" ]; then
        fail "$name: server script not found at $script"
    fi

    # Already running?
    if [ -f "$pid_file" ]; then
        local existing
        existing=$(cat "$pid_file" 2>/dev/null || echo "")
        if [ -n "$existing" ] && kill -0 "$existing" 2>/dev/null; then
            ok "$name already running (pid $existing)"
            return 0
        fi
    fi

    info "Starting $name MCP server on port $port..."
    nohup "$VENV_PY" "$script" > "$log_file" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$pid_file"

    # Health check loop
    local i=0
    while [ "$i" -lt 30 ]; do
        if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
            ok "$name healthy (pid $new_pid)"
            return 0
        fi
        # Bail early if process already died
        if ! kill -0 "$new_pid" 2>/dev/null; then
            warn "$name process exited before becoming healthy — last log lines:"
            tail -n 20 "$log_file" || true
            fail "$name failed to start"
        fi
        sleep 1
        i=$((i + 1))
    done

    warn "$name did not respond on /health within 30s — last log lines:"
    tail -n 20 "$log_file" || true
    fail "$name health check timed out"
}

start_server "brain"    5050
start_server "personal" 5051

echo ""
echo "MCP daemons running:"
for name in brain personal; do
    pid_file="$SCRIPT_DIR/$name/mcp.pid"
    log_file="$SCRIPT_DIR/$name/mcp.log"
    if [ -f "$pid_file" ]; then
        echo "  $name  pid=$(cat "$pid_file")  log=$log_file"
    fi
done
