"""brain/tool_schemas.py — JSON Schema definitions for MCP tools (v2)."""

MEMORY_SEARCH_SCHEMA = {
    "type": "object",
    "properties": {
        "query": {
            "type": "string",
            "description": "Natural language search query",
        },
        "source_tables": {
            "type": "array",
            "items": {"type": "string"},
            "description": (
                "Optional list of content tables to restrict search "
                "(team_members, topic_documents, memory_entries, "
                "session_notes, standing_orders, ideas, operator_intent). "
                "Omit to search all."
            ),
        },
        "limit": {
            "type": "integer",
            "default": 10,
            "description": "Max results to return",
        },
        "summary_only": {
            "type": "boolean",
            "default": False,
            "description": (
                "If true, return lightweight columns only (slug, title/summary, "
                "timestamps — no body, no persona). Reduces payload significantly."
            ),
        },
        "mode": {
            "type": "string",
            "enum": ["hybrid", "vector_only"],
            "default": "hybrid",
            "description": (
                "Search mode. 'hybrid' (default) uses RRF fusion of semantic + "
                "full-text search. 'vector_only' uses pure cosine-distance ranking "
                "and returns a 'distance' field instead of 'rrf_score'."
            ),
        },
        "distance_threshold": {
            "type": "number",
            "default": 0.7,
            "description": (
                "Max cosine distance for vector_only mode (0.0 = identical, "
                "2.0 = opposite). Results beyond this threshold are filtered out. "
                "Only applies when mode='vector_only'."
            ),
        },
    },
    "required": ["query"],
}

MEMORY_GET_SCHEMA = {
    "type": "object",
    "properties": {
        "source_table": {
            "type": "string",
            "description": (
                "One of: team_members, topic_documents, memory_entries, "
                "session_notes, standing_orders, ideas, operator_intent, brain_config"
            ),
        },
        "slug": {
            "type": "string",
            "description": "The row's slug (or key, for brain_config)",
        },
    },
    "required": ["source_table", "slug"],
}

MEMORY_UPSERT_SCHEMA = {
    "type": "object",
    "properties": {
        "source_table": {"type": "string", "description": "Target content table. Metadata columns are per-table."},
        "slug": {"type": "string", "description": "Row slug (immutable). For brain_config, this is the key."},
        "body": {"type": "string", "description": "Full markdown body. For brain_config, this is the value."},
        "edited_by": {"type": "string", "description": "Who made the edit", "default": "claude"},
        "change_note": {"type": "string", "description": "Short explanation of what changed"},
        "title": {"type": "string", "description": "Row title (topic_documents, memory_entries, session_notes, standing_orders, ideas, operator_intent)"},
        "display_name": {"type": "string", "description": "Display name (team_members)"},
        "role": {"type": "string", "description": "Role title (team_members)"},
        "persona": {"type": "string", "description": "Persona text (team_members)"},
        "summary": {"type": "string", "description": "One-line summary (all content tables)"},
        "capabilities": {"type": "array", "items": {"type": "string"}, "description": "Skill tags (team_members)"},
        "always_inject": {"type": "boolean", "description": "Auto-inject at session start (team_members, operator_intent)"},
        "project_context": {"type": "string", "description": "Project context (team_members)"},
        "model_tier": {"type": "string", "description": "LLM tier: opus/sonnet/haiku (team_members)"},
        "status": {"type": "string", "description": "active or retired (team_members)"},
        "tags": {"type": "array", "items": {"type": "string"}, "description": "Freeform tags (multiple tables)"},
        "entry_type": {"type": "string", "description": "Memory type (memory_entries): user_pref, ship_log, lesson_learned, etc."},
        "section": {"type": "string", "description": "Intent section (operator_intent): identity, core_value, tradeoff, etc."},
        "topic": {"type": "string", "description": "Topic category (topic_documents)"},
        "namespace": {"type": "string", "description": "Project namespace (topic_documents, memory_entries)"},
        "scope": {"type": "string", "description": "system/operator/project (topic_documents, memory_entries, standing_orders, operator_intent)"},
        "source_path": {"type": "string", "description": "File path reference (topic_documents)"},
        "related_topic": {"type": "string", "description": "Related topic slug (memory_entries)"},
        "occurred_on": {"type": "string", "format": "date", "description": "Event date (memory_entries)"},
        "trigger_pattern": {"type": "string", "description": "Trigger description (standing_orders)"},
        "active": {"type": "boolean", "description": "Active flag (standing_orders)"},
        "effective_from": {"type": "string", "format": "date", "description": "Effective date (standing_orders)"},
        "priority": {"type": "integer", "description": "Sort priority (operator_intent)"},
        "category": {"type": "string", "description": "Idea category (ideas)"},
        "estimated_cost": {"type": "string", "description": "Cost estimate (ideas)"},
        "estimated_effort": {"type": "string", "description": "Effort: small/medium/large (ideas)"},
        "biggest_risk": {"type": "string", "description": "Primary risk (ideas)"},
        "next_action": {"type": "string", "description": "Next action item (ideas)"},
        "filed_on": {"type": "string", "format": "date", "description": "Filing date (ideas)"},
        "linked_docs": {"type": "array", "items": {"type": "string"}, "description": "Related doc slugs (ideas)"},
        "session_ended_at": {"type": "string", "format": "date-time", "description": "Session end time (session_notes) — optional; leave null when logging mid-session"},
        "projects_touched": {"type": "array", "items": {"type": "string"}, "description": "Projects touched (session_notes)"},
        "description": {"type": "string", "description": "Config description (brain_config)"},
    },
    "required": ["source_table", "slug", "body"],
}

