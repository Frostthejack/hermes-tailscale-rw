---
name: kanban-worker
description: Pitfalls, examples, and edge cases for Hermes Kanban workers. The lifecycle itself is auto-injected into every worker's system prompt as KANBAN_GUIDANCE (from agent/prompt_builder.py); this skill is what you want when you need deeper detail on specific scenarios.
version: 2.5.0
metadata:
  hermes:
    tags: [kanban, multi-agent, collaboration, workflow, pitfalls]
    related_skills: [kanban-orchestrator]
---

# Kanban Worker — Pitfalls and Examples

> You're seeing this skill because the Hermes Kanban dispatcher spawned you as a worker with `--skills kanban-worker` — it's loaded automatically for every dispatched worker. The **lifecycle** (6 steps: orient → work → heartbeat → block/complete) also lives in the `KANBAN_GUIDANCE` block that's auto-injected into your system prompt. This skill is the deeper detail: good handoff shapes, retry diagnostics, edge cases.

## Kanban-First Imperative — ALL Work Goes Through the Board

**For any project that has a kanban board, EVERY piece of work must be routed through the kanban board.** This is non-negotiable. The kanban board is the single source of truth for all logs, code changes, investigation reports, and history.

This includes:
- **Coding tasks** — features, fixes, refactors → backend-eng or frontend-eng
- **Bug reports** → reviewer first (see Bug Routing Workflow below)
- **Investigation/research** → researcher or analyst tasks
- **Code review** → reviewer tasks
- **Ops work** → ops tasks
- **Quick checks or "small" fixes** → still create a task, even if it seems trivial

**Why:** Direct work outside the board leaves no trace. When something breaks later, there's no log, no comment history, no way to trace what changed or why. The board's event log, comments, and run history are the project's memory.

**Anti-pattern:** Reading files, running commands, or making changes directly because "it's just a quick look" or "it's too small for a task." If it touches the project, it goes on the board.

## Bug Routing Workflow

When a bug is reported on a kanban-tracked project:

1. **Create a reviewer task** — Assign to `reviewer`. The reviewer investigates the bug, determines root cause, and creates specific fix tasks. The reviewer does NOT implement fixes.
2. **Reviewer creates fix tasks** — Based on findings, the reviewer creates tasks assigned to the correct specialist:
   - **backend-eng** — Rust code, Tauri config, window management, webhook server, system tray
   - **frontend-eng** — React/TypeScript, CSS/rendering, SVG assets, Zustand store, UI components
   - **ops** — Build, deployment, CI/CD, GitHub
3. **Fix tasks include verification criteria** — Each fix task must have clear VERIFICATION steps so the implementer can self-verify before marking done.
4. **Reviewer completes after fix tasks are created** — The reviewer task is done once fix tasks exist with correct assignees and descriptions. The reviewer does not wait for fixes to be implemented.

**Do NOT:**
- Assign bug fixes directly to backend-eng or frontend-eng without reviewer investigation
- Let the reviewer implement fixes — their job is diagnosis and task creation
- Skip the reviewer for "obvious" bugs — the reviewer may find the root cause is different from what was assumed

## Workspace handling

Your workspace kind determines how you should behave inside `$HERMES_KANBAN_WORKSPACE`:

| Kind | What it is | How to work |
|---|---|---|
| `scratch` | Fresh tmp dir, yours alone | Read/write freely; it gets GC'd when the task is archived. **NEVER use for coding project work** — only for transient data (downloads, extracts, one-off scripts). |
| `worktree` | Git worktree on an isolated branch | **Default for coding tasks.** Create the worktree if it doesn't exist, do all work here, commit to the isolated branch. The orchestrator merges after review. |
| `dir:<path>` | Shared persistent directory | Other runs will read what you write. For ops tasks that need the live project tree. Path is guaranteed absolute. |

### Coding project tasks — worktree directive

**For any task that involves writing or modifying project source code**, the workspace SHOULD be `worktree` (the default for backend-eng, frontend-eng, claude-lane, agy-lane). The `scratch` workspace kind is **explicitly forbidden** for project code work.

**Worktree workflow for coding tasks:**
```bash
# 1. Verify you're in the project repo (the worktree base)
cd $PROJECTS_ROOT/<project-name>/
git remote -v  # confirm it's the right repo

# 2. If the worktree doesn't exist yet, create it
if [ ! -d ".worktrees/<task-id>" ]; then
  git worktree add .worktrees/<task-id> -b kanban/<task-id>
fi

# 3. cd into the worktree and do all work there
cd .worktrees/<task-id>

# 4. Implement, test, commit
git add -A
git commit -m "feat: <task description>"

# 5. Push the branch (so the orchestrator can merge it)
git push origin kanban/<task-id>
```

