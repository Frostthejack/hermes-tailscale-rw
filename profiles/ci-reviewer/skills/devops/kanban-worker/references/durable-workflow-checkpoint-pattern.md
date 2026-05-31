# Durable Workflow Checkpoint Pattern

> Reference for the kanban-worker skill. Captures the checkpoint/resume mechanism that makes multi-step kanban tasks survive crashes and context loss.

## Why This Exists

Regular kanban workers are fragile — if the session crashes, the context compresses, or the worker is killed, all in-memory progress is lost. The checkpoint pattern writes step-level progress to disk so a fresh worker (or the same worker after recovery) can resume from the last completed step.

Centaur (paradigmxyz) does this with Postgres. Our equivalent uses:
- **Kanban SQLite** → task-level durability (already exists)
- **Checkpoint JSON files** → step-level durability (this doc)
- **project-state.md YAML block** → project-level durability
- **Hindsight bank** → cross-session memory durability

## Checkpoint File

**Location:** `~/.hermes/workflows/<task-id>.checkpoint.json`

**Shape:**
```json
{
  "task_id": "t_abc123",
  "title": "Implement auth module",
  "project": "rollsiege",
  "phase": 2,
  "steps": [
    {"id": 1, "name": "Create DB schema", "status": "done", "completed_at": "2026-05-27T10:00:00Z"},
    {"id": 2, "name": "Write API routes", "status": "done", "completed_at": "2026-05-27T10:05:00Z"},
    {"id": 3, "name": "Add middleware", "status": "in_progress", "started_at": "2026-05-27T10:10:00Z"},
    {"id": 4, "name": "Write tests", "status": "pending"},
    {"id": 5, "name": "Run CI", "status": "pending"}
  ],
  "last_updated": "2026-05-27T10:12:00Z",
  "last_commit": "a1b2c3d"
}
```

**Resume at startup:**
```python
import json, os
checkpoint_file = os.path.expanduser(f"~/.hermes/workflows/<task-id>.checkpoint.json")
if os.path.exists(checkpoint_file):
    with open(checkpoint_file) as f:
        checkpoint = json.load(f)
    for step in checkpoint["steps"]:
        if step["status"] != "done":
            resume_step = step
            break
```

**Write after each step:**
```python
import json, os, time
checkpoint["last_updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
os.makedirs(os.path.dirname(checkpoint_file), exist_ok=True)
with open(checkpoint_file, "w") as f:
    json.dump(checkpoint, f, indent=2)
```

**Cleanup on completion:**
```bash
rm -f ~/.hermes/workflows/<task-id>.checkpoint.json
```

## When to Use Checkpoints

- Multi-file coding tasks (each file = one step)
- Tasks with explicit `## Steps:` section in body
- Any task estimated >5 min
- Tasks that span verification sub-steps

## When Checkpoints Are Optional

- Single-action tasks (update README, bump version)
- Tasks with no clear step decomposition

## Integration with Hindsight

Checkpoint files handle **intra-task** durability. Hindsight handles **inter-task** durability (knowledge across sessions). Both should be used together.
