#!/usr/bin/env bash
set -euo pipefail

# Fresh Brain — Portable AI Orchestration Setup
# Creates and configures two databases: brain and personal.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRAIN_SCHEMA="$SCRIPT_DIR/brain/schema.sql"
PERSONAL_SCHEMA="$SCRIPT_DIR/personal/schema.sql"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

echo ""
echo "========================================="
echo "  Fresh Brain — Setup"
echo "========================================="
echo ""

# ── 1. Interactive questions ──────────────────────────────────

read -rp "What's your name? (e.g., Alex): " USER_NAME
read -rp "What's your title/role? (e.g., Captain): " USER_TITLE
read -rp "What's your timezone? (e.g., America/New_York): " USER_TZ
read -rp "What should the AI call you? (e.g., Captain): " AI_ADDRESS

echo ""

# ── 2. Prerequisites ─────────────────────────────────────────

info "Checking prerequisites..."

# PostgreSQL running
if pg_isready -q 2>/dev/null; then
    ok "PostgreSQL is running"
else
    fail "PostgreSQL is not running. Start it and try again."
fi

# pgvector extension
if psql -d postgres -tAc "SELECT 1 FROM pg_available_extensions WHERE name='vector'" 2>/dev/null | grep -q 1; then
    ok "pgvector extension available"
else
    fail "pgvector extension not found. Install it: brew install pgvector (macOS) or see https://github.com/pgvector/pgvector"
fi

# Python 3
if command -v python3 &>/dev/null; then
    ok "Python 3 found: $(python3 --version 2>&1)"
else
    fail "Python 3 not found. Install it and try again."
fi

# Optional Python packages (warn only)
for pkg in psycopg2 sentence_transformers; do
    if python3 -c "import $pkg" 2>/dev/null; then
        ok "Python package: $pkg"
    else
        warn "Python package '$pkg' not installed (needed for MCP servers)"
    fi
done

# Schema files exist
for f in "$BRAIN_SCHEMA" "$PERSONAL_SCHEMA"; do
    [ -f "$f" ] || fail "Schema file not found: $f"
done
ok "All schema files present"

echo ""

# ── 3. Create databases ──────────────────────────────────────

DATABASES=("brain" "personal")
CREATED=()
SKIPPED=()

for db in "${DATABASES[@]}"; do
    if psql -lqt 2>/dev/null | cut -d\| -f1 | grep -qw "$db"; then
        warn "Database '$db' already exists."
        read -rp "  Drop and recreate? (y/N): " answer
        if [[ "${answer,,}" == "y" ]]; then
            dropdb "$db"
            createdb "$db"
            CREATED+=("$db")
        else
            SKIPPED+=("$db")
        fi
    else
        createdb "$db"
        CREATED+=("$db")
    fi
done

echo ""

# ── 4. Apply schemas ─────────────────────────────────────────

apply_schema() {
    local db="$1" schema="$2" label="$3"
    # Skip if database was skipped (already existed, user said no)
    for s in "${SKIPPED[@]+"${SKIPPED[@]}"}"; do
        [[ "$s" == "$db" ]] && { warn "Skipping schema for $label (database not recreated)"; return; }
    done
    info "Applying schema to $label ($db)..."
    psql -d "$db" -f "$schema" -q 2>&1 | grep -v "^$" || true
    ok "$label schema applied"
}

apply_schema "brain"    "$BRAIN_SCHEMA"    "Brain"
apply_schema "personal" "$PERSONAL_SCHEMA" "Personal"

echo ""

# ── 5. Seed data ────────────────────────────────────────────

# Brain seed data (team members, standing orders, topic docs)
if ! printf '%s\n' "${SKIPPED[@]+"${SKIPPED[@]}"}" | grep -qx "brain"; then
    info "Seeding Brain data..."
    psql -d brain -f "$SCRIPT_DIR/brain/seed.sql" -q 2>&1 | grep -v "^$" || true
    ok "Brain seed data loaded"

    info "Seeding Brain config..."
    psql -d brain -q <<EOSQL
INSERT INTO brain_config (key, value, description) VALUES
    ('operator_name',  '${USER_NAME//\'/\'\'}',    'Operator name'),
    ('operator_title', '${USER_TITLE//\'/\'\'}',   'Operator role/title'),
    ('timezone',       '${USER_TZ//\'/\'\'}',      'Default timezone'),
    ('ai_address',     '${AI_ADDRESS//\'/\'\'}',   'How the AI addresses the operator')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, description = EXCLUDED.description;
EOSQL
    ok "Brain config seeded"
fi

# Personal seed data
if ! printf '%s\n' "${SKIPPED[@]+"${SKIPPED[@]}"}" | grep -qx "personal"; then
    info "Seeding Personal data..."
    psql -d personal -f "$SCRIPT_DIR/personal/seed.sql" -q 2>&1 | grep -v "^$" || true

    info "Seeding Personal config..."
    psql -d personal -q <<EOSQL
INSERT INTO personal_config (key, value, description) VALUES
    ('owner_name',     '${USER_NAME//\'/\'\'}',       'Database owner'),
    ('timezone',       '${USER_TZ//\'/\'\'}',         'Default timezone'),
    ('database_name',  'personal',                     'Canonical database identifier')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, description = EXCLUDED.description;
EOSQL
    ok "Personal config seeded"
fi

echo ""

# ── 6. Summary ────────────────────────────────────────────────

echo "========================================="
echo "  Setup Complete"
echo "========================================="
echo ""

if [ ${#CREATED[@]} -gt 0 ]; then
    echo -e "${GREEN}Created:${NC}"
    for db in "${CREATED[@]}"; do echo "  - $db"; done
fi
if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped (already existed):${NC}"
    for db in "${SKIPPED[@]}"; do echo "  - $db"; done
fi

echo ""
echo "Operator: $USER_NAME ($USER_TITLE)"
echo "Timezone: $USER_TZ"
echo "AI address: $AI_ADDRESS"
echo ""
echo "Next steps:"
echo "  1. Install Python dependencies:"
echo "     pip install -r brain/requirements.txt"
echo "     pip install -r personal/requirements.txt"
echo "  2. Copy .env.example files to .env and fill in your values:"
echo "     cp brain/.env.example brain/.env"
echo "     cp personal/.env.example personal/.env"
echo "  3. Configure MCP servers in ~/.claude.json (see README.md)"
echo "  4. Restart Claude Code"
echo "  5. The orchestrator will detect a fresh brain and walk you through onboarding"
echo ""
echo "Your Fresh Brain is ready."
