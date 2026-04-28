#!/usr/bin/env bash
# migrate.sh — Apply raw SQL migrations to brain or personal databases.
# Usage: ./migrate.sh <brain|personal> [target_version]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

DB="$1"
TARGET="${2:-}"

case "$DB" in
    brain)
        MIGRATIONS_DIR="$REPO_DIR/brain/migrations"
        VERSION_QUERY="SELECT value::int FROM brain_config WHERE key = 'schema_version'"
        version_update() { psql -d brain -qc "UPDATE brain_config SET value = '$1' WHERE key = 'schema_version'"; }
        ;;
    personal)
        MIGRATIONS_DIR="$REPO_DIR/personal/migrations"
        VERSION_QUERY="SELECT COALESCE(MAX(version), 0) FROM schema_version"
        version_update() { psql -d personal -qc "INSERT INTO schema_version (version, name) VALUES ($1, '$(basename "$2")') ON CONFLICT (version) DO NOTHING"; }
        ;;
    *)
        echo "Usage: $0 <brain|personal> [target_version]" >&2
        exit 1
        ;;
esac

# Get current schema version
CURRENT=$(psql -d "$DB" -tA -c "$VERSION_QUERY" 2>/dev/null | tr -d ' ')
if [ -z "$CURRENT" ]; then
    echo "ERROR: Could not read schema_version from $DB" >&2
    exit 1
fi
echo "Database: $DB | Current version: $CURRENT"

# Collect migration files, sorted numerically
APPLIED=0
for FILE in $(ls "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort); do
    BASENAME=$(basename "$FILE")
    # Extract version number from NNN_ prefix
    FILE_VERSION=$(echo "$BASENAME" | grep -oE '^[0-9]+' | sed 's/^0*//')
    [ -z "$FILE_VERSION" ] && continue

    # Skip if already applied
    [ "$FILE_VERSION" -le "$CURRENT" ] && continue

    # Stop if past target
    if [ -n "$TARGET" ] && [ "$FILE_VERSION" -gt "$TARGET" ]; then
        break
    fi

    echo "Applying: $BASENAME (v$FILE_VERSION)..."
    psql -d "$DB" -v ON_ERROR_STOP=1 -f "$FILE"

    # Update version tracker
    if [ "$DB" = "brain" ]; then
        version_update "$FILE_VERSION"
    else
        version_update "$FILE_VERSION" "$FILE"
    fi

    echo "  -> v$FILE_VERSION applied."
    APPLIED=$((APPLIED + 1))
done

if [ "$APPLIED" -eq 0 ]; then
    echo "Nothing to apply. Schema is up to date."
else
    echo "Done. Applied $APPLIED migration(s)."
fi
