"""
enterprise/mcp_health.py — public liveness endpoint for personal MCP server.

GET /health → 200 {"status":"ok"} or 503 {"status":"degraded"}
"""

import logging
from datetime import datetime, timezone

from flask import Blueprint, jsonify

from mcp_db import get_conn, put_conn

logger = logging.getLogger("personal.health")

health_bp = Blueprint("health", __name__)


@health_bp.get("/health")
def health():
    conn = None
    db_ok = False
    try:
        conn = get_conn()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        db_ok = True
    except Exception as exc:
        logger.warning("/health DB ping failed: %s", exc)
    finally:
        if conn:
            put_conn(conn)

    payload = {
        "status": "ok" if db_ok else "degraded",
        "db": "ok" if db_ok else "error",
        "service": "personal-mcp",
        "version": "1.0.0",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    return jsonify(payload), 200 if db_ok else 503
