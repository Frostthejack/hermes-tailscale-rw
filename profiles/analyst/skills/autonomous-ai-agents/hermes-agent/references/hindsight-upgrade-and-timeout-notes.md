# Hindsight API: Upgrade, Version Mismatch, and Reflect Timeout Notes

## WSL vs Windows pip Installations Are Separate

The Hindsight API server (`hindsight-api`) was installed via **`pip` on Windows**:
```
C:\Users\luned\AppData\Local\Programs\Python\Python312\Lib\site-packages\hindsight_api\
```

There is also a **pipx venv in WSL** at:
```
/home/frostthejack/.local/share/pipx/venvs/hindsight-api/
```

**These are completely different installations.** Upgrading one does NOT affect the other.

| Action | WSL pipx | Windows pip |
|--------|----------|-------------|
| Upgrade command | `pipx upgrade hindsight-api` | `pip install --upgrade hindsight-api` |
| Serves requests from | WSL | Windows |

**If the server runs on Windows, upgrade via Windows pip, NOT WSL pipx.**

## Version Mismatch: Control Plane vs Server

The Control Plane (npm) and API server (pip) must be on matching major.minor versions.

- **v0.6.0** (2026-05-05): Added `time_field` query param to `/stats/memories-timeseries`
- **v0.5.6** (2026-04-28): Does NOT support `time_field`

If Control Plane v0.6.x sends `time_field` to server v0.5.6:
```
Unknown parameters ignored: [time_field] for GET /v1/default/banks/{bank_id}/stats/memories-timeseries
```

**Fix**: Upgrade both, then restart:
```powershell
# Windows PowerShell
npm install -g @vectorize-io/hindsight-control-plane@latest
pip install --upgrade hindsight-api
```

## Startup Command (Windows)

```powershell
$env:HINDSIGHT_API_LLM_PROVIDER="openrouter"
$env:HINDSIGHT_API_DATABASE_URL="postgresql://frostthejack:Thefrosty1@127.0.0.1:5432/hindsight"
$env:HINDSIGHT_API_LLM_API_KEY="sk-or-v1-..."
$env:HINDSIGHT_API_LLM_MODEL="@preset/encephalon"
hindsight-api
```

## Reflect Timeout and Empty LLM Responses

### Error Pattern

```
Provider returned empty message content (openrouter/@preset/encephalon, scope=reflect, finish_reason=length)
...
TimeoutError: Reflect operation timed out after 300 seconds.
```

`refresh_mental_model` calls `reflect_async` which runs an agentic loop. The LLM returns empty content (`finish_reason=length`) when context is too large. Retries then exhaust the wall timeout.

### Configurable Timeouts

| Env Var | Default | Effect |
|---------|---------|--------|
| `HINDSIGHT_API_REFLECT_WALL_TIMEOUT` | `300` | Total wall-clock timeout for reflect (seconds) |
| `HINDSIGHT_API_REFLECT_MAX_ITERATIONS` | `10` | Max agentic loop iterations |
| `HINDSIGHT_API_REFLECT_MAX_CONTEXT_TOKENS` | `128000` | Max context tokens |
| `HINDSIGHT_API_REFLECT_LLM_TIMEOUT` | `120` | Per-call LLM timeout (seconds) |

### Mitigation for Large Banks

For banks with 9000+ nodes and 380K+ links:
- Increase wall timeout: `$env:HINDSIGHT_API_REFLECT_WALL_TIMEOUT=600`
- Reduce iterations: `$env:HINDSIGHT_API_REFLECT_MAX_ITERATIONS=5`
- Transient failures auto-retry on next worker poll cycle (~5 hours)

## Dependency Conflicts After Upgrade

Upgrading `hindsight-api` via pip may upgrade `opentelemetry-*` to 1.42.x, conflicting with `logfire` (expects 1.39.x). Fix:
```powershell
pip install logfire --upgrade
```
