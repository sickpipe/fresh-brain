"""
brain/mcp_server.py — Flask MCP server for brain v2.

Endpoints:
    GET  /health          — liveness (health.py)
    POST /mcp             — MCP JSON-RPC dispatch (bearer-auth)
    POST /context-inject  — lightweight search for auto-injection hook

Tools (7):
    memory_search, memory_get, memory_upsert, memory_list_recent,
    memory_history, memory_rollback, memory_list_capabilities
"""

import json
import logging
import os
import secrets
import traceback

from flask import Flask, jsonify, request
from dotenv import load_dotenv

from db import get_conn, put_conn
from health import health_bp
from mcp_tools import get as tool_get
from mcp_tools import history as tool_history
from mcp_tools import list_capabilities as tool_list_capabilities
from mcp_tools import list_recent as tool_list_recent
from mcp_tools import rollback as tool_rollback
from mcp_tools import search as tool_search
from mcp_tools import upsert as tool_upsert
from rate_limit import MCP_LIMIT, init_rate_limiting, limiter
from tool_schemas import SCHEMAS as TOOL_SCHEMAS

_BRAIN_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(_BRAIN_DIR, ".env"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
logger = logging.getLogger("brain.mcp")


# -------------------------------------------------------------------- auth
def _load_token() -> str:
    tok = os.getenv("BRAIN_MCP_TOKEN")
    if not tok:
        tok = "dev-" + secrets.token_urlsafe(24)
        logger.warning("BRAIN_MCP_TOKEN unset — generated ephemeral token: %s", tok)
    return tok


BRAIN_MCP_TOKEN = _load_token()


def _check_auth() -> bool:
    hdr = request.headers.get("Authorization", "")
    if not hdr.startswith("Bearer "):
        return False
    return secrets.compare_digest(hdr[7:].strip(), BRAIN_MCP_TOKEN)


# ---------------------------------------------------------- accept-header
def _normalize_accept_header():
    accept = request.headers.get("Accept", "")
    if "application/json" in accept and "text/event-stream" in accept:
        return
    logger.debug("Normalizing non-standard Accept header: %r", accept)


# ------------------------------------------------------------------ tools
TOOLS = {
    "memory_search": {
        "fn": tool_search,
        "description": (
            "Semantic search across brain content tables. "
            "Args: query (str, required), source_tables (list[str], optional), "
            "limit (int, default 10), summary_only (bool, default false)."
        ),
    },
    "memory_get": {
        "fn": tool_get,
        "description": (
            "Fetch one row by source_table + slug. "
            "Args: source_table (str), slug (str)."
        ),
    },
    "memory_upsert": {
        "fn": tool_upsert,
        "description": (
            "Insert or update a row. Records history before overwrite, "
            "recomputes embedding. Args: source_table, slug, body, "
            "+ table-specific metadata, edited_by?, change_note?."
        ),
    },
    "memory_list_recent": {
        "fn": tool_list_recent,
        "description": (
            "List recent rows from one table sorted by updated_at. "
            "Args: source_table, limit (default 20), summary_only (bool, default false)."
        ),
    },
    "memory_history": {
        "fn": tool_history,
        "description": (
            "Read document_history entries for a specific slug. "
            "Args: source_table, source_slug, limit (default 10), "
            "summary_only (bool, default true)."
        ),
    },
    "memory_rollback": {
        "fn": tool_rollback,
        "description": (
            "Restore a previous version from document_history. "
            "Records current version in history first (reversible). "
            "Args: source_table, slug, history_id, edited_by (default 'rollback')."
        ),
    },
    "memory_list_capabilities": {
        "fn": tool_list_capabilities,
        "description": (
            "Find team members by capabilities (AND logic). "
            "Args: capabilities (list[str], required)."
        ),
    },
}


def _dispatch_tool(name: str, args: dict) -> dict:
    tool = TOOLS.get(name)
    if tool is None:
        raise ValueError(f"Unknown tool: {name}")
    conn = get_conn()
    try:
        result = tool["fn"](conn, **(args or {}))
        conn.commit()
        return result
    except Exception:
        conn.rollback()
        raise
    finally:
        put_conn(conn)


# ----------------------------------------------------------------- factory
def create_app() -> Flask:
    app = Flask(__name__)
    app.config["SEND_FILE_MAX_AGE_DEFAULT"] = 0

    init_rate_limiting(app)
    app.register_blueprint(health_bp)

    @app.before_request
    def _before():
        _normalize_accept_header()

    @app.post("/mcp")
    @limiter.limit(MCP_LIMIT)
    def mcp():
        if not _check_auth():
            return jsonify({"error": "unauthorized"}), 401
        try:
            payload = request.get_json(force=True, silent=False) or {}
        except Exception as exc:
            return jsonify({"error": f"invalid JSON: {exc}"}), 400

        method = payload.get("method")
        rpc_id = payload.get("id")

        # MCP handshake
        if method == "initialize":
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "brain-mcp", "version": "2.0.0"},
                },
            })

        # Notifications (no response)
        if method and method.startswith("notifications/"):
            return ("", 204)

        # tools/list
        if method == "tools/list":
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {"tools": [
                    {
                        "name": n,
                        "description": t["description"],
                        "inputSchema": TOOL_SCHEMAS[n],
                    }
                    for n, t in TOOLS.items()
                ]},
            })

        # tools/call + minimal envelope
        if method == "tools/call":
            params = payload.get("params") or {}
            tool_name = params.get("name")
            tool_args = params.get("arguments") or {}
        elif method is None:
            tool_name = payload.get("tool")
            tool_args = payload.get("arguments") or {}
        else:
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"},
            }), 404

        if not tool_name:
            return jsonify({"error": "missing tool name"}), 400

        try:
            result = _dispatch_tool(tool_name, tool_args)
        except ValueError as exc:
            logger.info("Tool %s rejected args: %s", tool_name, exc)
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "error": {"code": -32602, "message": str(exc)},
            }), 400
        except Exception as exc:
            logger.error(
                "Tool %s failed: %s\n%s", tool_name, exc, traceback.format_exc()
            )
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "error": {"code": -32000, "message": str(exc)},
            }), 500

        if method == "tools/call":
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "content": [
                        {"type": "text", "text": json.dumps(result, default=str)}
                    ],
                    "isError": False,
                },
            })
        return jsonify(result)

    @app.post("/context-inject")
    @limiter.limit("120 per minute")
    def context_inject():
        """Lightweight search for the UserPromptSubmit auto-injection hook."""
        if not _check_auth():
            return jsonify({"error": "unauthorized"}), 401
        payload = request.get_json(force=True, silent=True) or {}
        query = payload.get("query", "").strip()
        if not query:
            return jsonify({"count": 0, "results": []})

        limit = min(int(payload.get("limit", 3)), 5)
        conn = get_conn()
        try:
            result = tool_search(conn, query=query, limit=limit)
            conn.commit()
            for r in result.get("results", []):
                body = r.get("body", "")
                r["body_preview"] = body[:800] if body else ""
                r.pop("body", None)
                r.pop("persona", None)
                r.pop("project_context", None)
            return jsonify(result)
        except Exception:
            conn.rollback()
            raise
        finally:
            put_conn(conn)

    return app


app = create_app()


if __name__ == "__main__":
    port = int(os.getenv("BRAIN_MCP_PORT", "5050"))
    logger.info("Starting brain MCP server on 0.0.0.0:%d", port)
    logger.info("Bearer token: %s", BRAIN_MCP_TOKEN)
    app.run(host="0.0.0.0", port=port, debug=False)
