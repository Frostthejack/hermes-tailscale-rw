# Kanban Database Diagnostic Queries

The kanban board's `board.json` only contains metadata (name, slug, icon). All task data lives in `kanban.db` (SQLite) at:

```
~/.hermes/kanban/boards/<slug>/kanban.db
```

## Schema

Key tables:
- `tasks` — all tasks with columns: `id`, `title`, `body`, `assignee`, `status`, `priority`, `created_at`, `started_at`, `completed_at`, `workspace_path`, `result`, `skills`, etc.
- `task_links` — dependency edges: `parent_id` → `child_id`
- `task_events` — full event log: `task_id`, `kind`, `payload` (JSON), `created_at`
- `task_comments` — human/worker comments on tasks

## Common Diagnostics

### Find all blocked tasks with their block reason

```python
import sqlite3, json
conn = sqlite3.connect('/home/frostthejack/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()

c.execute("""
    SELECT t.id, t.title, t.assignee, t.status,
           e.kind, e.payload, e.created_at
    FROM tasks t
    JOIN task_events e ON e.task_id = t.id
    WHERE t.status = 'blocked'
    AND e.created_at = (
        SELECT MAX(e2.created_at) FROM task_events e2
        WHERE e2.task_id = t.id AND e2.kind IN ('blocked','gave_up','crashed')
    )
""")
for row in c.fetchall():
    print(f"[{row[3]}] {row[1]} ({row[0]}) — event: {row[4]}, payload: {row[5]}")
conn.close()
```

### Map the dependency graph for blocked tasks

```python
# Show parent→child links for all blocked tasks
c.execute("""
    SELECT tl.parent_id, tl.child_id, tp.title as parent_title, tc.title as child_title,
           tp.status as parent_status, tc.status as child_status
    FROM task_links tl
    JOIN tasks tp ON tp.id = tl.parent_id
    JOIN tasks tc ON tc.id = tl.child_id
    WHERE tc.status = 'blocked' OR tp.status = 'blocked'
""")
for row in c.fetchall():
    print(f"  {row[0]}({row[4]}) → {row[1]}({row[5]})")
    print(f"    {row[2]} → {row[3]}")
```

### Full event history for a specific task

```python
c.execute("""
    SELECT kind, payload, created_at
    FROM task_events
    WHERE task_id = ?
    ORDER BY created_at
""", ('t_<id>',))
for row in c.fetchall():
    payload = json.loads(row[1]) if row[1] else {}
    print(f"  [{row[2]}] {row[0]}: {json.dumps(payload, indent=2)}")
```

### Find tasks blocked by protocol violations

```python
c.execute("""
    SELECT t.id, t.title, t.assignee, e.payload
    FROM tasks t
    JOIN task_events e ON e.task_id = t.id
    WHERE e.kind = 'gave_up'
    AND e.payload LIKE '%protocol_violation%'
""")
```

## Event Kinds

| Kind | Meaning |
|---|---|
| `created` | Task created |
| `claimed` | Worker claimed the task |
| `spawned` | Worker process started (payload has `pid`) |
| `claim_extended` | Worker heartbeat extended the claim |
| `completed` | Task completed successfully |
| `blocked` | Worker blocked with a reason |
| `gave_up` | Dispatcher gave up after retries (payload has `error`, `failures`) |
| `crashed` | Worker process crashed |
| `protocol_violation` | Worker exited without calling complete/block |
| `promoted` | Task unblocked and returned to ready |
| `linked` | Dependency link added |
| `claim_rejected` | Claim rejected (e.g., parents not done) |

## Resolution Patterns

**Protocol violation (worker exited rc=0 without completing):**
1. Check if work was actually done (git log, file changes, CI)
2. If done: `hermes kanban unblock <id>` then `hermes kanban complete <id> --summary "..."`
3. If not done: `hermes kanban unblock <id>` to retry, or fix manually
4. Investigate why the worker didn't call `kanban_complete` — check worker logs
5. The KANBAN_GUIDANCE has been updated (2026-05-16) to tell workers to checkpoint early and always call `kanban_complete` or `kanban_block` before session end.

**Bulk reset blocked tasks (protocol violation retry):**
```python
import sqlite3, time
conn = sqlite3.connect('/home/frostthejack/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
blocked_tasks = ['t_xxx', 't_yyy']  # task ids to reset
for task_id in blocked_tasks:
    c.execute("""UPDATE tasks SET status='ready', claim_lock=NULL, claim_expires=NULL,
                 worker_pid=NULL, current_run_id=NULL, consecutive_failures=0,
                 last_failure_error=NULL WHERE id=?""", (task_id,))
    c.execute("""INSERT INTO task_events (task_id, run_id, kind, payload, created_at)
                 VALUES (?, NULL, 'unblocked', ?, ?)""",
              (task_id, '{"reason": "manual unblock"}', int(time.time())))
conn.commit()
conn.close()
```

**Iteration budget exhausted:**
- The task is too complex for a single worker run
- Consider breaking into subtasks, or doing the work manually

**Parents not done:**
- Check `task_links` for the dependency chain
- Complete or unblock parent tasks first

## Cron Job Delivery Target

When a cron job's `deliver: "origin"` doesn't land in the expected Discord thread,
set the delivery target explicitly:
```
deliver: 'discord:<channel_id>:<thread_id>'
```
Get the thread ID from the Discord thread URL or by asking the user.
