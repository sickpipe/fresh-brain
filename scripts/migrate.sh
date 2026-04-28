#!/usr/bin/env bash
# migrate.sh — Apply raw SQL migrations to brain or personal databases.
#
# Tracking model: each database has an `applied_migrations` table keyed by
# filename. The runner queries that set, applies anything missing in sorted
# order, and records the filename on success. The legacy `schema_version`
# field/table is no longer consulted for gating (kept for informational
# consumers like bootstrap).
#
# Each migration runs inside a single psql transaction (--single-transaction),
# and the INSERT into applied_migrations runs in a second transaction
# immediately after. If the migration fails, nothing is recorded; if the
# INSERT fails for any reason, the migration body has already committed and
# the operator gets a clear error to resolve manually.
#
# Usage: ./migrate.sh <brain|personal>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <brain|personal>" >&2
    exit 1
fi

TARGET_DB="$1"

case "$TARGET_DB" in
    brain)
        DB="brain"
        MIGRATIONS_DIR="$REPO_DIR/brain/migrations"
        ;;
    personal)
        DB="personal"
        MIGRATIONS_DIR="$REPO_DIR/personal/migrations"
        ;;
    *)
        echo "Usage: $0 <brain|personal>" >&2
        exit 1
        ;;
esac

if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "ERROR: Migrations directory not found: $MIGRATIONS_DIR" >&2
    exit 1
fi

# Verify applied_migrations table exists. If it does not, the bootstrap
# migration that creates it has not been applied yet — the operator must
# apply it manually via psql -f before the runner can take over.
TABLE_EXISTS=$(psql -d "$DB" -tA -c \
    "SELECT to_regclass('public.applied_migrations') IS NOT NULL" 2>/dev/null \
    | tr -d ' ')

if [ "$TABLE_EXISTS" != "t" ]; then
    echo "ERROR: applied_migrations table not found in $DB." >&2
    echo "       Bootstrap it with: psql -d $DB -f $MIGRATIONS_DIR/<NNN>_applied_migrations.sql" >&2
    exit 1
fi

echo "Database: $DB"
echo "Migrations dir: $MIGRATIONS_DIR"

# Pull the set of already-applied filenames into a sorted newline-delimited list.
APPLIED_LIST=$(psql -d "$DB" -tA -c \
    "SELECT filename FROM applied_migrations ORDER BY filename")

# Helper: is a given filename already in the applied set?
is_applied() {
    local needle="$1"
    while IFS= read -r row; do
        [ "$row" = "$needle" ] && return 0
    done <<<"$APPLIED_LIST"
    return 1
}

APPLIED_COUNT=0
SKIPPED_COUNT=0

# Iterate every .sql file in numeric/lexical order.
shopt -s nullglob
FILES=("$MIGRATIONS_DIR"/*.sql)
shopt -u nullglob

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No .sql migrations found in $MIGRATIONS_DIR"
    exit 0
fi

# sort for deterministic order
IFS=$'\n' SORTED_FILES=($(printf '%s\n' "${FILES[@]}" | sort))
unset IFS

for FILE in "${SORTED_FILES[@]}"; do
    BASENAME=$(basename "$FILE")

    if is_applied "$BASENAME"; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    echo "Applying: $BASENAME"

    # Compute checksum BEFORE applying so we record exactly what we ran.
    CHECKSUM=$(shasum -a 256 "$FILE" | awk '{print $1}')

    # --single-transaction wraps the whole file in BEGIN/COMMIT. \quit inside
    # the file (used to separate UP from DOWN) commits the transaction and
    # exits cleanly — psql treats \quit as a successful end of input.
    if ! psql -d "$DB" -v ON_ERROR_STOP=1 --single-transaction -f "$FILE"; then
        echo "  -> FAILED. Rolled back. Aborting." >&2
        exit 1
    fi

    # Record the apply. Done in a separate transaction; if this fails the
    # operator must INSERT manually and re-run.
    psql -d "$DB" -v ON_ERROR_STOP=1 -qc \
        "INSERT INTO applied_migrations (filename, checksum) VALUES ('$BASENAME', '$CHECKSUM') ON CONFLICT (filename) DO NOTHING"

    echo "  -> OK"
    APPLIED_COUNT=$((APPLIED_COUNT + 1))
done

echo ""
echo "Summary: applied $APPLIED_COUNT, skipped $SKIPPED_COUNT (already in applied_migrations)."

if [ "$APPLIED_COUNT" -eq 0 ]; then
    echo "No new migrations. Schema is up to date."
fi
