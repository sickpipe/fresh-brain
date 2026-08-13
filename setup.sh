#!/usr/bin/env bash
set -euo pipefail

# Fresh Brain — Portable AI Orchestration Setup
# Creates and configures two databases: brain and personal.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRAIN_SCHEMA="$SCRIPT_DIR/brain/schema.sql"
PERSONAL_SCHEMA="$SCRIPT_DIR/personal/schema.sql"

# Postgres connection settings. psql/createdb/dropdb honor these natively;
# we read them once so we can also bake them into the .env DSNs in section 7.
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
export PGHOST PGPORT

# Build a DSN that omits the port when it's the default (cleaner) and
# includes it otherwise. Used by .env writers below.
pg_dsn() {
    local db="$1"
    if [ "$PGPORT" = "5432" ]; then
        echo "postgresql://${PGHOST}/${db}"
    else
        echo "postgresql://${PGHOST}:${PGPORT}/${db}"
    fi
}

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

# Shared Claude Code layer installer (skills, global CLAUDE.md, auto-memory).
# Also sourced by scripts/update.sh so install and update can't drift.
# shellcheck source=scripts/lib/claude-layer.sh
. "$SCRIPT_DIR/scripts/lib/claude-layer.sh"

echo ""
echo "========================================="
echo "  Fresh Brain — Setup"
echo "========================================="
echo ""

# ── 1. Interactive questions ──────────────────────────────────

read -rp "What's your name? (e.g., Alex): " USER_NAME
read -rp "What's your title/role? (e.g., Founder): " USER_TITLE
read -rp "What's your timezone? (e.g., America/New_York): " USER_TZ
read -rp "What should the AI call you? (e.g., Boss): " AI_ADDRESS

echo ""
read -rp "What would you like to call your personal dashboard? (default: Personal): " PERSONAL_DB_NAME
PERSONAL_DB_NAME="${PERSONAL_DB_NAME:-Personal}"
read -rp "Personal dashboard URL? (default: http://127.0.0.1:5001): " PERSONAL_DB_URL
PERSONAL_DB_URL="${PERSONAL_DB_URL:-http://127.0.0.1:5001}"

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
if command -v python3 >/dev/null 2>&1; then
    ok "Python 3 found: $(python3 --version 2>&1)"
else
    fail "Python 3 not found. Install it and try again."
fi

