"""
brain/mcp_tools_query.py — Read-only / lightweight MCP tools.

Split from mcp_tools.py for Dark Code 300-line compliance.
Contains: list_recent, history, rollback, list_capabilities, load_core, patch.
"""

import json
import logging

from psycopg2.extras import RealDictCursor

from mcp_tools import _cols, _fetch_snapshot, _log_access, _pk, _row_to_json, _vec_literal, upsert
from chunking import write_chunks
from embeddings import EMBEDDING_MODEL, embed
from history import VERSIONED_TABLES, record_history
from tool_tables import RECENCY_COLUMN, SUMMARY_COLUMNS, TABLE_COLUMNS, UPSERT_META_COLUMNS

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
            f"{not_deleted} ORDER BY {order_col} DESC NULLS LAST LIMIT %s",
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
            "history_id, source_table, source_key, body, snapshot, "
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


# ---------------------------------------------------------------- load_core
def load_core(conn, summary_only: bool = False) -> dict:
    """Single bootstrap call — returns config, active team roster, tiered standing orders, signal tag map, and always-inject operator intent.

    When summary_only=True, team_members and tier1_orders are returned in their
    lightweight projection (no persona, body, or project_context). Default False
    preserves full bodies for tier1 orders and full persona/body/project_context
    for team_members.
    """
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT key, value, description FROM brain_config ORDER BY key")
        config = [_row_to_json(dict(r)) for r in cur.fetchall()]

        cur.execute(
            f"SELECT {_cols('team_members', summary_only)} FROM team_members "
            "WHERE status = 'active' AND deleted_at IS NULL ORDER BY display_name"
        )
        team = [_row_to_json(dict(r)) for r in cur.fetchall()]

        # Tier 1: full body when summary_only=False; lightweight projection otherwise
        cur.execute(
            f"SELECT {_cols('standing_orders', summary_only)} FROM standing_orders "
            "WHERE tier = 1 AND active = true AND deleted_at IS NULL "
            "ORDER BY updated_at DESC"
        )
        tier1_orders = [_row_to_json(dict(r)) for r in cur.fetchall()]

        # Tier 2: compact manifest only
        cur.execute(
            "SELECT slug, manifest_summary, signal_tags FROM standing_orders "
            "WHERE tier = 2 AND active = true AND deleted_at IS NULL "
            "ORDER BY updated_at DESC"
        )
        tier2_manifest = [_row_to_json(dict(r)) for r in cur.fetchall()]

        # Signal tag map from brain_config
        cur.execute(
            "SELECT value FROM brain_config WHERE key = 'signal_tag_map'"
        )
        tag_row = cur.fetchone()
        signal_tag_map = json.loads(tag_row["value"]) if tag_row else {}

        summary_cols = ", ".join(SUMMARY_COLUMNS["operator_intent"])
        cur.execute(
            f"SELECT {summary_cols} FROM operator_intent "
            "WHERE always_inject = true AND deleted_at IS NULL ORDER BY priority"
        )
        intent = [_row_to_json(dict(r)) for r in cur.fetchall()]

    return {
        "config": config,
        "team_members": team,
        "tier1_orders": tier1_orders,
        "tier2_manifest": tier2_manifest,
        "signal_tag_map": signal_tag_map,
        "operator_intent": intent,
    }


# ------------------------------------------------------------------- patch
_PATCHABLE_FIELDS = set()
for _cols_list in UPSERT_META_COLUMNS.values():
    _PATCHABLE_FIELDS.update(_cols_list)
_PATCHABLE_FIELDS.add("body")


def patch(
    conn,
    source_table: str,
    slug: str,
    edited_by: str | None = None,
    change_note: str | None = None,
    **fields,
) -> dict:
    """Partial update — only modifies provided fields. Records history first."""
    if source_table not in UPSERT_META_COLUMNS:
        raise ValueError(f"patch: unknown source_table '{source_table}'")
    if not slug:
        raise ValueError("patch: slug is required")
    if not fields:
        raise ValueError("patch: at least one field to update is required")

    allowed = set(UPSERT_META_COLUMNS[source_table]) | {"body"}
    unknown = [k for k in fields if k not in allowed]
    if unknown:
        raise ValueError(f"patch: unknown fields for {source_table}: {unknown}")

    snapshot = _fetch_snapshot(conn, source_table, slug)
    if snapshot is None:
        raise ValueError(f"patch: no existing row {source_table}/{slug}")

    if source_table in VERSIONED_TABLES:
        record_history(conn, source_table, slug, snapshot, edited_by, change_note)

    set_clauses = []
    values = []
    for field, val in fields.items():
        set_clauses.append(f"{field} = %s")
        values.append(val)

    needs_reembed = "body" in fields
    if needs_reembed:
        vec = _vec_literal(embed(fields["body"]))
        set_clauses.append("embedding = %s::vector")
        values.append(vec)
        set_clauses.append("embedding_model = %s")
        values.append(EMBEDDING_MODEL)

    if source_table != "session_notes":
        set_clauses.append("updated_at = now()")

    values.append(slug)
    sql = f"UPDATE {source_table} SET {', '.join(set_clauses)} WHERE slug = %s RETURNING slug"

    with conn.cursor() as cur:
        cur.execute(sql, values)
        returned = cur.fetchone()

    chunk_count = 0
    if needs_reembed:
        chunk_count = write_chunks(conn, source_table, slug, fields["body"])

    return {
        "source_table": source_table,
        "slug": returned[0],
        "patched_fields": list(fields.keys()),
        "chunk_count": chunk_count,
    }
