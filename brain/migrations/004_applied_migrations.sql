-- Migration: 004_applied_migrations
-- Database: brain
-- Date: 2026-04-28
-- Description: Add applied_migrations ledger so the runner can track each
--              migration filename instead of relying on the single-integer
--              schema_version gate. The brain_config 'schema_version' key is
--              kept as informational metadata (consumers like bootstrap still
--              read it) but the runner no longer consults it for gating.
--
-- Why: 002_hybrid_search_and_improvements.sql internally bumps schema_version
-- 4 -> 5, and 003_session_notes_title_tags.sql bumps 5 -> 6. The old runner
-- gated on filename number <= schema_version, which produced inconsistent
-- behavior when an in-flight migration changed the gate mid-run. A per-DB
-- applied_migrations set is unambiguous: a filename is either applied or it
-- isn't. No version arithmetic, no ordering races.

-- ========== UP ==========

CREATE TABLE applied_migrations (
    filename    TEXT PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    checksum    TEXT
);

-- Backfill every migration that already exists on disk so the runner
-- treats them as applied on the next invocation.
INSERT INTO applied_migrations (filename) VALUES
    ('001_baseline_v4.sql'),
    ('002_hybrid_search_and_improvements.sql'),
    ('003_session_notes_title_tags.sql'),
    ('004_applied_migrations.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '7' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line — paste into psql manually) ==========
\quit

DROP TABLE IF EXISTS applied_migrations;
UPDATE brain_config SET value = '6' WHERE key = 'schema_version';
