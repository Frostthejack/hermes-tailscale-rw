# Worker Crash Diagnosis — Workspace Mismatch

## Symptom
Multiple tasks blocked with `pid not alive` and `consecutive_failures` at retry limit. Tasks involve code changes (TypeScript fixes, feature implementation, bug fixes). Rate limit errors are NOT present in logs.

## Root Cause
Tasks were created with `workspace_kind=scratch` instead of `workspace_kind=dir:<path>`. Scratch workspaces are empty temporary directories — no source code, no `node_modules`, no `.git`. Workers that try to read/write project files crash immediately because the files don't exist.

## Diagnosis
1. Check workspace: `hermes kanban --board <slug> show <task_id>` — look for `workspace: scratch @ /home/<user>/.hermes/kanban/...`
2. If workspace is `scratch` and the task body mentions source code files or `WORKING DIRECTORY:`, it's a workspace mismatch
3. Confirm by listing the workspace: `ls <workspace_path>` — will be empty or nearly empty
4. Check if multiple blocked tasks share the same pattern (batch creation often sets all to scratch)

## Fix
Update the SQLite DB directly (no CLI command exists for workspace changes):

```python
import sqlite3, time
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
now = int(time.time())

for task_id in blocked_task_ids:
    # Fix workspace
    c.execute("UPDATE tasks SET workspace_kind='dir', workspace_path=? WHERE id=?",
              ('/mnt/c/Users/<user>/Documents/Projects/<project>/', task_id))
    # Reset crash state
    c.execute("""UPDATE tasks SET 
        status='ready', claim_lock=NULL, claim_expires=NULL, 
        worker_pid=NULL, current_run_id=NULL, 
        consecutive_failures=0, last_failure_error=NULL, max_retries=3
        WHERE id=?""", (task_id,))
    # Log the unblock
    c.execute("INSERT INTO task_events (task_id, run_id, kind, payload, created_at) VALUES (?, NULL, 'unblocked', ?, ?)",
              (task_id, '{"reason": "workspace fixed from scratch to dir"}', now))

conn.commit()
conn.close()
```

After fix, the dispatcher picks up tasks on the next tick (~60s).

## Prevention
- When creating kanban tasks for code work, always use `workspace: dir:<path>` in the task body
- The `kanban_create` tool does NOT have a workspace parameter — workspace is set by the dispatcher based on profile defaults
- If a profile's default workspace is `scratch`, tasks that involve code will crash until manually fixed
- Check profile workspace defaults: `hermes kanban assignees` or profile config YAML
- **Stale task check:** Before fixing, verify the task's fix hasn't already been applied in a prior commit. Run `npx tsc --noEmit` or check git log for the relevant files. If already fixed, mark done instead of unblocking.
