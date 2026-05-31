# Event Bus — API Reference

*File-based event bus for kanban state changes. Source: `scripts/kanban_event_bus.py`*

## Quick Start

```python
from kanban_event_bus import EventBus, emit_task_completed, emit_task_created

# Emit an event (orchestrator side)
emit_task_completed(
    board_slug="rollsiege",
    task_id="t_abc123",
    title="Fix login flow",
    assignee="backend-eng",
    summary="Fixed token refresh, added 3 tests",
)

# Read events (worker side)
bus = EventBus("rollsiege")
events = bus.get_events(since=last_check_timestamp)
for event in events:
    if event["data"].get("assignee") == "my-profile":
        # This event affects me
        pass
```

## Event Types

| Type | Data Fields | When to Emit |
|------|------------|--------------|
| `task_created` | task_id, title, assignee, parent_id | After `kanban_create` |
| `task_claimed` | task_id, title, assignee | After claiming a task |
| `task_completed` | task_id, title, summary | After `kanban_complete` |
| `task_blocked` | task_id, title, reason | After `kanban_block` |

## Storage

- **Location**: `~/.hermes/kanban/events/<board_slug>.jsonl`
- **Format**: JSON Lines (one event per line)
- **Retention**: 24h auto-pruning on read
- **No locking needed**: append-only writes

## Checkpoint Pattern for Workers

```python
import json, os, time

checkpoint_file = os.path.expanduser("~/.hermes/kanban/events/last_check.json")

# Read last checkpoint
last_check = 0
if os.path.exists(checkpoint_file):
    with open(checkpoint_file) as f:
        last_check = json.load(f).get("timestamp", 0)

# Get new events
bus = EventBus("rollsiege")
events = bus.get_events(since=last_check)

# Process events...
for event in events:
    pass  # Your logic here

# Update checkpoint
with open(checkpoint_file, "w") as f:
    json.dump({"timestamp": int(time.time())}, f)
```