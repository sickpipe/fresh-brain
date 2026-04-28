"""
Brain DB — SQLAlchemy Metadata Models

Schema source of truth for the brain Postgres database. Runtime code
uses raw psycopg2 (no ORM); this file exists for Alembic autogenerate
only. Mirror pattern: newvision/nv_models.py.

NOTE: File exceeds the 300-line dark code limit. Documented exception
approved for schema definitions (same reasoning as nv_models.py —
inherently large, cannot be split without breaking Alembic's single-
metadata requirement).

VECTOR BLIND SPOT: ivfflat vector indexes cannot be declared via
SQLAlchemy Index() — `USING ivfflat (embedding vector_cosine_ops)` is
pgvector-specific DDL. Those indexes are created via raw op.execute()
in the initial migration. Alembic autogenerate will NOT detect changes
to vector indexes; manual migration DDL required.

CREATE EXTENSION BLIND SPOT: `CREATE EXTENSION vector` is not expressed
in SQLAlchemy metadata. The initial migration runs it as its first
statement. Subsequent migrations assume the extension is present.
"""

from sqlalchemy import (
    MetaData,
    Table,
    Column,
    Integer,
    BigInteger,
    Text,
    Boolean,
    CheckConstraint,
    Index,
    Date,
    ARRAY,
)
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, TSVECTOR
from pgvector.sqlalchemy import Vector

metadata = MetaData()

EMBEDDING_DIM = 384  # all-MiniLM-L6-v2 (local, sentence-transformers)

# ============================================================================
# team_members — one row per specialist profile (replaces Team/*.md)
# ============================================================================

team_members = Table(
    "team_members",
    metadata,
    Column("slug", Text, primary_key=True),
    Column("display_name", Text, nullable=False),
    Column("role", Text, nullable=False),
    Column("persona", Text, nullable=False),
    Column("body", Text, nullable=False),
    Column(
        "model_tier",
        Text,
        CheckConstraint("model_tier IN ('opus','sonnet','haiku')", name="team_members_model_tier_check"),
    ),
    Column(
        "status",
        Text,
        CheckConstraint("status IN ('active','retired')", name="team_members_status_check"),
        nullable=False,
        server_default="'active'",
    ),
    Column("tags", ARRAY(Text)),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text),
    Column("tsv", TSVECTOR),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("updated_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("deleted_at", TIMESTAMP(timezone=True)),
)

Index("idx_team_members_status", team_members.c.status)

# ============================================================================
# topic_documents — long-form ops reference docs (evenrail-ops, nv-operations, etc.)
# ============================================================================

topic_documents = Table(
    "topic_documents",
    metadata,
    Column("slug", Text, primary_key=True),
    Column("title", Text, nullable=False),
    Column("body", Text, nullable=False),
    Column("topic", Text, nullable=False),
    Column("source_path", Text),
    Column("tags", ARRAY(Text)),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text),
    Column("tsv", TSVECTOR),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("updated_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("deleted_at", TIMESTAMP(timezone=True)),
)

Index("idx_topic_documents_topic", topic_documents.c.topic)
Index("idx_topic_documents_updated_at", topic_documents.c.updated_at.desc())

# ============================================================================
# memory_entries — atomic facts split out of MEMORY.md
# ============================================================================

memory_entries = Table(
    "memory_entries",
    metadata,
    Column("slug", Text, primary_key=True),
    Column(
        "entry_type",
        Text,
        CheckConstraint(
            "entry_type IN ('user_pref','dictation_map','architecture_fact','ship_log',"
            "'tool_note','trading_context','credential_note','protocol_pointer','lesson_learned')",
            name="memory_entries_entry_type_check",
        ),
        nullable=False,
    ),
    Column("title", Text, nullable=False),
    Column("body", Text, nullable=False),
    Column("related_topic", Text),
    Column("tags", ARRAY(Text)),
    Column("occurred_on", Date),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text),
    Column("tsv", TSVECTOR),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("updated_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("deleted_at", TIMESTAMP(timezone=True)),
)

