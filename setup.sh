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

# ── 5b. Seed applied_migrations ledger ──────────────────────
# schema.sql contains the full baseline state, so every migration file
# shipped in the template is already represented. Backfill the runner's
# ledger so `./scripts/migrate.sh` won't try to re-apply them.

seed_applied_migrations() {
    local db="$1" mig_dir="$2"
    [ -d "$mig_dir" ] || return 0
    for f in "$mig_dir"/*.sql; do
        [ -e "$f" ] || continue
        local fname
        fname=$(basename "$f")
        psql -d "$db" -q -c \
            "INSERT INTO applied_migrations (filename) VALUES ('$fname') ON CONFLICT (filename) DO NOTHING" \
            > /dev/null
    done
}

if ! printf '%s\n' "${SKIPPED[@]+"${SKIPPED[@]}"}" | grep -qx "brain"; then
    info "Seeding Brain applied_migrations ledger..."
    seed_applied_migrations "brain" "$SCRIPT_DIR/brain/migrations"
    ok "Brain applied_migrations seeded"
fi

if ! printf '%s\n' "${SKIPPED[@]+"${SKIPPED[@]}"}" | grep -qx "personal"; then
    info "Seeding Personal applied_migrations ledger..."
    seed_applied_migrations "personal" "$SCRIPT_DIR/personal/migrations"
    ok "Personal applied_migrations seeded"
fi

echo ""

# ── 6. Python environment ───────────────────────────────────
# Build a project-local venv and install both requirements.txt files into
# it. Re-runnable: keeps an existing venv if Python >= 3.10, otherwise
# rebuilds. pip output is intentionally not silenced — first install is
# slow because torch is a multi-hundred-MB download.

VENV_DIR="$SCRIPT_DIR/.venv"

needs_new_venv=true
if [ -x "$VENV_DIR/bin/python" ]; then
    venv_ver=$("$VENV_DIR/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo "0.0")
    venv_major=${venv_ver%%.*}
    venv_minor=${venv_ver##*.}
    if [ "$venv_major" -ge 3 ] && [ "$venv_minor" -ge 10 ]; then
        ok "Reusing existing venv (Python $venv_ver) at .venv"
        needs_new_venv=false
    else
        warn "Existing .venv uses Python $venv_ver (need 3.10+) — recreating"
        rm -rf "$VENV_DIR"
    fi
fi

if [ "$needs_new_venv" = true ]; then
    info "Creating Python virtualenv at .venv..."
    python3 -m venv "$VENV_DIR"
    ok "venv created"
fi

VENV_PY="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"

info "Upgrading pip in venv..."
"$VENV_PIP" install --upgrade pip

info "Installing brain + personal Python dependencies (this can take a few minutes — torch is large)..."
"$VENV_PIP" install -r "$SCRIPT_DIR/brain/requirements.txt" -r "$SCRIPT_DIR/personal/requirements.txt"
ok "Python dependencies installed"

echo ""

# ── 7. Configure environment files ──────────────────────────
# Write brain/.env and personal/.env with random tokens. If a .env already
# exists, prompt before overwriting and recover the existing token from
# the file so MCP registration in step 9 uses the live value.

write_env_file() {
    # write_env_file <path> <body>
    local path="$1" body="$2"
    printf '%s\n' "$body" > "$path"
}

short_token() {
    # First 8 chars only — never echo the full secret
    echo "${1:0:8}…"
}

read_env_var() {
    # read_env_var <file> <key> -> stdout: value (empty if missing)
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    grep -E "^${key}=" "$file" | head -n 1 | cut -d= -f2- || true
}

BRAIN_ENV="$SCRIPT_DIR/brain/.env"
PERSONAL_ENV="$SCRIPT_DIR/personal/.env"

# ── brain/.env ─────────────────────────────────────────────
brain_overwrite=true
if [ -f "$BRAIN_ENV" ]; then
    read -rp "  Overwrite brain/.env? (y/N): " ans
    if [[ "${ans,,}" != "y" ]]; then
        brain_overwrite=false
        existing_token=$(read_env_var "$BRAIN_ENV" "BRAIN_MCP_TOKEN")
        if [ -n "$existing_token" ]; then
            BRAIN_MCP_TOKEN="$existing_token"
            ok "Reusing existing brain/.env (token: $(short_token "$BRAIN_MCP_TOKEN"))"
        else
            warn "Existing brain/.env has no BRAIN_MCP_TOKEN — generating a new one and overwriting"
            brain_overwrite=true
        fi
    fi
fi

if [ "$brain_overwrite" = true ]; then
    BRAIN_MCP_TOKEN=$(openssl rand -hex 32)
    write_env_file "$BRAIN_ENV" "DATABASE_BRAIN_APP_URL=postgresql://localhost/brain
BRAIN_MCP_TOKEN=$BRAIN_MCP_TOKEN
BRAIN_MCP_PORT=5050"
    ok "Wrote brain/.env (token: $(short_token "$BRAIN_MCP_TOKEN"))"
fi

# ── personal/.env ─────────────────────────────────────────
personal_overwrite=true
if [ -f "$PERSONAL_ENV" ]; then
    read -rp "  Overwrite personal/.env? (y/N): " ans
    if [[ "${ans,,}" != "y" ]]; then
        personal_overwrite=false
        existing_token=$(read_env_var "$PERSONAL_ENV" "PERSONAL_MCP_TOKEN")
        existing_secret=$(read_env_var "$PERSONAL_ENV" "SECRET_KEY")
        if [ -n "$existing_token" ]; then
            PERSONAL_MCP_TOKEN="$existing_token"
            PERSONAL_SECRET_KEY="${existing_secret:-$(openssl rand -hex 32)}"
            ok "Reusing existing personal/.env (token: $(short_token "$PERSONAL_MCP_TOKEN"))"
        else
            warn "Existing personal/.env has no PERSONAL_MCP_TOKEN — generating new and overwriting"
            personal_overwrite=true
        fi
    fi
fi

if [ "$personal_overwrite" = true ]; then
    PERSONAL_MCP_TOKEN=$(openssl rand -hex 32)
    PERSONAL_SECRET_KEY=$(openssl rand -hex 32)
    write_env_file "$PERSONAL_ENV" "DATABASE_PERSONAL_APP_URL=postgresql://localhost/personal
DATABASE_BRAIN_APP_URL=postgresql://localhost/brain
SECRET_KEY=$PERSONAL_SECRET_KEY
PORT=5001
PERSONAL_MCP_TOKEN=$PERSONAL_MCP_TOKEN
PERSONAL_MCP_PORT=5051"
    ok "Wrote personal/.env (token: $(short_token "$PERSONAL_MCP_TOKEN"))"
fi

echo ""

# ── 8. Summary ────────────────────────────────────────────────

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
