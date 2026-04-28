"""
db_helpers.py — Database connection and query helpers for Enterprise Dashboard.

Provides a context-manager-based connection (db_conn) so every caller gets
automatic close on all paths including exceptions, plus thin query helpers
that preserve the original call-site signatures from server.py.
"""

import os
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

DATABASE_URL = os.environ.get("DATABASE_PERSONAL_APP_URL")
if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_PERSONAL_APP_URL not set; ensure .env is readable at "
        + os.path.dirname(os.path.abspath(__file__))
    )

# Brain DB is optional — app boots fine without it.
DATABASE_BRAIN_URL = os.environ.get("DATABASE_BRAIN_APP_URL")


@contextmanager
def db_conn():
    """
    Context manager that opens a psycopg2 connection and guarantees close.

    Usage:
        with db_conn() as conn:
            rows = query_all(conn, sql, params)
    """
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    try:
        yield conn
    finally:
        conn.close()


@contextmanager
def brain_conn():
    """
    Context manager for the brain database connection.

    Returns None (yields nothing usable) if DATABASE_BRAIN_APP_URL is not set,
    so callers must handle the None case.

    Usage:
        with brain_conn() as conn:
            if conn is None:
                return fallback
            rows = query_all(conn, sql, params)
    """
    if not DATABASE_BRAIN_URL:
        yield None
        return
    conn = psycopg2.connect(DATABASE_BRAIN_URL, cursor_factory=RealDictCursor)
    try:
        yield conn
    finally:
        conn.close()


def get_db():
    """Open a new psycopg2 connection with RealDictCursor as default cursor.

    Prefer db_conn() context manager over this for automatic close. This
    function is retained for code paths that need manual lifecycle control.
    """
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)


def query_all(conn, sql, params=()):
    """Execute sql and return all rows as RealDictRow objects."""
    cur = conn.cursor()
    cur.execute(sql, params)
    rows = cur.fetchall()
    cur.close()
    return rows


def query_one(conn, sql, params=()):
    """Execute sql and return the first row, or None."""
    cur = conn.cursor()
    cur.execute(sql, params)
    row = cur.fetchone()
    cur.close()
    return row


def exec_write(conn, sql, params=()):
    """Execute a write statement (INSERT/UPDATE/DELETE). Caller commits."""
    cur = conn.cursor()
    cur.execute(sql, params)
    cur.close()


def rows_to_dicts(rows):
    """Convert RealDictRow objects to plain dicts.

    Identity-ish operation retained for API parity with the SQLite version.
    """
    return [dict(r) for r in rows]
