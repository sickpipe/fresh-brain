"""
brain/mcp_tools_query.py — Read-only / lightweight MCP tools.

Split from mcp_tools.py for Dark Code 300-line compliance.
Contains: list_recent, history, rollback, list_capabilities.
"""

import logging

from psycopg2.extras import RealDictCursor

from mcp_tools import _cols, _log_access, _pk, _row_to_json, upsert
from tool_tables import RECENCY_COLUMN, TABLE_COLUMNS

logger = logging.getLogger(__name__)


# -------------------------------------------------------------- list_recent
def list_recent(
    conn,
    source_table: str,
    limit: int = 20,
    summary_only: bool = False,
) -> dict:
    if source_table == "brain_config":
        return _list_config(conn)
    if source_table not in TABLE_COLUMNS:
        raise ValueError(f"list_recent: unknown source_table '{source_table}'")
    limit = max(1, min(int(limit), 100))
    order_col = RECENCY_COLUMN[source_table]
    not_deleted = "" if source_table == "session_notes" else "WHERE deleted_at IS NULL"
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"SELECT {_cols(source_table, summary_only)} FROM {source_table} "
            f"{not_deleted} ORDER BY {order_col} DESC LIMIT %s",
            (limit,),
        )
        rows = [_row_to_json(dict(r)) for r in cur.fetchall()]
    return {"source_table": source_table, "count": len(rows), "results": rows}


def _list_config(conn) -> dict:
    """List all brain_config rows."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT key, value, description FROM brain_config ORDER BY key")
        rows = [_row_to_json(dict(r)) for r in cur.fetchall()]
    return {"source_table": "brain_config", "count": len(rows), "results": rows}


# ------------------------------------------------------------------ history
def history(
    conn,
    source_table: str,
    source_slug: str,
    limit: int = 10,
    summary_only: bool = True,
) -> dict:
    """Read document_history entries for a slug. Most recent first."""
    limit = max(1, min(int(limit), 50))
    if summary_only:
        cols = (
            "history_id, source_table, source_key, edited_by, change_note, "
            "length(body) AS body_length, edited_at"
        )
    else:
        cols = (
            "history_id, source_table, source_key, body, "
            "edited_by, change_note, edited_at"
        )
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"""
            SELECT {cols}
            FROM document_history
            WHERE source_table = %s AND source_key = %s
            ORDER BY edited_at DESC
            LIMIT %s
            """,
            (source_table, source_slug, limit),
        )
        rows = [_row_to_json(dict(r)) for r in cur.fetchall()]
    return {
        "source_table": source_table,
        "slug": source_slug,
        "count": len(rows),
        "results": rows,
    }


# ----------------------------------------------------------------- rollback
def rollback(
    conn,
    source_table: str,
    slug: str,
    history_id: int,
    edited_by: str = "rollback",
) -> dict:
    """Restore a previous version from document_history. Itself reversible."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT body FROM document_history "
            "WHERE history_id = %s AND source_table = %s AND source_key = %s",
            (history_id, source_table, slug),
        )
        row = cur.fetchone()
    if not row:
        raise ValueError(
            f"rollback: no history entry {history_id} for {source_table}/{slug}"
        )
    return upsert(
        conn,
        source_table,
        slug,
        row["body"],
        edited_by=edited_by,
        change_note=f"rollback to history_id={history_id}",
    )


# ------------------------------------------------------- list_capabilities
def list_capabilities(conn, capabilities: list[str]) -> dict:
    """Find active team members matching ALL given capabilities."""
    if not capabilities:
        raise ValueError("list_capabilities: at least one capability required")
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT slug, display_name, role, summary, capabilities, status
            FROM team_members
            WHERE status = 'active' AND deleted_at IS NULL
              AND capabilities @> %s
            ORDER BY display_name
            """,
            (capabilities,),
        )
        rows = [_row_to_json(dict(r)) for r in cur.fetchall()]
    return {
        "capabilities_query": capabilities,
        "count": len(rows),
        "results": rows,
    }
