"""
enterprise/mcp_tables.py — table-shape constants for personal MCP tools.

Defines which tables are accessible, which columns are readable/writable,
which tables support full-text search, and which get history tracking.
"""

ACCESSIBLE_TABLES = [
    "workspaces", "missions", "tasks", "task_items",
    "notes", "assets", "tags", "personal_config", "document_history",
    "journal_entries",
]

SEARCHABLE_TABLES = ["tasks", "notes", "task_items", "assets", "journal_entries"]

HISTORY_TABLES = {"notes": "content", "missions": "description", "tasks": "description", "journal_entries": "content"}

SELECT_COLUMNS = {
    "workspaces": [
        "id", "slug", "name", "type", "color", "icon",
        "sort_order", "is_default", "created_at",
    ],
    "missions": [
        "id", "name", "slug", "description", "status", "priority",
        "started_at", "target_date", "completed_at", "metadata_json",
        "deleted_at", "workspace_id", "created_at", "updated_at",
    ],
    "tasks": [
        "id", "mission_id", "title", "description", "status", "priority",
        "due_date", "completed_at", "assigned_to", "source_asset_id",
        "metadata_json", "resolution", "deleted_at", "workspace_id",
        "created_at", "updated_at",
    ],
    "task_items": [
        "id", "task_id", "item_type", "title", "description",
        "price", "price_currency", "price_period", "status",
        "source_url", "notes", "pros", "cons", "specs",
        "deleted_at", "workspace_id", "created_at", "updated_at",
    ],
    "notes": [
        "id", "mission_id", "title", "content", "note_type",
        "source_url", "source_asset_id", "metadata_json",
        "deleted_at", "task_id", "workspace_id", "created_at", "updated_at",
    ],
    "assets": [
        "id", "file_path", "original_filename", "file_type", "mime_type",
        "file_size", "sha256_hash", "title", "description", "source_url",
        "exif_json", "metadata_json", "processing_status",
        "is_duplicate", "duplicate_of_id",
        "deleted_at", "created_at", "updated_at",
    ],
    "tags": [
        "id", "name", "category", "description", "color", "created_at",
    ],
    "personal_config": [
        "key", "value", "description", "updated_at",
    ],
    "document_history": [
        "history_id", "source_table", "source_key", "body",
        "edited_by", "change_note", "edited_at",
    ],
    "journal_entries": [
        "id", "entry_date", "content", "grounded_response",
        "linked_topics", "mood_tags", "themes",
        "created_at", "updated_at", "deleted_at",
    ],
}

SUMMARY_COLUMNS = {
    "workspaces": ["id", "slug", "name", "type", "sort_order"],
    "missions": ["id", "name", "slug", "status", "priority", "workspace_id", "updated_at"],
    "tasks": ["id", "mission_id", "title", "status", "priority", "assigned_to", "due_date", "workspace_id", "updated_at"],
    "task_items": ["id", "task_id", "item_type", "title", "status", "price", "workspace_id", "updated_at"],
    "notes": ["id", "mission_id", "title", "note_type", "task_id", "workspace_id", "created_at", "updated_at"],
    "assets": ["id", "title", "original_filename", "file_type", "processing_status", "updated_at"],
    "tags": ["id", "name", "category", "color"],
    "personal_config": ["key", "value", "description", "updated_at"],
    "document_history": ["history_id", "source_table", "source_key", "edited_by", "change_note", "edited_at"],
    "journal_entries": [
        "id", "entry_date", "themes", "mood_tags", "linked_topics", "updated_at",
    ],
}

WRITABLE_COLUMNS = {
    "workspaces": ["slug", "name", "type", "color", "icon", "sort_order", "is_default"],
    "missions": [
        "name", "slug", "description", "status", "priority",
        "started_at", "target_date", "completed_at", "metadata_json", "workspace_id",
    ],
    "tasks": [
        "mission_id", "title", "description", "status", "priority",
        "due_date", "completed_at", "assigned_to", "source_asset_id",
        "metadata_json", "resolution", "workspace_id",
    ],
    "task_items": [
        "task_id", "item_type", "title", "description",
        "price", "price_currency", "price_period", "status",
        "source_url", "notes", "pros", "cons", "specs", "workspace_id",
    ],
    "notes": [
        "mission_id", "title", "content", "note_type",
        "source_url", "source_asset_id", "metadata_json", "task_id", "workspace_id",
    ],
    "assets": [
        "file_path", "original_filename", "file_type", "mime_type",
        "file_size", "sha256_hash", "title", "description", "source_url",
        "exif_json", "metadata_json", "processing_status",
    ],
    "tags": ["name", "category", "description", "color"],
    "personal_config": ["value", "description"],
    "journal_entries": [
        "entry_date", "content", "grounded_response",
        "linked_topics", "mood_tags", "themes",
    ],
}

REQUIRED_ON_CREATE = {
    "workspaces": ["slug", "name", "type"],
    "missions": ["name", "slug"],
    "tasks": ["mission_id", "title"],
    "task_items": ["task_id", "title"],
    "notes": ["title", "content"],
    "assets": ["file_path", "original_filename", "file_type", "sha256_hash"],
    "tags": ["name"],
    "personal_config": ["key", "value"],
    "journal_entries": ["entry_date", "content"],
}

HAS_SOFT_DELETE = {"missions", "tasks", "task_items", "notes", "assets", "journal_entries"}
