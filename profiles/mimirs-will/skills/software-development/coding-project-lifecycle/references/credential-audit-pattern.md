# Credential Audit Pattern

> How to discover, verify, and document all credentials for a project.

## When to Use

- User asks "what are the credentials for project X?"
- User asks "find the API keys / database URL / auth tokens for project X"
- During Phase 0.3 when setting up project-state.md secrets section
- When onboarding a new agent to an existing project
- When debugging "why doesn't this deploy?" — missing env vars are a common cause

## Step 1: Find All Credential References

Search the codebase for all env var names and credential patterns:

```bash
# Find all process.env / env() / os.environ references
grep -rn "process\.env\|os\.environ\|env(" \
  --include="*.ts" --include="*.js" --include="*.tsx" --include="*.jsx" \
  --include="*.py" --include="*.go" --include="*.rs" \
  /path/to/project/ | grep -v node_modules

# Find all .env file references
find /path/to/project/ -name ".env*" -not -path "*/node_modules/*"

# Find hardcoded URLs/domains that identify the service
grep -rn "supabase\.co\|firebase\|amazonaws\|cloudinary\|stripe" \
  --include="*.ts" --include="*.js" --include="*.tsx" \
  /path/to/project/ | grep -v node_modules
```

## Step 2: Read .env Files

```bash
# Read all .env files (they should be gitignored but may exist locally)
cat /path/to/project/.env.local 2>/dev/null
cat /path/to/project/.env 2>/dev/null
cat /path/to/project/.env.production 2>/dev/null
```

> **Warning:** `.env.local` files may contain truncated/redacted values (e.g., `postgres:***` or `eyJhbG...X1-4`). These are NOT the real values.

## Step 3: Check Vercel (if project is deployed there)

```bash
# List env vars (values may be truncated in listing)
cd /path/to/project && vercel env ls

# Pull development env vars to a file
vercel env pull /tmp/env-pull.env
cat /tmp/env-pull.env
```

> **Warning:** Vercel's `env ls` truncates values. `env pull` may also return truncated values if the stored value itself was entered truncated. Use the Vercel API with `?decrypt=true` for encrypted vars.

## Step 4: Check Vercel API for Decrypted Values

```python
import urllib.request, json

with open('/home/frostthejack/.vercel/auth.json') as f:
    token = json.load(f)['token']

project_id = "<vercel-project-id>"  # from .vercel/repo.json
url = f"https://api.vercel.com/v9/projects/{project_id}/env"

req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read())

for env_var in data.get('envs', []):
    key = env_var.get('key', '')
    if any(k in key for k in ['SUPABASE', 'DATABASE', 'API_KEY', 'SECRET', 'TOKEN']):
        env_id = env_var.get('id', '')
        # Get decrypted value
        detail_url = f"https://api.vercel.com/v9/projects/{project_id}/env/{env_id}?decrypt=true"
        req2 = urllib.request.Request(detail_url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req2) as resp2:
            detail = json.loads(resp2.read())
            val = detail.get('value', '')
            print(f"{key}: {val[:20]}... ({len(val)} chars)" if len(val) > 20 else f"{key}: {val}")
```

## Step 5: Verify Credential Completeness

For each credential found, check:

| Check | What to look for |
|-------|-----------------|
| **Truncated values** | `eyJhbG...X1-4` — middle replaced with `...` means the real key was never saved |
| **Placeholder values** | `placeholder`, `your-key-here`, `TODO`, `FIXME` |
| **Empty values** | `KEY=` with nothing after `=` |
| **Wrong environment** | Key exists in Vercel production but not in `.env.local` for local dev |
| **Mismatched names** | Code references `NEXT_PUBLIC_FOO` but env var is named `FOO` |

## Step 6: Document in Vault

Write findings to a document in the vault (e.g., `<vault>/supabase.md` or the project's `project-state.md` Secrets section):

```markdown
## Secrets & Environment Variables

| Variable | Value | Location | Status |
|----------|-------|----------|--------|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://xxx.supabase.co` | `.env.local` + Vercel | ✅ Complete |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `eyJhbG...X1-4` | `.env.local` + Vercel | ⚠️ Truncated — needs real key |
| `SUPABASE_SERVICE_ROLE_KEY` | `placeholder` | `.env.local` | ⚠️ Placeholder — needs real key |
| `DATABASE_URL` | `postgres://user:***@host/db` | Vercel (encrypted) | ⚠️ Password redacted |

### Action Needed
1. Log into Supabase dashboard → Settings → API
2. Copy full anon key and service role key
3. Update `.env.local` and Vercel
```

## Common Patterns

### Supabase Projects
- **URL**: `https://<project-ref>.supabase.co` — find in `src/lib/supabase.ts` or `.env.local`
- **Anon key**: JWT starting with `eyJhbG` — should be ~200+ chars. If truncated, get from Supabase dashboard
- **Service role key**: Also a JWT — should NOT be in client-side code, only server-side
- **Database URL**: `postgresql://postgres.<ref>:<password>@aws-1-<region>.pooler.supabase.com:6543/postgres`

### Vercel-Hosted Projects
- Vercel project ID is in `.vercel/repo.json` as `projects[0].id`
- Vercel org/team ID is in `.vercel/repo.json` as `projects[0].orgId`
- Auth token is in `~/.vercel/auth.json` (WSL) or `%APPDATA%\.vercel\auth.json` (Windows)
- Encrypted env vars need `?decrypt=true` via API — `vercel env pull` does NOT decrypt

### Credentials Never Found in Code
If you can't find a credential value anywhere:
1. It may only exist in the cloud provider's env var config (Vercel, Railway, etc.)
2. It may have been entered truncated/placeholder and never fixed
3. Check with the user — they may need to regenerate the key
