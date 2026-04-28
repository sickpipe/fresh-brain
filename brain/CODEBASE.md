# brain — Codebase Map

## Entry Points

- **mcp_server.py** — Flask MCP server. `GET /health`, `POST /mcp`. Bearer-auth via `BRAIN_MCP_TOKEN` env var. Port 5050 local, bind 127.0.0.1. Dispatches four tools. Application-factory pattern (`create_app()`).
- **migrate_md_to_db.archived.py** — One-time (idempotent) ETL. Populated all 7 content tables from the Captain's markdown corpus on 2026-04-24 and reindexed ivfflat indexes at the end. Archived; do NOT re-run — the brain is now the source of truth and the legacy markdown corpus has been frozen.

## Backend Core Files

- **db.py** — psycopg2 connection helper. `get_conn(admin=False, dict_cursor=False)`. Admin path uses `DATABASE_BRAIN_DOADMIN_URL`; runtime uses `DATABASE_BRAIN_APP_URL`. Raw psycopg2 only — no SQLAlchemy at runtime.
- **embeddings.py** — Local embedding via `sentence-transformers` model `all-MiniLM-L6-v2` (384 dims). `embed(text) -> list[float]`. Runs entirely on-device, no API key needed.
- **history.py** — `record_history(conn, source_table, source_key, body, edited_by, change_note)`. Inserts a row into `document_history`. Does NOT commit. Must be called BEFORE an upsert that replaces an existing row.
- **mcp_tools.py** — The four tool implementations (`search`, `get`, `upsert`, `list_recent`). Pure DB logic; HTTP envelope is in mcp_server.py. Never SELECTs the `embedding` column in responses (useless to the LLM caller). `upsert` records history first, embeds, then `INSERT … ON CONFLICT (slug) DO UPDATE`.

## Migration Helpers

- **md_parsers.py** — Section-splitter parsers for MEMORY.md (H2 → entry_type mapping with ship-log/dictation-map overrides), CLAUDE.md (Standing Order blocks), ideas.md, CAPTAIN-INTENT.md.
- **md_parsers_simple.py** — Whole-file parsers (Team/*.md, memory/*.md topic docs) + shared utilities (`slugify`, `extract_date`).

## Schema Source of Truth

- **brain_models.py** — SQLAlchemy `Table()` metadata. Used by Alembic autogen ONLY. Runtime does NOT import it. Documented >300-line exception (same as nv_models.py).
- **alembic/** — migrations directory. Baseline migration already applied; schema is live on DO Managed Postgres NYC3.

## Key Rules

- 300-line file limit applies to all Python except `brain_models.py` (documented exception).
- Never `SELECT embedding` in tool responses.
- `record_history` before every upsert replace; the single `document_history` table covers all 6 versioned content tables.
- Bulk inserts require `REINDEX INDEX idx_*_embedding` afterward — ivfflat indexes built on empty tables return 0 rows for cosine-ORDER-BY until rebuilt. Migration script does this automatically.
- Embeddings are local (all-MiniLM-L6-v2, 384 dims); no external API calls.

## Environment Variables (brain/.env, chmod 600, gitignored)

- `DATABASE_BRAIN_APP_URL` — local Postgres connection string
- `BRAIN_MCP_TOKEN` — bearer token for `/mcp` (generated if unset, logged at startup)
- `BRAIN_MCP_PORT` — optional port override (default 5050)

## Local Development

```
source venv/bin/activate
pip install flask sentence-transformers requests   # one-time, already done
python mcp_server.py                               # 127.0.0.1:5050
```

## Deployment — Local Only

The brain runs locally on this Mac. Flask dev server on `127.0.0.1:5050`, Postgres at `127.0.0.1:5432/brain`. No external hosting. A prior DO droplet deployment (`165.22.32.250` / `brain.evenrail.com`) is decommissioned — that service may still be running but is no longer the source of truth.
