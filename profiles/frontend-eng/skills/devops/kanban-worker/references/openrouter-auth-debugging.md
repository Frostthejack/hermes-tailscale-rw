# OpenRouter Auth Debugging

## "Missing Authentication header" — Two Root Causes

### Cause 1: Provider Rate-Limit / Abuse Block (MOST COMMON)

Symptoms: Key status endpoint `/api/v1/auth/key` ALSO returns 401. Direct `curl` with same key returns 401. All models fail. Key was working earlier then suddenly stopped.

Root cause: OpenRouter's abuse/rate protection temporarily blocked the key, usually after a worker crash loop generates 1000+ failed auth attempts in a short period.

Diagnosis:
```bash
curl -s "https://openrouter.ai/api/v1/auth/key" -H "Bearer <key>"
# If 401: key is blocked, NOT a code bug
```

Fix: Wait 15-60 min for cooldown, or regenerate key at https://openrouter.ai/keys.

### Cause 2: Code Not Sending Authorization Header

Symptoms: Key status endpoint works (returns key details), direct `curl` works, only Hermes/OpenAI client requests fail.

Key files to inspect (in order):
1. `hermes_cli/env_loader.py` — `load_hermes_dotenv()`, `_apply_external_secret_sources()`, `_seed_from_env()`
2. `agent/credential_pool.py` — `load_pool()`, `_select_pool_entry()`, `_seed_from_env()` (line 1824)
3. `agent/auxiliary_client.py` — `_try_openrouter()` (line 1492): `or_key = explicit_api_key or os.getenv("OPENROUTER_API_KEY")`
4. `agent/agent_init.py` — `init_agent()` (line 139), `if api_key and base_url:` branch (line 693)
5. `agent/agent_runtime_helpers.py` — `create_openai_client()` (line 1252)

### Credential Resolution Order

1. Profile `.env` loaded by `load_hermes_dotenv()` via `python-dotenv` (respects `HERMES_HOME`)
2. Bitwarden via `_apply_external_secret_sources()` (only if `secrets.bitwarden.enabled: true` in config.yaml)
3. Credential pool (`auth.json`) seeded from .env and Bitwarden during `load_pool()`
4. `resolve_provider_client()` checks: credential pool → `os.getenv("OPENROUTER_API_KEY")` → fails with "not set"

Important: `_seed_from_env()` parses the `.env` file directly (via `load_env()`), NOT from `os.environ`. A Bitwarden pool entry can override the `.env` value.

### Worker-Specific Flow

Worker spawned as `hermes -p <profile>`:
1. `_apply_profile_override()` reads `-p` from argv → sets `HERMES_HOME` to profile dir
2. `load_hermes_dotenv()` loads profile `.env` from `HERMES_HOME`
3. Worker inherits gateway's `os.environ` BUT `load_hermes_dotenv` re-reads profile `.env`

Gotcha: Default profile's `secrets.bitwarden.enabled: true` in `~/.hermes/config.yaml` injects a key via Bitwarden. If the worker inherits the gateway's env (which has `OPENROUTER_API_KEY` from Bitwarden), it may get the wrong key. Check `~/.hermes/auth.json` for stale openrouter pool entries.

### Debug Patch Pattern

When auth fails, add temporary prints at key points, test, then remove:

```python
# In _try_openrouter() after line 1504:
or_key = explicit_api_key or os.getenv("OPENROUTER_API_KEY")
print(f"DEBUG _try_openrouter: explicit={'SET' if explicit_api_key else 'NONE'}, env={'SET' if os.getenv('OPENROUTER_API_KEY') else 'NONE'}, key_len={len(or_key) if or_key else 0}", file=sys.stderr)

# In create_openai_client() in agent_runtime_helpers.py:
client_kwargs = dict(client_kwargs)
_dk = client_kwargs.get("api_key", "")
print(f"DEBUG create_openai_client: api_key_len={len(_dk)}", file=sys.stderr)
```

### Quick Fix Checklist

1. `curl -s "https://openrouter.ai/api/v1/auth/key" -H "Bearer <key>"` — if 401, key blocked (wait/regenerate)
2. If key works in curl: check `~/.hermes/auth.json` for stale openrouter pool entries from Bitwarden
3. Check profile `.env` exists and has `OPENROUTER_API_KEY`
4. Check profile `config.yaml` doesn't have `secrets.bitwarden.enabled: true` (or has `override_existing: false`)
5. Remove all debug patches after testing
