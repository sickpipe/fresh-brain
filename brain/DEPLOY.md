# brain — Local Deployment

## Running

The brain runs locally on this Mac. No external hosting.

```
cd ~/FreshBrain/brain
source venv/bin/activate
python mcp_server.py          # 127.0.0.1:5050
```

## Environment

`brain/.env` (chmod 600, gitignored):
- `DATABASE_BRAIN_APP_URL` — local Postgres (`postgresql://spock@127.0.0.1:5432/brain`)
- `BRAIN_MCP_TOKEN` — bearer token for `/mcp`
- `BRAIN_MCP_PORT` — port override (default 5050)

## Smoke test

```
curl -sS http://127.0.0.1:5050/health
```

## REINDEX after bulk inserts

ivfflat indexes built on empty tables return 0 rows for cosine-ORDER-BY until rebuilt:

```
psql brain -c "SELECT indexname FROM pg_indexes WHERE schemaname='public' AND indexname LIKE '%embedding%';"
# Then for each:
psql brain -c "REINDEX INDEX <index_name>;"
```

## Prior DO deployment (decommissioned)

A previous deployment ran on the Evenrail droplet (`165.22.32.250`) as `brain-mcp.service` behind nginx at `brain.evenrail.com`. That service may still be running but is no longer the source of truth. The local Postgres DB is authoritative.
