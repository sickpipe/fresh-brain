# Brain Database Migrations

Raw numbered SQL migrations. No ORM, no framework.

## Convention
- Files: `NNN_short_description.sql` (zero-padded 3 digits)
- Each file has `-- ========== UP ==========` and `-- ========== DOWN ==========` sections
- Header: Migration name, database, date, one-line description
- Applied by `~/FreshBrain/scripts/migrate.sh brain`

## Version Tracking
- `brain_config` key `schema_version` holds the current version number
- Baseline is v4 (001_baseline_v4.sql is a comment-only marker)

## Rules
- Never modify a migration after it has been applied
- Never skip a version number
- Test DOWN section before shipping (when applicable)
