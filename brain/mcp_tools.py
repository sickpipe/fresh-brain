"""
brain/mcp_tools.py — MCP tool implementations for brain v2.

Tools: search (in search.py), get, upsert + query tools (in mcp_tools_query.py).
The HTTP layer (mcp_server.py) handles JSON-RPC + auth.
We never SELECT the `embedding` column in responses.
"""

import logging
from datetime import date, datetime

from psycopg2.extras import RealDictCursor

from chunking import write_chunks
from embeddings import EMBEDDING_MODEL, embed
from history import VERSIONED_TABLES, record_history
from tool_tables import (
    RECENCY_COLUMN,
    SEARCHABLE_TABLES,
    SUMMARY_COLUMNS,
    TABLE_COLUMNS,
    UPSERT_META_COLUMNS,
)

logger = logging.getLogger(__name__)

PK_COLUMN = {"brain_config": "key"}


def _pk(table: str) -> str:
    return PK_COLUMN.get(table, "slug")


def _cols(table: str, summary_only: bool = False) -> str:
    if summary_only and table in SUMMARY_COLUMNS:
        return ", ".join(SUMMARY_COLUMNS[table])
    return ", ".join(TABLE_COLUMNS[table])


def _row_to_json(row: dict) -> dict:
    out = {}
    for k, v in row.items():
        if isinstance(v, (datetime, date)):
            out[k] = v.isoformat()
        else:
            out[k] = v
    return out


def _log_access(conn, source_table: str, slug: str, tool: str):
    """Bump access counters on content tables and append to access_log."""
    if source_table in ("brain_config", "session_notes"):
        return
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"UPDATE {source_table} SET last_accessed_at = now(), "
                f"access_count = access_count + 1 WHERE slug = %s",
                (slug,),
            )
            cur.execute(
                "INSERT INTO access_log (source_table, slug, tool) "
                "VALUES (%s, %s, %s)",
                (source_table, slug, tool),
            )
    except Exception as exc:
        logger.debug("access log write failed (non-fatal): %s", exc)


# -------------------------------------------------------------------- search
from search import search  # noqa: E402, F401


# ----------------------------------------------------------------------- get
def get(conn, source_table: str, slug: str) -> dict:
    if source_table not in TABLE_COLUMNS:
        raise ValueError(f"get: unknown source_table '{source_table}'")
    pk = _pk(source_table)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"SELECT {_cols(source_table)} FROM {source_table} WHERE {pk} = %s",
            (slug,),
        )
        row = cur.fetchone()
    if row:
        _log_access(conn, source_table, slug, "get")
        return _row_to_json(dict(row))
    return None


# -------------------------------------------------------------------- upsert
def _vec_literal(vec: list[float]) -> str:
    return "[" + ",".join(repr(float(x)) for x in vec) + "]"


def _fetch_snapshot(conn, source_table: str, slug: str) -> dict | None:
    """Fetch full row as dict for history snapshot (excludes embedding)."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"SELECT {_cols(source_table)} FROM {source_table} WHERE slug = %s",
            (slug,),
        )
        row = cur.fetchone()
    return dict(row) if row else None


def upsert(
    conn,
    source_table: str,
    slug: str,
    body: str,
    edited_by: str | None = None,
    change_note: str | None = None,
    **metadata,
) -> dict:
    """Upsert a row. Records full-row snapshot in history before overwrite."""
    if source_table == "brain_config":
        return _upsert_config(conn, slug, body, **metadata)

    if source_table not in UPSERT_META_COLUMNS:
        raise ValueError(f"upsert: unknown source_table '{source_table}'")
    if not slug:
        raise ValueError("upsert: slug is required")
    if body is None:
        raise ValueError("upsert: body is required")

    allowed = UPSERT_META_COLUMNS[source_table]
    unknown = [k for k in metadata if k not in allowed]
    if unknown:
        raise ValueError(
            f"upsert: unknown metadata columns for {source_table}: {unknown}"
        )

    if source_table in VERSIONED_TABLES:
        snapshot = _fetch_snapshot(conn, source_table, slug)
        if snapshot is not None:
            record_history(
                conn,
                source_table=source_table,
                source_key=slug,
                snapshot=snapshot,
                edited_by=edited_by,
                change_note=change_note,
            )

    vec_literal = _vec_literal(embed(body))

    cols = ["slug", "body"] + list(metadata.keys()) + ["embedding", "embedding_model"]
    placeholders = ["%s", "%s"] + ["%s"] * len(metadata) + ["%s::vector", "%s"]
    values: list = (
        [slug, body] + list(metadata.values()) + [vec_literal, EMBEDDING_MODEL]
    )

    has_updated_at = source_table != "session_notes"
    update_cols = ["body"] + list(metadata.keys()) + ["embedding", "embedding_model"]
    update_assigns = []
    for c in update_cols:
        if c == "embedding":
            update_assigns.append("embedding = EXCLUDED.embedding")
        else:
            update_assigns.append(f"{c} = EXCLUDED.{c}")
    if has_updated_at:
        update_assigns.append("updated_at = now()")

    sql = (
        f"INSERT INTO {source_table} ({', '.join(cols)}) "
        f"VALUES ({', '.join(placeholders)}) "
        f"ON CONFLICT (slug) DO UPDATE SET {', '.join(update_assigns)} "
        f"RETURNING slug"
    )

    with conn.cursor() as cur:
        cur.execute(sql, values)
        returned = cur.fetchone()

    chunk_count = write_chunks(conn, source_table, slug, body)

    return {
        "source_table": source_table,
        "slug": returned[0],
        "chunk_count": chunk_count,
    }


def _upsert_config(conn, key: str, value: str, **metadata) -> dict:
    """Upsert a brain_config row. No embedding, no history, no chunking."""
    description = metadata.get("description")
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO brain_config (key, value, description)
            VALUES (%s, %s, %s)
            ON CONFLICT (key) DO UPDATE SET
                value = EXCLUDED.value,
                description = COALESCE(EXCLUDED.description, brain_config.description)
            RETURNING key
            """,
            (key, value, description),
        )
        returned = cur.fetchone()
    return {"source_table": "brain_config", "slug": returned[0], "chunk_count": 0}


# --------------------------------------------- re-exports from query module
from mcp_tools_query import (  # noqa: E402, F401
    history,
    list_capabilities,
    list_recent,
    load_core,
    patch,
    rollback,
)
