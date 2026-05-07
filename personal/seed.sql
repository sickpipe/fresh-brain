-- Personal Database Seed Data
-- Default config values for a fresh install.

INSERT INTO personal_config (key, value, description) VALUES
    ('owner_name', '', 'Name of the database owner (set during onboarding)'),
    ('timezone', 'UTC', 'Owner timezone'),
    ('database_name', 'personal', 'Display name for this database'),
    ('schema_version', '20', 'Schema version for reference');

INSERT INTO schema_version (version, name) VALUES
    (20, 'seed_baseline');
