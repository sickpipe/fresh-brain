-- Migration: 014_external_document_links.sql
-- Database: brain
-- Date: 2026-05-11
-- Description: Cross-database external document links table.
--   Links external files (Google Drive, Dropbox, local, URL) to records
--   in any of the three databases (brain, personal, evenrail_app).
--   Supports soft delete, provider metadata, and verified-at tracking.

-- ========== UP ==========

CREATE TABLE external_document_links (
    id            BIGSERIAL PRIMARY KEY,
    target_db     TEXT NOT NULL CHECK (target_db IN ('brain', 'personal', 'evenrail_app')),
    target_table  TEXT NOT NULL,
    target_key    TEXT NOT NULL,
    provider      TEXT NOT NULL CHECK (provider IN ('google_drive', 'dropbox', 'local', 'url')),
    provider_ref  TEXT NOT NULL,
    url           TEXT,
    title         TEXT NOT NULL,
    doc_type      TEXT,
    mime_type     TEXT,
    provider_meta JSONB NOT NULL DEFAULT '{}',
    status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'broken')),
    last_verified TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ
);

-- Primary lookup: find all documents attached to a specific record.
CREATE INDEX idx_external_document_links_target
    ON external_document_links (target_db, target_table, target_key)
    WHERE deleted_at IS NULL;

-- Dedup / lookup by provider file ID.
CREATE INDEX idx_external_document_links_provider_ref
    ON external_document_links (provider, provider_ref);

-- Upsert dedup: same file linked to the same record should update, not duplicate.
CREATE UNIQUE INDEX uq_external_document_links_dedup
    ON external_document_links (provider, provider_ref, target_db, target_table, target_key)
    WHERE deleted_at IS NULL;

-- Filter by status (e.g. find broken links for verification sweeps).
CREATE INDEX idx_external_document_links_status
    ON external_document_links (status)
    WHERE deleted_at IS NULL;

-- Soft-delete-aware ID scan (consistent with routing_log pattern).
CREATE INDEX idx_external_document_links_live
    ON external_document_links (id)
    WHERE deleted_at IS NULL;

CREATE TRIGGER trg_external_document_links_updated_at
    BEFORE UPDATE ON external_document_links
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('014_external_document_links.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '14' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

DROP TRIGGER IF EXISTS trg_external_document_links_updated_at ON external_document_links;
DROP TABLE IF EXISTS external_document_links;

DELETE FROM applied_migrations WHERE filename = '014_external_document_links.sql';
UPDATE brain_config SET value = '13' WHERE key = 'schema_version';
