# Creating New Lane Profiles — Credential Setup

When creating a new agent-lane profile (e.g., `claude_lane`), the profile needs proper
credential setup BEFORE the first kanban dispatch. Without it, workers immediately fail with
HTTP 401 and the credential pool marks the entry as `exhausted`, causing infinite retry loops.

## Required Steps (in order)

### 1. Create the profile
```bash
hermes profile create <profile-name> --clone claude-lane
# OR copy from an existing profile:
cp -r ~/.hermes/profiles/claude-lane ~/.hermes/profiles/<profile-name>
```

### 2. Create the profile `.env` with the API key
```bash
# MUST use terminal echo — write_file tool may redact the key
echo "OPENROUTER_API_KEY=*** > ~/.hermes/profiles/<profile-name>/.env
```

### 3. Set the key in the profile config.yaml
```yaml
# ~/.hermes/profiles/<profile-name>/config.yaml
providers:
  openrouter:
    api_key: sk-or-...2138
```

### 4. Clear any auto-seeded credential pool entries
```bash
python3 -c "
import json
p = '~/.hermes/profiles/<profile-name>/auth.json'
auth = json.load(open(p))
# Remove exhausted entries
auth['credential_pool']['openrouter'] = [
    e for e in auth['credential_pool'].get('openrouter', [])
    if e.get('last_status') != 'exhausted'
]
json.dump(auth, open(p, 'w'), indent=2)
print('Cleaned auth.json')
"
```

### 5. Verify the gateway has the key in its environment
```bash
systemctl --user show-environment | grep OPENROUTER
# Should show: OPENROUTER_API_KEY=sk-or-v1-858...
# If not: hermes gateway stop; sleep 2; hermes gateway start
```

### 6. Verify with `hermes auth list`
The openrouter entry should show:
- `source: env:OPENROUTER_API_KEY`
- No `last_status` (not `exhausted`)
- Fingerprint starting with `sha256:e551bd2e604ef5d4`

### 7. Create profile.yaml with a description
```yaml
# ~/.hermes/profiles/<profile-name>/profile.yaml
description: "Agent lane profile — delegates coding to Claude Code CLI. Spawns claude -p in isolated git worktrees."
```

## Common Pitfalls

1. **Using `write_file` tool for `.env`** — it may redact the key. Always use `echo "KEY=val" > file` via terminal.
2. **Setting key only in profile `.env`** — the gateway process doesn't load profile `.envs`. Workers inherit the gateway's env. The key must ALSO be in `~/.hermes/.env`.
3. **Not clearing auth.json** — if a previous dispatch seeded an exhausted entry, it persists across restarts.
4. **Model name mismatch** — use `@preset/coder` (not `@preset/code`). Wrong model gives HTTP 404 "Preset not found".
5. **Bitwarden override** — new profiles cloned from `claude-lane` inherit `secrets.bitwarden.override_existing: true`. Set to `false` if not using Bitwarden.
