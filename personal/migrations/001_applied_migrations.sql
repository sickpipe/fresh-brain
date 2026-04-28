-- Migration: 001_applied_migrations
-- Database: personal
-- Date: 2026-04-28
-- Description: Bootstrap the applied_migrations ledger for fresh-installed
--              personal databases. Tracks each migration filename instead of
--              gating on MAX(version) from schema_version. schema_version is
--              kept as informational metadata only.
--
-- See brain/migrations/004_applied_migrations.sql for the full rationale.
-- Same table shape across brain and personal.
--
-- Note: this template ships personal/schema.sql containing the full v18
-- baseline. New installs apply schema.sql, then run this migration to
-- bootstrap the applied_migrations ledger.

-- ========== UP ==========

CREATE TABLE applied_migrations (
    filename    TEXT PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    checksum    TEXT
);

INSERT INTO applied_migrations (filename) VALUES
    ('001_applied_migrations.sql')
ON CONFLICT (filename) DO NOTHING;

-- Record in legacy schema_version table for continuity.
INSERT INTO schema_version (version, name)
VALUES (19, '001_applied_migrations')
ON CONFLICT (version) DO NOTHING;

-- ========== DOWN (do not run above this line — paste into psql manually) ==========
\quit

DROP TABLE IF EXISTS applied_migrations;
DELETE FROM schema_version WHERE version = 19;
