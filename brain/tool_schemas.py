"""
brain/tool_schemas.py — JSON Schema definitions for MCP tools (v2).

Each tool's inputSchema is required by the MCP spec for tools/list.
Per-table metadata ownership is annotated in descriptions to reduce
hallucinated cross-table parameters.
"""

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
        "source_table": {
            "type": "string",
            "description": (
                "Target content table. Metadata columns are per-table — "
                "see each column's description for which tables accept it."
            ),
        },
        "slug": {
            "type": "string",
            "description": "Row slug (immutable once written). For brain_config, this is the key.",
        },
        "body": {
            "type": "string",
            "description": "Full markdown body. For brain_config, this is the value.",
        },
        "edited_by": {
            "type": "string",
            "description": "Who made the edit",
            "default": "claude",
        },
        "change_note": {
            "type": "string",
            "description": "Short explanation of what changed",
        },
        "title": {
            "type": "string",
            "description": "Row title (topic_documents, memory_entries, standing_orders, ideas, operator_intent)",
        },
        "display_name": {
            "type": "string",
            "description": "Display name (team_members only)",
        },
        "role": {
            "type": "string",
            "description": "Role title (team_members only)",
        },
        "persona": {
            "type": "string",
            "description": "Persona text (team_members only)",
        },
        "summary": {
            "type": "string",
            "description": "One-line summary for lightweight listings (all content tables)",
        },
        "capabilities": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Skill tags for capability-based lookup (team_members only)",
        },
        "always_inject": {
            "type": "boolean",
            "description": "Auto-inject summary at session start (team_members, operator_intent)",
        },
        "project_context": {
            "type": "string",
            "description": "Operator-specific project context, separate from body (team_members only)",
        },
        "model_tier": {
            "type": "string",
            "description": "LLM tier: opus/sonnet/haiku (team_members only)",
        },
        "status": {
            "type": "string",
            "description": "active or retired (team_members only)",
        },
        "tags": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Freeform tags (team_members, topic_documents, memory_entries, standing_orders, operator_intent)",
        },
        "entry_type": {
            "type": "string",
            "description": "Memory type (memory_entries only): user_pref, architecture_fact, ship_log, tool_note, trading_context, lesson_learned",
        },
        "section": {
            "type": "string",
            "description": "Intent section (operator_intent only): identity, core_value, tradeoff, decision_boundary, success_criterion, do_not_rule",
        },
        "topic": {
            "type": "string",
            "description": "Topic category (topic_documents only)",
        },
        "namespace": {
            "type": "string",
            "description": "Project namespace, default 'global' (topic_documents, memory_entries only)",
        },
        "scope": {
            "type": "string",
            "description": "Scope tag: system/operator/project (topic_documents, memory_entries, standing_orders, operator_intent)",
        },
        "source_path": {
            "type": "string",
            "description": "File path reference (topic_documents only)",
        },
        "related_topic": {
            "type": "string",
            "description": "Related topic slug (memory_entries only)",
        },
        "occurred_on": {
            "type": "string",
            "format": "date",
            "description": "Date the event occurred (memory_entries only)",
        },
        "trigger_pattern": {
            "type": "string",
            "description": "Human-readable trigger description (standing_orders only)",
        },
        "active": {
            "type": "boolean",
            "description": "Whether the order is active (standing_orders only)",
        },
        "effective_from": {
            "type": "string",
            "format": "date",
            "description": "Effective date (standing_orders only)",
        },
        "priority": {
            "type": "integer",
            "description": "Sort priority (operator_intent only)",
        },
        "category": {
            "type": "string",
            "description": "Idea category (ideas only)",
        },
        "estimated_cost": {
            "type": "string",
            "description": "Cost estimate (ideas only)",
        },
        "estimated_effort": {
            "type": "string",
            "description": "Effort: small/medium/large (ideas only)",
        },
        "biggest_risk": {
            "type": "string",
            "description": "Primary risk (ideas only)",
        },
        "next_action": {
            "type": "string",
            "description": "Next action item (ideas only)",
        },
        "filed_on": {
            "type": "string",
            "format": "date",
            "description": "Filing date (ideas only)",
        },
        "linked_docs": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Related document slugs (ideas only)",
        },
        "session_ended_at": {
            "type": "string",
            "format": "date-time",
            "description": "Session end time (session_notes only)",
        },
        "projects_touched": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Projects touched in session (session_notes only)",
        },
        "description": {
            "type": "string",
            "description": "Config description (brain_config only)",
        },
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

SCHEMAS = {
    "memory_search": MEMORY_SEARCH_SCHEMA,
    "memory_get": MEMORY_GET_SCHEMA,
    "memory_upsert": MEMORY_UPSERT_SCHEMA,
    "memory_list_recent": MEMORY_LIST_RECENT_SCHEMA,
    "memory_history": MEMORY_HISTORY_SCHEMA,
    "memory_rollback": MEMORY_ROLLBACK_SCHEMA,
    "memory_list_capabilities": MEMORY_LIST_CAPABILITIES_SCHEMA,
}
