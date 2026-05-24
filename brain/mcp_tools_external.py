"""
brain/mcp_tools_external.py — MCP tools for external document links.

Tools: link_external, list_external_links.
Manages the external_document_links table (created by migration).
"""

from __future__ import annotations

import json
import logging
from datetime import date, datetime

from psycopg2.extras import RealDictCursor

logger = logging.getLogger(__name__)

VALID_TARGET_DBS = {"brain", "personal", "evenrail_app"}
VALID_PROVIDERS = {"google_drive", "dropbox", "local", "url"}
VALID_STATUSES = {"active", "archived", "broken"}
ALLOWED_URL_SCHEMES = ("http://", "https://")

# Conflict columns for upsert dedup
UPSERT_CONFLICT = ("provider", "provider_ref", "target_db", "target_table", "target_key")


def _row_to_json(row: dict) -> dict:
    """Convert date/datetime values to ISO strings for JSON serialization."""
    out = {}
    for k, v in row.items():
        if isinstance(v, (datetime, date)):
            out[k] = v.isoformat()
        else:
            out[k] = v
    return out


def link_external(
    conn,
    target_db: str,
    target_table: str,
    target_key: str,
    provider: str,
    provider_ref: str,
    title: str,
    url: str | None = None,
    doc_type: str | None = None,
    mime_type: str | None = None,
    provider_meta: dict | None = None,
    status: str | None = None,
) -> dict:
    """Create or update an external document link.

    Upsert on (provider, provider_ref, target_db, target_table, target_key).
    """
    if not target_db or not target_table or not target_key:
        raise ValueError("link_external: target_db, target_table, and target_key are required")
    if target_db not in VALID_TARGET_DBS:
        raise ValueError(
            f"link_external: invalid target_db '{target_db}'. "
            f"Must be one of: {', '.join(sorted(VALID_TARGET_DBS))}"
        )
    if not provider or not provider_ref or not title:
        raise ValueError("link_external: provider, provider_ref, and title are required")
    if provider not in VALID_PROVIDERS:
        raise ValueError(
            f"link_external: invalid provider '{provider}'. "
            f"Must be one of: {', '.join(sorted(VALID_PROVIDERS))}"
        )
    if status is not None and status not in VALID_STATUSES:
        raise ValueError(
            f"link_external: invalid status '{status}'. "
            f"Must be one of: {', '.join(sorted(VALID_STATUSES))}"
        )
    if url is not None:
        if not isinstance(url, str) or not url.startswith(ALLOWED_URL_SCHEMES):
            raise ValueError(
                "link_external: url must be http:// or https:// (got an unsupported scheme)"
            )
        if len(url) > 2048:
            raise ValueError("link_external: url exceeds 2048 chars")

    meta_json = json.dumps(provider_meta) if provider_meta else "{}"

    sql = """
        INSERT INTO external_document_links
            (target_db, target_table, target_key, provider, provider_ref,
             url, title, doc_type, mime_type, provider_meta, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, COALESCE(%s, 'active'))
        ON CONFLICT (provider, provider_ref, target_db, target_table, target_key)
            WHERE deleted_at IS NULL
        DO UPDATE SET
            url           = COALESCE(EXCLUDED.url, external_document_links.url),
            title         = EXCLUDED.title,
            doc_type      = COALESCE(EXCLUDED.doc_type, external_document_links.doc_type),
            mime_type     = COALESCE(EXCLUDED.mime_type, external_document_links.mime_type),
            provider_meta = CASE
                WHEN EXCLUDED.provider_meta = '{}'::jsonb
                THEN external_document_links.provider_meta
                ELSE EXCLUDED.provider_meta
            END,
            status        = COALESCE(EXCLUDED.status, external_document_links.status),
            updated_at    = now()
        RETURNING id, target_db, target_table, target_key, provider, provider_ref,
                  url, title, doc_type, mime_type, provider_meta, status,
                  last_verified, created_at, updated_at
    """
    params = (
        target_db, target_table, target_key, provider, provider_ref,
        url, title, doc_type, mime_type, meta_json, status,
    )

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        row = cur.fetchone()

    return _row_to_json(dict(row))


def list_external_links(
    conn,
    target_db: str | None = None,
    target_table: str | None = None,
    target_key: str | None = None,
    provider: str | None = None,
    doc_type: str | None = None,
    status: str | None = None,
    limit: int = 50,
) -> dict:
    """List external document links with optional filters.

    Excludes soft-deleted records by default.
    """
    limit = min(max(1, limit), 200)

    conditions = ["deleted_at IS NULL"]
    params: list = []

    if target_db is not None:
        conditions.append("target_db = %s")
        params.append(target_db)
    if target_table is not None:
        conditions.append("target_table = %s")
        params.append(target_table)
    if target_key is not None:
        conditions.append("target_key = %s")
        params.append(target_key)
    if provider is not None:
        conditions.append("provider = %s")
        params.append(provider)
    if doc_type is not None:
        conditions.append("doc_type = %s")
        params.append(doc_type)
    if status is not None:
        conditions.append("status = %s")
        params.append(status)

    sql = (
        "SELECT id, target_db, target_table, target_key, provider, provider_ref, "
        "url, title, doc_type, mime_type, provider_meta, status, "
        "last_verified, created_at, updated_at "
        "FROM external_document_links "
        f"WHERE {' AND '.join(conditions)} "
        "ORDER BY created_at DESC "
        "LIMIT %s"
    )
    params.append(limit)

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    return {
        "count": len(rows),
        "links": [_row_to_json(dict(r)) for r in rows],
    }
