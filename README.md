# Fresh Brain

Portable AI orchestration template for Claude Code.

Sets up a **brain** database (AI memory, team members, standing orders) and a **personal** database (missions, tasks, notes) with MCP servers that plug directly into Claude Code.

## What You Get

- **Brain MCP Server** -- Postgres + pgvector memory server with semantic search, version history, and team member profiles
- **Personal MCP Server** -- Task/mission tracker with full-text search, workspaces, and document history
- **3 Starter Team Members** -- Orchestrator, Developer, and Researcher ready to go
- **Starter Packs** -- Optional additional team members (health, finance, creative, legal, ops) offered during first-run setup

## Quick Start

```bash
git clone https://github.com/sickpipe/fresh-brain.git
cd fresh-brain
chmod +x setup.sh
./setup.sh
```

The setup script will:

1. Ask your name, title, timezone, and how the AI should address you
2. Check prerequisites (PostgreSQL, pgvector, Python 3)
3. Create and seed the `brain` and `personal` databases
4. Apply schemas and insert starter data

After setup, configure your Claude Code MCP servers by adding to `~/.claude.json`:

```json
{
  "mcpServers": {
    "brain": {
      "command": "python3",
      "args": ["/path/to/fresh-brain/brain/mcp_server.py"],
      "env": {
        "DATABASE_BRAIN_APP_URL": "postgresql://localhost/brain",
        "BRAIN_MCP_TOKEN": "your-token",
        "BRAIN_MCP_PORT": "5050"
      }
    },
    "personal": {
      "command": "python3",
      "args": ["/path/to/fresh-brain/personal/mcp_server.py"],
      "env": {
        "DATABASE_PERSONAL_APP_URL": "postgresql://localhost/personal",
        "PERSONAL_MCP_TOKEN": "your-token",
        "PERSONAL_MCP_PORT": "5051"
      }
    }
  }
}
```

Restart Claude Code. The orchestrator will detect a fresh brain and walk you through onboarding.

## Prerequisites

- PostgreSQL with [pgvector](https://github.com/pgvector/pgvector) extension
- Python 3.10+
- `pip install -r brain/requirements.txt` and `pip install -r personal/requirements.txt`

## Structure

```
fresh-brain/
  brain/          # AI memory MCP server (pgvector semantic search)
  personal/       # Mission/task MCP server (full-text search)
  scripts/        # Database migration runner
  setup.sh        # First-run setup
```

## Onboarding

See [brain/CLAUDE.md](brain/CLAUDE.md) for the full orchestrator bootstrap flow, delegation framework, and team management protocol.

## License

MIT
