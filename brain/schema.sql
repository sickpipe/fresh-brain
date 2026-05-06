-- Brain Database Schema (v12)
-- Generated from live database: 2026-05-06
-- Source of truth for fresh installs. Kept in sync with migrations.
--
-- SEARCH: Brain uses pgvector semantic search (all-MiniLM-L6-v2, 384-dim)
-- plus tsvector/GIN full-text search for hybrid retrieval. Every searchable
-- table has both an HNSW vector index and a generated tsvector column with
-- GIN index. See migration 002_hybrid_search_and_improvements.sql.
--
-- v6 (003_session_notes_title_tags.sql): session_notes gains title + tags
-- columns and session_ended_at becomes nullable so notes can be logged
-- mid-session.
--
-- v7 (004_applied_migrations.sql): adds applied_migrations ledger. The
-- migrate.sh runner tracks each filename rather than gating on a single
-- schema_version integer. brain_config.schema_version is now informational
-- only — bootstrap may still read it but the runner does not.
--
-- v8 (006_add_routing_log.sql): adds routing_log table to track all memory
-- saves across databases for audit and correctness verification.
--
-- v9 (007_add_edited_by_guard.sql): adds edited_by guard column to
-- standing_orders, team_members, and brain_config. Tracks system vs
-- operator authorship so data migrations can skip customized rows.
--
-- v10 (008_update_remember_this_protocol.sql): updates remember-this-protocol
-- standing order body to include routing log step (Step 4).
--
-- v11 (010_add_mcp_tool_log.sql): mcp_tool_log table for tool call
-- observability — tracks tool name, args, duration, success/error.
--
-- v12 (011_session_notes_consolidated_at.sql): session_notes gains
-- consolidated_at column — marks notes archived by the consolidation
-- agent so search excludes them by default.

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- Function: touch_updated_at()
-- ============================================================
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- brain_config: key-value system settings
-- ============================================================
CREATE TABLE brain_config (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    description TEXT,
    edited_by   TEXT NOT NULL DEFAULT 'system' CHECK (edited_by IN ('system', 'operator')),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_brain_config_updated_at
    BEFORE UPDATE ON brain_config FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- team_members
-- ============================================================
CREATE TABLE team_members (
    slug             TEXT PRIMARY KEY,
    display_name     TEXT NOT NULL,
    role             TEXT NOT NULL,
    persona          TEXT NOT NULL,
    body             TEXT NOT NULL,
    summary          TEXT,
    capabilities     TEXT[] DEFAULT '{}',
    always_inject    BOOLEAN NOT NULL DEFAULT FALSE,
    project_context  TEXT,
    model_tier       TEXT CHECK (model_tier IN ('opus','sonnet','haiku')),
    status           TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    tags             TEXT[],
    embedding        vector(384),
    embedding_model  TEXT,
    last_accessed_at TIMESTAMPTZ,
    access_count     INTEGER NOT NULL DEFAULT 0,
    tsv              tsvector GENERATED ALWAYS AS (
                         to_tsvector('english',
                             coalesce(display_name, '') || ' ' ||
                             coalesce(role, '') || ' ' ||
                             coalesce(body, ''))
                     ) STORED,
    edited_by        TEXT NOT NULL DEFAULT 'system' CHECK (edited_by IN ('system', 'operator')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_team_members_status ON team_members(status);
CREATE INDEX idx_team_members_capabilities ON team_members USING GIN (capabilities);
CREATE INDEX idx_team_members_always_inject ON team_members(always_inject) WHERE always_inject = TRUE;
CREATE INDEX idx_team_members_embedding ON team_members USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_team_members_tsv ON team_members USING GIN (tsv);
CREATE INDEX idx_team_members_slug_live ON team_members(slug) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_team_members_updated_at
    BEFORE UPDATE ON team_members FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- topic_documents
-- ============================================================
CREATE TABLE topic_documents (
    slug             TEXT PRIMARY KEY,
    title            TEXT NOT NULL,
    body             TEXT NOT NULL,
    topic            TEXT NOT NULL,
    summary          TEXT,
    namespace        TEXT NOT NULL DEFAULT 'global',
    scope            TEXT NOT NULL DEFAULT 'system' CHECK (scope IN ('system','operator','project')),
    source_path      TEXT,
    tags             TEXT[],
    embedding        vector(384),
    embedding_model  TEXT,
    last_accessed_at TIMESTAMPTZ,
    access_count     INTEGER NOT NULL DEFAULT 0,
    tsv              tsvector GENERATED ALWAYS AS (
                         to_tsvector('english',
                             coalesce(title, '') || ' ' ||
                             coalesce(body, ''))
                     ) STORED,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_topic_documents_topic ON topic_documents(topic);
CREATE INDEX idx_topic_documents_namespace ON topic_documents(namespace);
CREATE INDEX idx_topic_documents_updated_at ON topic_documents(updated_at DESC);
CREATE INDEX idx_topic_documents_embedding ON topic_documents USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_topic_documents_tsv ON topic_documents USING GIN (tsv);
CREATE INDEX idx_topic_documents_slug_live ON topic_documents(slug) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_topic_documents_updated_at
    BEFORE UPDATE ON topic_documents FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- memory_entries
-- ============================================================
CREATE TABLE memory_entries (
    slug             TEXT PRIMARY KEY,
    entry_type       TEXT NOT NULL,
    title            TEXT NOT NULL,
    body             TEXT NOT NULL,
    summary          TEXT,
    namespace        TEXT NOT NULL DEFAULT 'global',
    scope            TEXT NOT NULL DEFAULT 'system' CHECK (scope IN ('system','operator','project')),
    related_topic    TEXT,
    tags             TEXT[],
    occurred_on      DATE,
    embedding        vector(384),
    embedding_model  TEXT,
    last_accessed_at TIMESTAMPTZ,
    access_count     INTEGER NOT NULL DEFAULT 0,
    tsv              tsvector GENERATED ALWAYS AS (
                         to_tsvector('english',
                             coalesce(title, '') || ' ' ||
                             coalesce(body, ''))
                     ) STORED,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_memory_entries_type ON memory_entries(entry_type);
CREATE INDEX idx_memory_entries_namespace ON memory_entries(namespace);
CREATE INDEX idx_memory_entries_related_topic ON memory_entries(related_topic);
CREATE INDEX idx_memory_entries_updated_at ON memory_entries(updated_at DESC);
CREATE INDEX idx_memory_entries_embedding ON memory_entries USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_memory_entries_tsv ON memory_entries USING GIN (tsv);
CREATE INDEX idx_memory_entries_slug_live ON memory_entries(slug) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_memory_entries_updated_at
    BEFORE UPDATE ON memory_entries FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- session_notes (append-only, no soft-delete)
-- ============================================================
-- session_ended_at is nullable: notes can be logged mid-session and the
-- end timestamp gets set when the session truly closes (no silent now()
-- default — that would lie about session duration).
CREATE TABLE session_notes (
    slug             TEXT PRIMARY KEY,
    title            TEXT,
    session_ended_at TIMESTAMPTZ,
    summary          TEXT NOT NULL,
    body             TEXT NOT NULL,
    projects_touched TEXT[],
    tags             TEXT[],
    embedding        vector(384),
    embedding_model  TEXT,
    tsv              tsvector GENERATED ALWAYS AS (
                         to_tsvector('english',
                             coalesce(summary, '') || ' ' ||
                             coalesce(body, ''))
                     ) STORED,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    consolidated_at  TIMESTAMPTZ
);

CREATE INDEX idx_session_notes_ended_at ON session_notes(session_ended_at DESC);
CREATE INDEX idx_session_notes_embedding ON session_notes USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_session_notes_tsv ON session_notes USING GIN (tsv);

-- ============================================================
-- standing_orders
-- ============================================================
CREATE TABLE standing_orders (
    slug             TEXT PRIMARY KEY,
    title            TEXT NOT NULL,
    body             TEXT NOT NULL,
    summary          TEXT,
    scope            TEXT NOT NULL DEFAULT 'system' CHECK (scope IN ('system','operator','project')),
    active           BOOLEAN NOT NULL DEFAULT true,
    trigger_pattern  TEXT,
    effective_from   DATE,
    tags             TEXT[],
    embedding        vector(384),
    embedding_model  TEXT,
    last_accessed_at TIMESTAMPTZ,
    access_count     INTEGER NOT NULL DEFAULT 0,
    tsv              tsvector GENERATED ALWAYS AS (
                         to_tsvector('english',
                             coalesce(title, '') || ' ' ||
                             coalesce(body, ''))
                     ) STORED,
    edited_by        TEXT NOT NULL DEFAULT 'system' CHECK (edited_by IN ('system', 'operator')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_standing_orders_active ON standing_orders(active);
CREATE INDEX idx_standing_orders_embedding ON standing_orders USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_standing_orders_tsv ON standing_orders USING GIN (tsv);
CREATE INDEX idx_standing_orders_slug_live ON standing_orders(slug) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_standing_orders_updated_at
    BEFORE UPDATE ON standing_orders FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- ideas
-- ============================================================
CREATE TABLE ideas (
    slug             TEXT PRIMARY KEY,
    title            TEXT NOT NULL,
    status           TEXT NOT NULL CHECK (status IN (
        'proposed','deferred','approved','built','shipped','rejected'
    )),
    category         TEXT,
    summary          TEXT NOT NULL,
    body             TEXT,
    estimated_cost   TEXT,
    estimated_effort TEXT CHECK (estimated_effort IN ('small','medium','large')),
    biggest_risk     TEXT,
    next_action      TEXT,
    filed_on         DATE NOT NULL,
    linked_docs      TEXT[],
    embedding        vector(384),
    embedding_model  TEXT,
    last_accessed_at TIMESTAMPTZ,
    access_count     INTEGER NOT NULL DEFAULT 0,
    tsv              tsvector GENERATED ALWAYS AS (
                         to_tsvector('english',
                             coalesce(title, '') || ' ' ||
                             coalesce(body, coalesce(summary, '')))
                     ) STORED,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_ideas_status ON ideas(status);
CREATE INDEX idx_ideas_category ON ideas(category);
CREATE INDEX idx_ideas_embedding ON ideas USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_ideas_tsv ON ideas USING GIN (tsv);
CREATE INDEX idx_ideas_slug_live ON ideas(slug) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_ideas_updated_at
    BEFORE UPDATE ON ideas FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- operator_intent
-- ============================================================
CREATE TABLE operator_intent (
    slug             TEXT PRIMARY KEY,
    section          TEXT NOT NULL CHECK (section IN (
        'identity','core_value','tradeoff','decision_boundary',
        'success_criterion','do_not_rule'
    )),
    title            TEXT NOT NULL,
    body             TEXT NOT NULL,
    summary          TEXT,
    always_inject    BOOLEAN NOT NULL DEFAULT FALSE,
    scope            TEXT NOT NULL DEFAULT 'operator' CHECK (scope IN ('system','operator','project')),
    priority         INTEGER,
    tags             TEXT[],
    embedding        vector(384),
    embedding_model  TEXT,
    last_accessed_at TIMESTAMPTZ,
    access_count     INTEGER NOT NULL DEFAULT 0,
    tsv              tsvector GENERATED ALWAYS AS (
                         to_tsvector('english',
                             coalesce(title, '') || ' ' ||
                             coalesce(body, ''))
                     ) STORED,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_operator_intent_section ON operator_intent(section);
CREATE INDEX idx_operator_intent_embedding ON operator_intent USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_operator_intent_tsv ON operator_intent USING GIN (tsv);
CREATE INDEX idx_operator_intent_slug_live ON operator_intent(slug) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_operator_intent_updated_at
    BEFORE UPDATE ON operator_intent FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- document_chunks
-- ============================================================
CREATE TABLE document_chunks (
    id              BIGSERIAL PRIMARY KEY,
    source_table    TEXT NOT NULL,
    source_key      TEXT NOT NULL,
    chunk_index     INTEGER NOT NULL,
    heading         TEXT,
    body            TEXT NOT NULL,
    embedding       vector(384),
    embedding_model TEXT NOT NULL DEFAULT 'all-MiniLM-L6-v2',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_table, source_key, chunk_index)
);

CREATE INDEX idx_document_chunks_source ON document_chunks(source_table, source_key);
CREATE INDEX idx_document_chunks_embedding ON document_chunks USING hnsw (embedding vector_cosine_ops);

-- ============================================================
-- document_history
-- ============================================================
CREATE TABLE document_history (
    history_id   BIGSERIAL PRIMARY KEY,
    source_table TEXT NOT NULL,
    source_key   TEXT NOT NULL,
    body         TEXT NOT NULL,
    snapshot     JSONB NOT NULL,
    edited_by    TEXT,
    edited_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    change_note  TEXT
);

CREATE INDEX idx_document_history_source ON document_history(source_table, source_key, edited_at DESC);

-- ============================================================
-- access_log
-- ============================================================
CREATE TABLE access_log (
    id           BIGSERIAL PRIMARY KEY,
    source_table TEXT NOT NULL,
    slug         TEXT NOT NULL,
    tool         TEXT NOT NULL,
    accessed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_access_log_source ON access_log(source_table, slug);
CREATE INDEX idx_access_log_time ON access_log(accessed_at DESC);

-- ============================================================
-- routing_log: tracks all memory saves across databases (v8)
-- ============================================================
CREATE TABLE routing_log (
    id                BIGSERIAL PRIMARY KEY,
    destination_db    TEXT NOT NULL CHECK (destination_db IN ('brain', 'personal', 'evenrail_app')),
    destination_table TEXT NOT NULL,
    record_slug       TEXT NOT NULL,
    rationale         TEXT NOT NULL,
    triggered_by      TEXT NOT NULL,
    session_context   TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ
);

CREATE INDEX idx_routing_log_destination_db ON routing_log (destination_db);
CREATE INDEX idx_routing_log_destination_table ON routing_log (destination_table);
CREATE INDEX idx_routing_log_record_slug ON routing_log (record_slug);
CREATE INDEX idx_routing_log_created_at ON routing_log (created_at DESC);
CREATE INDEX idx_routing_log_db_created ON routing_log (destination_db, created_at DESC);
CREATE INDEX idx_routing_log_live ON routing_log (id) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_routing_log_updated_at
    BEFORE UPDATE ON routing_log FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- mcp_tool_log: append-only MCP tool call observability (v11)
-- ============================================================
CREATE TABLE mcp_tool_log (
    id              BIGSERIAL PRIMARY KEY,
    tool_name       TEXT NOT NULL,
    arguments       JSONB,
    result_size     INTEGER,
    duration_ms     REAL NOT NULL,
    success         BOOLEAN NOT NULL DEFAULT TRUE,
    error_message   TEXT,
    session_id      TEXT,
    called_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_mcp_tool_log_called_at ON mcp_tool_log (called_at DESC);
CREATE INDEX idx_mcp_tool_log_tool_name ON mcp_tool_log (tool_name);
CREATE INDEX idx_mcp_tool_log_session_id ON mcp_tool_log (session_id) WHERE session_id IS NOT NULL;

-- ============================================================
-- applied_migrations: per-filename migration ledger (v7)
-- ============================================================
-- The migrate.sh runner consults this table (not brain_config.schema_version)
-- to decide which migrations to apply. checksum is the sha256 of file
-- contents at apply time, captured for drift detection.
CREATE TABLE applied_migrations (
    filename    TEXT PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    checksum    TEXT
);
