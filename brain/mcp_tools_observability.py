"""
brain/mcp_tools_observability.py — MCP tool-call observability.

Provides log_tool_call() for fire-and-forget instrumentation and
query_tool_log() for the memory_query_tool_log MCP tool.
"""

import json
import logging
from datetime import date, datetime

from psycopg2.extras import RealDictCursor

from db import get_conn, put_conn

logger = logging.getLogger(__name__)


def _row_to_json(row: dict) -> dict:
    out = {}
    for k, v in row.items():
        if isinstance(v, (datetime, date)):
            out[k] = v.isoformat()
        else:
            out[k] = v
    return out


def _sanitize_args(args: dict | None) -> dict | None:
    """Truncate body values so the log table stays lean."""
    if not args:
        return args
    sanitized = {}
    for k, v in args.items():
        if k == "body" and isinstance(v, str) and len(v) > 200:
            sanitized[k] = v[:200] + "…"
        else:
            sanitized[k] = v
    return sanitized


def log_tool_call(
    tool_name: str, args: dict | None, result_size: int | None,
    duration_ms: float, success: bool, error_message: str | None,
):
    """Fire-and-forget INSERT into mcp_tool_log. Never raises."""
    try:
        conn = get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO mcp_tool_log "
                    "(tool_name, arguments, result_size, duration_ms, "
                    "success, error_message) "
                    "VALUES (%s, %s, %s, %s, %s, %s)",
                    (
                        tool_name,
                        json.dumps(_sanitize_args(args), default=str),
                        result_size,
                        duration_ms,
                        success,
                        error_message[:500] if error_message else None,
                    ),
                )
            conn.commit()
        except Exception:
            conn.rollback()
        finally:
            put_conn(conn)
    except Exception:
        pass


def query_tool_log(
    conn,
    tool_name: str | None = None,
    session_id: str | None = None,
    since_hours: int = 24,
    limit: int = 50,
) -> dict:
    """Query mcp_tool_log with optional filters."""
    limit = max(1, min(int(limit), 200))
    since_hours = max(1, min(int(since_hours), 720))

    conditions = ["called_at > now() - make_interval(hours => %s)"]
    params: list = [since_hours]

    if tool_name:
        conditions.append("tool_name = %s")
        params.append(tool_name)
    if session_id:
        conditions.append("session_id = %s")
        params.append(session_id)

    where = " AND ".join(conditions)
    params.append(limit)

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f"SELECT id, tool_name, arguments, result_size, duration_ms, "
            f"success, error_message, session_id, called_at "
            f"FROM mcp_tool_log WHERE {where} "
            f"ORDER BY called_at DESC LIMIT %s",
            params,
        )
        rows = [_row_to_json(dict(r)) for r in cur.fetchall()]

    return {"count": len(rows), "results": rows}
