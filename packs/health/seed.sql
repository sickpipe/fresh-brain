-- Health Knowledge System — Starter Pack
-- Run: psql -U brain_user -d brain -f packs/health/seed.sql
-- Idempotent: all inserts use ON CONFLICT DO NOTHING

-- ============================================================
-- Team Member: Health Specialist
-- ============================================================

INSERT INTO team_members (slug, display_name, role, summary, capabilities, status, persona)
VALUES (
  'health-specialist',
  'Health Specialist',
  'Health Specialist & Wellness Advisor',
  'Health specialist who interprets lab results, advises on wellness, nutrition, supplements, and metabolic health with a functional medicine lens.',
  ARRAY['health', 'wellness', 'lab-interpretation', 'nutrition', 'supplements', 'functional-medicine', 'metabolic-health'],
  'active',
  'Speaks with clinical authority on health topics. Uses a functional medicine lens — looks for root causes rather than symptom management. Interprets lab results in context of the full picture. Conservative with supplement recommendations (food-first). Flags risks clearly. Maintains a persistent working hypothesis that evolves with new data.'
) ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- Topic Document: Health Index (master table of contents)
-- ============================================================

INSERT INTO topic_documents (slug, title, body, topic, summary, namespace, scope, tags)
VALUES (
  'health-index',
  'Health Index — Master Table of Contents',
  E'# Health Index — Master Table of Contents\n\n*Last updated: (auto-maintained)*\n*Purpose: Always load this document first before any health dispatch.*\n\n## How to Use This Index\n\n1. Load this document + health-context before every health dispatch\n2. Use tags and relationships to identify which documents to load\n3. After any health knowledge addition, update this index\n\n## Brain Topic Documents (Knowledge Base)\n\n| Slug | Title | Key Topics | Last Updated |\n|------|-------|------------|---------------|\n| `health-context` | Health Context (persistent state) | hypotheses, open questions, patterns | — |\n| `health-knowledge-protocols` | Intake & Dispatch Protocols | procedures, intake, dispatch | — |\n\n## Personal DB Notes (Patient Chart)\n\n*(Add note references here as your health mission grows)*\n\n## Key Relationships\n\n*(Add causal chains here as you build knowledge)*\n\n## Retrieval Guide\n\n| Question Type | Load These |\n|---------------|------------|\n| General health | health-context, relevant framework docs |\n| Lab interpretation | health-context, lab notes from personal DB |\n| Supplement decisions | health-context, relevant mechanism docs |\n| New research intake | health-context (check against hypotheses), this index |\n\n## Domain Tags\n\n- `mitochondria`, `thyroid`, `sleep`, `inflammation`\n- `supplements`, `nutrition`, `cardiovascular`\n- `testing`, `labs`',
  'health',
  'Master index of all health knowledge. Always loaded before any health dispatch.',
  'global',
  'operator',
  ARRAY['health', 'index', 'core', 'always-load']
) ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- Topic Document: Health Context (persistent specialist state)
-- ============================================================

INSERT INTO topic_documents (slug, title, body, topic, summary, namespace, scope, tags)
VALUES (
  'health-context',
  'Health Context — Persistent Specialist State',
  E'# Health Context — Persistent Specialist State\n\n*Last updated: (initial)*\n*Purpose: Load before every health dispatch for specialist continuity.*\n\n## Working Hypotheses\n\n*(Add hypotheses here as health work progresses. Format: hypothesis, supporting evidence, tests, confidence level)*\n\n## Open Questions\n\n*(Track unresolved questions that need labs, research, or testing)*\n\n## Observed Patterns\n\n*(Document patterns noticed across sessions: what helps, what hurts, correlations)*\n\n## Current Protocol Assessment\n\n| Element | Status | Notes |\n|---------|--------|-------|\n| *(Add current supplements, diet, lifestyle here)* | | |\n\n## Evolving Interpretations\n\n*(Higher-level synthesis that connects hypotheses and patterns into a coherent picture)*',
  'health',
  'Persistent specialist state: working hypotheses, open questions, observed patterns. Updated after each health dispatch.',
  'global',
  'operator',
  ARRAY['health', 'context', 'persistent-state', 'hypotheses', 'core']
) ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- Topic Document: Health Protocols (intake & dispatch)
-- ============================================================

