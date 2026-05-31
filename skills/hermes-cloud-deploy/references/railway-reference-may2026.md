# Railway Platform Reference (Updated May 2026)

## Healthchecks

- Railway queries your healthcheck endpoint until HTTP 200, then switches traffic.
- **Healthcheck hostname**: `healthcheck.railway.app` (not your app's domain). If your app does hostname filtering, add this to allowed hosts.
- **Default timeout**: 300 seconds (5 min). Override with `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` env var.
- Railway injects a `PORT` env var — healthchecks go to this port.
- After healthcheck passes, Railway does **NOT** continuously monitor. For uptime monitoring, use Uptime Kuma template.
- **Volume services**: get brief downtime on redeploy (Railway can't do zero-downtime with attached volumes).
- Configure in dashboard: Service → Settings → Healthcheck path.

## Volumes

| Plan | Size | Max Volumes |
|------|------|-------------|
| Free | 0.5GB | 1 |
| Trial | 3GB | 3 |
| Hobby | 5GB | 10 |
| Pro | 50GB | 20+ (self-serve up to 1TB) |

- **One volume per service**. No replicas with volumes.
- Live resize on Pro (online, no downtime). Down-size NOT supported.
- Non-root containers need `RAILWAY_RUN_UID=0` for volume access.
- ~2-3% overhead for filesystem metadata.
- `railway volume browse` and `railway volume files` for CLI management.
- Deleted volumes are queued for 48h then permanently removed.

## PostgreSQL (Managed Plugin)

- Auto-injected env vars: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, `DATABASE_URL`
- Most libraries auto-detect `DATABASE_URL`.
- External TCP Proxy enabled by default (billed for egress).
- Config tuning via `ALTER SYSTEM SET ...` + `SELECT pg_reload_conf()` + restart deployment.
- `RAILWAY_SHM_SIZE_BYTES` to increase shared memory (default 64MB).
- Extensions: pgvector available (for Hindsight embeddings). PostGIS, TimescaleDB in template marketplace.
- Native backups feature available.

## Railway Agent (AI)

- Built into Railway dashboard. Chat-based AI assistant.
- Can: create services, set variables, diagnose deployments, read logs, auto-open PRs with fixes.
- **Pricing**: Anthropic per-token rates, no markup.
- Useful command: ask it "why did my deployment fail?" for auto-diagnosis.

## Deployment Debugging

```bash
# Build logs:
railway service logs --service <name> --build --latest

# Runtime logs:
railway service logs --service <name> --latest

# Detect failed new deployment (kept old one active):
railway service list --json
# Compare deploymentId vs latestDeployment.id

# Shell into running container:
railway run /bin/bash

# Trigger redeploy:
railway service redeploy --service <name> --yes
```

## CLI Quirks (MSYS/Windows)

- `railway up` hangs in MSYS (interactive selector). Use `railway service redeploy --yes` instead.
- `railway run` runs locally with Railway env vars, NOT in the container.
- `railway service redeploy --yes` triggers a new build.
