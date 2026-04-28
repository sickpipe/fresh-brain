"""
brain/db.py — psycopg2 connection pool for the brain Postgres DB.

Uses ThreadedConnectionPool (minconn=2, maxconn=8) for connection reuse.
get_conn() borrows from the pool; put_conn() returns it.
"""

import logging
import os

import psycopg2
from psycopg2.pool import ThreadedConnectionPool
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

_BRAIN_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(_BRAIN_DIR, ".env"))

APP_URL_VAR = "DATABASE_BRAIN_APP_URL"
ADMIN_URL_VAR = "DATABASE_BRAIN_DOADMIN_URL"

_pool: ThreadedConnectionPool | None = None


def _url(admin: bool = False) -> str:
    var = ADMIN_URL_VAR if admin else APP_URL_VAR
    url = os.getenv(var)
    if not url:
        fallback = os.getenv(APP_URL_VAR) if admin else None
        if fallback:
            logger.warning("%s not set; falling back to %s", var, APP_URL_VAR)
            return fallback
        raise RuntimeError(f"{var} is not set in brain/.env")
    return url


def _get_pool() -> ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = ThreadedConnectionPool(
            minconn=2,
            maxconn=8,
            dsn=_url(),
        )
    return _pool


def get_conn():
    """Borrow a connection from the pool. Return it with put_conn()."""
    return _get_pool().getconn()


def put_conn(conn):
    """Return a connection to the pool."""
    try:
        _get_pool().putconn(conn)
    except Exception:
        pass


def get_admin_conn():
    """Direct connection for admin/migration use. Caller must close."""
    return psycopg2.connect(_url(admin=True))
