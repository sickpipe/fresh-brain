-- Migration: 002_hybrid_search_and_improvements
-- Database: brain
-- Date: 2026-04-28
-- Description: Add missing HNSW vector indexes, tsvector columns for hybrid
--              search, and JSONB snapshot column to document_history.

-- ========== UP ==========

-- ------------------------------------------------------------
-- 1. Missing HNSW vector indexes
-- These tables have embedding vector(384) but no HNSW index.
-- team_members and document_chunks already have them.
-- ------------------------------------------------------------

CREATE INDEX idx_topic_documents_embedding
    ON topic_documents USING hnsw (embedding vector_cosine_ops);

CREATE INDEX idx_memory_entries_embedding
    ON memory_entries USING hnsw (embedding vector_cosine_ops);

CREATE INDEX idx_standing_orders_embedding
    ON standing_orders USING hnsw (embedding vector_cosine_ops);

CREATE INDEX idx_ideas_embedding
    ON ideas USING hnsw (embedding vector_cosine_ops);

CREATE INDEX idx_operator_intent_embedding
    ON operator_intent USING hnsw (embedding vector_cosine_ops);

CREATE INDEX idx_session_notes_embedding
    ON session_notes USING hnsw (embedding vector_cosine_ops);

-- ------------------------------------------------------------
-- 2. tsvector generated columns + GIN indexes for hybrid search
-- Each table gets a `tsv` column built from its text fields,
-- enabling combined vector + full-text search.
-- ------------------------------------------------------------

-- team_members: display_name + role + body
ALTER TABLE team_members ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(display_name, '') || ' ' ||
            coalesce(role, '') || ' ' ||
            coalesce(body, ''))
    ) STORED;
CREATE INDEX idx_team_members_tsv ON team_members USING GIN (tsv);

-- topic_documents: title + body
ALTER TABLE topic_documents ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(body, ''))
    ) STORED;
CREATE INDEX idx_topic_documents_tsv ON topic_documents USING GIN (tsv);

-- memory_entries: title + body
ALTER TABLE memory_entries ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(body, ''))
    ) STORED;
CREATE INDEX idx_memory_entries_tsv ON memory_entries USING GIN (tsv);

-- session_notes: summary + body
ALTER TABLE session_notes ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(summary, '') || ' ' ||
            coalesce(body, ''))
    ) STORED;
CREATE INDEX idx_session_notes_tsv ON session_notes USING GIN (tsv);

-- standing_orders: title + body
ALTER TABLE standing_orders ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(body, ''))
    ) STORED;
CREATE INDEX idx_standing_orders_tsv ON standing_orders USING GIN (tsv);

-- ideas: title + coalesce(body, summary)
-- body is nullable on ideas, so fall back to summary
ALTER TABLE ideas ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(body, coalesce(summary, '')))
    ) STORED;
CREATE INDEX idx_ideas_tsv ON ideas USING GIN (tsv);

-- operator_intent: title + body
ALTER TABLE operator_intent ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(body, ''))
    ) STORED;
CREATE INDEX idx_operator_intent_tsv ON operator_intent USING GIN (tsv);

-- ------------------------------------------------------------
-- 3. document_history: add JSONB snapshot column
-- Stores full-row snapshots instead of body-only. Existing rows
-- get a minimal snapshot wrapping their body text.
-- ------------------------------------------------------------

ALTER TABLE document_history ADD COLUMN snapshot JSONB;

UPDATE document_history
   SET snapshot = jsonb_build_object('body', body)
 WHERE snapshot IS NULL;

ALTER TABLE document_history ALTER COLUMN snapshot SET NOT NULL;

-- Update schema version
UPDATE brain_config SET value = '5' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line — paste into psql manually) ==========
-- To rollback, run ONLY the lines below this point.
\quit

-- Drop tsvector columns (cascades drop the GIN indexes)
ALTER TABLE team_members DROP COLUMN IF EXISTS tsv;
ALTER TABLE topic_documents DROP COLUMN IF EXISTS tsv;
ALTER TABLE memory_entries DROP COLUMN IF EXISTS tsv;
ALTER TABLE session_notes DROP COLUMN IF EXISTS tsv;
ALTER TABLE standing_orders DROP COLUMN IF EXISTS tsv;
ALTER TABLE ideas DROP COLUMN IF EXISTS tsv;
ALTER TABLE operator_intent DROP COLUMN IF EXISTS tsv;

-- Drop HNSW indexes added in this migration
DROP INDEX IF EXISTS idx_topic_documents_embedding;
DROP INDEX IF EXISTS idx_memory_entries_embedding;
DROP INDEX IF EXISTS idx_standing_orders_embedding;
DROP INDEX IF EXISTS idx_ideas_embedding;
DROP INDEX IF EXISTS idx_operator_intent_embedding;
DROP INDEX IF EXISTS idx_session_notes_embedding;

-- Revert document_history snapshot
ALTER TABLE document_history ALTER COLUMN snapshot DROP NOT NULL;
ALTER TABLE document_history DROP COLUMN IF EXISTS snapshot;

-- Revert schema version
UPDATE brain_config SET value = '4' WHERE key = 'schema_version';
