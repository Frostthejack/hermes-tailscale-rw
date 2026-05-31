# Board Health Watcher — Cron Prompt Template

Use this template when creating an Active Board Watcher cron job for a project.

## Cron Configuration

```
name: <Project> Active Board Watcher
schedule: every 300m
repeat: forever
deliver: discord:<channel_id>:<thread_id>
enabled_toolsets: ["terminal", "file"]
```

## Prompt Template

```
You are the <Project> Active Board Watcher. Check the board health, Vercel deployment logs, and Supabase project health. Fix issues and create kanban tasks for any problems found.

## Step 1: Check Board Status
Run: hermes kanban --board <slug> list

Look for:
- Blocked tasks — any task with status=blocked
- Stuck running tasks — tasks running for a long time without progress
- Phantom completions — tasks marked "done" but with no actual implementation
- Tasks with consecutive_failures
- Tasks with wrong workspace (scratch instead of dir)

## Step 2: Check Vercel Deployment Health

Get Vercel token:
VERCEL_TOKEN=$(python3 -c "import json; d=json.load(open('/home/frostthejack/.vercel/auth.json')); print(d['token'])")

List deployments via API (write Python script to /tmp/ to avoid pipe security blocks):
python3 /tmp/vercel_deployments.py

Check deployment events for errors:
python3 /tmp/vercel_logs.py

Look for: runtime errors (500-504), build failures, timeouts, env var issues, DB connection errors

## Step 3: Check Supabase Project Health

Option A — App health endpoint (preferred):
curl -s "https://<project>.vercel.app/api/health/supabase" | python3 -m json.tool

Option B — Fetch service role key from Vercel API, then use Supabase Management API

Option C — Public endpoints (no auth):
curl -s -o /dev/null -w "%{http_code}" "https://<ref>.supabase.co/rest/v1/"
curl -s "https://<ref>.supabase.co/auth/v1/health"

Check Vercel logs for Supabase errors: P1001, P1002, P1003, ECONNREFUSED, auth failures

## Step 4: Check Worker Health
ls ~/.hermes/kanban/boards/<slug>/logs/
sqlite3 ~/.hermes/kanban/boards/<slug>/kanban.db "SELECT id, title, status, consecutive_failures, last_failure_error FROM tasks WHERE status IN ('blocked', 'running') AND consecutive_failures > 0;"

## Step 5: Fix Issues
- Blocked tasks with dead workers: reset to ready, clear crash counters
- Stuck running tasks: reclaim and reset
- Phantom completions: verify files, reset if stubs
- Wrong workspace: update to dir: with project path

## Step 6: Create Kanban Tasks for Discovered Issues
- Vercel/Supabase infra errors → ops
- API runtime errors → backend-eng
- Build failures → frontend-eng or backend-eng

## Step 7: Verify Build Health
cd /path/to/project
git status --short
git log --oneline -5
npx tsc --noEmit 2>&1 | grep "^src/" | head -20

## Step 8: Report
Summary of: board health, Vercel status, Supabase status, tasks created, board state
If nothing needs attention, output "[SILENT]".
```

## Vercel API Python Scripts

### /tmp/vercel_deployments.py
```python
import json, subprocess
token = json.load(open('/home/frostthejack/.vercel/auth.json'))['token']
project_id = 'prj_<project-id>'
result = subprocess.run(
    ['curl', '-s', f'https://api.vercel.com/v6/deployments?projectId={project_id}&limit=10',
     '-H', f'Authorization: Bearer {token}'],
    capture_output=True, text=True
)
data = json.loads(result.stdout)
for d in data.get('deployments', [])[:10]:
    msg = d.get('meta',{}).get('githubCommitMessage','')[:60].replace('\n',' ')
    print(f"{d['uid'][:12]} | {d['state']:10} | {d['created']} | {msg}")
```

### /tmp/vercel_logs.py
```python
import json, subprocess
token = json.load(open('/home/frostthejack/.vercel/auth.json'))['token']
project_id = 'prj_<project-id>'
result = subprocess.run(
    ['curl', '-s', f'https://api.vercel.com/v6/deployments?projectId={project_id}&limit=1',
     '-H', f'Authorization: Bearer {token}'],
    capture_output=True, text=True
)
data = json.loads(result.stdout)
dep = data['deployments'][0]
dep_id = dep['uid']
print(f"Latest: {dep_id} | State: {dep['state']}")
result2 = subprocess.run(
    ['curl', '-s', f'https://api.vercel.com/v13/deployments/{dep_id}/events?limit=200',
     '-H', f'Authorization: Bearer {token}'],
    capture_output=True, text=True
)
events = json.loads(result2.stdout)
for event in events:
    payload = event.get('payload', {})
    text = json.dumps(payload).lower()
    if any(kw in text for kw in ['error', 'fatal', 'panic', 'crash', 'timeout', '500', '502', '503', '504']):
        print(f"  [{event.get('type','')}] {json.dumps(payload)[:300]}")
```

## Common Supabase Error Patterns in Vercel Logs

| Error | Meaning |
|-------|---------|
| P1001 | Can't reach database server |
| P1002 | Database timeout |
| P1003 | Database connection limit |
| ECONNREFUSED | Connection refused |
| invalid_grant | OAuth token expired/invalid |
| token_expired | Session token expired |
| user_not_found | Auth user doesn't exist |
