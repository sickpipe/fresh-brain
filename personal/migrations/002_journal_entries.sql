-- Migration: 002_journal_entries.sql
-- Database: personal
-- Date: 2026-05-07
-- Description: Add journal_entries table for the Grounded Journal feature
--
-- Why: The operator writes freeform reflections and the AI responds grounded
-- in saved knowledge (brain wiki, past journals, ideas). Each entry captures
-- the raw journal text, the AI's grounded response, which brain topics were
-- referenced, mood/theme tags, and full-text search. Follows personal DB
-- conventions: integer PK, tsvector search, touch_updated_at trigger,
-- deleted_at soft delete.

-- ========== UP ==========

-- journal_entries: freeform operator reflections with AI-grounded responses
CREATE TABLE journal_entries (
    id                  SERIAL PRIMARY KEY,
    entry_date          DATE NOT NULL,
    content             TEXT NOT NULL,
    grounded_response   TEXT,
    linked_topics       TEXT[],
    mood_tags           TEXT[],
    themes              TEXT[],
    search_tsv          tsvector GENERATED ALWAYS AS (
                            to_tsvector('english',
                                coalesce(content, '') || ' ' ||
                                coalesce(grounded_response, ''))
                        ) STORED,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ
);

-- Full-text search on journal content + AI response.
CREATE INDEX idx_journal_entries_search
    ON journal_entries USING GIN (search_tsv);

-- Filter by date range (most common query pattern).
CREATE INDEX idx_journal_entries_date
    ON journal_entries (entry_date DESC) WHERE deleted_at IS NULL;

-- Filter by mood tags (GIN for array containment queries).
CREATE INDEX idx_journal_entries_mood_tags
    ON journal_entries USING GIN (mood_tags);

-- Filter by themes (GIN for array containment queries).
CREATE INDEX idx_journal_entries_themes
    ON journal_entries USING GIN (themes);

-- Filter by linked brain topics (find all journals referencing a topic slug).
CREATE INDEX idx_journal_entries_linked_topics
    ON journal_entries USING GIN (linked_topics);

CREATE TRIGGER trg_journal_entries_updated_at
    BEFORE UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('002_journal_entries.sql')
ON CONFLICT (filename) DO NOTHING;

-- Record in legacy schema_version for continuity.
INSERT INTO schema_version (version, name)
VALUES (20, '002_journal_entries')
ON CONFLICT (version) DO NOTHING;

-- ========== DOWN (do not run above this line — paste into psql manually) ==========
\quit

DROP TABLE IF EXISTS journal_entries;
DELETE FROM applied_migrations WHERE filename = '002_journal_entries.sql';
DELETE FROM schema_version WHERE version = 20;
