"""
brain/chunking.py — body-into-chunks splitter + chunk persistence.

Splits long bodies on H2 (`\\n## `) boundaries; sub-splits on H3
(`\\n### `) if any single H2 still exceeds the cap. Embeds each chunk
via embeddings.embed and bulk-inserts into document_chunks.

Threshold rule:
  - If len(body) <= MAX_PARENT_EMBED_CHARS (20000), DO NOT chunk.
    The parent row's main embedding covers the whole body.
  - Otherwise produce N chunks (preamble + one per H2 section).
  - Chunks belonging to a row are always written transactionally as
    a delete-then-insert by the caller (see mcp_tools.upsert).

Why 20000 instead of 28000 (OpenAI's truncation point): leaves headroom
for non-ASCII / prose-heavy text where char-to-token ratio drifts from
3.5:1 toward 3:1. We'd rather chunk one extra row than silently lose
the tail.
"""

from __future__ import annotations

import logging
import re
import time
from typing import Iterable

from embeddings import EMBEDDING_MODEL, embed

logger = logging.getLogger(__name__)

# Chunk-trigger threshold. Bodies up to this length stay un-chunked
# (one parent embedding). Above this, we slice.
MAX_PARENT_EMBED_CHARS = 20000

# If a single H2 section exceeds this, sub-split on H3.
MAX_CHUNK_CHARS = 20000

# Polite throttle when embedding more than a few chunks back-to-back.
THROTTLE_AFTER_N = 3
THROTTLE_SECONDS = 0.2


def _split_on_heading(body: str, heading_marker: str) -> list[tuple[str | None, str]]:
    """
    Split body on `\\n<heading_marker>` boundaries. Returns a list of
    (heading, section_body) tuples. The first tuple has heading=None
    if there is content before the first heading; otherwise the first
    tuple's heading is the first heading line.

    `heading_marker` is the literal prefix WITH trailing space, e.g.
    `'## '` or `'### '`.
    """
    # Use a regex anchored to start-of-line for safe splitting that
    # preserves the heading line in the matched section.
    pattern = re.compile(rf"(?m)^{re.escape(heading_marker)}")
    # Find all match start positions.
    starts = [m.start() for m in pattern.finditer(body)]
    if not starts:
        return [(None, body)]

    sections: list[tuple[str | None, str]] = []
    # Preamble before first heading (if any)
    if starts[0] > 0:
        preamble = body[: starts[0]].rstrip("\n")
        if preamble.strip():
            sections.append((None, preamble))

    # Each heading section runs until the next heading start or EOF.
    bounds = starts + [len(body)]
    for i in range(len(starts)):
        section = body[bounds[i] : bounds[i + 1]]
        # Heading line is the first line of the section.
        first_nl = section.find("\n")
        if first_nl == -1:
            heading_line = section.strip()
        else:
            heading_line = section[:first_nl].strip()
        # Strip the leading marker for the heading text itself.
        heading_text = heading_line[len(heading_marker) :].strip() if heading_line.startswith(heading_marker) else heading_line
        sections.append((heading_text, section))
    return sections


def split_body(body: str) -> list[tuple[str | None, str]]:
    """
    Return [(heading, chunk_body), ...] for an oversized body.
    Each chunk_body INCLUDES the heading line so it's self-describing
    when re-embedded. Caller is responsible for the threshold gate.
    """
    sections = _split_on_heading(body, "## ")
    # Sub-split any oversized H2 section on H3 boundaries.
    expanded: list[tuple[str | None, str]] = []
    for heading, section in sections:
        if len(section) <= MAX_CHUNK_CHARS:
            expanded.append((heading, section))
            continue
        h3_split = _split_on_heading(section, "### ")
        if len(h3_split) == 1:
            # No H3 sub-headings — best we can do is keep the section as-is
            # and let embeddings.embed truncate. Better than dropping content.
            logger.warning(
                "chunking: H2 section %r is %d chars and has no H3 sub-headings; "
                "embedding will truncate the tail",
                heading, len(section),
            )
            expanded.append((heading, section))
            continue
        for sub_h, sub_body in h3_split:
            # Prefix the parent H2 heading to sub-chunks so embeddings
            # carry section context.
            label = f"{heading} :: {sub_h}" if sub_h else heading
            expanded.append((label, sub_body))
    return expanded


def should_chunk(body: str) -> bool:
    """True if the body is long enough to require chunking."""
    return len(body) > MAX_PARENT_EMBED_CHARS


def _vec_literal(vec: list[float]) -> str:
    return "[" + ",".join(repr(float(x)) for x in vec) + "]"


def write_chunks(conn, source_table: str, slug: str, body: str) -> int:
    """
    Replace existing chunks for (source_table, slug) with freshly-embedded
    chunks derived from `body`. Idempotent. Caller controls commit.

    Returns the number of chunks written. Returns 0 if the body is below
    the threshold (and no chunks remain).
    """
    # Always delete prior chunks for this slug. If body is short, this
    # is the only step (cleans up after a row that USED to be long).
    with conn.cursor() as cur:
        cur.execute(
            "DELETE FROM document_chunks WHERE source_table = %s AND source_key = %s",
            (source_table, slug),
        )

    if not should_chunk(body):
        return 0

    sections = split_body(body)
    if not sections:
        return 0

    rows = []
    for idx, (heading, chunk_body) in enumerate(sections):
        vec = embed(chunk_body)
        rows.append(
            (
                source_table,
                slug,
                idx,
                heading,
                chunk_body,
                _vec_literal(vec),
                EMBEDDING_MODEL,
            )
        )
        if (idx + 1) >= THROTTLE_AFTER_N and (idx + 1) < len(sections):
            time.sleep(THROTTLE_SECONDS)

    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO document_chunks
                (source_table, source_key, chunk_index, heading, body,
                 embedding, embedding_model)
            VALUES (%s, %s, %s, %s, %s, %s::vector, %s)
            """,
            rows,
        )
    logger.info(
        "chunking: wrote %d chunks for %s/%s (body=%d chars)",
        len(rows), source_table, slug, len(body),
    )
    return len(rows)
