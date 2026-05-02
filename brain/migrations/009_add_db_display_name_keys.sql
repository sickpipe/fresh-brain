-- Migration: 009_add_db_display_name_keys.sql
-- Database: brain
-- Date: 2026-05-02
-- Description: Add brain_config keys for database display names and app URLs

-- ========== UP ==========

INSERT INTO brain_config (key, value, description) VALUES
    ('personal_db_display_name', '', 'Display name for the personal database (set during setup)'),
    ('personal_db_app_url',      '', 'Personal dashboard URL (set during setup)'),
    ('business_db_display_name', '', 'Display name for the business database (set when business pack installed)'),
    ('business_db_app_url',      '', 'Business dashboard URL (set when business pack installed)')
ON CONFLICT (key) DO NOTHING;

-- ========== DOWN ==========

DELETE FROM brain_config WHERE key IN (
    'personal_db_display_name',
    'personal_db_app_url',
    'business_db_display_name',
    'business_db_app_url'
);
