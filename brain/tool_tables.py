"""
brain/tool_tables.py — table-shape constants for mcp_tools (v2).

Five dicts keyed by source_table:
    SEARCHABLE_TABLES  — tables that participate in semantic search
    TABLE_COLUMNS      — full SELECT column list for `get` (excludes embedding)
    SUMMARY_COLUMNS    — lightweight column set for summary_only mode
    UPSERT_META_COLUMNS — allowed metadata kwargs for `upsert`
    RECENCY_COLUMN     — order column for `list_recent`
"""

SEARCHABLE_TABLES = [
    "team_members",
    "topic_documents",
    "memory_entries",
    "session_notes",
    "standing_orders",
    "ideas",
    "operator_intent",
]

TABLE_COLUMNS = {
    "team_members": [
        "slug", "display_name", "role", "persona", "body", "summary",
        "capabilities", "always_inject", "project_context", "model_tier",
        "status", "tags", "embedding_model",
        "last_accessed_at", "access_count",
        "created_at", "updated_at", "deleted_at",
    ],
    "topic_documents": [
        "slug", "title", "body", "topic", "summary", "namespace", "scope",
        "source_path", "tags", "embedding_model",
        "last_accessed_at", "access_count",
        "created_at", "updated_at", "deleted_at",
    ],
    "memory_entries": [
        "slug", "entry_type", "title", "body", "summary", "namespace", "scope",
        "related_topic", "tags", "occurred_on", "embedding_model",
        "last_accessed_at", "access_count",
        "created_at", "updated_at", "deleted_at",
    ],
    "session_notes": [
        "slug", "title", "session_ended_at", "summary", "body",
        "projects_touched", "tags", "embedding_model", "created_at",
    ],
    "standing_orders": [
        "slug", "title", "body", "summary", "scope", "active",
        "trigger_pattern", "effective_from", "tags", "embedding_model",
        "last_accessed_at", "access_count",
        "created_at", "updated_at", "deleted_at",
    ],
    "ideas": [
        "slug", "title", "status", "category", "summary", "body",
        "estimated_cost", "estimated_effort", "biggest_risk", "next_action",
        "filed_on", "linked_docs", "embedding_model",
        "last_accessed_at", "access_count",
        "created_at", "updated_at", "deleted_at",
    ],
    "operator_intent": [
        "slug", "section", "title", "body", "summary", "always_inject",
        "scope", "priority", "tags", "embedding_model",
        "last_accessed_at", "access_count",
        "created_at", "updated_at", "deleted_at",
    ],
    "brain_config": [
        "key", "value", "description", "updated_at",
    ],
}

SUMMARY_COLUMNS = {
    "team_members": [
        "slug", "display_name", "role", "summary", "capabilities",
        "status", "always_inject", "tags", "updated_at",
    ],
    "topic_documents": [
        "slug", "title", "summary", "topic", "namespace", "scope",
        "tags", "updated_at",
    ],
    "memory_entries": [
        "slug", "entry_type", "title", "summary", "namespace",
        "related_topic", "tags", "updated_at",
    ],
    "session_notes": [
        "slug", "title", "session_ended_at", "summary",
        "projects_touched", "tags", "created_at",
    ],
    "standing_orders": [
        "slug", "title", "summary", "scope", "active",
        "trigger_pattern", "tags", "updated_at",
    ],
    "ideas": [
        "slug", "title", "status", "category", "summary",
        "estimated_effort", "next_action", "updated_at",
    ],
    "operator_intent": [
        "slug", "section", "title", "summary", "priority",
        "always_inject", "tags", "updated_at",
    ],
    "brain_config": [
        "key", "value", "description", "updated_at",
    ],
}

UPSERT_META_COLUMNS = {
    "team_members": [
        "display_name", "role", "persona", "model_tier", "status",
        "tags", "summary", "capabilities", "always_inject", "project_context",
    ],
    "topic_documents": [
        "title", "topic", "source_path", "tags",
        "summary", "namespace", "scope",
    ],
    "memory_entries": [
        "entry_type", "title", "related_topic", "tags", "occurred_on",
        "summary", "namespace", "scope",
    ],
    "session_notes": [
        "title", "session_ended_at", "summary", "projects_touched", "tags",
    ],
    "standing_orders": [
        "title", "scope", "active", "effective_from", "tags",
        "summary", "trigger_pattern",
    ],
    "ideas": [
        "title", "status", "category", "summary", "estimated_cost",
        "estimated_effort", "biggest_risk", "next_action",
        "filed_on", "linked_docs",
    ],
    "operator_intent": [
        "section", "title", "priority", "tags",
        "summary", "always_inject", "scope",
    ],
    "brain_config": [
        "value", "description",
    ],
}

RECENCY_COLUMN = {
    "team_members": "updated_at",
    "topic_documents": "updated_at",
    "memory_entries": "updated_at",
    "session_notes": "session_ended_at",
    "standing_orders": "updated_at",
    "ideas": "updated_at",
    "operator_intent": "updated_at",
    "brain_config": "updated_at",
}
