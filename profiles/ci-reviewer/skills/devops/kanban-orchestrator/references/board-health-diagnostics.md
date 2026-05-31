# Board Health Diagnosis — Scratch Workspace & Stale Task Patterns

## Pattern: Scratch Workspace Causing Worker Crashes

### Symptom
Multiple tasks blocked with `pid not alive` and `consecutive_failures` at retry limit (usually 2). All tasks were created around the same time and share the same board.

### Diagnosis
Check workspace configuration on blocked tasks:
```python
import sqlite3
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
c.execute("SELECT id, title, assignee, workspace_kind, workspace_path, consecutive_failures, last_failure_error FROM tasks WHERE status='blocked'")
for row in c.fetchall():
    print(f"  {row[0]} ({row[2]}): ws={row[3]} path={row[4]} failures={row[5]} error={row[6]}")
conn.close()
```

**Root cause pattern:** `workspace_kind=scratch` for tasks that involve writing/modifying project source code. Scratch directories are empty tmp dirs — workers have no source code to work with and crash immediately.

### Fix
Update workspace to `dir` pointing to the project directory, reset crash counters, and unblock:
```python
import sqlite3, time
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
now = int(time.time())

blocked_tasks = ['t_xxx', 't_yyy']
project_dir = '/mnt/c/Users/<user>/Documents/Projects/<project>'

for task_id in blocked_tasks:
    c.execute("UPDATE tasks SET workspace_kind='dir', workspace_path=? WHERE id=?", (project_dir, task_id))
    c.execute("""UPDATE tasks SET status='ready', claim_lock=NULL, claim_expires=NULL,
                 worker_pid=NULL, current_run_id=NULL, consecutive_failures=0,
                 last_failure_error=NULL, max_retries=3 WHERE id=?""", (task_id,))
    c.execute("""INSERT INTO task_events (task_id, run_id, kind, payload, created_at)
                 VALUES (?, NULL, 'unblocked', ?, ?)""",
              (task_id, '{"reason": "workspace fixed from scratch to dir"}', now))
conn.commit()
conn.close()
```

### Prevention
- When creating kanban tasks for code work, always use `workspace_kind=dir` with the project path
- The `scratch` workspace should only be used for transient data tasks (downloads, extracts, one-off scripts)
- Board health watcher cron jobs should check for this pattern

---

## Pattern: Stale Tasks (Fix Already Applied)

### Symptom
A task is blocked or ready, but CI review comments indicate the error was already resolved in a prior commit. The task's described error no longer appears in build output.

### Diagnosis
1. Read the CI review comments on the task — they often note "this may be stale"
2. Run the verification criteria from the task body
3. Check git log for commits between task creation and now that may have fixed the issue

### Fix
If the fix is already in the code, archive the task:
```python
import sqlite3, time
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
now = int(time.time())
c.execute("UPDATE tasks SET status='archived', completed_at=? WHERE id=?", (now, task_id))
c.execute("""INSERT INTO task_events (task_id, run_id, kind, payload, created_at)
             VALUES (?, NULL, 'archived', ?, ?)""",
          (task_id, '{"reason": "fix already applied in prior commit"}', now))
conn.commit()
conn.close()
```

### Prevention
- Before creating tasks for build errors, verify the errors still exist in the current code
- CI reviewer should flag stale tasks in its comments
- Board health watcher should detect and archive stale blocked tasks

---

## Pattern: Phantom Blocked Tasks (Implemented but Marked Blocked)

### Symptom
Multiple tasks blocked with `consecutive_failures=1` and `last_failure_error` containing "protocol violation" or "exited cleanly (rc=0) without calling kanban_complete or kanban_block". The tasks were created around the same time and share the same board.

### Root Cause
Workers completed the actual work (wrote code, registered commands) but the API stream dropped or the agent exited cleanly before calling `kanban_complete`. The dispatcher interprets this as a crash and marks the task blocked after retries are exhausted.

### Diagnosis
For each blocked task, verify whether the implementation already exists in the code:

```bash
# For Discord slash commands: check if @tree.command is registered
grep -n "@tree.command(name=\"<command>\"/" /path/to/discord.py

# For general code: check if the expected function/file exists
grep -n "async def <function_name>" /path/to/file.py

# For any task: check if expected files exist on disk
ls -la /path/to/expected/file
```

Also check the task's run events to confirm the pattern:
```python
c.execute("SELECT kind, payload FROM task_events WHERE task_id=? ORDER BY created_at", (task_id,))
```

Look for: `protocol_violation` event with `exit_code: 0` followed by `gave_up`.

### Decision Matrix

| Implementation exists? | Code is substantive? | Action |
|---|---|---|
| Yes | Yes (real code, not stubs) | **Mark as done** — set status='done', clear failures |
| Yes | No (stubs/placeholders) | Reset to ready with workspace fix, re-dispatch |
| No | — | Reset to ready with workspace fix, re-dispatch |

### Fix for Implemented Tasks
```python
import sqlite3
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
implemented_tasks = ['t_xxx', 't_yyy']  # tasks where implementation exists
for task_id in implemented_tasks:
    c.execute("UPDATE tasks SET status='done', consecutive_failures=0, last_failure_error=NULL WHERE id=?", (task_id,))
conn.commit()
conn.close()
```

### Fix for Not-Implemented Tasks (workspace reset)
```python
import sqlite3, time
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
now = int(time.time())
project_dir = '/path/to/project/'

for task_id in not_implemented_tasks:
    # Fix workspace first
    c.execute("UPDATE tasks SET workspace_kind='dir', workspace_path=? WHERE id=?", (project_dir, task_id))
    # Reset to ready
    c.execute("""UPDATE tasks SET status='ready', claim_lock=NULL, claim_expires=NULL,
                 worker_pid=NULL, current_run_id=NULL, consecutive_failures=0,
                 last_failure_error=NULL, max_retries=3 WHERE id=?""", (task_id,))
    c.execute("""INSERT INTO task_events (task_id, run_id, kind, payload, created_at)
                 VALUES (?, NULL, 'unblocked', ?, ?)""",
              (task_id, '{"reason": "workspace fixed, retry after protocol violation"}', now))
conn.commit()
conn.close()
```

### Prevention
- **Workspace is the #1 cause of protocol violations.** Workers in scratch workspaces can't find project files, produce empty responses, and exit cleanly. Always use `workspace_kind=dir` for code tasks.
- When bulk-creating tasks, verify workspace after creation — the `hermes kanban create` CLI does NOT support `--workspace-kind` or `--workspace-path` flags. You MUST set workspace via SQLite after creation.
- Board health watcher should check for this pattern: blocked tasks with protocol violation errors where the implementation already exists.
