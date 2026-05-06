-- Migration: 010_add_mcp_tool_log.sql
-- Database: brain
-- Date: 2026-05-06
-- Description: Add append-only table for MCP tool call observability
--
-- Why: Every MCP tool call should be tracked so the operator can see what
-- context the LLM requested, how long it took, and how often each tool
-- is used. This is fire-and-forget logging — failures never block the
-- tool call itself.

-- ========== UP ==========

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

CREATE INDEX idx_mcp_tool_log_called_at
    ON mcp_tool_log (called_at DESC);

CREATE INDEX idx_mcp_tool_log_tool_name
    ON mcp_tool_log (tool_name);

CREATE INDEX idx_mcp_tool_log_session_id
    ON mcp_tool_log (session_id) WHERE session_id IS NOT NULL;

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('010_add_mcp_tool_log.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '11' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

DROP TABLE IF EXISTS mcp_tool_log;
DELETE FROM applied_migrations WHERE filename = '010_add_mcp_tool_log.sql';
UPDATE brain_config SET value = '10' WHERE key = 'schema_version';
