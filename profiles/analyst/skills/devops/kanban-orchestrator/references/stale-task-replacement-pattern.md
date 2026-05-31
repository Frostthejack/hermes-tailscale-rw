# Stale Task Replacement Pattern

## When to Use
A task is blocked after many worker failures, but investigation shows:
- The original issue is already fixed in CI (CI reviewer comments confirm passing tests)
- OR: The task needs a completely fresh approach after N failed attempts

## Workflow

### Step 1 — Verify Stale (mark done)
If CI shows the tests are already passing:
```bash
hermes kanban --board <slug> complete <task_id> --summary "CI reviewer confirmed tests passing. Marking done based on CI evidence."
```

### Step 2 — Create Replacement (for persistent issues)
If the issue is real but previous workers failed:
```bash
hermes kanban --board <slug> create "<focused title>" --assignee <profile> --body "<full context + root cause + what failed + verification>"
```

### Step 3 — Link Old Task as Parent
This preserves the full comment history and run logs for the new worker:
```bash
hermes kanban --board <slug> link <old_blocked_task_id> <new_task_id>
```

### Step 4 — Fix Workspace Immediately
`kanban_create` defaults to `scratch` workspace. For code tasks, fix via SQLite BEFORE the worker picks it up:
```python
import sqlite3
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
c.execute("UPDATE tasks SET workspace_kind='dir', workspace_path='/path/to/project/' WHERE id='<new_task_id>'")
conn.commit()
conn.close()
```

### Step 5 — Verify Dispatch
```bash
hermes kanban --board <slug> show <new_task_id>
```
Check that status is `running` and workspace is `dir`.

## Real-World Example (RollSiege, 2026-05-18)
- **t_6f9c145d** (edge-cases, 17 tests): CI reviewer confirmed all tests passing across 5 runs → marked done
- **t_251b259f** (gameOver regression): 10+ worker crashes, 5+ failed fix attempts → created **t_e3e3abaf** with focused root cause analysis, linked old task as parent, fixed workspace to `dir`