**After `kanban_complete`:** The orchestrator will merge the branch (via PR or cherry-pick) and clean up the worktree. Do NOT merge your own branch.

**If the workspace is `scratch` but the task involves project code:**
1. STOP — do not write code in the scratch directory
2. Check if the task body specifies a `WORKING DIRECTORY:` field
3. If yes, `cd` to that directory, create a worktree there, and work in it
4. If no, `kanban_block` with: "Task involves project code but workspace is scratch. Need WORKING DIRECTORY: $PROJECTS_ROOT/<project-name>/"
5. Never improvise a temp location for project code

**Why worktrees:** Each task gets its own branch and working directory. Parallel workers never conflict. The orchestrator reviews and merges each branch independently. Clean git history per task.

**Why `scratch` is forbidden for code:** Scratch directories are GC'd when the task is archived. Any code written there is permanently lost.

## Checkpoint Pattern — Survive Crashes and Resume

**For any task with multiple steps, write a checkpoint file after each step.** This is the durable workflow mechanism — if the session crashes or the worker is killed, the next worker (or orchestrator) reads the checkpoint and resumes from the last completed step instead of starting over.

### Checkpoint File Location

```
~/.hermes/workflows/<task-id>.checkpoint.json
```

### Checkpoint JSON Shape

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

### Resume Protocol (Run at Startup)

Before doing any work on a task:

```python
import json, os

checkpoint_file = os.path.expanduser(f"~/.hermes/workflows/<task-id>.checkpoint.json")
resume_step = None

if os.path.exists(checkpoint_file):
    with open(checkpoint_file) as f:
        checkpoint = json.load(f)
    # Find first non-done step
    for step in checkpoint["steps"]:
        if step["status"] != "done":
            resume_step = step
            break
    if resume_step:
        print(f"Resuming from step {resume_step['id']}: {resume_step['name']}")
    else:
        print("All steps already done — verify and complete")
else:
    print("No checkpoint — starting fresh")
```

### Write Checkpoint After Each Step

```python
import json, os, time

checkpoint_file = os.path.expanduser(f"~/.hermes/workflows/<task-id>.checkpoint.json")

# Load existing or create new
if os.path.exists(checkpoint_file):
    with open(checkpoint_file) as f:
        checkpoint = json.load(f)
else:
    checkpoint = {
        "task_id": "<task-id>",
        "title": "<task title>",
        "project": "<project-name>",
        "phase": <phase-number>,
        "steps": [<list of step dicts from task body>],
        "last_updated": None,
        "last_commit": None
    }

# Update the step that just completed
for step in checkpoint["steps"]:
    if step["id"] == <completed-step-id>:
        step["status"] = "done"
        step["completed_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    elif step["id"] == <next-step-id>:
        step["status"] = "in_progress"
        step["started_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

checkpoint["last_updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

os.makedirs(os.path.dirname(checkpoint_file), exist_ok=True)
with open(checkpoint_file, "w") as f:
    json.dump(checkpoint, f, indent=2)
```

### When to Write Checkpoints

- **After every file write / code change** on multi-file tasks
- **After completing each verification sub-step**
- **After pushing a commit** (update `last_commit` field)
- **Before calling `kanban_block`** — ensure checkpoint reflects current progress

### Cleanup On Completion

When you call `kanban_complete`, delete the checkpoint file:

```bash
rm -f ~/.hermes/workflows/<task-id>.checkpoint.json
```

### For Single-Step Tasks

If a task has no `## Steps:` section in its body and is clearly one action (e.g., "update README"), checkpoint files are optional. Use judgment — if the task might take >5 min or crosses multiple files, write checkpoints.

## Tenant isolation

If `$HERMES_TENANT` is set, the task belongs to a tenant namespace. When reading or writing persistent memory, prefix memory entries with the tenant so context doesn't leak across tenants:

- Good: `business-a: Acme is our biggest customer`
- Bad (leaks): `Acme is our biggest customer`

## Good summary + metadata shapes

The `kanban_complete(summary=..., metadata=...)` handoff is how downstream workers read what you did. Patterns that work:

**Coding task:**
```python
kanban_complete(
    summary="Created API client, added 4 tests, 3 TODOs remaining",
    metadata={
        "changed_files": ["colony_client.py", "colony_schemas.py"],
        "tests_run": 4,
        "tests_passed": 4,
        "approved": True,
    },
)
```

**Review task:**
```python
kanban_complete(
    summary="Review completed. 2 critical, 3 high-priority issues found. Fix tasks created.",
    metadata={
        "findings": [
            {"severity": "critical", "file": "api/search.py", "line": 42, "issue": "raw SQL concat"},
            {"severity": "high", "file": "api/settings.py", "issue": "missing CSRF middleware"},
        ],
        "approved": False,
    },
)
```

Shape `metadata` so downstream parsers (reviewers, aggregators, schedulers) can use it without re-reading your prose.

**Multi-agent handoff (with structured handoff receipt):**
```python
kanban_complete(
    summary="Created API client, added 4 tests, 3 TODOs remaining",
    metadata={
        # Handoff receipt — helps next agent pick up smoothly
        "handoff_receipt": {
            "what_was_done": "Implemented ColonyClient with get_posts, create_post, add_comment methods",
            "what_is_next": [
                "Add vote and reaction support",
                "Wire up to notification polling",
            ],
            "what_is_blocked": [],
            "key_decisions": [
                "Used pydantic validation for all API bodies (colony_schemas.py)",
                "Stored API key in ~/.hermes/credentials/colony.json, not memory tool",
            ],
            "files_to_review": ["colony_client.py", "colony_schemas.py"],
            "last_commit": "a1b2c3d",
        },
        # Standard task metadata
        "changed_files": ["colony_client.py", "colony_schemas.py"],
        "tests_run": 4,
        "tests_passed": 4,
    },
)
```

## File-Based Event Bus — React to State Changes Immediately

Instead of polling the kanban DB on cron intervals (which causes stale context
windows), use the file-based event bus to react to state changes in near-real-time.

**Location:** `scripts/kanban_event_bus.py` (in this skill directory)
**Storage:** `~/.hermes/kanban/events/<board_slug>.jsonl`

### For Orchestrator Profiles

When you create tasks or complete work, emit events so other agents can react:

```python
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kanban_event_bus import emit_task_completed, emit_task_created, emit_task_blocked

# After completing a task:
emit_task_completed(
    board_slug="rollsiege",
    task_id="t_abc123",
    title="Fix login flow",
    assignee="backend-eng",
    summary="Fixed token refresh, added 3 tests",
)

# After creating a downstream task:
emit_task_created(
    board_slug="rollsiege",
    task_id="t_def456",
    title="Add rate limiter",
    assignee="backend-eng",
    parent_id="t_abc123",
)
```

### For Worker Profiles

Before starting work, check for recent events that might affect your task:

```python
from kanban_event_bus import EventBus
import json, os

checkpoint_file = os.path.expanduser("~/.hermes/kanban/events/last_check.json")
last_check = 0
if os.path.exists(checkpoint_file):
    with open(checkpoint_file) as f:
        last_check = json.load(f).get("timestamp", 0)

bus = EventBus("rollsiege")
events = bus.get_events(since=last_check)

for event in events:
    if event["type"] == "task_completed":
        if event["assignee"] == "backend-eng":
            pass  # A dependency completed — you may need to wait
        pass

# Update checkpoint
with open(checkpoint_file, "w") as f:
    json.dump({"timestamp": int(time.time())}, f)
```

## Previous run outcome — decide whether to resume or start fresh

When you're spawned for a task that has a previous run (i.e., `last_run` is present in the task payload):

**Read `last_run.outcome` first:**
- `outcome: "completed"` — the previous attempt actually finished. Just verify the work is still good.
- `outcome: "timed_out"` — the previous attempt hit `max_runtime_seconds`. You may need to chunk the work or shorten it.
- `outcome: "crashed"` — OOM or segfault. Reduce memory footprint.
- `outcome: "spawn_failed"` + `error: "..."` — usually a profile config issue (missing credential, bad PATH). Ask the human via `kanban_block` instead of retrying blindly.
- `outcome: "reclaimed"` + `summary: "task archived..."` — operator archived the task out from under the previous run; you probably shouldn't be running at all, check status carefully.
- `outcome: "blocked"` — a previous attempt blocked; the unblock comment should be in the thread by now.

## Hindsight Memory Retention — MANDATORY, DO NOT SKIP

