# Personal Database Migrations

Raw numbered SQL migrations. No ORM, no framework.

## Convention
- Files: `NNN_short_description.sql` (zero-padded 3 digits)
- Each file has `-- ========== UP ==========` and `-- ========== DOWN ==========` sections
- Header: Migration name, database, date, one-line description
- Applied by `./scripts/migrate.sh personal`

## Version Tracking
- `applied_migrations` table holds the set of applied filenames — this is what
  the runner consults
- `schema_version` table is informational only (still updated for continuity,
  no longer consulted by the runner)
- Baseline is v18 — `personal/schema.sql` is the source of truth for fresh
  installs, and `setup.sh` backfills the `applied_migrations` ledger so the
  runner does not attempt to re-apply baseline migrations

## Rules
- Never modify a migration after it has been applied
- Never skip a version number
- Test DOWN section before shipping (when applicable)
