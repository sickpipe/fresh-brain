-- Personal Database Schema (v18)
-- Generated from live database: 2026-04-28
-- Source of truth for fresh installs. Kept in sync with migrations.
--
-- Key differences from brain:
--   - Integer PKs (relational hierarchy, not document store)
--   - tsvector full-text search (not pgvector semantic search)
--   - No embeddings or chunking
--   - Hierarchical: workspaces -> missions -> tasks -> task_items
--   - document_history for version tracking (shared pattern with brain)
--   - personal_config for self-description (mirrors brain_config)
--   - Soft-delete via deleted_at only (no is_deleted boolean)

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
-- schema_version: migration tracking ledger
-- ============================================================
CREATE TABLE schema_version (
    version     INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    applied     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- personal_config: key-value settings (mirrors brain_config)
-- ============================================================
CREATE TABLE personal_config (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_personal_config_updated_at
    BEFORE UPDATE ON personal_config FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- workspaces
-- ============================================================
CREATE TABLE workspaces (
    id          SERIAL PRIMARY KEY,
    slug        TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    type        TEXT NOT NULL CHECK (type IN ('personal', 'business')),
    color       TEXT,
    icon        TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_default  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- missions
-- ============================================================
CREATE TABLE missions (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    slug            TEXT NOT NULL UNIQUE,
    description     TEXT,
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('planning','active','paused','completed','archived')),
    priority        INTEGER DEFAULT 0,
    started_at      TIMESTAMPTZ,
    target_date     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    metadata_json   JSONB DEFAULT '{}'::jsonb,
    deleted_at      TIMESTAMPTZ,
    workspace_id    INTEGER REFERENCES workspaces(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    search_tsv      tsvector GENERATED ALWAYS AS (to_tsvector('english',
                        coalesce(name, '') || ' ' || coalesce(description, ''))) STORED
);

CREATE INDEX idx_missions_workspace ON missions(workspace_id);
CREATE INDEX idx_missions_status ON missions(status) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_missions_updated_at
    BEFORE UPDATE ON missions FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- tasks
-- ============================================================
CREATE TABLE tasks (
    id              SERIAL PRIMARY KEY,
    mission_id      INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    description     TEXT,
    status          TEXT NOT NULL DEFAULT 'todo'
                    CHECK (status IN ('todo','in_progress','blocked','done','cancelled')),
    priority        INTEGER NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 4),
    due_date        TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    assigned_to     TEXT,
    source_asset_id INTEGER,
    metadata_json   JSONB DEFAULT '{}'::jsonb,
    resolution      TEXT,
    deleted_at      TIMESTAMPTZ,
    workspace_id    INTEGER REFERENCES workspaces(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    search_tsv      tsvector GENERATED ALWAYS AS (to_tsvector('english',
                        coalesce(title, '') || ' ' || coalesce(description, ''))) STORED
);

CREATE INDEX idx_tasks_mission ON tasks(mission_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_priority ON tasks(priority DESC);
CREATE INDEX idx_tasks_due ON tasks(due_date);
CREATE INDEX idx_tasks_mission_status ON tasks(mission_id, status);
CREATE INDEX idx_tasks_workspace ON tasks(workspace_id);
CREATE INDEX idx_tasks_active ON tasks(mission_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_search ON tasks USING GIN (search_tsv);

CREATE TRIGGER trg_tasks_updated_at
    BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- assets
-- ============================================================
CREATE TABLE assets (
    id                  SERIAL PRIMARY KEY,
    file_path           TEXT NOT NULL,
    original_filename   TEXT NOT NULL,
    file_type           TEXT NOT NULL,
    mime_type           TEXT,
    file_size           INTEGER,
    sha256_hash         TEXT NOT NULL,
    title               TEXT,
    description         TEXT,
    source_url          TEXT,
    exif_json           JSONB DEFAULT '{}'::jsonb,
    metadata_json       JSONB DEFAULT '{}'::jsonb,
    processing_status   TEXT NOT NULL DEFAULT 'pending'
                        CHECK (processing_status IN ('pending','processing','completed','failed','skipped')),
    is_duplicate        BOOLEAN NOT NULL DEFAULT FALSE,
    duplicate_of_id     INTEGER REFERENCES assets(id) ON DELETE SET NULL,
    deleted_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    search_tsv          tsvector GENERATED ALWAYS AS (to_tsvector('english',
                            coalesce(title, '') || ' ' || coalesce(description, '') || ' ' || coalesce(original_filename, ''))) STORED
);

CREATE INDEX idx_assets_hash ON assets(sha256_hash);
CREATE INDEX idx_assets_file_type ON assets(file_type) WHERE deleted_at IS NULL;
CREATE INDEX idx_assets_processing ON assets(processing_status) WHERE deleted_at IS NULL;
CREATE INDEX idx_assets_search ON assets USING GIN (search_tsv);

-- Deferred FK: tasks.source_asset_id -> assets.id
ALTER TABLE tasks ADD CONSTRAINT fk_tasks_source_asset
    FOREIGN KEY (source_asset_id) REFERENCES assets(id) ON DELETE SET NULL;

CREATE TRIGGER trg_assets_updated_at
    BEFORE UPDATE ON assets FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- task_items
-- ============================================================
CREATE TABLE task_items (
    id              SERIAL PRIMARY KEY,
    task_id         INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    item_type       TEXT NOT NULL DEFAULT 'general',
    title           TEXT NOT NULL,
    description     TEXT,
    price           FLOAT,
    price_currency  TEXT NOT NULL DEFAULT 'USD',
    price_period    TEXT CHECK (price_period IS NULL OR price_period IN
                    ('total','monthly','weekly','nightly','yearly')),
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','favorite','done','dismissed')),
    source_url      TEXT,
    notes           TEXT,
    pros            TEXT,
    cons            TEXT,
    specs           JSONB NOT NULL DEFAULT '{}'::jsonb,
    deleted_at      TIMESTAMPTZ,
    workspace_id    INTEGER REFERENCES workspaces(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    search_tsv      tsvector GENERATED ALWAYS AS (to_tsvector('english',
                        coalesce(title, '') || ' ' || coalesce(description, ''))) STORED
);

CREATE INDEX idx_task_items_task ON task_items(task_id);
CREATE INDEX idx_task_items_type ON task_items(item_type);
CREATE INDEX idx_task_items_status ON task_items(status);
CREATE INDEX idx_task_items_workspace ON task_items(workspace_id);
CREATE INDEX idx_task_items_active ON task_items(task_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_task_items_search ON task_items USING GIN (search_tsv);

CREATE TRIGGER trg_task_items_updated_at
    BEFORE UPDATE ON task_items FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- asset_missions junction
-- ============================================================
CREATE TABLE asset_missions (
    asset_id    INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    mission_id  INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (asset_id, mission_id)
);

CREATE INDEX idx_asset_missions_mission ON asset_missions(mission_id);

-- ============================================================
-- notes
-- ============================================================
CREATE TABLE notes (
    id              SERIAL PRIMARY KEY,
    mission_id      INTEGER REFERENCES missions(id) ON DELETE SET NULL,
    title           TEXT NOT NULL,
    content         TEXT NOT NULL,
    note_type       TEXT NOT NULL DEFAULT 'general'
                    CHECK (note_type IN ('general','research','idea','decision','meeting','reference')),
    source_url      TEXT,
    source_asset_id INTEGER REFERENCES assets(id) ON DELETE SET NULL,
    metadata_json   JSONB DEFAULT '{}'::jsonb,
    deleted_at      TIMESTAMPTZ,
    task_id         INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
    workspace_id    INTEGER REFERENCES workspaces(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    search_tsv      tsvector GENERATED ALWAYS AS (to_tsvector('english',
                        coalesce(title, '') || ' ' || coalesce(content, ''))) STORED
);

CREATE INDEX idx_notes_mission ON notes(mission_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_notes_type ON notes(note_type);
CREATE INDEX idx_notes_task_id ON notes(task_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_notes_workspace ON notes(workspace_id);
CREATE INDEX idx_notes_search ON notes USING GIN (search_tsv);

CREATE TRIGGER trg_notes_updated_at
    BEFORE UPDATE ON notes FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- tags + junctions
-- ============================================================
CREATE TABLE tags (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    category    TEXT DEFAULT 'general',
    description TEXT,
    color       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tags_category ON tags(category);

CREATE TABLE task_tags (
    task_id     INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (task_id, tag_id)
);

CREATE TABLE note_tags (
    note_id     INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (note_id, tag_id)
);

-- ============================================================
-- document_history (shared pattern with brain)
-- ============================================================
CREATE TABLE document_history (
    history_id      BIGSERIAL PRIMARY KEY,
    source_table    TEXT NOT NULL,
    source_key      TEXT NOT NULL,
    body            TEXT NOT NULL,
    edited_by       TEXT DEFAULT 'system',
    change_note     TEXT,
    edited_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_document_history_source ON document_history(source_table, source_key, edited_at DESC);