MEMORY_LIST_RECENT_SCHEMA = {
    "type": "object",
    "properties": {
        "source_table": {
            "type": "string",
            "description": (
                "Content table to list. Also accepts 'brain_config' "
                "to list all config keys."
            ),
        },
        "limit": {"type": "integer", "default": 20},
        "summary_only": {
            "type": "boolean",
            "default": False,
            "description": (
                "If true, return lightweight columns only (slug, title/summary, "
                "timestamps — no body, no persona). Reduces payload significantly."
            ),
        },
    },
    "required": ["source_table"],
}

MEMORY_HISTORY_SCHEMA = {
    "type": "object",
    "properties": {
        "source_table": {
            "type": "string",
            "description": "Content table the row belongs to",
        },
        "source_slug": {
            "type": "string",
            "description": "Slug of the document to get history for",
        },
        "limit": {
            "type": "integer",
            "default": 10,
            "description": "Max history entries (most recent first)",
        },
        "summary_only": {
            "type": "boolean",
            "default": True,
            "description": (
                "If true, return metadata only (no body snapshots). "
                "Set false to include body for rollback."
            ),
        },
    },
    "required": ["source_table", "source_slug"],
}

MEMORY_ROLLBACK_SCHEMA = {
    "type": "object",
    "properties": {
        "source_table": {
            "type": "string",
            "description": "Content table the row belongs to",
        },
        "slug": {
            "type": "string",
            "description": "Slug of the document to roll back",
        },
        "history_id": {
            "type": "integer",
            "description": "The history_id to restore (from memory_history results)",
        },
        "edited_by": {
            "type": "string",
            "default": "rollback",
            "description": "Who initiated the rollback",
        },
    },
    "required": ["source_table", "slug", "history_id"],
}

MEMORY_LIST_CAPABILITIES_SCHEMA = {
    "type": "object",
    "properties": {
        "capabilities": {
            "type": "array",
            "items": {"type": "string"},
            "description": (
                "Required capabilities (AND logic). "
                "Example: ['python', 'database']"
            ),
        },
    },
    "required": ["capabilities"],
}

MEMORY_LOAD_CORE_SCHEMA = {
    "type": "object",
    "properties": {},
    "required": [],
}

