# shellcheck shell=bash
# Fresh Brain — Claude Code layer installer
#
# Shared by setup.sh (first-run, may prompt) and scripts/update.sh (must be
# fully non-interactive). Everything that writes into ~/.claude/ lives here so
# the install path and the update path can never drift apart again.
#
# Three surfaces are installed:
#
#   1. Operator skills  -> ~/.claude/skills/{brain,end-session}
#        The summoned half. Only loaded when the operator types /brain.
#
#   2. Global CLAUDE.md -> ~/.claude/CLAUDE.md  (sentinel-delimited block)
#        The plain-Claude-Code half. This is the ONLY file Claude Code loads in
#        every working directory, so the opt-in model and the database routing
#        map have to live here. A repo-root CLAUDE.md only loads inside the
#        repo; auto-memory only loads for one working directory. Neither can
#        carry awareness globally.
#
#   3. Auto-memory seed -> ~/.claude/projects/<slug>/memory/
#        A growth surface for knowledge to accumulate across sessions. It is
#        NOT the delivery mechanism for awareness (see #2). Create-if-absent,
#        always — this directory is operator-owned and may hold months of work.
#
# bash 3.2 compatible (macOS /bin/bash). No associative arrays, no ${var,,},
# no readarray.

# ── Logging ───────────────────────────────────────────────────
# Reuse the caller's colored helpers when present, otherwise fall back to
# plain echo so the library is usable standalone (and in tests).

if ! declare -f info >/dev/null 2>&1; then
    info() { echo "[INFO]  $*"; }
fi
if ! declare -f ok >/dev/null 2>&1; then
    ok()   { echo "[OK]    $*"; }
fi
if ! declare -f warn >/dev/null 2>&1; then
    warn() { echo "[WARN]  $*"; }
fi

# ── Constants ─────────────────────────────────────────────────

FB_BEGIN_MARKER='<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->'
FB_END_MARKER='<!-- FRESH BRAIN: END -->'

# ── Helpers ───────────────────────────────────────────────────

fb_claude_dir()  { echo "$HOME/.claude"; }
fb_backup_dir()  { echo "$HOME/.claude/backups"; }
fb_utc_stamp()   { date -u +%Y%m%dT%H%M%SZ; }

# fb_project_slug: Claude Code keys per-project memory by the absolute working
# directory with '/' replaced by '-'. We seed the operator's HOME, which is
# where most people launch Claude Code from.
fb_project_slug() {
    printf '%s' "$HOME" | tr '/' '-'
}

# fb_global_block_body: the managed content of ~/.claude/CLAUDE.md.
#
# This loads in EVERY session, so every line costs context in every session.
# Keep it under a screen. No timestamps, no host-specific values — the output
# must be byte-identical on every run or idempotency breaks.
fb_global_block_body() {
    cat <<'FBBLOCK'
# Fresh Brain

Default to **plain Claude Code**. Do read-only and simple work directly. Surface options rather than auto-driving.

## The brain is opt-in

The full orchestrator — DB-backed memory bootstrap, standing orders, specialist delegation, database-first logging — does **not** auto-fire. Summon it with `/brain`; close out with `/end-session`.

Until it is summoned in a session:

- Don't run bootstrap rituals or `load_core`.
- Don't fire standing orders or auto-dispatch to specialists.
- Don't treat delegation/database-first as mandatory.

Read-only MCP lookups are fine unsummoned when a specific question calls for one. Just don't enter full orchestrator mode.

## Database routing

Two local Postgres databases are reachable over MCP. The namespace in the tool name is the database.

- **brain** (`mcp__brain__*`) — system/meta: team roster, standing orders, topic documents, session notes, operator intent, config. Probes: `memory_search`, `memory_get`, `memory_list_recent`.
- **personal** (`mcp__personal__*`) — life: workspaces, missions, tasks, notes, journal entries. Probes: `personal_search`, `personal_list`, `personal_stats`.

Routing rule: how-the-system-works / team / past sessions → **brain**. Personal life / missions / tasks / journal → **personal**.

If a brain or personal tool is missing, the MCP daemons may be down — run `./scripts/start-mcp.sh` in the Fresh Brain repo and restart Claude Code.
FBBLOCK
}

