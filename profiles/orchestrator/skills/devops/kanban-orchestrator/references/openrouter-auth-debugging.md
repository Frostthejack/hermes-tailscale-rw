# OpenRouter Credential Resolution — Debugging Guide

## Symptoms That Look Like Code Bugs

- HTTP 401 "Missing Authentication header" from OpenRouter
- Workers crash immediately (rc=0, no kanban_complete)
- config.yaml has correct key but workers fail
- Key works with curl but fails through Hermes

## Credential Resolution Order

resolve_provider_client("openrouter") reads from:
1. Credential pool (auth.json) if pool_present
2. os.environ["OPENROUTER_API_KEY"] — PRIMARY source, set by load_hermes_dotenv()
3. config.yaml api_key is NOT used by the API client

## Key Insight

config.yaml api_key is for display/auxiliary only. The actual API client reads from the env var. Always check the .env file, not config.yaml, when debugging auth failures.

## Debugging Steps

1. Test key: curl -s "https://openrouter.ai/api/v1/auth/key" -H "Bearer KEY"
   - Fails = key invalid/rate-limited, not a code bug
   - Works = check credential resolution path
2. Check auth.json credential pool for stale Bitwarden entries
3. Check for redact_secrets masking in gateway status

## Rate-Limit Cascade Pattern

Crash loops (1000+ failed auth requests) trigger OpenRouter abuse protection. ALL requests return 401 even from direct curl. Recovery: wait for cooldown or generate new key. Always test the key directly before debugging code.