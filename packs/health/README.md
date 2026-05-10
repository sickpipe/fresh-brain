# Health Knowledge System — Starter Pack

Adds a structured health knowledge management system to your Fresh Brain instance.

## What's Included

- **Health Specialist** team member (capabilities: health, wellness, lab-interpretation, nutrition, supplements, functional-medicine, metabolic-health)
- **Health Index** — master table of contents for all health knowledge (always loaded before health work)
- **Health Context** — persistent specialist state document (working hypotheses, open questions, patterns)
- **Health Protocols** — intake and dispatch procedures for the knowledge system

## Architecture

Two-layer system:
- **Layer 1 (Personal DB):** Patient chart — labs, symptoms, protocol, journal
- **Layer 2 (Brain topic_documents):** Medical library — curated frameworks, mechanisms, research

## How to Install

Run the seed file against your brain database:
```bash
psql -U brain_user -d brain -f packs/health/seed.sql
```

## How It Works

**Intake (when you share a video/study):** Extract > Distill > Position > Link > Dual-save (personal note + brain topic_document) > Update Index + Context

**Dispatch (when health work is needed):** Load Health Index + Context + Mission description > Multi-query search > Brief specialist with full context

The knowledge compounds — every session that touches health makes the specialist smarter for next time.
