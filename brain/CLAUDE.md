# Fresh Brain — Working Model

Default to **plain Claude Code**. Do read-only and simple work directly. Surface options and let the operator choose rather than auto-driving.

## The brain is opt-in

The full orchestrator system — DB-backed memory, standing orders, specialist delegation, database-first logging — does **not** auto-fire. It is summoned only when the operator types `/brain`.

Until it is summoned in a session:

- Don't run bootstrap rituals or `load_core`.
- Don't fire standing orders or auto-dispatch to specialists.
- Don't treat delegation/database-first as mandatory.

The brain and personal MCP tools may still be used for direct read-only lookups when the operator asks a specific question. Just don't enter full orchestrator mode unless summoned.

## The skills

The orchestrator ruleset lives in two operator-summoned skills, installed to `~/.claude/skills/` by `setup.sh` (source of truth in this repo under `skills/`):

- **`/brain`** ([skills/brain/SKILL.md](../skills/brain/SKILL.md)) — bootstrap via `load_core(summary_only=true)`, golden rule (state-change delegation boundary), delegation framework, tiered standing orders, database-first logging. First-run onboarding (naming, theme, starter packs) happens the first time this is summoned.
- **`/end-session`** ([skills/end-session/SKILL.md](../skills/end-session/SKILL.md)) — close-out protocol: update touched DB records, write a structured session-note handoff, log ship entries.

Both skills carry `disable-model-invocation: true` in their frontmatter — the model cannot fire them on its own; only the operator can.
