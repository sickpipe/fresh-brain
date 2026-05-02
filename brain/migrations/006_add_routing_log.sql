-- Migration: 006_add_routing_log.sql
-- Database: brain
-- Date: 2026-05-01
-- Description: Add routing_log table to track all memory saves across databases
--
-- Why: Every memory save/upsert touches one of three databases (brain,
-- personal, evenrail_app) and a specific table within it. This table
-- records the routing decision so periodic audits can verify correctness,
-- spot misrouted data, and trace who triggered each write.

-- ========== UP ==========

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

-- Query patterns:
--   "Show me everything routed to personal last week"
--   "What got written to standing_orders today?"
--   "Find all saves for slug X across all databases"
--   "Audit: what did team member Y write this session?"

CREATE INDEX idx_routing_log_destination_db
    ON routing_log (destination_db);

CREATE INDEX idx_routing_log_destination_table
    ON routing_log (destination_table);

CREATE INDEX idx_routing_log_record_slug
    ON routing_log (record_slug);

CREATE INDEX idx_routing_log_created_at
    ON routing_log (created_at DESC);

-- Composite index for the most common audit query: filter by db + time range
CREATE INDEX idx_routing_log_db_created
    ON routing_log (destination_db, created_at DESC);

-- Soft-delete filter: live rows only
CREATE INDEX idx_routing_log_live
    ON routing_log (id) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_routing_log_updated_at
    BEFORE UPDATE ON routing_log FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('006_add_routing_log.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '8' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

DROP TRIGGER IF EXISTS trg_routing_log_updated_at ON routing_log;
DROP TABLE IF EXISTS routing_log;
DELETE FROM applied_migrations WHERE filename = '006_add_routing_log.sql';
UPDATE brain_config SET value = '7' WHERE key = 'schema_version';