INSERT INTO topic_documents (slug, title, body, topic, summary, namespace, scope, tags)
VALUES (
  'health-knowledge-protocols',
  'Health Knowledge System — Intake & Dispatch Protocols',
  E'# Health Knowledge System — Intake & Dispatch Protocols\n\n## Architecture\n\nTwo-layer system:\n- **Layer 1 (Personal DB):** Patient chart — labs, symptoms, protocol, journal. Things ABOUT the operator.\n- **Layer 2 (Brain topic_documents):** Medical library — curated frameworks, mechanisms, research. Things the operator has LEARNED.\n\nKey documents (always loaded for health work):\n- `health-index` — master table of contents\n- `health-context` — specialist persistent state\n\n---\n\n## Intake Protocol (When operator shares a video/study/article)\n\n### Step 1: Extract\n- Fetch/scrape the content\n- Identify: key claims, mechanisms, cited studies, dosages, protocols\n\n### Step 2: Distill\n- Remove filler, consolidate into assertions\n- Note confidence level (RCT vs podcast vs case study)\n- Preserve provenance (source, date, author credentials)\n\n### Step 3: Position\n- Compare against existing knowledge (search brain for related health docs)\n- Classify: Adopt / Interesting but unverified / Contradicts current protocol\n\n### Step 4: Link\n- Identify relationships to existing documents\n- Flag conflicts with current protocol or working hypotheses\n- Tag with domain tags from Health Index\n\n### Step 5: Save (dual write)\n- **Personal DB (note):** Full annotated research note with personal relevance\n- **Brain (topic_document):** Distilled framework. Opinionated, standalone, searchable.\n- **Update Health Index** — add new document\n- **Update Health Context** — if findings change hypotheses or protocol assessment\n- **Create cross-links** — link new document to related existing docs\n\n### Step 6: Confirm\n- Report to operator what was saved, where, what changed\n\n---\n\n## Dispatch Protocol (When health work is needed)\n\n### Before dispatching health specialist:\n\n1. Load health mission description from personal DB (current state)\n2. Load Health Index (always)\n3. Load Health Context (always)\n4. Multi-query semantic search (3-5 targeted queries)\n5. Follow cross-links one hop from retrieved documents\n6. Load specific personal DB notes if Index retrieval guide points to them\n\n### After specialist delivers:\n\n1. Review output quality\n2. Save new knowledge per Intake Protocol\n3. Update Health Context with new insights\n4. Update Health Index if new documents created\n5. Propose crystallization if output is substantial\n\n---\n\n## Quality Gates\n\n- Never store raw dumps — always distill first\n- Every topic_document must be independently readable\n- Confidence levels must be explicit\n- Contradictions to current protocol flagged for operator review\n- Cross-links mandatory — no isolated knowledge islands',
  'health',
  'Operating procedures for the health knowledge system: intake (videos/studies/articles) and dispatch (comprehensive specialist context).',
  'global',
  'system',
  ARRAY['health', 'protocol', 'intake', 'dispatch', 'system']
) ON CONFLICT (slug) DO NOTHING;

-- ============================================================
-- Cross-links between health documents
-- ============================================================

INSERT INTO topic_document_links (source_slug, target_slug, link_type)
VALUES
  ('health-index', 'health-context', 'references'),
  ('health-index', 'health-knowledge-protocols', 'references'),
  ('health-knowledge-protocols', 'health-index', 'references'),
  ('health-knowledge-protocols', 'health-context', 'references')
ON CONFLICT DO NOTHING;

-- ============================================================
-- Update starter-packs topic_document to reference this pack
-- ============================================================

UPDATE topic_documents
SET body = body || E'\n\n## Installable Packs\n\nThese packs ship as self-contained seed files in the `packs/` directory.\n\n### Health Knowledge System (`packs/health/`)\nA structured health knowledge management system with:\n- Health Specialist team member\n- Health Index (master table of contents, always loaded before health dispatch)\n- Health Context (persistent specialist state: hypotheses, patterns, open questions)\n- Health Protocols (intake & dispatch procedures)\n- Cross-links between all health documents\n\nInstall: `psql -U brain_user -d brain -f packs/health/seed.sql`'
WHERE slug = 'starter-packs';
