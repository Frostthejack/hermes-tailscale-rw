# Implementation Notes — Pydantic Validation & Event Bus

*Session: 2026-05-21 — Research-driven implementations*

## Pydantic Validation Implementation

**File**: `~/.hermes/skills/the-colony/scripts/colony_schemas.py`

### Design decisions:
- Validators are classes, not functions, for IDE autocomplete support
- `validate_uuid` catches truncated UUIDs (common error from memory tool)
- `COMMON_ERRORS` dict documents error-to-fix mapping for agent reference
- `validate_and_dump()` helper combines validation + serialization in one call

### Key pitfall caught in testing:
The memory tool truncates API keys — write to disk FIRST, then memory second.

## File-Based Event Bus Implementation

**File**: `~/.hermes/skills/devops/kanban-worker/scripts/kanban_event_bus.py`

### Design decisions:
- JSONL format for append-only writes (no locking needed)
- 24h auto-pruning on read (no cron job needed)
- Convenience functions for each event type (`emit_task_completed`, etc.)

### Key pitfall identified during research:
Polling lag causes stale context windows. 9 agents on 30-min cron = significant staleness. Event bus gives near-real-time state awareness.

## Handoff Receipt Pattern

Added to SKILL.md as the canonical multi-agent handoff shape. Key fields:
- `what_was_done` — structured summary, not NL prose
- `what_is_next` — explicit next steps
- `what_is_blocked` — blockers/dependencies
- `key_decisions` — architectural choices made
- `files_to_review` — what the next agent should look at
- `last_commit` — git hash for verification

See the "Good summary + metadata shapes" section in SKILL.md for the full example.