Index("idx_memory_entries_type", memory_entries.c.entry_type)
Index("idx_memory_entries_related_topic", memory_entries.c.related_topic)
Index("idx_memory_entries_updated_at", memory_entries.c.updated_at.desc())

# ============================================================================
# session_notes — append-only session handoff log
# ============================================================================
# No updated_at, no soft-delete — handoffs are historical record.
# Corrections are filed as NEW rows referencing the original slug.

session_notes = Table(
    "session_notes",
    metadata,
    Column("slug", Text, primary_key=True),
    Column("title", Text),
    # session_ended_at nullable (v6) — populated when session truly ends.
    Column("session_ended_at", TIMESTAMP(timezone=True)),
    Column("summary", Text, nullable=False),
    Column("body", Text, nullable=False),
    Column("projects_touched", ARRAY(Text)),
    Column("tags", ARRAY(Text)),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text),
    Column("tsv", TSVECTOR),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
)

Index("idx_session_notes_ended_at", session_notes.c.session_ended_at.desc())

# ============================================================================
# standing_orders — codified behavioral rules (CLAUDE.md "Standing Order: X" blocks)
# ============================================================================

standing_orders = Table(
    "standing_orders",
    metadata,
    Column("slug", Text, primary_key=True),
    Column("title", Text, nullable=False),
    Column("body", Text, nullable=False),
    Column(
        "scope",
        Text,
        CheckConstraint("scope IN ('all','spock','team','captain')", name="standing_orders_scope_check"),
        nullable=False,
    ),
    Column("active", Boolean, nullable=False, server_default="TRUE"),
    Column("effective_from", Date),
    Column("tags", ARRAY(Text)),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text),
    Column("tsv", TSVECTOR),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("updated_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("deleted_at", TIMESTAMP(timezone=True)),
)

Index("idx_standing_orders_active", standing_orders.c.active)

# ============================================================================
# ideas — deferred-but-not-dead backlog (current ideas.md)
# ============================================================================

ideas = Table(
    "ideas",
    metadata,
    Column("slug", Text, primary_key=True),
    Column("title", Text, nullable=False),
    Column(
        "status",
        Text,
        CheckConstraint(
            "status IN ('proposed','deferred','approved','built','shipped','rejected')",
            name="ideas_status_check",
        ),
        nullable=False,
    ),
    Column("category", Text),
    Column("summary", Text, nullable=False),
    Column("body", Text),
    Column("estimated_cost", Text),
    Column(
        "estimated_effort",
        Text,
        CheckConstraint("estimated_effort IN ('small','medium','large')", name="ideas_estimated_effort_check"),
    ),
    Column("biggest_risk", Text),
    Column("next_action", Text),
    Column("filed_on", Date, nullable=False),
    Column("linked_docs", ARRAY(Text)),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text),
    Column("tsv", TSVECTOR),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("updated_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("deleted_at", TIMESTAMP(timezone=True)),
)

Index("idx_ideas_status", ideas.c.status)
Index("idx_ideas_category", ideas.c.category)

# ============================================================================
# captain_intent — chunked CAPTAIN-INTENT.md (values, tradeoffs, decisions)
# ============================================================================

captain_intent = Table(
    "captain_intent",
    metadata,
    Column("slug", Text, primary_key=True),
    Column(
        "section",
        Text,
        CheckConstraint(
            "section IN ('identity','core_value','tradeoff','decision_boundary',"
            "'success_criterion','do_not_rule')",
            name="captain_intent_section_check",
        ),
        nullable=False,
    ),
    Column("title", Text, nullable=False),
    Column("body", Text, nullable=False),
    Column("priority", Integer),
    Column("tags", ARRAY(Text)),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text),
    Column("tsv", TSVECTOR),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("updated_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("deleted_at", TIMESTAMP(timezone=True)),
)

Index("idx_captain_intent_section", captain_intent.c.section)

