# Kanban Orchestrator — Board Diagnostics & Failure Patterns

## Board Health Quick Assessment

When asked to "review the current state of the kanban board":

1. Run `hermes kanban --board <slug> list` to see all tasks
2. Count statuses: done / running / blocked / ready / todo / archived
3. **Focus on blocked tasks first** — investigate root causes
4. Check if running tasks are making_progress or stuck (look at run counts)
5. **Don't assume rate limits** — always verify API key status first

## Investigating Blocked Tasks

### Step 1: Check task details
```bash
hermes kanban --board <slug> show <task_id>
```
Note: `consecutive_failures`, `last_failure_error`, `max_retries`

### Step 2: Check recent events
Look for patterns in the task event log:
- `protocol_violation` → worker exited cleanly without `kanban_complete`/`kanban_block`
- `crashed` → worker process died (OOM, segfault, timeout)
- `timed_out` → exceeded `max_runtime_seconds`
- `reclaimed` → manual or dispatcher reclaim

### Step 3: Query the database for patterns
```python
import sqlite3
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()

# Find all blocked tasks with their error
c.execute("SELECT id, title, consecutive_failures, last_failure_error FROM tasks WHERE status='blocked'")
for row in c.fetchall():
    print(row)

# Count failure types
c.execute("SELECT last_failure_error, COUNT(*) FROM tasks WHERE status='blocked' GROUP BY last_failure_error")
for row in c.fetchall():
    print(row)
```

### Step 4: Read the API key status
Check OpenRouter rate limits:
```python
import urllib.request, json
# Read API key from env
req = urllib.request.Request('https://openrouter.ai/api/v1/auth/key',
    headers={'Authorization': 'Bearer <key>'})
with urllib.request.urlopen(req, rai10) as resp:
    data = json.loads(resp.read().decode())
    d = data['data']
    print(f"is_free_tier: {d['is_free_tier']}")
    print(f"limit: {d['limit']} ({d['limit_reset']})")
    print(f"remaining: {d['limit_remaining']}")
    print(f"usage: {d['usage']}")
```

**Common mistake:** Assuming paid accounts (`is_free_tier: false`) have no limits. They still have weekly dollar limits that can be exhausted.

## Protocol Violation Pattern

**Symptom:** Task has 10,000+ runs all showing `protocol_violation` or `pid not alive`

**Root cause:** `handle_max_iterations()` API call fails (rate limit, timeout, etc.) → exception propagates past `kanban_block` → worker exits without calling lifecycle tools

**Fix:** Already applied to `conversation_loop.py` — wrap `_handle_max_iterations()` in try/except

## When to Scrap and Recreate Tasks

Consider scrapping blocked tasks when:
1. The task has been blocked for >24 hours with no progress
2. The blocked reason is stale (API that was down is now up)
3. The task body/workspace config needs to change
4. The failed task is poisoning the profile's backoff state (other tasks for same profile won't spawn)

**Scrap pattern:**
1. Archive old blocked tasks: `hermes kanban --board <slug> archive <id>`
2. Create new tasks with correct workspace/assignee/retry settings
3. Route new tasks through the board properly

## Worker Spawn Verification

After creating code tasks and dispatching:
1. Verify the task has `workspace_kind='dir'` pointing to the canonical project path
2. Verify the task has a reasonable `max_runtime_seconds` (or 0 for unlimited)
3. Verify the task body includes `VERIFICATION:` criteria
4. **After first run:** check if the output looks reasonable; 10,000+ runs on one task = something is fundamentally wrong
