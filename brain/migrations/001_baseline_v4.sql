-- Migration: 001_baseline_v4.sql
-- Database: brain
-- Date: 2026-04-28
-- Description: Baseline marker for brain schema v4. No SQL executed.

-- This migration is a reference marker. The actual schema is in ../schema.sql.
-- Brain went v1 -> v4 through a mix of Alembic (v1) and direct DB changes (v2-v4).
-- This file establishes the baseline for the new raw SQL migration system.

-- ========== UP ==========

-- Tables present at v4 (reference only, not executed):
--   brain_config        — key-value system settings
--   team_members        — AI team member profiles (pgvector embeddings)
--   topic_documents     — reference docs, ops guides
--   memory_entries      — facts, preferences, ship logs
--   session_notes       — end-of-session summaries (append-only)
--   standing_orders     — automated behavior triggers
--   ideas               — ideas pipeline (proposed -> shipped)
--   operator_intent     — operator values and decision boundaries
--   document_chunks     — chunked content with embeddings
--   document_history    — version history for all content tables
--   access_log          — read access tracking

-- ========== DOWN ==========

-- N/A: baseline migration, rollback not supported
