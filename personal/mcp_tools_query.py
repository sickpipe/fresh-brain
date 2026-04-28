"""
enterprise/mcp_tools_query.py — Query-oriented MCP tools for the personal database.

Extracted from mcp_tools.py: search, history, rollback, stats.
"""

import logging

from psycopg2.extras import RealDictCursor

from mcp_tables import (
    HAS_SOFT_DELETE,
    HISTORY_TABLES,
    SEARCHABLE_TABLES,
    SELECT_COLUMNS,
)
from mcp_tools import _cols, _fts_query, _row_to_json, update

logger = logging.getLogger(__name__)


# -------------------------------------------------------------------- search
def search(conn, query: str, tables: list[str] | None = None) -> dict:
    if not query or not query.strip():
        raise ValueError("search: query is required")

    search_tables = tables or SEARCHABLE_TABLES
    for t in search_tables:
        if t not in SEARCHABLE_TABLES:
            raise ValueError(f"search: table '{t}' does not support search")

    tsq = _fts_query(query)
    if tsq is None:
        return {"query": query, "count": 0, "results": []}

    results = []
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        for t in search_tables:
            not_deleted = "AND deleted_at IS NULL" if t in HAS_SOFT_DELETE else ""
            cur.execute(
                f"SELECT {_cols(t, summary_only=True)}, "
                f"ts_rank(search_tsv, to_tsquery('english', %s)) AS rank "
                f"FROM {t} "
                f"WHERE search_tsv @@ to_tsquery('english', %s) {not_deleted} "
                f"ORDER BY rank DESC LIMIT 20",
                (tsq, tsq),
            )
            for row in cur.fetchall():
                rd = _row_to_json(dict(row))
                rd["_table"] = t
                results.append(rd)

    results.sort(key=lambda r: r.get("rank", 0), reverse=True)
    results = results[:50]

    return {"query": query, "count": len(results), "results": results}


# ------------------------------------------------------------------- history
def history(
    conn,
    table: str,
    id: int,
    limit: int = 10,
    summary_only: bool = True,
) -> dict:
    if table not in HISTORY_TABLES:
        raise ValueError(
            f"history: table '{table}' does not have history tracking "
            f"(supported: {list(HISTORY_TABLES.keys())})"
        )
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
            f"SELECT {cols} FROM document_history "
            f"WHERE source_table = %s AND source_key = %s "
            f"ORDER BY edited_at DESC LIMIT %s",
            (table, str(id), limit),
        )
        rows = [_row_to_json(dict(r)) for r in cur.fetchall()]

    return {"table": table, "id": id, "count": len(rows), "results": rows}


# ------------------------------------------------------------------ rollback
def rollback(
    conn,
    table: str,
    id: int,
    history_id: int,
    edited_by: str = "rollback",
) -> dict:
    if table not in HISTORY_TABLES:
        raise ValueError(f"rollback: table '{table}' does not have history tracking")

    content_col = HISTORY_TABLES[table]

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT body FROM document_history "
            "WHERE history_id = %s AND source_table = %s AND source_key = %s",
            (history_id, table, str(id)),
        )
        row = cur.fetchone()

    if not row:
        raise ValueError(
            f"rollback: no history entry {history_id} for {table}/{id}"
        )

    return update(
        conn, table, id,
        {content_col: row["body"]},
        edited_by=edited_by,
        change_note=f"rollback to history_id={history_id}",
    )


# --------------------------------------------------------------------- stats
def stats(conn, workspace_id: int | None = None) -> dict:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        ws_filter = "AND workspace_id = %s" if workspace_id is not None else ""
        params = (workspace_id,) if workspace_id is not None else ()

        def _count(table, extra=""):
            soft = "deleted_at IS NULL" if table in HAS_SOFT_DELETE else "TRUE"
            sql = f"SELECT count(*) FROM {table} WHERE {soft} {extra}"
            if ws_filter and "workspace_id" in SELECT_COLUMNS.get(table, []):
                sql += f" {ws_filter}"
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            return cur.fetchone()["count"]

        def _task_count(status):
            sql = "SELECT count(*) FROM tasks WHERE deleted_at IS NULL AND status = %s"
            p = [status]
            if workspace_id is not None:
                sql += " AND workspace_id = %s"
                p.append(workspace_id)
            cur.execute(sql, p)
            return cur.fetchone()["count"]

        result = {
            "total_missions": _count("missions"),
            "total_tasks": _count("tasks"),
            "tasks_todo": _task_count("todo"),
            "tasks_in_progress": _task_count("in_progress"),
            "tasks_blocked": _task_count("blocked"),
            "tasks_done": _task_count("done"),
            "tasks_cancelled": _task_count("cancelled"),
            "total_notes": _count("notes"),
            "total_items": _count("task_items"),
            "total_assets": _count("assets"),
            "total_tags": _count("tags"),
        }

    return result
