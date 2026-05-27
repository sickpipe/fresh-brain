"""brain/mcp_server.py — Flask MCP server for brain v2 (16 tools)."""

import json
import logging
import os
import secrets
import time
import traceback

from flask import Flask, jsonify, request
from dotenv import load_dotenv

from db import get_conn, put_conn
from health import health_bp
from mcp_cache import cache_clear, cache_get, cache_set
from mcp_tools import get as tool_get
from mcp_tools import history as tool_history
from mcp_tools import list_capabilities as tool_list_capabilities
from mcp_tools import list_recent as tool_list_recent
from mcp_tools import load_core as tool_load_core
from mcp_tools import patch as tool_patch
from mcp_tools import rollback as tool_rollback
from mcp_tools import search as tool_search
from mcp_tools import upsert as tool_upsert
from mcp_tools import link_documents as tool_link_documents
from mcp_tools import list_links as tool_list_links
from mcp_tools import log_order_fire as tool_log_order_fire
from mcp_tools_archivist import consolidate_notes as tool_consolidate_notes
from mcp_tools_external import link_external as tool_link_external
from mcp_tools_external import list_external_links as tool_list_external_links
from mcp_tools_observability import log_tool_call as _log_tool_call
from mcp_tools_observability import query_tool_log as tool_query_tool_log
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
        logger.warning("BRAIN_MCP_TOKEN unset — generated ephemeral token (length=%d)", len(tok))
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
    "memory_search": {"fn": tool_search, "description": "Semantic search across brain content tables."},
    "memory_get": {"fn": tool_get, "description": "Fetch one row by source_table + slug."},
    "memory_upsert": {"fn": tool_upsert, "description": "Insert or update a row. Records history, recomputes embedding."},
    "memory_list_recent": {"fn": tool_list_recent, "description": "List recent rows from one table sorted by updated_at."},
    "memory_history": {"fn": tool_history, "description": "Read document_history entries for a specific slug."},
    "memory_rollback": {"fn": tool_rollback, "description": "Restore a previous version from document_history (reversible)."},
    "memory_list_capabilities": {"fn": tool_list_capabilities, "description": "Find team members by capabilities (AND logic)."},
    "memory_load_core": {"fn": tool_load_core, "description": "Bootstrap — returns config, roster, standing orders, operator intent. Default summary_only=true returns the lightweight projection (no persona/body/project_context on team_members and tier1_orders); pass summary_only=false for the legacy full payload."},
    "memory_patch": {"fn": tool_patch, "description": "Partial update — modifies only provided fields. Records history."},
    "memory_query_tool_log": {"fn": tool_query_tool_log, "description": "Query MCP tool call history for observability."},
    "memory_consolidate_notes": {"fn": tool_consolidate_notes, "description": "Archive old session notes into digest topic documents."},
    "memory_link_documents": {"fn": tool_link_documents, "description": "Create a directional link between two topic documents."},
    "memory_list_links": {"fn": tool_list_links, "description": "List all cross-links for a topic document."},
    "memory_log_order_fire": {"fn": tool_log_order_fire, "description": "Record a standing order fire in the audit log."},
    "memory_link_external": {"fn": tool_link_external, "description": "Create or update an external document link (upserts on provider+ref+target)."},
    "memory_list_external_links": {"fn": tool_list_external_links, "description": "List external document links with optional filters."},
}


CACHEABLE_TOOLS = {
    "memory_load_core", "memory_get", "memory_list_recent",
    "memory_list_capabilities", "memory_search", "memory_list_links",
    "memory_list_external_links",
}
WRITE_TOOLS = {
    "memory_upsert", "memory_patch", "memory_rollback",
    "memory_consolidate_notes", "memory_link_documents",
    "memory_log_order_fire", "memory_link_external",
}


def _dispatch_tool(name: str, args: dict) -> dict:
    tool = TOOLS.get(name)
    if tool is None:
        raise ValueError(f"Unknown tool: {name}")

    # Check cache for read-only tools
    cached = False
    if name in CACHEABLE_TOOLS:
        hit = cache_get(name, args)
        if hit is not None:
            cached = True
            result_json = json.dumps(hit, default=str)
            _log_tool_call(name, args, len(result_json), 0, True, None,
                           cached=True)
            return hit

    t0 = time.monotonic()
    conn = get_conn()
    try:
        result = tool["fn"](conn, **(args or {}))
        conn.commit()
        duration_ms = (time.monotonic() - t0) * 1000
        result_json = json.dumps(result, default=str)
        _log_tool_call(name, args, len(result_json), duration_ms, True, None,
                       cached=False)

        if name in CACHEABLE_TOOLS:
            cache_set(name, args, result)
        elif name in WRITE_TOOLS:
            cache_clear()

        return result
    except Exception as exc:
        conn.rollback()
        duration_ms = (time.monotonic() - t0) * 1000
        _log_tool_call(name, args, None, duration_ms, False, str(exc))
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
    logger.info("Starting brain MCP server on 127.0.0.1:%d", port)
    logger.info("Bearer token loaded (length=%d)", len(BRAIN_MCP_TOKEN))
    app.run(host="127.0.0.1", port=port, debug=False)
