# Hindsight API Server — Version Matching & Upgrade

## Critical Rule: Control Plane and Server MUST Match

The Hindsight Control Plane (`@vectorize-io/hindsight-control-plane`, served via `npx`) and the Hindsight API server (`hindsight-api`, served via `hindsight-api` CLI) **must be on the same major.minor version**. A mismatch causes:

- **Control Plane newer than server**: Server logs `Unknown parameters ignored: [time_field] for GET /v1/default/banks/{bank_id}/stats/memories-timeseries` every ~5 seconds (polling interval). The server's unknown-params middleware rejects parameters it doesn't recognize.
- **Server newer than Control Plane**: Control Plane UI may reference API features that exist but the client doesn't send, causing silent feature gaps.

### Version History (relevant parameters)

| Version | `memories-timeseries` params | Notes |
|---------|------------------------------|-------|
| 0.5.6 | `period` only | `time_field` not recognized |
| 0.6.0+ | `period`, `time_field` (default: `created_at`) | `time_field` toggle added for bucketing by `mentioned_at` / `occurred_start` |

### How to Check Versions

```powershell
# Server version (Windows)
(Invoke-RestMethod -Uri "http://localhost:8888/version").api_version

# Control Plane version — check the npx package
npx @vectorize-io/hindsight-control-plane --version
```

### How to Upgrade

**The server runs on Windows, so upgrade from Windows — NOT from WSL.**

```powershell
# Windows PowerShell (NOT WSL)
pip install --upgrade hindsight-api
```

**Do NOT use pipx for this.** The `hindsight-api` package is installed globally on Windows Python, not in a pipx venv. Upgrading via pipx in WSL only upgrades the WSL copy but leaves the Windows server binary unchanged.

After upgrading, restart the server:

```powershell
# Stop the old process
Get-NetTCPConnection -LocalPort 8888 -State Listen | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }

# Start the new version (with your usual env vars)
$env:HINDSIGHT_API_LLM_PROVIDER="openrouter"
$env:HINDSIGHT_API_DATABASE_URL="postgresql://frostthejack:Thefrosty1@127.0.0.1:5432/hindsight"
$env:HINDSIGHT_API_LLM_API_KEY="sk-or-v1-..."
$env:HINDSIGHT_API_LLM_MODEL="@preset/encephalon"
hindsight-api
```

### Dependency Conflict Warning

Upgrading `hindsight-api` may also upgrade `opentelemetry-*` packages (to 1.42.x), which can conflict with `logfire` (expects 1.39.x). If the server won't start after upgrade:

```powershell
pip install logfire --upgrade
```

Then restart. The server should start cleanly after this.

### Verification After Upgrade

```powershell
# Check version
(Invoke-RestMethod -Uri "http://localhost:8888/version").api_version
# Should return "0.6.2" (or whatever the target version is)

# Check time_field is accepted
(Invoke-RestMethod -Uri "http://localhost:8888/v1/default/banks/hermes/stats/memories-timeseries?period=7d&time_field=created_at").time_field
# Should return "created_at"
```

### Known Transient Error on v0.5.6

```
TypeError: '<' not supported between instances of 'NoneType' and 'asyncpg.pgproto.pgproto.UUID'
```

This occurred in `entity_resolver.py:815` (`link_units_to_entities_batch_impl`) when a `None` value appeared in `unit_entity_pairs` during sorting. It's a v0.5.6 bug — the task auto-retries and usually succeeds on the second attempt. Fixed in v0.6.x. No user action needed beyond upgrading.
