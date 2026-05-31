# Credential Pool Exhaustion Pattern — agent-lane

> **⚠️ RULING (2026-05-27):** The credential pool exhaustion theory was investigated and **ruled out** as the root cause. The actual cause was the key being **revoked by OpenRouter** after 2754+ failed attempts. The credential pool entries were a symptom, not the cause. See `auth-debug.md` for the correct diagnostic flow. That file supersedes this one for auth debugging.

## Original Problem (Historical Reference)
The kanban dispatcher won't spawn workers for a task even though:
- Task is in `ready` status
- Task has a valid `assignee` (profile exists)
- `claim_lock IS NULL`
- `has_spawnable_ready()` returns `True`

Diagnosis shows `skipped_nonspawnable` in the dispatch result.

## Root Cause
The gateway's credential pool system in `~/.hermes/profiles/<profile>/auth.json` has marked the credential as `exhausted`:

```json
{
  "credential_pool": {
    "openrouter": [{
      "id": "8fc21a",
      "access_token": "***",
      "last_status": "exhausted",
      "last_error_code": 401,
      "last_error_message": "Missing Authentication header",
      "source": "env:OPENROUTER_API_KEY"
    }]
  }
}
```

The dispatcher checks the credential pool before spawning. If the credential is `exhausted`, it skips the profile entirely.

## How It Happens
1. Worker spawns and tries to make an API call
2. API call fails with 401 (bad/masked key, expired token, etc.)
3. Gateway marks the credential pool entry as `exhausted`
4. Dispatcher sees `exhausted` → skips spawning
5. Gateway re-creates the credential pool entry from `~/.hermes/.env` on restart, but if `.env` still has `***`, the new entry is also bad

## Credential Resolution Chain
1. `~/.hermes/.env` `OPENROUTER_API_KEY` — **highest precedence, read by gateway at startup**
2. `os.environ` `OPENROUTER_API_KEY` — fallback (NOT .bashrc, NOT profile .env)
3. Profile `config.yaml` `providers.openrouter.api_key` — NOT used by credential pool
4. Profile `.env` — NOT read by credential pool

**Key insight**: The credential pool ONLY reads from `~/.hermes/.env`. Profile-specific config is ignored for credential resolution.

## Fix Procedure
1. User must manually edit `~/.hermes/.env` (sandbox-protected, agent cannot write)
2. Replace `OPENROUTER_API_KEY=***` with the full 73-char key
3. Restart gateway: `hermes gateway restart`
4. Next dispatch tick will spawn workers with the correct credential

## Verification
```bash
# Test the key directly
python3 -c "
import urllib.request, json
key = 'sk-or-v1-...'
req = urllib.request.Request('https://openrouter.ai/api/v1/auth/key',
    headers={'Authorization': f'Bearer {key}'})
resp = urllib.request.urlopen(req, timeout=10)
print(json.loads(resp.read())['data']['label'])
"

# Check credential pool status
python3 -c "
import json
data = json.load(open('/home/frostthejack/.hermes/profiles/claude-lane/auth.json'))
for provider, creds in data.get('credential_pool', {}).items():
    for c in creds:
        print(f'{provider}: status={c.get(\"last_status\")}, token={c.get(\"access_token\", \"N/A\")[:10]}...')
"

# Reset exhausted credential (temporary — gateway may re-create)
python3 -c "
import json, time
path = '/home/frostthejack/.hermes/profiles/claude-lane/auth.json'
data = json.load(open(path))
data['credential_pool'] = {}
open(path, 'w').write(json.dumps(data, indent=2))
print('Cleared credential pool')
"
```

## Worker Log Evidence
```
⚠️  API call failed (attempt 1/3): AuthenticationError [HTTP 401]
   🔌 Provider: openrouter  Model: openrouter/owl-alpha
   📝 Error: HTTP 401: Missing Authentication header
❌ Non-retryable error (HTTP 401). Aborting.
```

Request dump shows: `"Authorization": "Bearer sk-or-v1-...2138"` (truncated/masked)

## Dispatcher Tick Evidence
```json
{
  "spawned": [],
  "skipped_nonspawnable": ["t_52d51c80"]
}
```

This means the dispatcher saw the task but couldn't spawn because the profile's credential is exhausted.

## Prevention
- Monitor worker logs after the first dispatch
- If workers fail with 401, immediately check and fix the credential pool
- Don't let the dispatcher retry exhausted credentials — it will just waste ticks
