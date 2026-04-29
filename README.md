# Fresh Brain

Portable AI orchestration template for Claude Code.

Sets up a **brain** database (AI memory, team members, standing orders) and a **personal** database (missions, tasks, notes) with MCP servers that plug directly into Claude Code.

## What You Get

- **Brain MCP Server** -- Postgres + pgvector memory server with hybrid search (semantic + full-text), version history, and team member profiles
- **Personal MCP Server** -- Task/mission tracker with full-text search, workspaces, and document history
- **3 Starter Team Members** -- Orchestrator, Developer, and Researcher ready to go
- **Starter Packs** -- Optional add-ons offered during first-run setup: Business (CRM/ERP), additional team members (health, finance, creative, ops), and standing orders

## How It Works

The orchestrator uses a three-tier memory retrieval system:

- **Core** — At session start, the orchestrator calls `load_core` to load its identity, team roster, standing orders, and operator intent in a single call. Always in context, zero search cost.
- **On-Demand** — During conversation, the orchestrator searches the brain when you mention a project, person, or system. Search combines semantic similarity (pgvector) with full-text matching (tsvector) using reciprocal rank fusion for accurate retrieval of both conceptual and exact-match queries.
- **Background** — At session end, the orchestrator records what happened (ship logs, session notes) so future sessions pick up where you left off.

All retrieval is agent-driven — the orchestrator decides when to search based on conversation context. No hooks, no latency penalty on every prompt.

## Quick Start

```bash
git clone https://github.com/sickpipe/fresh-brain.git
cd fresh-brain
./setup.sh
```

`setup.sh` is end-to-end. It will:

1. Ask your name, title, timezone, and how the AI should address you
2. Check prerequisites (PostgreSQL, pgvector, Python 3.10+)
3. Create and seed the `brain` and `personal` databases
4. Build a project-local `.venv` and `pip install` both requirements files (torch is large — first run takes a few minutes)
5. Generate `brain/.env` and `personal/.env` with random bearer tokens
6. Launch the brain (port 5050) and personal (port 5051) MCP daemons via `scripts/start-mcp.sh`, polling `/health` until both come up
7. Register both servers with Claude Code at user scope via `claude mcp add --transport http`

When the script finishes, restart Claude Code (Cmd+Q then reopen). The orchestrator will detect a fresh brain and walk you through onboarding.

## Brain Tools

| Tool | Purpose |
|------|---------|
| `memory_search` | Hybrid semantic + full-text search across content tables |
| `memory_get` | Fetch one row by table + slug |
| `memory_upsert` | Insert or update a full row (records history, recomputes embedding) |
| `memory_patch` | Partial update — modifies only provided fields without replacing the whole row |
| `memory_list_recent` | List recent rows from a table |
| `memory_history` | Read edit history for a row (full JSONB snapshots) |
| `memory_rollback` | Restore a previous version from history |
| `memory_list_capabilities` | Find team members by skill tags |
| `load_core` | Single bootstrap call — returns config, roster, standing orders, and operator intent |

## Prerequisites

- PostgreSQL with [pgvector](https://github.com/pgvector/pgvector) extension
- Python 3.10+

`setup.sh` builds its own `.venv` and installs Python deps automatically — no manual `pip install` step.

### Choosing your Postgres version (macOS / Homebrew)

`brew install pgvector` only ships extension files for the Postgres versions Homebrew has built it against on your machine. If you install a Postgres version pgvector wasn't built for, `setup.sh` will fail at the pgvector check even though both packages installed cleanly.

Before `brew install postgresql@<N>`, check which versions pgvector supports:

```bash
ls $(brew --prefix pgvector)/share/
# e.g. postgresql@17  postgresql@18  -> pick @17 or @18, NOT @16
```

Pick a Postgres version that appears in that listing.

### Python version on Intel Macs

PyTorch dropped Intel Mac support after version 2.2.x, and that last version doesn't ship Python 3.13 wheels. Fresh Brain's brain server uses local embeddings via `sentence-transformers`, which requires torch.

If you're on an Intel Mac:

```bash
brew install python@3.12
```

`setup.sh` will detect Intel + Python 3.13 and use brew's python@3.12 automatically.

## Structure

```
fresh-brain/
  brain/             # AI memory MCP server (hybrid semantic + full-text search)
  personal/          # Mission/task MCP server (full-text search)
  scripts/
    migrate.sh       # Apply pending DB migrations
    start-mcp.sh     # Idempotent daemon launcher (used by setup, also standalone)
    reset.sh         # Tear down everything for a clean reinstall
  setup.sh           # End-to-end first-run setup
```

## Search

Brain uses hybrid retrieval combining two approaches:

- **Semantic search** — pgvector cosine distance on 384-dim embeddings (all-MiniLM-L6-v2, runs locally)
- **Full-text search** — PostgreSQL tsvector/GIN indexes on titles and bodies

Results are merged using reciprocal rank fusion (RRF), so exact matches on project names and slugs rank alongside conceptually similar content.

## Security

- MCP server binds to `127.0.0.1` by default (localhost only)
- Bearer token auth on all endpoints
- Table and column whitelists prevent SQL injection
- All writes are versioned with full-row JSONB snapshots for rollback

## Onboarding

See [brain/CLAUDE.md](brain/CLAUDE.md) for the full orchestrator bootstrap flow, delegation framework, and team management protocol.

## Troubleshooting

- **Verify MCP servers are registered with Claude Code:** `claude mcp list` — you should see `brain` and `personal` entries pointing at `http://127.0.0.1:5050/mcp` and `:5051/mcp`.
- **Inspect daemon logs:** `tail brain/mcp.log` and `tail personal/mcp.log`. PIDs are recorded in `brain/mcp.pid` / `personal/mcp.pid`.
- **Restart daemons after a reboot:** `./scripts/start-mcp.sh` (idempotent — skips servers that are already running and healthy).
- **Full clean reset:** `./scripts/reset.sh` stops daemons, drops databases, removes Claude Code MCP entries, and deletes `.venv` + `.env` + log/pid files. Then re-run `./setup.sh`.

## License

MIT
