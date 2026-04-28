# Spock's Brain

Live AI orchestration instance — the working brain behind the operation.

For the clean starter template, see [Fresh Brain](https://github.com/sickpipe/fresh-brain).

## What's Here

- **Brain MCP Server** (`mcp_tools.py`, `mcp_tools_query.py`) — Postgres + pgvector backed memory server exposing search, upsert, history, and rollback tools to Claude
- **Schema** (`schema.sql`) — v4 schema with pgvector embeddings, full history tracking, and capability tags
- **Migrations** (`migrations/`) — raw SQL migrations (Alembic removed)
- **Models** (`brain_models.py`) — SQLAlchemy models for reference and tooling
- **Admin Scripts** (`scripts/`) — archive dumps, backfill utilities
- **Orchestrator Config** (`CLAUDE.md`) — bootstrap rules, delegation framework, team roster protocol

## Stack

- PostgreSQL + pgvector on DigitalOcean Managed DB
- Python, psycopg2, SQLAlchemy
- OpenAI `text-embedding-3-small` (1536 dims)
- Runs on a Mac Mini as the live operational instance

## Data

Operational data (team members, standing orders, config, memory entries) lives in Postgres, not in files. This repo contains the server code and schema only.
