-- Migration: 011_session_notes_consolidated_at.sql
-- Database: brain
-- Date: 2026-05-06
-- Description: Add consolidated_at column to session_notes for archival
--
-- Why: The consolidation agent merges older session notes into summary
-- documents. consolidated_at marks notes that have been archived so
-- search excludes them by default — keeping results focused on recent,
-- unconsolidated context.

-- ========== UP ==========

ALTER TABLE session_notes
    ADD COLUMN consolidated_at TIMESTAMPTZ DEFAULT NULL;

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('011_session_notes_consolidated_at.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '12' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

ALTER TABLE session_notes DROP COLUMN IF EXISTS consolidated_at;
DELETE FROM applied_migrations WHERE filename = '011_session_notes_consolidated_at.sql';
UPDATE brain_config SET value = '11' WHERE key = 'schema_version';
