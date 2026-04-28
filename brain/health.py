"""
brain/health.py — public liveness endpoint for brain MCP server.

GET /health
    200 + {"status":"ok","db":"ok","timestamp":"<iso utc>"}    when DB ping passes
    503 + {"status":"degraded","db":"error","timestamp":"..."} when DB unreachable

No auth. Rate-limited at HEALTH_LIMIT (see rate_limit.py).
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from flask import Blueprint, jsonify

from db import get_conn, put_conn
from rate_limit import HEALTH_LIMIT, limiter

logger = logging.getLogger("brain.health")

health_bp = Blueprint("health", __name__)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _db_ping() -> tuple[bool, str | None]:
    """Return (ok, error_message). Returns the connection to the pool."""
    conn = None
    try:
        conn = get_conn()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        return True, None
    except Exception as exc:
        return False, str(exc)
    finally:
        if conn is not None:
            try:
                put_conn(conn)
            except Exception:
                pass


@health_bp.get("/health")
@limiter.limit(HEALTH_LIMIT)
def health():
    db_ok, db_err = _db_ping()
    payload = {
        "status": "ok" if db_ok else "degraded",
        "db": "ok" if db_ok else "error",
        "service": "brain-mcp",
        "version": "2.0.0",
        "timestamp": _utc_now_iso(),
    }
    if not db_ok:
        payload["db_error"] = db_err
        logger.warning("/health DB ping failed: %s", db_err)
        return jsonify(payload), 503
    return jsonify(payload), 200
