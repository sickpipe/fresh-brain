#!/usr/bin/env bash
# Fresh Brain Update Script
# Usage: ./scripts/update.sh
# Pulls latest changes and applies all pending migrations across all databases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MIGRATE="$SCRIPT_DIR/migrate.sh"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; }

trap 'if [ $? -ne 0 ]; then fail "Update aborted. Check messages above for details."; fi' EXIT

# --- Helpers ---
db_exists() { psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw "$1"; }

schema_version() {
    local db="$1"
    psql -d "$db" -tA -c \
        "SELECT coalesce(max(filename),'(none)') FROM applied_migrations" 2>/dev/null \
        || echo "(no applied_migrations table)"
}

# --- 1. Pre-flight checks ---
echo ""
info "=== Fresh Brain Update ==="
echo ""

# Git repo
if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "Not a git repository: $REPO_DIR"
    exit 1
fi
ok "Git repo detected"

# Clean working tree
if ! git -C "$REPO_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
    fail "Working tree has uncommitted changes. Commit or stash them first."
    exit 1
fi
if [ -n "$(git -C "$REPO_DIR" ls-files --others --exclude-standard)" ]; then
    warn "Untracked files present (continuing anyway)"
fi
ok "Working tree is clean"

# PostgreSQL
if ! pg_isready -q 2>/dev/null; then
    fail "PostgreSQL is not running (pg_isready failed)"
    exit 1
fi
ok "PostgreSQL is running"

# Detect which databases exist
DATABASES=()
for db_pair in "brain:brain" "personal:personal" "evenrail:evenrail_app"; do
    key="${db_pair%%:*}"
    dbname="${db_pair##*:}"
    if db_exists "$dbname"; then
        DATABASES+=("$key:$dbname")
        ok "Database '$dbname' found"
    else
        warn "Database '$dbname' not found — skipping"
    fi
done

if [ ${#DATABASES[@]} -eq 0 ]; then
    fail "No Fresh Brain databases found. Run setup.sh first."
    exit 1
fi

# Print current schema versions
echo ""
info "Current schema versions:"
for db_pair in "${DATABASES[@]}"; do
    dbname="${db_pair##*:}"
    ver=$(schema_version "$dbname")
    echo "  $dbname: $ver"
done

# --- 2. Git pull ---
echo ""
info "Pulling latest changes..."

BEFORE_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)

if ! git -C "$REPO_DIR" pull --ff-only 2>&1; then
    fail "git pull --ff-only failed. Your branch has diverged from the remote."
    fail "Resolve with: git rebase origin/<branch> or git merge origin/<branch>"
    exit 1
fi

AFTER_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)

if [ "$BEFORE_SHA" = "$AFTER_SHA" ]; then
    info "Already up to date ($(echo "$BEFORE_SHA" | head -c 8))"
    GIT_CHANGED=false
else
    ok "Updated $(echo "$BEFORE_SHA" | head -c 8) → $(echo "$AFTER_SHA" | head -c 8)"
    GIT_CHANGED=true
fi

# --- 3. Apply migrations ---
echo ""
info "Applying migrations..."

TOTAL_APPLIED=0
TOTAL_SKIPPED=0
MIGRATION_RESULTS=()

for db_pair in "${DATABASES[@]}"; do
    key="${db_pair%%:*}"
    dbname="${db_pair##*:}"

    # migrate.sh supports brain and personal; check if the target is supported
    if [ ! -x "$MIGRATE" ]; then
        warn "migrate.sh not found or not executable — skipping all migrations"
        break
    fi

    # migrate.sh accepts brain|personal; other targets are unsupported
    if [ "$key" != "brain" ] && [ "$key" != "personal" ]; then
        warn "$dbname ($key): not yet supported by migrate.sh — skipping"
        MIGRATION_RESULTS+=("$dbname: no migrate.sh support")
        continue
    fi

    OUTPUT=$("$MIGRATE" "$key" 2>&1) && RC=0 || RC=$?

    if [ $RC -ne 0 ]; then
        fail "Migration failed for $dbname:"
        echo "$OUTPUT" >&2
        exit 1
    fi

    # Parse counts from migrate.sh summary line (macOS-compatible)
    APPLIED=$(echo "$OUTPUT" | sed -n 's/.*applied \([0-9]*\).*/\1/p' | tail -1)
    SKIPPED=$(echo "$OUTPUT" | sed -n 's/.*skipped \([0-9]*\).*/\1/p' | tail -1)
    APPLIED="${APPLIED:-0}"
    SKIPPED="${SKIPPED:-0}"

    TOTAL_APPLIED=$((TOTAL_APPLIED + APPLIED))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + SKIPPED))
    MIGRATION_RESULTS+=("$dbname: applied=$APPLIED skipped=$SKIPPED")

    if [ "$APPLIED" -gt 0 ]; then
        ok "$dbname: $APPLIED migration(s) applied"
    else
        info "$dbname: up to date"
    fi
done

# --- 4. Post-flight ---
echo ""
info "New schema versions:"
for db_pair in "${DATABASES[@]}"; do
    dbname="${db_pair##*:}"
    ver=$(schema_version "$dbname")
    echo "  $dbname: $ver"
done

echo ""
info "=== Summary ==="
if [ "$GIT_CHANGED" = true ]; then
    COMMITS=$(git -C "$REPO_DIR" log --oneline "$BEFORE_SHA..$AFTER_SHA" | wc -l | tr -d ' ')
    ok "Pulled $COMMITS new commit(s)"
else
    info "No new commits"
fi

if [ "$TOTAL_APPLIED" -gt 0 ]; then
    ok "Applied $TOTAL_APPLIED migration(s) across ${#DATABASES[@]} database(s)"
else
    info "No pending migrations"
fi

if [ "$TOTAL_SKIPPED" -gt 0 ]; then
    info "$TOTAL_SKIPPED migration(s) already applied (skipped)"
fi

for result in "${MIGRATION_RESULTS[@]}"; do
    echo "  $result"
done

# --- 5. Restart MCP servers ---
if [ "$GIT_CHANGED" = true ] || [ "$TOTAL_APPLIED" -gt 0 ]; then
    echo ""
    info "Restarting MCP servers (code or schema changed)..."
    START_SCRIPT="$SCRIPT_DIR/start-mcp.sh"
    if [ -x "$START_SCRIPT" ]; then
        "$START_SCRIPT" --restart
    else
        warn "start-mcp.sh not found — restart servers manually"
    fi
else
    info "No changes — MCP servers left running"
fi

echo ""
ok "Update complete."
