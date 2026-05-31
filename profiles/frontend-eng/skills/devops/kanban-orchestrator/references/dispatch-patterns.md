# Dispatcher Dispatch Patterns — Quick Reference

## Task Status Lifecycle

```
triage → specify → todo → ready → running → done
                                  ↓
                               blocked → ready (after unblock)
```

**Key insight**: The dispatcher only picks up tasks in `ready` status. Tasks created via `hermes kanban create` land in `todo` and must be explicitly moved to `ready`.

## How to Dispatch a Task

1. Create the task (lands in `todo`)
2. Set to `ready`:
   ```python
   import sqlite3
   conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
   c = conn.cursor()
   c.execute("UPDATE tasks SET status='ready' WHERE id=?", (task_id,))
   conn.commit()
   conn.close()
   ```
3. Trigger dispatch:
   ```bash
   hermes kanban --board <slug> dispatch
   ```
4. Verify:
   ```bash
   hermes kanban --board <slug> show <id>
   ```

## Profile Blocked-Task Backoff

When a profile has a blocked task with many consecutive failures, the dispatcher throttles the **entire profile**. New tasks in `ready` won't be spawned.

**Fix**: Archive the old blocked task, then reset the new task to `ready`:
```python
c.execute("UPDATE tasks SET status='archived' WHERE id=?", (blocked_task_id,))
c.execute("UPDATE tasks SET status='ready', claim_lock=NULL, claim_expires=NULL, worker_pid=NULL, current_run_id=NULL, consecutive_failures=0, last_failure_error=NULL, max_retries=3 WHERE id=?", (new_task_id,))
```

## Worker Crash Loop Pattern

When workers crash immediately (within 60s) with `pid not alive`:
1. Check if the task workspace is `scratch` but needs `dir` → fix via SQLite
2. Check if the profile has a blocked task causing backoff → archive it
3. Check worker logs: `~/.hermes/kanban/boards/<slug>/logs/<task_id>.log`
4. Reset `max_retries` to 3 (default `None` = 2) before re-dispatching

## Dispatch Requires Running Gateway

`hermes kanban dispatch` only works when the gateway is running. Check with:
```bash
hermes gateway status
```
If not running: `hermes gateway start`
