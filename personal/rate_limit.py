"""
personal/rate_limit.py — Flask-Limiter configuration for the personal MCP server.

Single Limiter instance, in-memory storage (per-worker counters).

Limits:
    - Global default: 200/minute per IP (safety net across all endpoints)
    - /mcp           : 60/minute per IP (generous for legitimate loops)
    - /health        : 30/minute per IP (covers monitors)

429 responses are JSON ({"error":"rate_limit_exceeded","retry_after":...}) with
a Retry-After header.
"""

from __future__ import annotations

import logging

from flask import Flask, jsonify, request
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

logger = logging.getLogger("personal.rate_limit")

# Per-endpoint limit strings — exported so mcp_server.py can decorate routes.
MCP_LIMIT = "60 per minute"
HEALTH_LIMIT = "30 per minute"
DEFAULT_LIMITS = ["200 per minute"]


# Module-level Limiter; init_app() is called from create_app().
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=DEFAULT_LIMITS,
    storage_uri="memory://",
    strategy="fixed-window",
    headers_enabled=True,
)


def _rate_limit_response(exc) -> tuple:
    """Render a JSON 429 with retry-after metadata."""
    description = getattr(exc, "description", "rate limit exceeded")
    retry_after = 60
    try:
        retry_after = int(getattr(exc, "retry_after", 60) or 60)
    except (TypeError, ValueError):
        retry_after = 60
    payload = {
        "error": "rate_limit_exceeded",
        "detail": str(description),
        "retry_after": retry_after,
    }
    response = jsonify(payload)
    response.status_code = 429
    response.headers["Retry-After"] = str(retry_after)
    logger.info(
        "rate_limit hit ip=%s path=%s detail=%s",
        get_remote_address(),
        request.path if request else "?",
        description,
    )
    return response


def init_rate_limiting(app: Flask) -> Limiter:
    """
    Bind the module-level limiter to the Flask app and install the JSON 429
    handler. Must be called from create_app() BEFORE routes are decorated.
    """
    limiter.init_app(app)

    from flask_limiter.errors import RateLimitExceeded

    @app.errorhandler(RateLimitExceeded)
    def _handle_429(exc):  # noqa: F811
        return _rate_limit_response(exc)

    logger.info(
        "rate-limit installed: default=%s mcp=%s health=%s",
        DEFAULT_LIMITS,
        MCP_LIMIT,
        HEALTH_LIMIT,
    )
    return limiter
