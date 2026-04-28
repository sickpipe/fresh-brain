"""
brain/history.py — document_history write helper.

Stores a full-row JSONB snapshot plus body text for backwards compat.
Call BEFORE an upsert that replaces an existing row.
Transaction: this helper does NOT commit.
"""

import json
import logging
from datetime import date, datetime

logger = logging.getLogger(__name__)

VERSIONED_TABLES = {
    "team_members",
    "topic_documents",
    "memory_entries",
    "standing_orders",
    "ideas",
    "operator_intent",
}


def _json_default(obj):
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    return str(obj)


def record_history(
    conn,
    source_table: str,
    source_key: str,
    snapshot: dict,
    edited_by: str | None = None,
    change_note: str | None = None,
) -> None:
    """Insert a row into document_history with full JSONB snapshot. Does NOT commit."""
    if source_table not in VERSIONED_TABLES:
        raise ValueError(
            f"source_table '{source_table}' is not versioned "
            f"(allowed: {sorted(VERSIONED_TABLES)})"
        )
    if snapshot is None:
        raise ValueError("record_history() requires a non-null snapshot")

    body = snapshot.get("body", "")
    snapshot_json = json.dumps(snapshot, default=_json_default)

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO document_history
                (source_table, source_key, body, snapshot, edited_by, change_note)
            VALUES (%s, %s, %s, %s::jsonb, %s, %s)
            """,
            (source_table, source_key, body, snapshot_json, edited_by, change_note),
        )
    logger.debug(
        "record_history: %s/%s (edited_by=%s)", source_table, source_key, edited_by
    )