# Platform-aware Python selection.
#
# Two distinct macOS edge cases require falling back to brew's python@3.12:
#
#   1. Default python3 is x86_64 on macOS with version >= 3.13.
#      PyTorch dropped x86_64 macOS support after 2.2.x, and torch 2.2.x has
#      no Python 3.13 wheels. This hits both real Intel Macs AND Apple
#      Silicon Macs whose `python3` came from a Rosetta/Intel brew at
#      /usr/local/ — `uname -m` says arm64 but the Python binary is x86_64.
#      So we check Python's architecture (platform.machine()), not the
#      hardware's (uname -m).
#
#   2. Default python3 is too old (< 3.10) on macOS. Fresh Brain itself
#      requires 3.10+. Same fallback path: prefer brew's python@3.12.
#
# In both cases the fix is identical — locate python@3.12 under whichever
# brew prefix exists (Apple Silicon /opt/homebrew or Intel/Rosetta
# /usr/local) and use it.
PYTHON_BIN="python3"
sys_os="$(uname -s)"
default_py_ver=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo "0.0")
default_py_major=${default_py_ver%%.*}
default_py_minor=${default_py_ver##*.}
# Architecture of the running Python interpreter (NOT of the hardware).
# Returns x86_64 if Python is Rosetta/Intel-compiled, arm64 if native
# Apple Silicon, etc. This is the canonical way and works on Linux too.
default_py_arch=$(python3 -c 'import platform;print(platform.machine())' 2>/dev/null || echo "unknown")

# find_brew_py312: echo path to a brew-installed python@3.12 if one
# exists under either prefix; print nothing otherwise.
find_brew_py312() {
    for p in /opt/homebrew/opt/python@3.12/libexec/bin/python3 \
             /usr/local/opt/python@3.12/libexec/bin/python3; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

needs_py312_fallback=false
fallback_reason=""

# Case 1: macOS + x86_64 Python + Python >= 3.13 -> torch unavailable
if [ "$sys_os" = "Darwin" ] && [ "$default_py_arch" = "x86_64" ] \
   && [ "$default_py_major" -ge 3 ] && [ "$default_py_minor" -ge 13 ]; then
    needs_py312_fallback=true
    fallback_reason="x86_64 Python 3.13+ on macOS — PyTorch dropped x86_64 macOS support after 2.2.x, and torch 2.2.x has no Python 3.13 wheels"
fi

# Case 2: macOS + Python < 3.10 (regardless of architecture) -> Fresh Brain itself needs 3.10+
if [ "$sys_os" = "Darwin" ] && \
   { [ "$default_py_major" -lt 3 ] || \
     { [ "$default_py_major" -eq 3 ] && [ "$default_py_minor" -lt 10 ]; }; }; then
    needs_py312_fallback=true
    fallback_reason="default python3 is $default_py_ver (Fresh Brain requires 3.10+)"
fi

if [ "$needs_py312_fallback" = true ]; then
    if brew_py312=$(find_brew_py312); then
        PYTHON_BIN="$brew_py312"
        ok "Using $brew_py312 — $fallback_reason"
    else
        fail "$fallback_reason.

       Fresh Brain's brain server uses local embeddings via
       sentence-transformers, which requires torch. The supported workaround
       is to install python@3.12 via Homebrew:

           brew install python@3.12

       After installing, re-run ./setup.sh. setup.sh will look for
       python@3.12 under either brew prefix:
           /opt/homebrew/opt/python@3.12/libexec/bin/python3   (Apple Silicon brew)
           /usr/local/opt/python@3.12/libexec/bin/python3      (Intel/Rosetta brew)"
    fi
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
        case "$answer" in
            [yY]|[yY][eE][sS])
                dropdb "$db"
                createdb "$db"
                CREATED+=("$db")
                ;;
            *)
                SKIPPED+=("$db")
                ;;
        esac
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
    ('operator_name',              '${USER_NAME//\'/\'\'}',          'Operator name'),
    ('operator_title',             '${USER_TITLE//\'/\'\'}',         'Operator role/title'),
    ('timezone',                   '${USER_TZ//\'/\'\'}',            'Default timezone'),
    ('ai_address',                 '${AI_ADDRESS//\'/\'\'}',         'How the AI addresses the operator'),
    ('personal_db_display_name',   '${PERSONAL_DB_NAME//\'/\'\'}',  'Display name for the personal database'),
    ('personal_db_app_url',        '${PERSONAL_DB_URL//\'/\'\'}',   'Personal dashboard URL')
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
    info "Creating Python virtualenv at .venv (using $PYTHON_BIN)..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
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
    ans_lc=$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')
    if [ "$ans_lc" != "y" ] && [ "$ans_lc" != "yes" ]; then
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
    write_env_file "$BRAIN_ENV" "DATABASE_BRAIN_APP_URL=$(pg_dsn brain)
BRAIN_MCP_TOKEN=$BRAIN_MCP_TOKEN
BRAIN_MCP_PORT=5050"
    ok "Wrote brain/.env (token: $(short_token "$BRAIN_MCP_TOKEN"))"
fi

# ── personal/.env ─────────────────────────────────────────
personal_overwrite=true
if [ -f "$PERSONAL_ENV" ]; then
    read -rp "  Overwrite personal/.env? (y/N): " ans
    ans_lc=$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')
    if [ "$ans_lc" != "y" ] && [ "$ans_lc" != "yes" ]; then
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
    write_env_file "$PERSONAL_ENV" "DATABASE_PERSONAL_APP_URL=$(pg_dsn personal)
DATABASE_BRAIN_APP_URL=$(pg_dsn brain)
SECRET_KEY=$PERSONAL_SECRET_KEY
PORT=5001
PERSONAL_MCP_TOKEN=$PERSONAL_MCP_TOKEN
PERSONAL_MCP_PORT=5051"
    ok "Wrote personal/.env (token: $(short_token "$PERSONAL_MCP_TOKEN"))"
fi

echo ""

# ── 8. Start MCP servers ────────────────────────────────────
# Launch logic lives in scripts/start-mcp.sh so it can also be invoked
# standalone (e.g. after a reboot).

info "Launching MCP daemons..."
bash "$SCRIPT_DIR/scripts/start-mcp.sh"

echo ""

