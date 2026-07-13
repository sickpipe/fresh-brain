---
name: end-session
description: Run the full session close-out — update touched DB records, write a structured session-note handoff, and log ship entries to brain. Operator-invoked only; never auto-fires.
disable-model-invocation: true
---

# End Session (summoned)

When invoked, run this full close-out sequence BEFORE the closing reply. Requires the brain MCP. If the brain wasn't summoned this session, still write a thin session note (Step 2) so the log has no gaps.

## Step 1: Update database records

For every project or mission touched during the session:

1. **Business database (if installed):** Fetch the current project record, update the `notes` field to reflect current state — clear resolved issues, add recent work summary, update status if changed.
2. **Personal missions/tasks:** Update status and notes in the personal database to reflect current state.

The databases are the source of truth. Session notes are a handoff aid — the databases are the persistent record.

## Step 2: Write session note

```
memory_upsert(
  source_table='session_notes',
  slug='session-YYYY-MM-DD-HHMMSS',
  title='<one-line summary of the session>',
  summary='<2-3 sentence overview>',
  body=<structured handoff — see format below>,
  session_ended_at=<current timestamp>,
  projects_touched=[<list of project/mission slugs>],
  tags=['end-session', <additional context tags>]
)
```

**Body format:**

```
## What happened
- <bullet list of meaningful work, decisions, files touched>

## Where we left off
- <current state — running processes, half-done work, open questions>

## Suggested next step (handoff prompt for next session)
- **Context:** <1-2 sentences — what state the next session inherits>
- **Task:** <the specific next move, framed as if dictated to the next session>
- **Constraints / references:** <files, decisions, gotchas the next session needs to know>
```

The "Suggested next step" block is a launching prompt, not a one-line afterthought. Treat it as the briefing that lets the next session start cold and move immediately.

## Step 3: Log ship entries

If deliverables were shipped (code committed, files created, configs applied, records updated), write a ship log:

```
memory_upsert(
  source_table='memory_entries',
  slug='ship-YYYY-MM-DD-<short-slug>',
  title='Ship: <what was delivered>',
  entry_type='ship_log',
  body='<summary of what shipped, where it lives, any follow-up needed>',
  occurred_on='YYYY-MM-DD'
)
```

## Rules

1. **Atomic write** — session notes are append-only. Write once at session end; don't create then update.
2. **Always populate title** — keep `memory_list_recent` output scannable.
3. **Set session_ended_at explicitly** — no silent defaults.
4. **Slug format** — `session-YYYY-MM-DD-HHMMSS` (mechanical, collision-proof).
5. **Thin entries are fine** — if the session was trivial, skip Steps 1 and 3 but still write a one-liner session note. Gaps in the log are worse than thin entries.
6. **Be concrete** — file paths, decisions, current state. Not narrative.
7. **Role references, not character names** — in session notes and ship logs, reference team members by role or slug (e.g., "the researcher," "backend-dev"), not themed display names. Keeps records theme-agnostic.
