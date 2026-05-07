"""
enterprise/mcp_tool_schemas.py — JSON Schema definitions for personal MCP tools.

Each tool's inputSchema is required by the MCP spec for tools/list.
"""

PERSONAL_GET_SCHEMA = {
    "type": "object",
    "properties": {
        "table": {
            "type": "string",
            "description": (
                "Table to fetch from: workspaces, missions, tasks, "
                "task_items, notes, assets, tags, journal_entries"
            ),
        },
        "id": {
            "type": "integer",
            "description": "Row ID",
        },
    },
    "required": ["table", "id"],
}

PERSONAL_LIST_SCHEMA = {
    "type": "object",
    "properties": {
        "table": {
            "type": "string",
            "description": (
                "Table to list from: workspaces, missions, tasks, "
                "task_items, notes, assets, tags, journal_entries"
            ),
        },
        "mission_id": {
            "type": "integer",
            "description": "Filter by mission (tasks, task_items, notes)",
        },
        "workspace_id": {
            "type": "integer",
            "description": "Filter by workspace",
        },
        "task_id": {
            "type": "integer",
            "description": "Filter by task (task_items, notes)",
        },
        "status": {
            "type": "string",
            "description": "Filter by status",
        },
        "limit": {
            "type": "integer",
            "default": 50,
            "description": "Max rows to return (max 200)",
        },
        "offset": {
            "type": "integer",
            "default": 0,
            "description": "Skip first N rows (for pagination)",
        },
        "summary_only": {
            "type": "boolean",
            "default": False,
            "description": "If true, return lightweight columns only",
        },
    },
    "required": ["table"],
}

PERSONAL_CREATE_SCHEMA = {
    "type": "object",
    "properties": {
        "table": {
            "type": "string",
            "description": (
                "Table to insert into: workspaces, missions, tasks, "
                "task_items, notes, assets, tags, journal_entries"
            ),
        },
        "data": {
            "type": "object",
            "description": (
                "Column values. Required fields vary by table: "
                "missions(name, slug), tasks(mission_id, title), "
                "notes(title, content), task_items(task_id, title), "
                "tags(name), workspaces(slug, name, type), "
                "assets(file_path, original_filename, file_type, sha256_hash), "
                "journal_entries(entry_date, content)"
            ),
        },
    },
    "required": ["table", "data"],
}

PERSONAL_UPDATE_SCHEMA = {
    "type": "object",
    "properties": {
        "table": {
            "type": "string",
            "description": "Table to update",
        },
        "id": {
            "type": "integer",
            "description": "Row ID to update",
        },
        "data": {
            "type": "object",
            "description": "Fields to update (only writable columns accepted)",
        },
        "edited_by": {
            "type": "string",
            "default": "claude",
            "description": "Who made the edit (for history tracking)",
        },
        "change_note": {
            "type": "string",
            "description": "Short explanation of what changed (for history tracking)",
        },
    },
    "required": ["table", "id", "data"],
}

PERSONAL_SEARCH_SCHEMA = {
    "type": "object",
    "properties": {
        "query": {
            "type": "string",
            "description": "Search query (full-text, prefix-matched)",
        },
        "tables": {
            "type": "array",
            "items": {"type": "string"},
            "description": (
                "Tables to search (default: all searchable). "
                "Searchable: tasks, notes, task_items, assets, journal_entries"
            ),
        },
    },
    "required": ["query"],
}

PERSONAL_HISTORY_SCHEMA = {
    "type": "object",
    "properties": {
        "table": {
            "type": "string",
            "description": "Table (history supported: notes, missions, tasks)",
        },
        "id": {
            "type": "integer",
            "description": "Row ID to get history for",
        },
        "limit": {
            "type": "integer",
            "default": 10,
            "description": "Max history entries",
        },
        "summary_only": {
            "type": "boolean",
            "default": True,
            "description": "If true, return metadata only (no body snapshots)",
        },
    },
    "required": ["table", "id"],
}

PERSONAL_ROLLBACK_SCHEMA = {
    "type": "object",
    "properties": {
        "table": {
            "type": "string",
            "description": "Table (history supported: notes, missions, tasks)",
        },
        "id": {
            "type": "integer",
            "description": "Row ID to roll back",
        },
        "history_id": {
            "type": "integer",
            "description": "The history_id to restore (from personal_history results)",
        },
        "edited_by": {
            "type": "string",
            "default": "rollback",
            "description": "Who initiated the rollback",
        },
    },
    "required": ["table", "id", "history_id"],
}

PERSONAL_STATS_SCHEMA = {
    "type": "object",
    "properties": {
        "workspace_id": {
            "type": "integer",
            "description": "Optional workspace filter. Omit for global stats.",
        },
    },
    "required": [],
}

SCHEMAS = {
    "personal_get": PERSONAL_GET_SCHEMA,
    "personal_list": PERSONAL_LIST_SCHEMA,
    "personal_create": PERSONAL_CREATE_SCHEMA,
    "personal_update": PERSONAL_UPDATE_SCHEMA,
    "personal_search": PERSONAL_SEARCH_SCHEMA,
    "personal_history": PERSONAL_HISTORY_SCHEMA,
    "personal_rollback": PERSONAL_ROLLBACK_SCHEMA,
    "personal_stats": PERSONAL_STATS_SCHEMA,
}
