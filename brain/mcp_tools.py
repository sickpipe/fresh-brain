"""
brain/mcp_tools.py — MCP tool implementations for brain v2.

Seven tools, each a plain function(conn, **args) -> dict:
    search, get, upsert, list_recent, history, rollback, list_capabilities

The HTTP layer (mcp_server.py) handles JSON-RPC + auth. This file is
pure DB logic. We never SELECT the `embedding` column in responses.
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
def search(
    conn,
    query: str,
    source_tables=None,
    limit: int = 10,
    summary_only: bool = False,
) -> dict:
    """
    Semantic search via pgvector cosine distance. Two passes:
      1. Main-embedding probe per requested content table.
      2. Chunk-embedding probe against document_chunks.
    Hits deduped by (source_table, slug); best distance wins.
    """
    if not query or not query.strip():
        raise ValueError("search: query is required")
    tables = source_tables or SEARCHABLE_TABLES
    for t in tables:
        if t not in SEARCHABLE_TABLES:
            raise ValueError(f"search: unknown source_table '{t}'")
    limit = max(1, min(int(limit), 50))

    qvec = embed(query)
    qvec_lit = "[" + ",".join(repr(float(x)) for x in qvec) + "]"

    best: dict[tuple[str, str], dict] = {}

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        # Pass 1: main embedding probe per content table
        for t in tables:
            cur.execute(
                f"""
                SELECT '{t}' AS source_table, slug,
                       (embedding <=> %s::vector) AS distance,
                       {_cols(t, summary_only)}
                FROM {t}
                WHERE embedding IS NOT NULL
                  {"AND deleted_at IS NULL" if t != "session_notes" else ""}
                ORDER BY embedding <=> %s::vector
                LIMIT %s
                """,
                (qvec_lit, qvec_lit, limit),
            )
            for row in cur.fetchall():
                key = (t, row["slug"])
                rd = _row_to_json(dict(row))
                cur_best = best.get(key)
                if cur_best is None or rd["distance"] < cur_best["distance"]:
                    best[key] = rd

        # Pass 2: chunk embedding probe
        chunk_limit = max(limit * 4, 20)
        cur.execute(
            """
            SELECT source_table, source_key AS slug,
                   MIN(embedding <=> %s::vector) AS distance
            FROM document_chunks
            WHERE source_table = ANY(%s)
            GROUP BY source_table, source_key
            ORDER BY distance ASC
            LIMIT %s
            """,
            (qvec_lit, list(tables), chunk_limit),
        )
        chunk_hits = cur.fetchall()

        for ch in chunk_hits:
            t = ch["source_table"]
            slug = ch["slug"]
            ch_dist = float(ch["distance"])
            key = (t, slug)
            cur_best = best.get(key)
            if cur_best is not None and cur_best["distance"] <= ch_dist:
                continue
            not_deleted = "" if t == "session_notes" else "AND deleted_at IS NULL"
            cur.execute(
                f"SELECT '{t}' AS source_table, slug, {_cols(t, summary_only)} "
                f"FROM {t} WHERE slug = %s {not_deleted}",
                (slug,),
            )
            parent = cur.fetchone()
            if not parent:
                continue
            rd = _row_to_json(dict(parent))
            rd["distance"] = ch_dist
            if cur_best is None or ch_dist < cur_best["distance"]:
                best[key] = rd

    results = sorted(best.values(), key=lambda r: r.get("distance", 1.0))[:limit]

    for r in results:
        _log_access(conn, r["source_table"], r["slug"], "search")

    return {"query": query, "count": len(results), "results": results}


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


def upsert(
    conn,
    source_table: str,
    slug: str,
    body: str,
    edited_by: str | None = None,
    change_note: str | None = None,
    **metadata,
) -> dict:
    """
    Upsert a row. If slug exists in a versioned table, record history
    first, then overwrite. Embedding is recomputed on every write.
    """
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
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT body FROM {source_table} WHERE slug = %s", (slug,)
            )
            existing = cur.fetchone()
        if existing is not None:
            record_history(
                conn,
                source_table=source_table,
                source_key=slug,
                body=existing[0],
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
    rollback,
)
