"""
Enterprise Personal — SQLAlchemy Metadata Models

Schema source of truth for the `personal` Postgres database,
which replaces the SQLite DB at Data/enterprise.db.

NOTE: This file exceeds the 300-line dark code limit. Documented exception
approved for schema definitions (inherently large, cannot be split without
breaking Alembic's single-metadata requirement). Mirrors nv_models.py's
documented exception.

The app (server.py) continues to use psycopg2 directly — NO ORM at runtime.
This file exists so Alembic autogenerate can detect schema drift against the
Python model definitions.

TRIGGER BLIND SPOT: one shared `touch_updated_at()` trigger function plus
5 per-table triggers live in production but are NOT represented in this
file. Alembic autogenerate does not detect trigger changes. Manual DDL
required for trigger modifications. Trigger DDL lives in the baseline
migration and must be updated there for future trigger changes.

Tables with updated_at triggers:
- missions
- tasks
- task_items
- notes
- assets

Reshape decisions (vs original SQLite schema):
- TEXT ISO timestamps -> TIMESTAMP(timezone=True)
- INTEGER 0/1 flags  -> Boolean
- TEXT JSON columns  -> JSONB
- FTS5 virtual tables -> tsvector GENERATED ALWAYS ... STORED + GIN indexes
  (see the baseline migration — SQLAlchemy Core does not express generated
  columns cleanly across dialects, so the tsvector columns and GIN indexes
  are added in the migration file, NOT here. This IS an autogenerate blind
  spot — future schema changes to FTS columns require manual migration DDL.)

Dropped at migration (present in SQLite, not carried over):
- task_dependencies (0 rows, dormant)
- asset_tags       (0 rows, dormant)
- processing_log   (0 rows, dormant)
- missions_backup_20260408 (legacy pre-workspace backup)
"""

from sqlalchemy import (
    MetaData,
    Table,
    Column,
    Integer,
    Text,
    String,
    Boolean,
    Float,
    CheckConstraint,
    ForeignKey,
    Index,
    UniqueConstraint,
    Date,
    text,
)
from sqlalchemy.dialects.postgresql import TIMESTAMP, JSONB, ARRAY

metadata = MetaData()

# ============================================================================
# SCHEMA VERSION — carried over, informational only. Alembic owns migrations.
# ============================================================================

