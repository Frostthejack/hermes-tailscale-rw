# Hindsight + Windows Setup

## Architecture

- **Hindsight API** (`hindsight-api`) runs on Windows (Python-based, installed via `pip`)
- **PostgreSQL** runs on Windows (native) at port 5433 with pgvector extension
- The API connects to PostgreSQL via the `HINDSIGHT_API_DATABASE_URL` environment variable
- Hindsight API listens on `0.0.0.0:8888` by default
- WSL reaches the API at `127.0.0.1:8888` (auto-forwarded in WSL2)

## Starting / Restarting Hindsight API on Windows

### Required Environment Variables

```powershell
$env:HINDSIGHT_API_LLM_PROVIDER="openrouter"
$env:HINDSIGHT_API_DATABASE_URL="postgresql://frostthejack:Thefrosty1@127.0.0.1:5432/hindsight"
$env:HINDSIGHT_API_LLM_API_KEY="sk-or-v1-..."
$env:HINDSIGHT_API_LLM_MODEL="@preset/encephalon"
hindsight-api
```

### Stopping the Server

```powershell
# Find the process
Get-NetTCPConnection -LocalPort 8888 -State Listen | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

### Health Check

```powershell
# Version check
(Invoke-RestMethod -Uri "http://localhost:8888/version").api_version

# time_field acceptance check (should return "created_at", no X-Ignored-Params warning)
(Invoke-RestMethod -Uri "http://localhost:8888/v1/default/banks/hermes/stats/memories-timeseries?period=7d&time_field=created_at").time_field
```

## Key Pitfalls

### Upgrade Must Be Done on Windows, Not WSL

The Hindsight API server runs on Windows. Upgrading via `pipx` in WSL **does not** upgrade the Windows installation. You must run the upgrade from Windows PowerShell:

```powershell
pip install --upgrade hindsight-api
```

### Version Matching with Control Plane

The Hindsight API server and Control Plane **must be on the same major.minor version**. See `references/hindsight-version-matching.md` for details.

### Dependency Conflicts After Upgrade

Upgrading `hindsight-api` may upgrade `opentelemetry-*` packages that conflict with `logfire`. If the server won't start:

```powershell
pip install logfire --upgrade
```

## Key Connection Details

| Component | Address | Notes |
|-----------|---------|-------|
| Hindsight API | `127.0.0.1:8888` (Windows) / `127.0.0.1:8888` (WSL, auto-forwarded) | Process must be running on Windows |
| PostgreSQL 18.4 | `127.0.0.1:5433` | Windows native, pgvector installed |
| Database | `hindsight` | User: `frostthejack`, Password: `Thefrosty1` |
| Control Plane | `localhost:9999` | `npx @vectorize-io/hindsight-control-plane --api-url http://localhost:8888` |

## Session History

- **2026-05-15**: Hindsight data migrated from WSL to Windows PG 18.4.
- **2026-05-24**: Upgraded `hindsight-api` from v0.5.6 to v0.6.2 via `pip install --upgrade hindsight-api` on Windows. Resolved `time_field` unknown parameter warnings.
