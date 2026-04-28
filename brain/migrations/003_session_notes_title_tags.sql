-- Migration: 003_session_notes_title_tags
-- Database: brain
-- Date: 2026-04-28
-- Description: Add title and tags columns to session_notes, drop NOT NULL on
--              session_ended_at so notes can be logged mid-session. Brings the
--              session_notes table in line with the other content tables
--              (topic_documents, memory_entries, ideas, standing_orders) which
--              all accept title and tags via memory_upsert.
--
-- Design choice — session_ended_at: made nullable, NO default. A session_note
-- written mid-session genuinely has no end time yet; defaulting to now() would
-- silently lie about when the session actually ended. The end-session protocol
-- can set it explicitly when the session closes. The DESC btree index on
-- session_ended_at handles NULLs without issue (NULLs sort last).

-- ========== UP ==========

-- Add title (nullable — backfilled from summary for existing rows below).
ALTER TABLE session_notes ADD COLUMN title TEXT;

-- Add tags array (nullable, matches other content tables).
ALTER TABLE session_notes ADD COLUMN tags TEXT[];

-- Backfill title from summary for existing rows so search/listing stays useful.
UPDATE session_notes SET title = summary WHERE title IS NULL;

-- Drop the NOT NULL constraint on session_ended_at.
ALTER TABLE session_notes ALTER COLUMN session_ended_at DROP NOT NULL;

-- Bump schema version.
UPDATE brain_config SET value = '6' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line — paste into psql manually) ==========
-- To rollback, run ONLY the lines below this point.
\quit

-- Restore NOT NULL on session_ended_at (will fail if any row has NULL — set
-- those to created_at first).
UPDATE session_notes SET session_ended_at = created_at WHERE session_ended_at IS NULL;
ALTER TABLE session_notes ALTER COLUMN session_ended_at SET NOT NULL;

-- Drop the new columns.
ALTER TABLE session_notes DROP COLUMN IF EXISTS tags;
ALTER TABLE session_notes DROP COLUMN IF EXISTS title;

-- Revert schema version.
UPDATE brain_config SET value = '5' WHERE key = 'schema_version';