schema_version = Table(
    "schema_version",
    metadata,
    Column("version", Integer, primary_key=True),
    Column(
        "applied_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
    Column("description", Text),
)

# ============================================================================
# WORKSPACES — Personal / Evenrail scoping (added Apr 8, 2026, SQLite v?)
# ============================================================================

workspaces = Table(
    "workspaces",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("slug", Text, nullable=False, unique=True),
    Column("name", Text, nullable=False),
    Column(
        "type",
        Text,
        CheckConstraint("type IN ('personal', 'business')"),
        nullable=False,
    ),
    Column("color", Text),
    Column("icon", Text),
    Column("sort_order", Integer, server_default=text("0")),
    Column("is_default", Boolean, nullable=False, server_default=text("FALSE")),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

# ============================================================================
# MISSIONS
# ============================================================================

missions = Table(
    "missions",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("name", Text, nullable=False, unique=True),
    Column("slug", Text, nullable=False, unique=True),
    Column("description", Text),
    Column(
        "status",
        Text,
        CheckConstraint(
            "status IN ('planning','active','paused','completed','archived')"
        ),
        nullable=False,
        server_default=text("'active'"),
    ),
    Column("priority", Integer, server_default=text("0")),
    Column("started_at", TIMESTAMP(timezone=True)),
    Column("target_date", TIMESTAMP(timezone=True)),
    Column("completed_at", TIMESTAMP(timezone=True)),
    Column("metadata_json", JSONB, server_default=text("'{}'::jsonb")),
    Column("deleted_at", TIMESTAMP(timezone=True)),
    Column("workspace_id", Integer, ForeignKey("workspaces.id")),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
    Column(
        "updated_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_missions_workspace", missions.c.workspace_id)

# ============================================================================
# ASSETS
# ============================================================================

assets = Table(
    "assets",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("file_path", Text, nullable=False),
    Column("original_filename", Text, nullable=False),
    Column("file_type", Text, nullable=False),
    Column("mime_type", Text),
    Column("file_size", Integer),
    Column("sha256_hash", Text, nullable=False),
    Column("title", Text),
    Column("description", Text),
    Column("source_url", Text),
    Column("exif_json", JSONB, server_default=text("'{}'::jsonb")),
    Column("metadata_json", JSONB, server_default=text("'{}'::jsonb")),
    Column(
        "processing_status",
        Text,
        CheckConstraint(
            "processing_status IN ('pending','processing','completed','failed','skipped')"
        ),
        nullable=False,
        server_default=text("'pending'"),
    ),
    Column("is_duplicate", Boolean, nullable=False, server_default=text("FALSE")),
    Column(
        "duplicate_of_id",
        Integer,
        ForeignKey("assets.id", ondelete="SET NULL"),
    ),
    Column("deleted_at", TIMESTAMP(timezone=True)),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
    Column(
        "updated_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_assets_hash", assets.c.sha256_hash)
Index("idx_assets_file_type", assets.c.file_type)
Index("idx_assets_processing", assets.c.processing_status)
Index("idx_assets_duplicate_of", assets.c.duplicate_of_id)

# ============================================================================
# ASSET <-> MISSION JOIN
# ============================================================================

asset_missions = Table(
    "asset_missions",
    metadata,
    Column(
        "asset_id",
        Integer,
        ForeignKey("assets.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "mission_id",
        Integer,
        ForeignKey("missions.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_asset_missions_asset", asset_missions.c.asset_id)
Index("idx_asset_missions_mission", asset_missions.c.mission_id)

# ============================================================================
# TASKS
# ============================================================================

tasks = Table(
    "tasks",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column(
        "mission_id",
        Integer,
        ForeignKey("missions.id", ondelete="CASCADE"),
        nullable=False,
    ),
    Column("title", Text, nullable=False),
    Column("description", Text),
    Column(
        "status",
        Text,
        CheckConstraint(
            "status IN ('todo','in_progress','blocked','done','cancelled')"
        ),
        nullable=False,
        server_default=text("'todo'"),
    ),
    Column(
        "priority",
        Integer,
        CheckConstraint("priority BETWEEN 0 AND 4"),
        nullable=False,
        server_default=text("0"),
    ),
    Column("due_date", TIMESTAMP(timezone=True)),
    Column("completed_at", TIMESTAMP(timezone=True)),
    Column("assigned_to", Text),
    Column(
        "source_asset_id",
        Integer,
        ForeignKey("assets.id", ondelete="SET NULL"),
    ),
    Column("metadata_json", JSONB, server_default=text("'{}'::jsonb")),
    Column("resolution", Text),
    Column("deleted_at", TIMESTAMP(timezone=True)),
    Column("workspace_id", Integer, ForeignKey("workspaces.id")),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
    Column(
        "updated_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_tasks_mission", tasks.c.mission_id)
Index("idx_tasks_status", tasks.c.status)
Index("idx_tasks_priority", tasks.c.priority.desc())
Index("idx_tasks_source_asset", tasks.c.source_asset_id)
Index("idx_tasks_due", tasks.c.due_date)
Index("idx_tasks_mission_status", tasks.c.mission_id, tasks.c.status)
Index("idx_tasks_workspace", tasks.c.workspace_id)
Index(
    "idx_tasks_mission_workspace",
    tasks.c.mission_id,
    tasks.c.workspace_id,
)

# ============================================================================
# TASK ITEMS — per-task research rows (generic items)
# ============================================================================

task_items = Table(
    "task_items",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column(
        "task_id",
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
    ),
    Column(
        "item_type",
        Text,
        nullable=False,
        server_default=text("'general'"),
    ),
    Column("title", Text, nullable=False),
    Column("description", Text),
    Column("price", Float),
    Column(
        "price_currency",
        Text,
        nullable=False,
        server_default=text("'USD'"),
    ),
    Column(
        "price_period",
        Text,
        CheckConstraint(
            "price_period IS NULL OR price_period IN ("
            "'total','monthly','weekly','nightly','yearly')"
        ),
    ),
    Column(
        "status",
        Text,
        CheckConstraint(
            "status IN ('active','favorite','done','dismissed')"
        ),
        nullable=False,
        server_default=text("'active'"),
    ),
    Column("source_url", Text),
    Column("notes", Text),
    Column("pros", Text),
    Column("cons", Text),
    Column("specs", JSONB, nullable=False, server_default=text("'{}'::jsonb")),
    Column("deleted_at", TIMESTAMP(timezone=True)),
    Column("workspace_id", Integer, ForeignKey("workspaces.id")),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
    Column(
        "updated_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_task_items_task", task_items.c.task_id)
Index("idx_task_items_type", task_items.c.item_type)
Index("idx_task_items_status", task_items.c.status)
Index(
    "idx_task_items_task_type",
    task_items.c.task_id,
    task_items.c.item_type,
    postgresql_where=(task_items.c.deleted_at.is_(None)),
)
Index("idx_task_items_price", task_items.c.price)
Index("idx_task_items_workspace", task_items.c.workspace_id)

# ============================================================================
# NOTES
# ============================================================================

notes = Table(
    "notes",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column(
        "mission_id",
        Integer,
        ForeignKey("missions.id", ondelete="SET NULL"),
    ),
    Column("title", Text, nullable=False),
    Column("content", Text, nullable=False),
    Column(
        "note_type",
        Text,
        CheckConstraint(
            "note_type IN ('general','research','idea','decision','meeting','reference')"
        ),
        nullable=False,
        server_default=text("'general'"),
    ),
    Column("source_url", Text),
    Column(
        "source_asset_id",
        Integer,
        ForeignKey("assets.id", ondelete="SET NULL"),
    ),
    Column("metadata_json", JSONB, server_default=text("'{}'::jsonb")),
    Column("deleted_at", TIMESTAMP(timezone=True)),
    Column("task_id", Integer, ForeignKey("tasks.id")),
    Column("workspace_id", Integer, ForeignKey("workspaces.id")),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
    Column(
        "updated_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_notes_mission", notes.c.mission_id)
Index("idx_notes_type", notes.c.note_type)
Index("idx_notes_task_id", notes.c.task_id)
Index("idx_notes_source_asset", notes.c.source_asset_id)
Index("idx_notes_workspace", notes.c.workspace_id)
Index(
    "idx_notes_mission_workspace",
    notes.c.mission_id,
    notes.c.workspace_id,
)
Index(
    "idx_notes_task_workspace",
    notes.c.task_id,
    notes.c.workspace_id,
)

# ============================================================================
# TAGS + JUNCTIONS
# ============================================================================

tags = Table(
    "tags",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("name", Text, nullable=False, unique=True),
    Column("category", Text, server_default=text("'general'")),
    Column("description", Text),
    Column("color", Text),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_tags_category", tags.c.category)

task_tags = Table(
    "task_tags",
    metadata,
    Column(
        "task_id",
        Integer,
        ForeignKey("tasks.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "tag_id",
        Integer,
        ForeignKey("tags.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

note_tags = Table(
    "note_tags",
    metadata,
    Column(
        "note_id",
        Integer,
        ForeignKey("notes.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "tag_id",
        Integer,
        ForeignKey("tags.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

# ============================================================================
# IDEAS — NEW table. Promotes ideas.md to the database per the
# Future Ideas Protocol (CLAUDE.md). Soft-delete pattern matches other
# content tables. tsvector + GIN over title+summary+biggest_risk+next_action
# added in the baseline migration (generated column, blind spot).
# ============================================================================

ideas = Table(
    "ideas",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("title", Text, nullable=False),
    Column(
        "status",
        Text,
        CheckConstraint(
            "status IN ('proposed','deferred','approved','built','shipped')"
        ),
        nullable=False,
        server_default=text("'proposed'"),
    ),
    Column("category", Text),
    Column(
        "date_filed",
        Date,
        nullable=False,
        server_default=text("CURRENT_DATE"),
    ),
    Column("summary", Text),
    Column("estimated_cost_text", Text),
    Column(
        "estimated_effort",
        Text,
        CheckConstraint(
            "estimated_effort IS NULL OR "
            "estimated_effort IN ('small','medium','large')"
        ),
    ),
    Column("linked_docs", ARRAY(Text), server_default=text("'{}'::text[]")),
    Column("biggest_risk", Text),
    Column("next_action", Text),
    Column("deleted_at", TIMESTAMP(timezone=True)),
    Column(
        "created_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
    Column(
        "updated_at",
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=text("CURRENT_TIMESTAMP"),
    ),
)

Index("idx_ideas_status", ideas.c.status)
Index("idx_ideas_date_filed", ideas.c.date_filed.desc())
