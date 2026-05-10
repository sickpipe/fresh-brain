-- Migration: 013_standing_orders_scaling.sql
-- Database: brain
-- Date: 2026-05-10
-- Description: Tiered standing orders with audit log and signal tag support.
--   - Add tier column (1 = always loaded, 2 = manifest only)
--   - Add manifest_summary for compact Tier 2 display
--   - Add signal_tags array for operator tag matching
--   - Create standing_order_fires audit log table
--   - Add signal_tag_map to brain_config
--   - Regenerate TSV to include manifest_summary
--   - Backfill tier for core orders
--
-- Does NOT add priority (removed per design review).
-- Does NOT add fire_count/last_fired_at to standing_orders
--   (fire tracking lives in the audit table).

-- ========== UP ==========

-- 1. Tier column: 1 = core (loaded in full at bootstrap), 2 = situational (manifest only)
ALTER TABLE standing_orders
    ADD COLUMN tier INTEGER NOT NULL DEFAULT 2;

ALTER TABLE standing_orders
    ADD CONSTRAINT chk_standing_orders_tier
    CHECK (tier IN (1, 2));

-- 2. Compact one-line summary for Tier 2 manifest display (~50 tokens max).
-- Enforced at 200 chars to prevent manifest bloat.
ALTER TABLE standing_orders
    ADD COLUMN manifest_summary VARCHAR(200);

-- 3. Signal tags: which operator prefixes map to this order.
-- Example: ARRAY['journal'] on a grounded-journal order.
-- An order can respond to multiple tags. A tag can map to multiple orders.
ALTER TABLE standing_orders
    ADD COLUMN signal_tags TEXT[];

-- 4. Audit log for standing order fires. Append-only.
-- Replaces fire_count/last_fired_at on the canonical row (separates
-- config from telemetry).
CREATE TABLE standing_order_fires (
    id              BIGSERIAL PRIMARY KEY,
    order_slug      TEXT NOT NULL REFERENCES standing_orders(slug),
    fired_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    match_method    TEXT NOT NULL,
    session_slug    TEXT,
    trigger_context TEXT
);

ALTER TABLE standing_order_fires
    ADD CONSTRAINT chk_standing_order_fires_match_method
    CHECK (match_method IN ('signal_tag', 'retrieval', 'manual_scan', 'direct'));

CREATE INDEX idx_standing_order_fires_slug ON standing_order_fires(order_slug);
CREATE INDEX idx_standing_order_fires_at ON standing_order_fires(fired_at DESC);

-- 5. Signal tag map in brain_config (operator-editable, no code deploy needed).
INSERT INTO brain_config (key, value, description)
VALUES (
    'signal_tag_map',
    '{"remember":["standing-remember-this-protocol"]}',
    'Maps operator signal tags to standing order slugs. JSON object: tag -> [slugs]. Loaded at bootstrap.'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, description = EXCLUDED.description;

-- 6. Backfill: set tier 1 for core orders.
UPDATE standing_orders SET tier = 1 WHERE slug IN (
    'standing-work-delegation-protocol',
    'standing-end-session-protocol',
    'standing-credential-security-gate',
    'standing-remember-this-protocol'
);

-- 7. Backfill: set signal_tags for orders that respond to operator prefixes.
UPDATE standing_orders SET signal_tags = ARRAY['remember']
    WHERE slug = 'standing-remember-this-protocol';

-- 8. Regenerate TSV to include manifest_summary in full-text search.
-- tsv is a GENERATED ALWAYS column -- must drop and recreate.
DROP INDEX IF EXISTS idx_standing_orders_tsv;
ALTER TABLE standing_orders DROP COLUMN IF EXISTS tsv;
ALTER TABLE standing_orders ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(body, '') || ' ' ||
            coalesce(manifest_summary, ''))
    ) STORED;
CREATE INDEX idx_standing_orders_tsv ON standing_orders USING GIN (tsv);

-- Register this migration in the ledger.
INSERT INTO applied_migrations (filename) VALUES ('013_standing_orders_scaling.sql')
ON CONFLICT (filename) DO NOTHING;

-- Bump schema_version for informational continuity.
UPDATE brain_config SET value = '14' WHERE key = 'schema_version';

-- ========== DOWN (do not run above this line -- paste into psql manually) ==========
\quit

-- Restore original TSV (title + body only).
DROP INDEX IF EXISTS idx_standing_orders_tsv;
ALTER TABLE standing_orders DROP COLUMN IF EXISTS tsv;
ALTER TABLE standing_orders ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(body, ''))
    ) STORED;
CREATE INDEX idx_standing_orders_tsv ON standing_orders USING GIN (tsv);

-- Remove signal_tag_map from brain_config.
DELETE FROM brain_config WHERE key = 'signal_tag_map';

-- Drop audit table and its indexes.
DROP TABLE IF EXISTS standing_order_fires;

-- Remove new columns from standing_orders.
ALTER TABLE standing_orders DROP COLUMN IF EXISTS signal_tags;
ALTER TABLE standing_orders DROP COLUMN IF EXISTS manifest_summary;
ALTER TABLE standing_orders DROP CONSTRAINT IF EXISTS chk_standing_orders_tier;
ALTER TABLE standing_orders DROP COLUMN IF EXISTS tier;

-- Unregister migration.
DELETE FROM applied_migrations WHERE filename = '013_standing_orders_scaling.sql';
UPDATE brain_config SET value = '13' WHERE key = 'schema_version';
