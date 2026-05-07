-- Migration: 012_topic_document_links.sql
-- Database: brain (template)
-- Date: 2026-05-07
-- Description: Add directional cross-link join table for topic_documents
--
-- Why: The compounding wiki needs to track which topic documents reference
-- each other. This enables traversable knowledge graphs — a document on
-- "Evenrail architecture" can link to "deployment runbook" (references),
-- a strategic analysis can note it was derived_from a research doc, and
-- a revised policy can mark it supersedes the old one. Directional links
-- let the MCP server walk the graph in either direction.
-- Adapted from live brain migration 008_topic_document_links.sql.

-- ========== UP ==========

-- topic_document_links: directional cross-references between topic_documents
-- Each row represents source_slug → target_slug with a typed relationship.
CREATE TABLE topic_document_links (
    source_slug TEXT NOT NULL REFERENCES topic_documents(slug) ON DELETE CASCADE,
    target_slug TEXT NOT NULL REFERENCES topic_documents(slug) ON DELETE CASCADE,
    link_type   TEXT NOT NULL CHECK (link_type IN (
        'references', 'derived_from', 'supersedes', 'related'
    )),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ,
    PRIMARY KEY (source_slug, target_slug, link_type)
);

-- Look up all links FROM a given document.
CREATE INDEX idx_topic_document_links_source
    ON topic_document_links (source_slug) WHERE deleted_at IS NULL;

-- Look up all links TO a given document (reverse traversal).
CREATE INDEX idx_topic_document_links_target
    ON topic_document_links (target_slug) WHERE deleted_at IS NULL;

-- Filter by link type across the whole graph.
CREATE INDEX idx_topic_document_links_type
    ON topic_document_links (link_type) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_topic_document_links_updated_at
    BEFORE UPDATE ON topic_document_links FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('012_topic_document_links.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '13' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

DROP TABLE IF EXISTS topic_document_links;
DELETE FROM applied_migrations WHERE filename = '012_topic_document_links.sql';
UPDATE brain_config SET value = '12' WHERE key = 'schema_version';