**Every worker session MUST end with a hindsight memory retention call before `kanban_complete`.** This is non-negotiable. If you complete a task, partially complete a task, or even just make progress — retain what you learned.

### The Rule

The sequence before completing ANY task MUST be:

1. Do the work
2. Verify the work (run VERIFICATION criteria)
3. **Retain to hindsight** (save what you learned)
4. `kanban_complete()` — report completion

### How to Retain

Use the `memory` tool to save to the `memory` target:

```
memory(
    action="add",
    target="memory",
    content="[profile-name]: [what you did]. [decisions made]. [key findings].)"
)
```

For profile-specific hindsight banks, also retain via the hindsight API if available:
```bash
curl -s -X POST http://localhost:8888/v1/default/banks/<profile-name>/memories \
  -H "Content-Type: application/json" \
  -d '{"items": [{"content": "<session summary>", "tags": ["<project>", "<work-type>"], "type": "observation"}]}'
```

### What to Retain by Profile

- **backend-eng**: Architecture decisions, API designs, DB schemas, bug patterns
- **frontend-eng**: UI/UX decisions, component patterns, accessibility techniques
- **ops**: Deployment procedures, monitoring configs, incident root causes
- **reviewer**: Recurring code quality issues, security checklist items, bug patterns
- **pm**: Project priorities, stakeholder feedback, prioritization decisions
- **analyst**: Data insights, metrics, performance bottlenecks
- **researcher**: Research findings, tech evaluations, best practices
- **writer**: Content style guides, documentation templates, publishing workflows

### If Hindsight Service Is Down

Write retention to `~/.hermes/pending-retention/<project>-<date>.md` and retain in the next session. Don't skip it.

> **See `references/durable-workflow-checkpoint-pattern.md` for the checkpoint/resume mechanism that makes multi-step tasks survive crashes.**
>
> **See `references/hindsight-retention-protocol.md` for the full protocol, tag conventions, and cross-bank reading patterns.**

## Verification discipline — DO NOT skip this

**Never mark a task `done` without running its verification criteria.** Every task that has a `VERIFICATION:` comment in its body or comments must have those checks executed and confirmed passing before `kanban_complete` is called. This is non-negotiable.

The pattern that breaks projects:
1. Worker writes code, marks task `done` with a summary like "shipped X"
2. Downstream tasks start based on the "done" status
3. The code doesn't actually work — tests fail, endpoints return errors, deployment breaks
4. The failure cascades through every dependent task
5. An entire phase has to be re-done

If you cannot verify (e.g., missing credentials, blocked by external service), `kanban_block` with the specific blocker. Do NOT mark done and move on.

If you discover that a previously-"done" task you depend on is actually broken, `kanban_block` your own task and add a comment explaining the dependency failure. The orchestrator will create a fix task for the broken dependency.

## Worker Crash / Protocol Violation Pattern

When a worker exits cleanly (rc=0) without calling `kanban_complete` or `kanban_block`, the dispatcher logs "protocol violation" and marks the task as crashed. After hitting the retry limit, the task becomes **blocked**.

**Common causes:**
- The worker finished the work but the LLM didn't call `kanban_complete` before exiting
- The worker hit an unhandled edge case and exited early
- The worker's process was killed (OOM, timeout)
- **API stream drop or token limit truncation** — the session ended before the worker could call `kanban_complete`

**Prevention (for workers):**
- **Call `kanban_complete` or `kanban_block` as early as possible.** Don't wait until you've done "enough" work — if you've made any progress, report it.
- **Write `kanban_comment` checkpoints** every few minutes so your progress is recorded even if the session drops.
- **If you sense the session might end soon** (e.g., you've been working for a while), call `kanban_block` with a summary of what you've done and what remains. This is always better than a silent exit.
- **ALWAYS commit and push your changes before calling `kanban_complete`.** This is the #1 cause of lost work in kanban execution.
- **Token limit awareness:** If you're doing many file writes or long diffs, you may hit the output token limit.

**Resolution (for orchestrator/human):**
1. Check if the work was actually completed (look at git history, CI status, code changes)
2. If the fix is already in the code: `hermes kanban unblock <id>` then `hermes kanban complete <id> --summary "Fixed in commit <hash>"`
3. If the work wasn't done: unblock and let a worker retry, or fix it manually
4. Check `hermes kanban log <id>` for the worker's output to understand what happened

**Phantom completions — workers die after writing code.**
