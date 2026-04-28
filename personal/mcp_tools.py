"""
enterprise/mcp_tools.py — MCP tool implementations for the personal database.

CRUD tools: get, list_, create, update  (defined here)
Query tools: search, history, rollback, stats  (re-exported from mcp_tools_query)

Pure DB logic. The HTTP layer (mcp_server.py) handles JSON-RPC + auth.
"""

import logging
import re
from datetime import date, datetime

from psycopg2.extras import RealDictCursor, Json

from mcp_tables import (
    ACCESSIBLE_TABLES,
    HAS_SOFT_DELETE,
    HISTORY_TABLES,
    REQUIRED_ON_CREATE,
    SELECT_COLUMNS,
    SUMMARY_COLUMNS,
    WRITABLE_COLUMNS,
)

logger = logging.getLogger(__name__)


def _row_to_json(row: dict) -> dict:
    out = {}
    for k, v in row.items():
        if isinstance(v, (datetime, date)):
            out[k] = v.isoformat()
        else:
            out[k] = v
    return out


def _cols(table: str, summary_only: bool = False) -> str:
    if summary_only and table in SUMMARY_COLUMNS:
        return ", ".join(SUMMARY_COLUMNS[table])
    return ", ".join(SELECT_COLUMNS[table])


def _validate_table(table: str, tool: str):
    if table not in ACCESSIBLE_TABLES:
        raise ValueError(f"{tool}: unknown table '{table}'")


def _fts_query(q: str) -> str | None:
    tokens = re.findall(r"\w+", q or "")
    if not tokens:
        return None
    return " & ".join(f"{t}:*" for t in tokens)


# ----------------------------------------------------------------------- get
def get(conn, table: str, id: int) -> dict | None:
    _validate_table(table, "get")
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        not_deleted = "AND deleted_at IS NULL" if table in HAS_SOFT_DELETE else ""
        cur.execute(
            f"SELECT {_cols(table)} FROM {table} WHERE id = %s {not_deleted}",
            (id,),
        )
        row = cur.fetchone()
    return _row_to_json(dict(row)) if row else None


# ---------------------------------------------------------------------- list
def list_(
    conn,
    table: str,
    mission_id: int | None = None,
    workspace_id: int | None = None,
    task_id: int | None = None,
    status: str | None = None,
    limit: int = 50,
    offset: int = 0,
    summary_only: bool = False,
) -> dict:
    _validate_table(table, "list")
    limit = max(1, min(int(limit), 200))
    offset = max(0, int(offset))

    conditions = []
    params = []

    if table in HAS_SOFT_DELETE:
        conditions.append("deleted_at IS NULL")

    if mission_id is not None and "mission_id" in SELECT_COLUMNS.get(table, []):
        conditions.append("mission_id = %s")
        params.append(mission_id)

    if workspace_id is not None and "workspace_id" in SELECT_COLUMNS.get(table, []):
        conditions.append("workspace_id = %s")
        params.append(workspace_id)

    if task_id is not None and "task_id" in SELECT_COLUMNS.get(table, []):
        conditions.append("task_id = %s")
        params.append(task_id)

    if status is not None and "status" in SELECT_COLUMNS.get(table, []):
        conditions.append("status = %s")
        params.append(status)

    where = "WHERE " + " AND ".join(conditions) if conditions else ""
    order = "updated_at DESC" if "updated_at" in SELECT_COLUMNS.get(table, []) else "created_at DESC"

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"SELECT {_cols(table, summary_only)} FROM {table} {where} "
            f"ORDER BY {order} LIMIT %s OFFSET %s",
            params + [limit, offset],
        )
        rows = [_row_to_json(dict(r)) for r in cur.fetchall()]

    return {"table": table, "count": len(rows), "results": rows}


# -------------------------------------------------------------------- create
def create(conn, table: str, data: dict) -> dict:
    _validate_table(table, "create")
    writable = WRITABLE_COLUMNS[table]
    required = REQUIRED_ON_CREATE[table]

    missing = [r for r in required if r not in data]
    if missing:
        raise ValueError(f"create: missing required fields for {table}: {missing}")

    allowed = set(writable) | set(required)
    unknown = [k for k in data if k not in allowed]
    if unknown:
        raise ValueError(f"create: unknown fields for {table}: {unknown}")

    cols = list(data.keys())
    placeholders = []
    values = []
    for c in cols:
        v = data[c]
        if isinstance(v, (dict, list)) and c in ("metadata_json", "exif_json", "specs"):
            placeholders.append("%s")
            values.append(Json(v))
        else:
            placeholders.append("%s")
            values.append(v)

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"INSERT INTO {table} ({', '.join(cols)}) "
            f"VALUES ({', '.join(placeholders)}) "
            f"RETURNING {_cols(table)}",
            values,
        )
        row = cur.fetchone()

    return _row_to_json(dict(row))


# -------------------------------------------------------------------- update
def update(
    conn,
    table: str,
    id: int,
    data: dict,
    edited_by: str | None = None,
    change_note: str | None = None,
) -> dict:
    _validate_table(table, "update")
    writable = WRITABLE_COLUMNS[table]

    unknown = [k for k in data if k not in writable]
    if unknown:
        raise ValueError(f"update: unknown fields for {table}: {unknown}")

    if not data:
        raise ValueError("update: no fields to update")

    # Record history before overwrite if this table supports it
    if table in HISTORY_TABLES:
        content_col = HISTORY_TABLES[table]
        if content_col in data:
            with conn.cursor() as cur:
                cur.execute(
                    f"SELECT {content_col} FROM {table} WHERE id = %s",
                    (id,),
                )
                existing = cur.fetchone()
                if existing and existing[0]:
                    cur.execute(
                        "INSERT INTO document_history "
                        "(source_table, source_key, body, edited_by, change_note) "
                        "VALUES (%s, %s, %s, %s, %s)",
                        (table, str(id), existing[0], edited_by, change_note),
                    )

    set_parts = []
    values = []
    for c, v in data.items():
        if isinstance(v, (dict, list)) and c in ("metadata_json", "exif_json", "specs"):
            set_parts.append(f"{c} = %s")
            values.append(Json(v))
        else:
            set_parts.append(f"{c} = %s")
            values.append(v)

    values.append(id)
    not_deleted = "AND deleted_at IS NULL" if table in HAS_SOFT_DELETE else ""

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"UPDATE {table} SET {', '.join(set_parts)} "
            f"WHERE id = %s {not_deleted} "
            f"RETURNING {_cols(table)}",
            values,
        )
        row = cur.fetchone()

    if not row:
        raise ValueError(f"update: {table} id={id} not found")

    return _row_to_json(dict(row))


# ---- Re-export query tools so `from mcp_tools import ...` still works ----
from mcp_tools_query import search, history, rollback, stats  # noqa: E402, F401
