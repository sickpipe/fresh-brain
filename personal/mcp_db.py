"""
enterprise/mcp_db.py — psycopg2 connection pool for the personal MCP server.

Mirrors brain/db.py. Uses ThreadedConnectionPool (minconn=2, maxconn=8).
Reads DATABASE_PERSONAL_APP_URL from .env.
"""

import logging
import os

import psycopg2
from psycopg2.pool import ThreadedConnectionPool
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(_DIR, ".env"))

_pool: ThreadedConnectionPool | None = None


def _url() -> str:
    url = os.getenv("DATABASE_PERSONAL_APP_URL")
    if not url:
        raise RuntimeError("DATABASE_PERSONAL_APP_URL is not set in .env")
    return url


def _get_pool() -> ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = ThreadedConnectionPool(minconn=2, maxconn=8, dsn=_url())
    return _pool


def get_conn():
    return _get_pool().getconn()


def put_conn(conn):
    try:
        _get_pool().putconn(conn)
    except Exception:
        pass
