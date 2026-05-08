"""
enterprise/mcp_server.py — Flask MCP server for the personal database.

Endpoints:
    GET  /health  — liveness
    POST /mcp     — MCP JSON-RPC dispatch (bearer-auth)

Tools (8):
    personal_get, personal_list, personal_create, personal_update,
    personal_search, personal_history, personal_rollback, personal_stats
"""

import json
import logging
import os
import secrets
import traceback

from flask import Flask, jsonify, request
from dotenv import load_dotenv

from mcp_db import get_conn, put_conn
from mcp_health import health_bp
from mcp_tools import (
    create as tool_create,
    get as tool_get,
    history as tool_history,
    list_ as tool_list,
    rollback as tool_rollback,
    search as tool_search,
    stats as tool_stats,
    update as tool_update,
)
from mcp_tool_schemas import SCHEMAS as TOOL_SCHEMAS
from rate_limit import MCP_LIMIT, init_rate_limiting, limiter

_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(_DIR, ".env"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
logger = logging.getLogger("personal.mcp")


# -------------------------------------------------------------------- auth
def _load_token() -> str:
    tok = os.getenv("PERSONAL_MCP_TOKEN")
    if not tok:
        tok = "dev-" + secrets.token_urlsafe(24)
        logger.warning("PERSONAL_MCP_TOKEN unset — generated ephemeral token (length=%d)", len(tok))
    return tok


PERSONAL_MCP_TOKEN = _load_token()


def _check_auth() -> bool:
    hdr = request.headers.get("Authorization", "")
    if not hdr.startswith("Bearer "):
        return False
    return secrets.compare_digest(hdr[7:].strip(), PERSONAL_MCP_TOKEN)


# ------------------------------------------------------------------ tools
TOOLS = {
    "personal_get": {
        "fn": tool_get,
        "description": (
            "Fetch one row by table + id. "
            "Args: table (str), id (int)."
        ),
    },
    "personal_list": {
        "fn": tool_list,
        "description": (
            "List/filter rows from a table. "
            "Args: table (str), mission_id?, workspace_id?, task_id?, "
            "status?, limit (default 50), offset?, summary_only?."
        ),
    },
    "personal_create": {
        "fn": tool_create,
        "description": (
            "Insert a new row. Returns the created row with its id. "
            "Args: table (str), data (object with column values)."
        ),
    },
    "personal_update": {
        "fn": tool_update,
        "description": (
            "Update specific fields on a row. Records history for notes, "
            "missions, tasks before overwriting content. "
            "Args: table, id, data, edited_by?, change_note?."
        ),
    },
    "personal_search": {
        "fn": tool_search,
        "description": (
            "Full-text search across personal database tables. "
            "Args: query (str), tables (list[str], optional)."
        ),
    },
    "personal_history": {
        "fn": tool_history,
        "description": (
            "Read document_history entries for a row. "
            "Supported tables: notes, missions, tasks. "
            "Args: table, id, limit?, summary_only?."
        ),
    },
    "personal_rollback": {
        "fn": tool_rollback,
        "description": (
            "Restore a previous version from document_history. "
            "Records current version first (reversible). "
            "Args: table, id, history_id, edited_by?."
        ),
    },
    "personal_stats": {
        "fn": tool_stats,
        "description": (
            "Dashboard-style counts and summaries. "
            "Args: workspace_id (int, optional)."
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

        if method == "initialize":
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "personal-mcp", "version": "1.0.0"},
                },
            })

        if method and method.startswith("notifications/"):
            return ("", 204)

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

    return app


app = create_app()


if __name__ == "__main__":
    port = int(os.getenv("PERSONAL_MCP_PORT", "5051"))
    logger.info("Starting personal MCP server on 127.0.0.1:%d", port)
    logger.info("Bearer token loaded (length=%d)", len(PERSONAL_MCP_TOKEN))
    app.run(host="127.0.0.1", port=port, debug=False)
