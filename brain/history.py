"""
brain/history.py — document_history write helper.

Single function: record_history(conn, source_table, source_key, body,
edited_by, change_note). Insert-only. Call BEFORE an upsert that
replaces an existing row — if the row doesn't exist yet, nothing to
record. Caller is responsible for passing the OLD body, not the new one.

Transaction: this helper does NOT commit. The caller controls the
transaction boundary so history + upsert stay atomic.
"""

import logging

logger = logging.getLogger(__name__)

# Must match the CHECK constraint on document_history.source_table
VERSIONED_TABLES = {
    "team_members",
    "topic_documents",
    "memory_entries",
    "standing_orders",
    "ideas",
    "operator_intent",
}


def record_history(
    conn,
    source_table: str,
    source_key: str,
    body: str,
    edited_by: str | None = None,
    change_note: str | None = None,
) -> None:
    """Insert a row into document_history. Does NOT commit."""
    if source_table not in VERSIONED_TABLES:
        raise ValueError(
            f"source_table '{source_table}' is not versioned "
            f"(allowed: {sorted(VERSIONED_TABLES)})"
        )
    if body is None:
        raise ValueError("record_history() requires a non-null body")

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO document_history
                (source_table, source_key, body, edited_by, change_note)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (source_table, source_key, body, edited_by, change_note),
        )
    logger.debug(
        "record_history: %s/%s (edited_by=%s)", source_table, source_key, edited_by
    )
