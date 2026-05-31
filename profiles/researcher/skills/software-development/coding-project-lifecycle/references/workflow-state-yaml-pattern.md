# Machine-Readable Workflow State in project-state.md

> Reference for the coding-project-lifecycle skill. The YAML block at the end of each project-state.md enables cron watchers and agents to parse project state without reading the full document.

## Shape

Every project-state.md in the vault gets this section appended:

```markdown
---

## Workflow State (Machine-Readable)

> This section is parsed by cron watchers and agents for durable workflow resume.
> Update it after every work session. Commit the vault after changes.

```yaml
# <Project Name> Workflow State
phase: <number>
phase_status: in_progress | complete | paused
paused: true | false
paused_reason: "<human-readable reason>"
last_resume_action: "<what to do when resuming>"
board_slug: <kanban-board-slug>
board_status: active | paused
cron_jobs_active: true | false
last_updated: "<ISO timestamp>"
```
```

## Additional Fields (project-specific)

Projects may add extra fields as needed:

```yaml
uncommitted_files: 13
uncommitted_summary: "webhook handler, App.tsx, pet components"
uncommitted_commit_hash: "a1b2c3d"
```

## When to Update

- After every work session (agent or human)
- When cron jobs are paused/resumed
- When phase changes
- When board status changes
- Before committing the vault

## How Agents Parse It

```python
import yaml, re

with open(project_state_path) as f:
    content = f.read()

# Extract the YAML block from the Workflow State section
match = re.search(r'## Workflow State.*?```yaml\n(.*?)\n```', content, re.DOTALL)
if match:
    state = yaml.safe_load(match.group(1))
    # state["phase"], state["phase_status"], state["last_resume_action"], etc.
```

## Relationship to Checkpoint Files

- **project-state.md YAML** → project-level state (which phase, what's next)
- **Checkpoint JSON files** (`~/.hermes/workflows/<task-id>.checkpoint.json`) → step-level state (which step within a task)
- **Kanban DB** → task-level state (done/ready/running/blocked)
- **Hindsight bank** → cross-session knowledge state

All four layers together form the durable workflow stack.
