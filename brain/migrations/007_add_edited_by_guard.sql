-- Migration: 007_add_edited_by_guard.sql
-- Database: brain
-- Date: 2026-05-02
-- Description: Add edited_by guard column to standing_orders, team_members,
--   and brain_config. Tracks whether a row was last written by the system
--   (template defaults, migrations) or the operator (manual customization).
--   Data migrations can use this to skip operator-customized rows.

-- ========== UP ==========

-- standing_orders
ALTER TABLE standing_orders
    ADD COLUMN IF NOT EXISTS edited_by TEXT NOT NULL DEFAULT 'system';

ALTER TABLE standing_orders
    ADD CONSTRAINT chk_standing_orders_edited_by
    CHECK (edited_by IN ('system', 'operator'));

-- team_members
ALTER TABLE team_members
    ADD COLUMN IF NOT EXISTS edited_by TEXT NOT NULL DEFAULT 'system';

ALTER TABLE team_members
    ADD CONSTRAINT chk_team_members_edited_by
    CHECK (edited_by IN ('system', 'operator'));

-- brain_config
ALTER TABLE brain_config
    ADD COLUMN IF NOT EXISTS edited_by TEXT NOT NULL DEFAULT 'system';

ALTER TABLE brain_config
    ADD CONSTRAINT chk_brain_config_edited_by
    CHECK (edited_by IN ('system', 'operator'));

-- Backfill: all existing rows are system defaults.
UPDATE standing_orders SET edited_by = 'system' WHERE edited_by IS DISTINCT FROM 'system';
UPDATE team_members   SET edited_by = 'system' WHERE edited_by IS DISTINCT FROM 'system';
UPDATE brain_config   SET edited_by = 'system' WHERE edited_by IS DISTINCT FROM 'system';

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('007_add_edited_by_guard.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '9' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

ALTER TABLE standing_orders DROP CONSTRAINT IF EXISTS chk_standing_orders_edited_by;
ALTER TABLE standing_orders DROP COLUMN IF EXISTS edited_by;

ALTER TABLE team_members DROP CONSTRAINT IF EXISTS chk_team_members_edited_by;
ALTER TABLE team_members DROP COLUMN IF EXISTS edited_by;

ALTER TABLE brain_config DROP CONSTRAINT IF EXISTS chk_brain_config_edited_by;
ALTER TABLE brain_config DROP COLUMN IF EXISTS edited_by;

DELETE FROM applied_migrations WHERE filename = '007_add_edited_by_guard.sql';
UPDATE brain_config SET value = '8' WHERE key = 'schema_version';
