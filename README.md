# Fresh Brain

Portable AI orchestration template for Claude Code.

Sets up a **brain** database (AI memory, team members, standing orders) and a **personal** database (missions, tasks, notes) with MCP servers that plug directly into Claude Code.

## What You Get

- **Brain MCP Server** -- Postgres + pgvector memory server with hybrid search (semantic + full-text), version history, and team member profiles
- **Personal MCP Server** -- Task/mission tracker with full-text search, workspaces, and document history
- **Opt-in Orchestrator** -- Plain Claude Code by default; summon the full orchestrator (memory bootstrap, standing orders, specialist delegation) on demand with `/brain`, and close out with `/end-session`. Both skills are operator-only — the model can't fire them on its own
- **Plain-Mode Awareness** -- Even unsummoned, Claude Code knows the two databases exist and which one holds what. Setup writes a managed block into your global `~/.claude/CLAUDE.md` (loads in every working directory) and seeds an auto-memory file you can grow over time
- **4 Starter Team Members** -- Orchestrator, Developer, Researcher, and HR Director ready to go
- **Starter Packs** -- Optional add-ons offered during first-run setup: Business (CRM/ERP), additional team members (health, finance, creative, ops), and standing orders
- **Re-Themeable** -- Choose a theme during setup (Star Trek, The Office, Lord of the Rings, anything) or switch anytime by telling the orchestrator to "apply theme: [name]." Character mappings are generated on the fly — no pre-built manifests needed

## How It Works

By default every session is plain Claude Code. Typing `/brain` summons the orchestrator, which uses a three-tier memory retrieval system:

- **Core** — On summoning, the orchestrator calls `load_core` to load its identity, team roster, standing orders, and operator intent in a single call. Always in context, zero search cost.
- **On-Demand** — During conversation, the orchestrator searches the brain when you mention a project, person, or system. Search combines semantic similarity (pgvector) with full-text matching (tsvector) using reciprocal rank fusion for accurate retrieval of both conceptual and exact-match queries.
- **Background** — When you type `/end-session`, the orchestrator records what happened (ship logs, session notes) so future sessions pick up where you left off.

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
8. Install the `/brain` and `/end-session` skills into `~/.claude/skills/` (prompting before overwriting any existing skill of the same name)
9. Write a managed block into your global `~/.claude/CLAUDE.md` carrying the opt-in working model and the brain/personal routing map (your existing file is backed up to `~/.claude/backups/` and appended to — never overwritten)
10. Seed `~/.claude/projects/<slug>/memory/` with a starter memory index and DB routing reference (create-if-absent — existing memory files are never touched)

When the script finishes, restart Claude Code (Cmd+Q then reopen) and type `/brain` — the orchestrator will detect a fresh brain and walk you through onboarding. Between summons, Claude Code stays in its plain default mode.

## The Two Layers

Fresh Brain installs into Claude Code at two levels, and they serve different jobs.

**Plain layer — always loaded.** A sentinel-delimited block in your global `~/.claude/CLAUDE.md`:

```
<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->
...
<!-- FRESH BRAIN: END -->
```

This is the only file Claude Code loads in *every* working directory, which is why the database routing map lives there. A repo-root `CLAUDE.md` loads only inside the repo, and auto-memory is keyed to a single working directory — neither can carry awareness everywhere. The block is small on purpose: it costs context in every session. Editing inside the markers is pointless (it gets rewritten); edit outside them freely.

Your file is never modified without a timestamped copy landing in `~/.claude/backups/` first. If the markers get mangled — a BEGIN with no END, or a duplicated block — setup does not guess where the block ends: it backs up, tells you what it found, keeps every line you wrote (only the marker lines are removed) and appends one properly terminated block at the end.

**Summoned layer — loaded on demand.** The `/brain` and `/end-session` skills in `~/.claude/skills/`. Nothing in the orchestrator ruleset — bootstrap, standing orders, delegation, database-first logging — enters context until you type `/brain`.

**Growth surface.** `~/.claude/projects/<slug>/memory/` holds a `MEMORY.md` index plus one-topic memory files. Setup seeds a DB routing reference and never touches it again; add to it as knowledge accumulates.

Both layers are installed by `scripts/lib/claude-layer.sh`, which `setup.sh` and `scripts/update.sh` share. `./scripts/update.sh` re-runs all of it non-interactively, so an existing install stays at parity with a fresh one.

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
| `memory_link_documents` | Create typed directional links between topic documents |
| `memory_list_links` | List links for a topic document (outgoing, incoming, or both) |

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
  skills/
    brain/           # /brain skill — summons the full orchestrator (installed to ~/.claude/skills/)
    end-session/     # /end-session skill — session close-out protocol
  scripts/
    lib/
      claude-layer.sh  # Installs the Claude Code layer (skills, global CLAUDE.md, auto-memory)
    migrate.sh       # Apply pending DB migrations
    update.sh        # git pull + migrations + Claude Code layer refresh (non-interactive)
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

See [brain/CLAUDE.md](brain/CLAUDE.md) for the opt-in working model and the two Claude Code layers, and [skills/brain/SKILL.md](skills/brain/SKILL.md) for the full orchestrator bootstrap flow, delegation framework, and team management protocol (first-run onboarding happens the first time you type `/brain`). Session close-out lives in [skills/end-session/SKILL.md](skills/end-session/SKILL.md).

## Troubleshooting

- **Verify MCP servers are registered with Claude Code:** `claude mcp list` — you should see `brain` and `personal` entries pointing at `http://127.0.0.1:5050/mcp` and `:5051/mcp`.
- **Inspect daemon logs:** `tail brain/mcp.log` and `tail personal/mcp.log`. PIDs are recorded in `brain/mcp.pid` / `personal/mcp.pid`.
- **Restart daemons after a reboot:** `./scripts/start-mcp.sh` (idempotent — skips servers that are already running and healthy).
- **Claude Code doesn't know about the databases in plain mode:** check that `~/.claude/CLAUDE.md` contains the `FRESH BRAIN: BEGIN` block, then restart Claude Code. `./scripts/update.sh` reinstalls it.
- **`/brain` isn't offered:** the skills aren't installed. `ls ~/.claude/skills/` should list `brain` and `end-session`; run `./scripts/update.sh` to reinstall, then restart Claude Code.
- **Removing the plain layer:** delete everything between the `FRESH BRAIN: BEGIN` and `END` markers in `~/.claude/CLAUDE.md` (markers included). Your pre-install file is in `~/.claude/backups/`.
- **Full clean reset:** `./scripts/reset.sh` stops daemons, drops databases, removes Claude Code MCP entries, and deletes `.venv` + `.env` + log/pid files. Then re-run `./setup.sh`.

## License

MIT