# ============================================================================
# cross_references — edges from brain rows to rows in sister DBs
# ============================================================================
# BIGSERIAL PK (not slug) — machine-generated relationships, readable PK
# earns nothing. foreign_id is TEXT because the three foreign DBs mix
# INTEGER ids with slug-like keys. No FK constraints on foreign_id
# (crosses DB boundaries); integrity enforced at write time by the MCP
# server.

cross_references = Table(
    "cross_references",
    metadata,
    Column("id", BigInteger, primary_key=True, autoincrement=True),
    Column(
        "source_table",
        Text,
        CheckConstraint(
            "source_table IN ('team_members','topic_documents','memory_entries',"
            "'session_notes','standing_orders','ideas','captain_intent')",
            name="cross_references_source_table_check",
        ),
        nullable=False,
    ),
    Column("source_key", Text, nullable=False),
    Column(
        "foreign_db",
        Text,
        CheckConstraint(
            "foreign_db IN ('evenrail_app','newvision_prod','personal')",
            name="cross_references_foreign_db_check",
        ),
        nullable=False,
    ),
    Column("foreign_table", Text, nullable=False),
    Column("foreign_id", Text, nullable=False),
    Column("note", Text, nullable=False),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("deleted_at", TIMESTAMP(timezone=True)),
)

Index(
    "idx_cross_references_source",
    cross_references.c.source_table,
    cross_references.c.source_key,
)
Index(
    "idx_cross_references_foreign",
    cross_references.c.foreign_db,
    cross_references.c.foreign_table,
    cross_references.c.foreign_id,
)

# ============================================================================
# document_chunks — chunked sub-embeddings for oversized parent rows
# ============================================================================
# Parent rows whose body exceeds the embedding model's token cap get sliced on H2
# headings here. Each chunk has its own embedding. Search unions parent +
# chunk hits and dedupes by (source_table, slug). Soft FK only (source_table
# + slug) — Postgres can't FK across the 7 content tables without a polymorphic
# helper, so mcp_tools.upsert is responsible for clearing chunks on row-body
# rewrite (and would clear them on row delete if a delete path existed).

document_chunks = Table(
    "document_chunks",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("source_table", Text, nullable=False),
    Column("slug", Text, nullable=False),
    Column("chunk_index", Integer, nullable=False),
    Column("heading", Text),
    Column("body", Text, nullable=False),
    Column("embedding", Vector(EMBEDDING_DIM)),
    Column("embedding_model", Text, nullable=False, server_default="'all-MiniLM-L6-v2'"),
    Column("created_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("updated_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
)

Index(
    "idx_document_chunks_source",
    document_chunks.c.source_table,
    document_chunks.c.slug,
    unique=False,
)
# UNIQUE (source_table, slug, chunk_index) — created in add_document_chunks.py
# ivfflat embedding index — created in add_document_chunks.py (lists=50)

# ============================================================================
# document_history — append-only version log for all versioned content tables
# ============================================================================
# App-level upsert copies the old body into this table before overwrite.
# source_table constrained to the 6 versioned content tables (session_notes
# and cross_references are not versioned).

document_history = Table(
    "document_history",
    metadata,
    Column("history_id", BigInteger, primary_key=True, autoincrement=True),
    Column(
        "source_table",
        Text,
        CheckConstraint(
            "source_table IN ('team_members','topic_documents','memory_entries',"
            "'standing_orders','ideas','captain_intent')",
            name="document_history_source_table_check",
        ),
        nullable=False,
    ),
    Column("source_key", Text, nullable=False),
    Column("body", Text, nullable=False),
    Column("snapshot", JSONB, nullable=False),
    Column("edited_by", Text),
    Column("edited_at", TIMESTAMP(timezone=True), nullable=False, server_default="now()"),
    Column("change_note", Text),
)

Index(
    "idx_document_history_source",
    document_history.c.source_table,
    document_history.c.source_key,
    document_history.c.edited_at.desc(),
)