# ── 9. Register with Claude Code ────────────────────────────
# Use `claude mcp add` so the operator doesn't have to hand-edit
# ~/.claude.json. User scope is deliberate (roaming, available in
# every working directory).
#
# Set FRESH_BRAIN_SKIP_MCP_REGISTER=1 to bypass this section — useful
# when running a sandbox install on a host that already has production
# brain/personal entries at user scope (e.g. test harness on the
# operator's main machine).

if [ "${FRESH_BRAIN_SKIP_MCP_REGISTER:-0}" = "1" ]; then
    warn "FRESH_BRAIN_SKIP_MCP_REGISTER=1 — skipping Claude Code MCP registration"
elif command -v claude >/dev/null 2>&1; then
    info "Registering MCP servers with Claude Code (user scope)..."

    # brain — name and URL must come BEFORE -H (variadic flag would eat them)
    claude mcp remove brain -s user 2>/dev/null || true
    claude mcp add --transport http -s user \
        brain http://127.0.0.1:5050/mcp \
        -H "Authorization: Bearer $BRAIN_MCP_TOKEN"
    ok "registered brain"

    # personal — same ordering as brain above
    claude mcp remove personal -s user 2>/dev/null || true
    claude mcp add --transport http -s user \
        personal http://127.0.0.1:5051/mcp \
        -H "Authorization: Bearer $PERSONAL_MCP_TOKEN"
    ok "registered personal"

    echo ""
    info "Verifying MCP registration:"
    claude mcp list 2>/dev/null | grep -E "(brain|personal)" || warn "claude mcp list returned no brain/personal entries"
else
    warn "claude CLI not found — skipping automatic MCP registration."
    echo "  Install Claude Code, then run these manually:"
    echo "    claude mcp add --transport http -s user brain http://127.0.0.1:5050/mcp -H \"Authorization: Bearer \$BRAIN_MCP_TOKEN\""
    echo "    claude mcp add --transport http -s user personal http://127.0.0.1:5051/mcp -H \"Authorization: Bearer \$PERSONAL_MCP_TOKEN\""
fi

echo ""

# ── 10. Install the Claude Code layer ────────────────────────
# Two halves, both handled by scripts/lib/claude-layer.sh:
#
#   Summoned half — the /brain and /end-session skills, copied into
#   ~/.claude/skills/. Interactive here: prompt before replacing a skill
#   the operator may have customized.
#
#   Plain half — a sentinel-delimited block in the GLOBAL ~/.claude/CLAUDE.md
#   (the only file loaded in every working directory) carrying the opt-in
#   model and the brain/personal routing map, plus a create-if-absent
#   auto-memory seed under ~/.claude/projects/<slug>/memory/.

info "Installing operator skills (/brain, /end-session)..."
install_operator_skills "$SCRIPT_DIR" interactive

echo ""

info "Installing global Claude Code instructions (~/.claude/CLAUDE.md)..."
install_global_claude_md

echo ""

info "Seeding Claude Code auto-memory..."
seed_auto_memory

echo ""

# ── 11. Generate root CLAUDE.md ──────────────────────────────
# Repo-scoped pointer only. The working model lives in the global
# ~/.claude/CLAUDE.md written above; this file exists so anyone working
# *inside the repo* gets the repo-local operational notes without paying
# for them in every unrelated session.

info "Generating root CLAUDE.md (repo notes)..."
install_repo_claude_md "$SCRIPT_DIR"

echo ""

# ── 12. Summary ───────────────────────────────────────────────

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
echo "  1. Restart Claude Code (Cmd+Q then reopen) so it picks up the new MCP servers and skills."
echo "  2. Open any directory and type /brain — the orchestrator will detect a fresh brain and walk you through onboarding."
echo "  3. When you're done working, type /end-session to write the handoff. Plain Claude Code is the default between summons."
echo ""
echo "Claude Code layer installed:"
echo "  Skills:        ~/.claude/skills/{brain,end-session}"
echo "  Global rules:  ~/.claude/CLAUDE.md (FRESH BRAIN block — loads in every directory)"
echo "  Auto-memory:   ~/.claude/projects/$(fb_project_slug)/memory/"
echo ""
echo "Daemon management:"
echo "  Restart MCP servers (e.g. after reboot):  ./scripts/start-mcp.sh"
echo "  Full reset (drop dbs, remove venv, etc):  ./scripts/reset.sh"
echo ""
echo "Your Fresh Brain is ready."