MEMORY_PATCH_SCHEMA = {
    "type": "object",
    "properties": {
        "source_table": {"type": "string", "description": "Target content table (same as upsert, excluding brain_config)."},
        "slug": {"type": "string", "description": "Slug of the existing row to patch."},
        "edited_by": {"type": "string", "description": "Who made the edit"},
        "change_note": {"type": "string", "description": "Short explanation of what changed"},
        "body": {"type": "string", "description": "New body text (triggers re-embedding)"},
        "title": {"type": "string", "description": "Updated title"},
        "summary": {"type": "string", "description": "Updated summary"},
        "status": {"type": "string", "description": "Updated status"},
        "active": {"type": "boolean", "description": "Updated active flag"},
        "tags": {"type": "array", "items": {"type": "string"}, "description": "Updated tags"},
        "priority": {"type": "integer", "description": "Updated priority"},
        "always_inject": {"type": "boolean", "description": "Updated always_inject"},
        "capabilities": {"type": "array", "items": {"type": "string"}, "description": "Updated capabilities"},
    },
    "required": ["source_table", "slug"],
}

MEMORY_QUERY_TOOL_LOG_SCHEMA = {
    "type": "object",
    "properties": {
        "tool_name": {
            "type": "string",
            "description": "Filter by tool name (e.g. 'memory_search')",
        },
        "session_id": {
            "type": "string",
            "description": "Filter by session ID",
        },
        "since_hours": {
            "type": "integer",
            "default": 24,
            "description": "Look back this many hours (max 720)",
        },
        "limit": {
            "type": "integer",
            "default": 50,
            "description": "Max results to return (max 200)",
        },
    },
    "required": [],
}

MEMORY_CONSOLIDATE_NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "older_than_days": {
            "type": "integer",
            "default": 14,
            "minimum": 1,
            "description": "Archive notes older than this many days",
        },
        "dry_run": {
            "type": "boolean",
            "default": False,
            "description": "Preview without archiving",
        },
    },
    "required": [],
}

MEMORY_LINK_DOCUMENTS_SCHEMA = {
    "type": "object",
    "properties": {
        "source_slug": {
            "type": "string",
            "description": "Slug of the source topic document",
        },
        "target_slug": {
            "type": "string",
            "description": "Slug of the target topic document",
        },
        "link_type": {
            "type": "string",
            "enum": ["references", "derived_from", "supersedes", "related"],
            "description": "Type of link: references, derived_from, supersedes, related",
        },
    },
    "required": ["source_slug", "target_slug", "link_type"],
}

MEMORY_LIST_LINKS_SCHEMA = {
    "type": "object",
    "properties": {
        "slug": {
            "type": "string",
            "description": "Slug of the topic document to list links for",
        },
        "direction": {
            "type": "string",
            "enum": ["outgoing", "incoming", "both"],
            "default": "both",
            "description": "Filter links by direction: outgoing (from this doc), incoming (to this doc), both (default)",
        },
    },
    "required": ["slug"],
}

SCHEMAS = {
    "memory_search": MEMORY_SEARCH_SCHEMA,
    "memory_get": MEMORY_GET_SCHEMA,
    "memory_upsert": MEMORY_UPSERT_SCHEMA,
    "memory_list_recent": MEMORY_LIST_RECENT_SCHEMA,
    "memory_history": MEMORY_HISTORY_SCHEMA,
    "memory_rollback": MEMORY_ROLLBACK_SCHEMA,
    "memory_list_capabilities": MEMORY_LIST_CAPABILITIES_SCHEMA,
    "memory_load_core": MEMORY_LOAD_CORE_SCHEMA,
    "memory_patch": MEMORY_PATCH_SCHEMA,
    "memory_query_tool_log": MEMORY_QUERY_TOOL_LOG_SCHEMA,
    "memory_consolidate_notes": MEMORY_CONSOLIDATE_NOTES_SCHEMA,
    "memory_link_documents": MEMORY_LINK_DOCUMENTS_SCHEMA,
    "memory_list_links": MEMORY_LIST_LINKS_SCHEMA,
}