# fb_repo_block_body: the managed content of the repo-root CLAUDE.md.
# Loads only when Claude Code is run inside the Fresh Brain repo, so it holds
# repo-local operational notes and deliberately does not repeat the working
# model (which is global and loads everywhere).
fb_repo_block_body() {
    cat <<'FBREPO'
# Fresh Brain — Repo Notes

The working model — plain Claude Code by default, orchestrator opt-in via `/brain`, brain/personal routing map — is installed globally in `~/.claude/CLAUDE.md` between the `FRESH BRAIN: BEGIN/END` markers. It loads in every session and is not repeated here.

Repo-local notes:

- Daemons: `./scripts/start-mcp.sh` (idempotent). Logs: `brain/mcp.log`, `personal/mcp.log`.
- Updates: `./scripts/update.sh` — pulls, migrates, and reinstalls the Claude Code layer (skills, global CLAUDE.md, auto-memory).
- If `/brain` reports that `load_core` is unavailable, the MCP servers aren't running. Start them, then restart Claude Code so the tools are rediscovered.
- Full working model and skill descriptions: `brain/CLAUDE.md`.
FBREPO
}

# ── 1. Operator skills ────────────────────────────────────────

# install_operator_skills <repo_dir> [mode]
#   mode: "interactive" (default) prompts before replacing an existing skill.
#         "auto" replaces silently when contents differ, backing up first.
install_operator_skills() {
    local repo_dir="$1"
    local mode="${2:-interactive}"
    local src_root="$repo_dir/skills"
    local dest_root="$HOME/.claude/skills"
    local name

    if [ ! -d "$src_root" ]; then
        warn "No skills/ directory in $repo_dir — skipping skill install"
        return 0
    fi

    for name in brain end-session; do
        _fb_install_one_skill "$src_root/$name" "$dest_root/$name" "$name" "$mode"
    done
}

_fb_install_one_skill() {
    local src="$1" dest="$2" name="$3" mode="$4"
    local ans ans_lc backup

    if [ ! -d "$src" ]; then
        warn "Skill source not found: $src — skipping"
        return 0
    fi

    if [ -d "$dest" ]; then
        if diff -rq "$src" "$dest" >/dev/null 2>&1; then
            ok "Skill '$name' already up to date"
            return 0
        fi
        if [ "$mode" = "auto" ]; then
            backup="$(fb_backup_dir)/skills/${name}.pre-fresh-brain-$(fb_utc_stamp)"
            mkdir -p "$(dirname "$backup")"
            cp -R "$dest" "$backup"
            info "Backed up existing skill '$name' -> $backup"
        else
            read -rp "  Skill '$name' already exists at $dest and differs. Overwrite? (y/N): " ans
            ans_lc=$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')
            if [ "$ans_lc" != "y" ] && [ "$ans_lc" != "yes" ]; then
                warn "Keeping existing skill '$name'"
                return 0
            fi
        fi
        rm -rf "$dest"
    fi

    mkdir -p "$(dirname "$dest")"
    cp -R "$src" "$dest"
    ok "Installed skill '$name' -> $dest"
}

# ── 2. CLAUDE.md managed blocks ───────────────────────────────

# install_global_claude_md
#   Creates, appends to, or updates the managed block in ~/.claude/CLAUDE.md.
#   Never clobbers operator-authored content: a pre-existing file with no
#   managed block is backed up and then APPENDED to, never rewritten.
#   Idempotent — running twice yields a byte-identical file.
install_global_claude_md() {
    mkdir -p "$(fb_claude_dir)"
    _fb_install_managed_block \
        "$(fb_claude_dir)/CLAUDE.md" \
        fb_global_block_body \
        "$(fb_backup_dir)/CLAUDE.md"
}

# install_repo_claude_md <repo_dir>
#   Same mechanism, applied to the repo-root CLAUDE.md — a short pointer that
#   only loads when Claude Code runs inside the Fresh Brain repo. Deliberately
#   does NOT repeat the working model (that's global); it carries repo-local
#   operational notes only. Generated, and gitignored.
install_repo_claude_md() {
    local repo_dir="$1"
    _fb_install_managed_block \
        "$repo_dir/CLAUDE.md" \
        fb_repo_block_body \
        "$(fb_backup_dir)/repo-CLAUDE.md"
}

