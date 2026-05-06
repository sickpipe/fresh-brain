"""
brain/mcp_tools_archivist.py — Session-note consolidation.

Provides consolidate_notes() for the memory_consolidate_notes MCP tool.
Archives old session notes by summarizing them into digest topic documents.
"""

import logging
from collections import defaultdict
from datetime import date, datetime

from psycopg2.extras import RealDictCursor

logger = logging.getLogger(__name__)


def _format_note(row: dict) -> str:
    """Format a single session note into a digest block."""
    created = row["created_at"]
    if isinstance(created, datetime):
        created = created.strftime("%Y-%m-%d")
    projects = ", ".join(row.get("projects_touched") or []) or "none"
    tags = ", ".join(row.get("tags") or []) or "none"
    return (
        f"### {row['title'] or row['summary']} ({created})\n"
        f"{row['summary']}\n\n"
        f"Projects: {projects}\n"
        f"Tags: {tags}"
    )


def consolidate_notes(
    conn,
    older_than_days: int = 14,
    dry_run: bool = False,
) -> dict:
    """Archive old session notes into digest topic documents."""
    older_than_days = max(1, int(older_than_days))

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT slug, title, summary, body, projects_touched, tags, "
            "       created_at "
            "FROM session_notes "
            "WHERE consolidated_at IS NULL "
            "  AND created_at < now() - make_interval(days => %s) "
            "ORDER BY created_at ASC",
            (older_than_days,),
        )
        rows = [dict(r) for r in cur.fetchall()]

    if not rows:
        return {"count": 0, "message": "No notes to consolidate"}

    # Group by first project touched (or "untagged")
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        pt = row.get("projects_touched") or []
        project = pt[0] if pt else "untagged"
        groups[project].append(row)

    digests_created = 0
    digests_updated = 0
    processed_slugs: list[str] = []

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        for project, notes in groups.items():
            # Determine year/month from the first note in the group
            first_created = notes[0]["created_at"]
            if isinstance(first_created, (datetime, date)):
                year = first_created.year
                month = f"{first_created.month:02d}"
            else:
                year = str(first_created)[:4]
                month = str(first_created)[5:7]

            target_slug = f"session-digest-{project}-{year}-{month}"
            digest_body = "\n\n".join(_format_note(n) for n in notes)

            # Check if slug exists
            cur.execute(
                "SELECT slug FROM topic_documents "
                "WHERE slug = %s AND deleted_at IS NULL",
                (target_slug,),
            )
            exists = cur.fetchone() is not None

            if exists:
                # Append to existing body
                cur.execute(
                    "UPDATE topic_documents "
                    "SET body = body || E'\\n\\n' || %s, "
                    "    updated_at = now() "
                    "WHERE slug = %s AND deleted_at IS NULL",
                    (digest_body, target_slug),
                )
                digests_updated += 1
            else:
                tags_val = ["session-digest", "archivist", project]
                cur.execute(
                    "INSERT INTO topic_documents "
                    "  (slug, title, topic, summary, namespace, scope, "
                    "   tags, body) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                    (
                        target_slug,
                        f"Session Digest: {project} — {year}-{month}",
                        "session-digest",
                        f"Consolidated session notes for {project}, "
                        f"{month}/{year}",
                        "global",
                        "system",
                        tags_val,
                        digest_body,
                    ),
                )
                digests_created += 1

            processed_slugs.extend(n["slug"] for n in notes)

        # Mark notes as consolidated (unless dry run)
        if not dry_run and processed_slugs:
            cur.execute(
                "UPDATE session_notes "
                "SET consolidated_at = now() "
                "WHERE slug = ANY(%s)",
                (processed_slugs,),
            )

    return {
        "count": len(processed_slugs),
        "digests_created": digests_created,
        "digests_updated": digests_updated,
        "dry_run": dry_run,
        "projects": list(groups.keys()),
    }
