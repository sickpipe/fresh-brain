-- Migration: 008_update_remember_this_protocol.sql
-- Database: brain
-- Date: 2026-05-02
-- Description: Update the remember-this-protocol standing order to include
--   the routing log step (Step 4). Only updates if edited_by = 'system',
--   respecting operator customizations.

-- ========== UP ==========

UPDATE standing_orders
SET body = $$## Protocol

When the operator says "remember this", "save this", "log this", or similar:

### Step 1 — Classify

| What it is | Where it goes |
|---|---|
| System knowledge, team config, ops docs, standing orders, ideas | Brain → appropriate table |
| Lessons learned, preferences, things that happened | Brain → `memory_entries` |
| Rules for how we work | Brain → `standing_orders` |
| Personal preferences, health, journal, contacts, finance | Personal (Enterprise) |
| Client/project deliverables, CRM records, invoices | Evenrail |
| Claude Code behavioral instructions (feedback, delegation rules) | Claude local memory (feedback type) |

### Step 2 — Pick the correct table within that database based on content type.

### Step 3 — Write the record using the appropriate MCP tool (memory_upsert, personal_create/update, evenrail_create/update).

### Step 4 — Log the routing decision

After every save, insert a row into `brain.routing_log`:

- `destination_db`: which database was written to (brain, personal, evenrail_app)
- `destination_table`: which table within that database
- `record_slug`: the slug of the saved record
- `rationale`: one-line explanation of why this database/table was chosen
- `triggered_by`: who initiated the save (operator, orchestrator, or team member slug)
- `session_context`: (optional) brief note on what was being discussed

This enables monthly audits to verify routing correctness and catch anomalies.

### Step 5 — Confirm to the operator what was saved and where.

## Rules

1. **One canonical location** — never duplicate the same content across databases.
2. **Infer from context** — if we've been working on Evenrail, it's business. If it's infrastructure/knowledge, it's brain. If it's personal life, it's Enterprise.
3. **Announce on ambiguity** — if something crosses boundaries, tell the operator where you're putting it so they can redirect.
4. **No local-memory-first** — brain is the source of truth for knowledge. Claude local memory is only for Claude Code behavioral instructions (feedback, delegation rules, etc.).
5. **Enterprise = personal database** (Star Trek theme: the operator's personal DB).
6. **Always log** — no save goes unlogged. The routing_log is how we audit and improve.$$
WHERE slug = 'standing-remember-this-protocol'
  AND edited_by = 'system';

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('008_update_remember_this_protocol.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '10' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

-- To roll back, restore the previous body from document_history:
--   SELECT body FROM document_history
--   WHERE source_table = 'standing_orders'
--     AND source_key = 'standing-remember-this-protocol'
--   ORDER BY edited_at DESC LIMIT 1;
-- Then UPDATE standing_orders SET body = <old_body>
--   WHERE slug = 'standing-remember-this-protocol';

DELETE FROM applied_migrations WHERE filename = '008_update_remember_this_protocol.sql';
UPDATE brain_config SET value = '9' WHERE key = 'schema_version';