# _fb_install_managed_block <target> <body_fn> <backup_prefix>
_fb_install_managed_block() {
    local target="$1" body_fn="$2" backup_prefix="$3"
    local tmp body backup

    body="$(mktemp "${TMPDIR:-/tmp}/fbclaude.XXXXXX")" || return 1
    "$body_fn" > "$body"

    if [ ! -f "$target" ]; then
        mkdir -p "$(dirname "$target")"
        _fb_write_block "$target" "$body"
        ok "Created $target with the Fresh Brain block"
        rm -f "$body"
        return 0
    fi

    if grep -Fqx "$FB_BEGIN_MARKER" "$target" 2>/dev/null; then
        tmp="$(mktemp "${TMPDIR:-/tmp}/fbclaudeout.XXXXXX")" || { rm -f "$body"; return 1; }
        awk -v b="$FB_BEGIN_MARKER" -v e="$FB_END_MARKER" -v bodyfile="$body" '
            $0 == b { print; while ((getline line < bodyfile) > 0) print line; close(bodyfile); inblock=1; next }
            $0 == e { print; inblock=0; next }
            !inblock { print }
        ' "$target" > "$tmp"
        if cmp -s "$tmp" "$target"; then
            ok "$target already current (no change)"
            rm -f "$tmp"
        else
            cat "$tmp" > "$target"
            rm -f "$tmp"
            ok "Refreshed the Fresh Brain block in $target"
        fi
        rm -f "$body"
        return 0
    fi

    # Existing operator file with no managed block: back up, then append.
    backup="${backup_prefix}.pre-fresh-brain-$(fb_utc_stamp).bak"
    mkdir -p "$(dirname "$backup")"
    cp "$target" "$backup"
    info "Backed up existing $(basename "$target") -> $backup"

    # Guarantee a trailing newline before appending so the marker starts a line.
    if [ -s "$target" ] && [ "$(tail -c 1 "$target" | wc -l | tr -d ' ')" = "0" ]; then
        printf '\n' >> "$target"
    fi
    printf '\n' >> "$target"
    _fb_append_block "$target" "$body"
    ok "Appended the Fresh Brain block to $target (your content preserved)"
    rm -f "$body"
}

_fb_write_block() {
    local target="$1" body="$2"
    : > "$target"
    _fb_append_block "$target" "$body"
}

_fb_append_block() {
    local target="$1" body="$2"
    printf '%s\n' "$FB_BEGIN_MARKER" >> "$target"
    cat "$body" >> "$target"
    printf '%s\n' "$FB_END_MARKER" >> "$target"
}

# ── 3. Auto-memory seed ───────────────────────────────────────

# seed_auto_memory
#   Seeds ~/.claude/projects/<slug-of-$HOME>/memory/ with an index and one
#   reference memory. Create-if-absent ONLY: an existing MEMORY.md or memory
#   file is left completely untouched and reported.
seed_auto_memory() {
    local slug mem_dir index seed
    slug="$(fb_project_slug)"
    mem_dir="$HOME/.claude/projects/$slug/memory"
    index="$mem_dir/MEMORY.md"
    seed="$mem_dir/reference_fresh_brain_databases.md"

    mkdir -p "$mem_dir"

    if [ -f "$seed" ]; then
        ok "Memory file already exists (left untouched): $seed"
    else
        cat > "$seed" <<'FBMEM'
---
name: fresh-brain-databases
description: Which Fresh Brain MCP database holds what — brain for system/team/knowledge, personal for life/missions/journal — so a plain session routes lookups without summoning /brain.
metadata:
  type: reference
---

Fresh Brain installs two local Postgres databases, each fronted by its own MCP
server. The namespace in the tool name is the database.

## brain — http://127.0.0.1:5050/mcp
System and meta layer: `team_members`, `standing_orders`, `topic_documents`,
`memory_entries`, `session_notes`, `operator_intent`, `brain_config`.
Team roster, how the system works, crystallized knowledge, past session
handoffs → here. Probes: `memory_search`, `memory_get`, `memory_list_recent`.

## personal — http://127.0.0.1:5051/mcp
Life layer: `workspaces`, `missions`, `tasks`, `task_items`, `notes`, `assets`,
`tags`, `journal_entries`. Work is organized under missions; domain records
live in that mission's notes/tasks/journal entries.
Probes: `personal_search`, `personal_list`, `personal_stats`.

## Routing rule
How-the-system-works / team / past sessions → **brain**.
Personal life / missions / tasks / journal → **personal**.

Read-only lookups are fine in plain Claude Code. Full orchestrator mode
(bootstrap, standing orders, delegation) requires the operator to type
`/brain`.
FBMEM
        ok "Seeded memory file: $seed"
    fi

    if [ -f "$index" ]; then
        ok "MEMORY.md already exists (left untouched): $index"
        info "  To index the seed, add: - [Fresh Brain databases](reference_fresh_brain_databases.md) — brain=system/team, personal=life/missions."
    else
        cat > "$index" <<'FBIDX'
- [Fresh Brain databases](reference_fresh_brain_databases.md) — which MCP DB holds what: brain=system/team/knowledge, personal=life/missions/journal. Route without /brain.
FBIDX
        ok "Seeded memory index: $index"
    fi
}

# ── Convenience ───────────────────────────────────────────────

# install_claude_layer <repo_dir> [mode]
#   Runs every installer in order.
install_claude_layer() {
    local repo_dir="$1" mode="${2:-interactive}"
    install_operator_skills "$repo_dir" "$mode"
    install_global_claude_md
    install_repo_claude_md "$repo_dir"
    seed_auto_memory
}
