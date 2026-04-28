"""
brain/search.py — Hybrid semantic + text search for brain v2.

Extracted from mcp_tools.py for Dark Code 300-line compliance.
Uses reciprocal rank fusion (RRF) to merge vector and text results.
"""

import logging

from psycopg2.extras import RealDictCursor

from embeddings import embed
from tool_tables import SEARCHABLE_TABLES, SUMMARY_COLUMNS, TABLE_COLUMNS

logger = logging.getLogger(__name__)

RRF_K = 60


def _cols(table: str, summary_only: bool = False) -> str:
    if summary_only and table in SUMMARY_COLUMNS:
        return ", ".join(SUMMARY_COLUMNS[table])
    return ", ".join(TABLE_COLUMNS[table])


def _row_to_json(row: dict) -> dict:
    from datetime import date, datetime
    out = {}
    for k, v in row.items():
        if isinstance(v, (datetime, date)):
            out[k] = v.isoformat()
        else:
            out[k] = v
    return out


def _not_deleted(table: str) -> str:
    return "" if table == "session_notes" else "AND deleted_at IS NULL"


def _vector_pass(cur, tables, qvec_lit, limit, summary_only):
    """Pass 1+2: main embedding + chunk probe. Returns {(table, slug): (row_dict, rank)}."""
    hits = {}
    rank = 0
    # Pass 1: main embedding per content table
    for t in tables:
        cur.execute(
            f"""
            SELECT '{t}' AS source_table, slug,
                   (embedding <=> %s::vector) AS distance,
                   {_cols(t, summary_only)}
            FROM {t}
            WHERE embedding IS NOT NULL {_not_deleted(t)}
            ORDER BY embedding <=> %s::vector
            LIMIT %s
            """,
            (qvec_lit, qvec_lit, limit),
        )
        for row in cur.fetchall():
            key = (t, row["slug"])
            rd = _row_to_json(dict(row))
            prev = hits.get(key)
            if prev is None or rd["distance"] < prev[0]["distance"]:
                rank += 1
                hits[key] = (rd, rank)

    # Pass 2: chunk embedding probe — filter out soft-deleted parents
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
        prev = hits.get(key)
        if prev is not None and prev[0]["distance"] <= ch_dist:
            continue
        nd = _not_deleted(t)
        cur.execute(
            f"SELECT '{t}' AS source_table, slug, {_cols(t, summary_only)} "
            f"FROM {t} WHERE slug = %s {nd}",
            (slug,),
        )
        parent = cur.fetchone()
        if not parent:
            continue
        rd = _row_to_json(dict(parent))
        rd["distance"] = ch_dist
        rank += 1
        hits[key] = (rd, rank)
    return hits


def _text_pass(cur, tables, query, limit):
    """Full-text search using tsv tsvector column. Returns {(table, slug): rank}."""
    hits = {}
    rank = 0
    for t in tables:
        nd = "AND deleted_at IS NULL" if t != "session_notes" else ""
        try:
            cur.execute(
                f"""
                SELECT slug, ts_rank(tsv, plainto_tsquery('english', %s)) AS rank
                FROM {t}
                WHERE tsv @@ plainto_tsquery('english', %s) {nd}
                ORDER BY rank DESC LIMIT %s
                """,
                (query, query, limit),
            )
        except Exception:
            logger.debug("text search skipped for %s (tsv column may not exist)", t)
            continue
        for row in cur.fetchall():
            rank += 1
            hits[(t, row["slug"])] = rank
    return hits


def _rrf_merge(vector_hits, text_hits, limit):
    """Reciprocal rank fusion. Returns sorted list of row dicts."""
    all_keys = set(vector_hits.keys()) | set(text_hits.keys())
    scored = []
    for key in all_keys:
        score = 0.0
        if key in vector_hits:
            _, vrank = vector_hits[key]
            score += 1.0 / (RRF_K + vrank)
        if key in text_hits:
            score += 1.0 / (RRF_K + text_hits[key])
        row_data = vector_hits[key][0] if key in vector_hits else None
        scored.append((score, key, row_data))
    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[:limit]


def search(conn, query, source_tables=None, limit=10, summary_only=False):
    """Hybrid semantic + text search with RRF merging."""
    if not query or not query.strip():
        raise ValueError("search: query is required")
    tables = source_tables or SEARCHABLE_TABLES
    for t in tables:
        if t not in SEARCHABLE_TABLES:
            raise ValueError(f"search: unknown source_table '{t}'")
    limit = max(1, min(int(limit), 50))

    qvec = embed(query)
    qvec_lit = "[" + ",".join(repr(float(x)) for x in qvec) + "]"

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        vector_hits = _vector_pass(cur, tables, qvec_lit, limit, summary_only)
        text_hits = _text_pass(cur, tables, query, limit)

    merged = _rrf_merge(vector_hits, text_hits, limit)

    # For text-only hits missing row data, fetch the rows
    results = []
    for score, key, row_data in merged:
        if row_data is None:
            t, slug = key
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                nd = _not_deleted(t)
                cur.execute(
                    f"SELECT '{t}' AS source_table, slug, {_cols(t, summary_only)} "
                    f"FROM {t} WHERE slug = %s {nd}",
                    (slug,),
                )
                parent = cur.fetchone()
            if not parent:
                continue
            row_data = _row_to_json(dict(parent))
        row_data["rrf_score"] = round(score, 6)
        results.append(row_data)

    from mcp_tools import _log_access
    for r in results:
        _log_access(conn, r["source_table"], r["slug"], "search")

    return {"query": query, "count": len(results), "results": results}
