# Credential Pool Debugging for New Profiles

## Symptom
New profile workers fail with `HTTP 401: Missing Authentication header` on first API call, while existing profiles work fine with the same key.

## Root Cause
The credential pool (`auth.json`) seeds from `os.environ` at worker spawn time. New profiles inherit the gateway's environment. If `OPENROUTER_API_KEY` is missing from the gateway's env, the pool captures an empty/stale value and marks it `exhausted` after the first 401. This exhausted entry persists across worker restarts even after clearing auth.json, because the pool re-seeds from the stale env on next spawn.

## Diagnosis Steps

```bash
# 1. Check what key the worker actually sent (request dump shows exact bytes)
python3 -c "
import json, glob
d = json.load(open(sorted(glob.glob('~/.hermes/profiles/<profile>/sessions/request_dump_*.json'))[-1]))
key = d['request']['headers']['Authorization'].replace('Bearer ', '')
print(f'Key length: {len(key)} — {\"OK\" if len(key) > 20 else \"MASKED/BROKEN\"}')
"

# 2. Check the profile auth.json for exhausted entries
python3 -c "
import json
auth = json.load(open('~/.hermes/profiles/<profile>/auth.json'))
for e in auth.get('credential_pool', {}).get('openrouter', []):
    print(f'  id={e[\"id\"]}, source={e[\"source\"]}, status={e.get(\"last_status\")}')
"

# 3. Check gateway actual environment
systemctl --user show-environment | grep OPENROUTER
```

## Fix

### Option A: Fix the default .env (best — fixes all profiles)
```bash
# 1. Write the real key to the default .env
echo "OPENROUTER_API_KEY=*** >> ~/.hermes/.env

# 2. Full gateway restart
hermes gateway stop; sleep 2; hermes gateway start
```

### Option B: Clear the profile credential pool
```bash
python3 -c "
import json, hashlib
p = '~/.hermes/profiles/<profile>/auth.json'
auth = json.load(open(p))
# Clear exhausted entries
auth['credential_pool']['openrouter'] = [
    e for e in auth['credential_pool'].get('openrouter', [])
    if e.get('last_status') != 'exhausted'
]
json.dump(auth, open(p, 'w'), indent=2)
print('Done')
"
```

## Key Fingerprint Reference

| Fingerprint (first 16) | Meaning |
|------------------------|---------|
| `sha256:e551bd2e604ef5d4` | Real OpenRouter key (73 chars) |
| `sha256:aa878ec238d40b23` | Masked/broken key (15 chars) |

## Prevention

1. Set `OPENROUTER_API_KEY` in both `~/.hermes/.env` AND `~/.hermes/profiles/<profile>/.env`
2. Create the profile `.env` BEFORE the first dispatch
3. Use `echo "KEY=val" > file` via terminal — the write_file tool may redact secrets
4. Verify with: `systemctl --user show-environment | grep OPENROUTER`
