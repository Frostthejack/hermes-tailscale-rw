---
name: kanban-orchestrator
description: Decomposition playbook + specialist-roster conventions + anti-temptation rules for an orchestrator profile routing work through Kanban. The "don't do the work yourself" rule and the basic lifecycle are auto-injected into every kanban worker's system prompt; this skill is the deeper playbook when you're specifically playing the orchestrator role.
version: 2.3.0
metadata:
  hermes:
    tags: [kanban, multi-agent, orchestration, routing]
    related_skills: [kanban-worker]
---

# Kanban Orchestrator — Decomposition Playbook

> The **core worker lifecycle** (including the `kanban_create` fan-out pattern and the "decompose, don't execute" rule) is auto-injected into every kanban process via the `KANBAN_GUIDANCE` system-prompt block. This skill is the deeper playbook when you're an orchestrator profile whose whole job is routing.

## When to use the board (vs. just doing the work)

Create Kanban tasks when any of these are true:

1. **Multiple specialists are needed.** Research + analysis + writing is three profiles.
2. **The work should survive a crash or restart.** Long-running, recurring, or important.
3. **The user might want to interject.** Human-in-the-loop at any step.
4. **Multiple subtasks can run in parallel.** Fan-out for speed.
5. **Review / iteration is expected.** A reviewer profile loops on drafter output.
6. **The audit trail matters.** Board rows persist in SQLite forever.

If *none* of those apply — it's a small one-shot reasoning task — use `delegate_task` instead or answer the user directly.

**Sequential scaffolding is NOT an exception.** Even if tasks must be done sequentially (e.g., Phase 1: scaffold → window → click-through → drag), create individual kanban tasks for each step. The dispatcher will pick them up one at a time if they have parent dependencies. The only true exceptions are: (a) research/analysis tasks that require orchestrator-level reasoning across multiple sources, (b) board setup and task creation itself, (c) summarizing results for the user.

## The anti-temptation rules

Your job description says "route, don't execute." The rules that enforce that:

- **Do not execute the work yourself.** Your restricted toolset usually doesn't even include terminal/file/code/web for implementation. If you find yourself "just fixing this quickly" — stop and create a task for the right specialist.
- **For any concrete task, create a Kanban task and assign it.** Every single time.
- **The user explicitly wants work routed through kanban with subagent delegation.** "Utilize the kanban. Break tasks into bite-sized pieces and have other agents focus on doing small tasks and self-verify." This is not a suggestion — it is the user's preferred workflow. Even if you can see the fix immediately, create the kanban task and let a subagent implement and verify it. The only exceptions are: (a) research/analysis tasks that require orchestrator-level reasoning across multiple sources, (b) board setup and task creation itself, (c) summarizing results for the user.
- **Even if you already have the fix in hand, create the kanban task first.** Committing a fix directly instead of routing it through kanban is a protocol violation. The user explicitly wants work broken into bite-sized pieces and delegated to subagents who self-verify. If you've already done the work, still create the task, assign it, and let the dispatcher's worker verify/complete it — or archive the task you created and note it was pre-resolved. Never skip the kanban.
- **If no specialist fits, ask the user which profile to create.** Do not default to doing it yourself under "close enough."
- **Decompose, route, and summarize — that's the whole job.**

## The standard specialist roster (convention)

Unless the user's setup has customized profiles, assume these exist. Adjust to whatever the user actually has — ask if you're unsure.

| Profile | Does | Default workspace_kind | Workspace path |
|---|---|---|---|
| `researcher` | Reads sources, gathers facts, writes findings | `scratch` | (auto) |
| `analyst` | Synthesizes, ranks, de-dupes. Consumes multiple `researcher` outputs | `scratch` | (auto) |
| `writer` | Drafts prose in the user's voice | `scratch` | (auto) |
| `reviewer` | Reads output, leaves findings, gates approval | `scratch` | (auto) |
| `backend-eng` | Writes server-side code (direct Hermes implementation) | `worktree` | `$PROJECTS_ROOT/<project>/.worktrees/<task-id>` |
| `frontend-eng` | Writes client-side code (direct Hermes implementation) | `worktree` | `$PROJECTS_ROOT/<project>/.worktrees/<task-id>` |
|| `claude-lane` | Delegates coding to **Claude Code CLI** (`claude -p`). Orchestrates: worktree → spawn → reconcile → verify → complete. For complex multi-file work. | `worktree` | (lane creates its own) |
| `claude_lane` | Same as `claude-lane` — delegates coding to **Claude Code CLI** (`claude -p`). Preferred active profile (claude-lane may have stale credentials). | `worktree` | (lane creates its own) |
| `agy-lane` | Delegates coding to **Antigravity CLI** (`agy -p`). Orchestrates: worktree → spawn → reconcile → verify → complete. For quick fixes and sandboxed execution. | `worktree` | (lane creates its own) |
| `ops` | Runs scripts, manages services, handles deployments | `dir:` | `$PROJECTS_ROOT/<project>/` |
| `orchestrator` | Decomposes work, routes tasks, monitors board, summarizes for user. NEVER executes. | `scratch` | (auto) |
| `ci-reviewer` | Monitors CI/CD pipelines, verifies build artifacts, gates deployments on green builds | `scratch` | (auto) |

**Workspace kind semantics:**
- **`scratch`** — Isolated temp dir, GC'd on task archive. For research, writing, transient data only. **NEVER for project code.**
- **`worktree`** — Git worktree on an isolated branch. For all coding tasks. Worker creates the worktree, commits to it, and the orchestrator merges after review.
- `dir:` — Shared persistent directory. For ops tasks that need the live project tree. Workers edit the shared branch directly.

## Decomposition playbook

### Step 1 — Understand the goal

Ask clarifying questions if the goal is ambiguous. Cheap to ask; expensive to spawn the wrong fleet.

### Step 2 — Sketch the task graph

Before creating anything, draft the graph out loud (in your response to the user). Example for "Analyze whether we should migrate to Postgres":

```
T1  researcher        research: Postgres cost vs current
T2  researcher        research: Postgres performance vs current
T3  analyst           synthesize migration recommendation       parents: T1, T2
T4  writer            draft decision memo                       parents: T3
```

Show this to the user. Let them correct it before you create anything.

### Step 3 — Create tasks and link

```python
t1 = kanban_create(
    title="research: Postgres cost vs current",
    assignee="researcher",
    body="Compare estimated infrastructure costs, migration costs, and ongoing ops costs over a 3-year window. Sources: AWS/GCP pricing, team time estimates, current Postgres bills from peers.",
    tenant=os.environ.get("HERMES_TENANT"),
)["task_id"]

t2 = kanban_create(
    title="research: Postgres performance vs current",
    assignee="researcher",
    body="Compare query latency, throughput, and scaling characteristics at our expected data volume (~500GB, 10k QPS peak). Sources: benchmark papers, public case studies, pgbench results if easy.",
)["task_id"]

t3 = kanban_create(
    title="synthesize migration recommendation",
    assignee="analyst",
    body="Read the findings from T1 (cost) and T2 (performance). Produce a 1-page recommendation with explicit trade-offs and a go/no-go call.",
    parents=[t1, t2],
)["task_id"]

t4 = kanban_create(
    title="draft decision memo",
    assignee="writer",
    body="Turn the analyst's recommendation into a 2-page memo for the CTO. Match the tone of previous decision memos in the team's knowledge base.",
    parents=[t3],
)["task_id"]
```

**`hermes kanban create` CLI syntax:** The title is a **positional argument**, not a `--title` flag. Correct: `hermes kanban --board <slug> create "Task title" --assignee <profile>`. Wrong: `hermes kanban --board <slug> create --title "Task title"`.

**`hermes kanban link` CLI syntax:** Both parent and child IDs are **positional arguments**, not flags. Correct: `hermes kanban --board <slug> link <parent_id> <child_id>`. Wrong: `hermes kanban --board <slug> link --parent <id> --child <id>`.

### Step 4 — Report back to the user

Tell them what you created in plain prose:

> I've queued 4 tasks:
> - **T1** (researcher): cost comparison
> - **T2** (researcher): performance comparison, in parallel with T1
> - **T3** (analyst): synthesizes T1 + T2 into a recommendation
> - **T4** (writer): turns T3 into a CTO memo
>
> The dispatcher will pick up T1 and T2 now. T3 starts when both finish. You'll get a gateway ping when T4 completes. Use the dashboard or `hermes kanban tail <id>` to follow along.

**Verification/Acceptance Criteria.** For any task where "done" vs "not done" is not self-evident (APIs, integrations, database operations, UI features), append a comment with specific test steps. This is cheaper than discovering breakage downstream. Shape:
```
VERIFICATION: After completing this task:
(1) <specific command or browser action> — <expected result>
(2) <another check> — <expected result>
(3) Error case: <invalid input> — <expected error>
```
Not every task needs this — file creation, config changes, and simple scaffolding usually don't. Use judgment for anything involving logic, networking, auth, or external services.

**Verification type.** For each task, decide:
- `self-verify` — worker runs the verification steps and documents evidence in their summary (default for most tasks)
- `independent-review` — a reviewer profile must independently verify before the task is considered done (required for E2E tests, production deployments, auth/security, and any task where the worker needed 3+ runs)

For independent review tasks, create a companion reviewer task linked as a parent of any downstream work that depends on the verified output. See the `kanban-verification-gate` skill for the full discipline.

## Common patterns

**Fan-out + fan-in (research → synthesize):** N `researcher` tasks with no parents, one `analyst` task with all of them as parents.

**Pipeline with gates:** `pm → backend-eng → reviewer`. Each stage's `parents=[previous_task]`. Reviewer blocks or completes; if reviewer blocks, the operator unblocks with feedback and respawns.

**Agent lane pipeline:** `pm → claude-lane → reviewer`. For large coding tasks, the orchestrator assigns to `claude-lane` instead of `backend-eng`. The lane profile spawns Claude Code in an isolated worktree, reconciles the diff, and completes. Reviewer then gates the output. Same pattern for `agy-lane`.

**Same-profile queue:** 50 tasks, all assigned to `translator`, no dependencies between them. Dispatcher serializes — translator processes them in priority order, accumulating experience in their own memory.

**Human-in-the-loop:** Any task can `kanban_block()` to wait for input. Dispatcher respawns after `/unblock`. The comment thread carries the full context.

## User Communication Preferences

**Phased execution with explicit gates.** This user works in distinct phases: Research → Plan → Build. Do NOT skip ahead. After each phase completes, present the output and wait for explicit approval before starting the next phase. When the user says "don't create anything yet," they mean it — research only.

**Proactively notify on progress.** The user wants push notifications to their messaging platform (Telegram) for:
- Task completions (with summary of what was done and verification results)
- Phase completions (with full summary of the phase)
- Blockers encountered (immediately, with context)
- Before starting any large change (ask first)

Use `send_message` to `telegram:frostthejack` for notifications. Don't wait to be asked.

**Ask before large changes.** Explicit user instruction: "Take proper steps at each stage to ensure things are working before moving onto next steps and ask before making large changes." This means:
- Before changing architecture, tech stack, or major dependencies — STOP and ask
- Before making changes that affect other systems (migrating DB, changing providers) — STOP and ask
- Before making changes that would take >30 minutes to reverse — STOP and ask

**Verification is non-negotiable.** User said "Verify code works, verify nothing is broken. Do debug tests and everything."

**"Done" ≠ verified.** When the user asks "does it work?", don't trust the kanban status alone. Actually verify: check that built artifacts exist (binaries, installers), run the test suite, inspect the source, test the scripts. Workers may mark tasks done based on their own verification, but independent confirmation is essential — especially before declaring a project complete to the user.

**Cron-based board monitoring.** When the user wants ongoing updates on a kanban board, create a cron job that polls `hermes kanban --board <slug> list`, parses status counts, and sends a Telegram message only when there are actual changes (newly completed, newly running, or blocked tasks). Use `every 2h` as a default interval. Include the cron job ID in your reply so the user can manage it.

## Profile Assignment Guide

When creating kanban tasks, assign to the right profile for the work type:

| Profile | Best for | NOT for |
|---------|----------|---------|
| `backend-eng` | Writing/modifying backend code, implementing features, code refactors (direct Hermes implementation) | Running services, deployments |
| `frontend-eng` | UI code, React/Vue/CSS, client-side logic (direct Hermes implementation) | Backend APIs, infrastructure |
| `claude_lane` | Same as `claude-lane` — delegates to **Claude Code CLI** (`claude -p`). **Preferred active profile** for Claude Code delegation. New profiles need `.env` with `OPENROUTER_API_KEY` created BEFORE first dispatch. | Research, deployments, tasks requiring Hermes-native tool access |
| `claude-lane` | Backend/frontend coding tasks delegated to **Claude Code CLI** (`claude -p`). NOTE: may have stale credentials — prefer `claude_lane` for new tasks. | Research, deployments, tasks requiring Hermes-native tool access |
| `claude_lane` | Same as `claude-lane` — delegates to **Claude Code CLI** (`claude -p`). **Preferred active profile** for Claude Code delegation. | Research, deployments, tasks requiring Hermes-native tool access |
| `agy-lane` | Backend/frontend coding tasks delegated to **Antigravity CLI** (`agy -p`). Use for quick fixes, lower-latency needs, or when sandbox isolation is preferred. | Research, deployments, tasks requiring Hermes-native tool access |
| `ops` | Installing packages, service management, deployments, env config | Writing application code |
| `researcher` | Gathering information, reading sources, summarizing | Writing production code |
| `analyst` | Synthesizing findings, ranking, deduplication | Original research |
| `writer` | Drafting prose, documentation, specs | Code implementation |
| `reviewer` | Reviewing output, gating approval, quality checks | Original creation |
| `pm` | Writing specs, acceptance criteria, project planning | Implementation |

### Agent Lane Routing Rules

**When to use `claude-lane` or `agy-lane` instead of `backend-eng`/`frontend-eng`:**

1. **Task involves >3 files or >100 lines of estimated change** → assign to `claude_lane` (better multi-file coherence)
2. **Task is a well-scoped bug fix or feature with clear acceptance criteria** → assign to `agy-lane` (faster, lower latency)
3. **Task requires deep multi-step reasoning or architecture decisions** → assign to `claude_lane` (Opus-quality reasoning)
4. **Task needs sandbox isolation** → assign to `agy-lane` (OS-level sandbox)
5. **User explicitly requests agent delegation** → assign to the requested lane profile

**Note:** `claude_lane` (underscore) is the preferred/active Claude Code lane profile. `claude-lane` (hyphen) may have stale credentials from a previous key that was rate-limited. Use `claude_lane` for all new tasks.

**When to keep `backend-eng`/`frontend-eng`** (direct Hermes implementation):
- Small, focused changes (< 3 files, < 50 lines)
- Tasks requiring project-specific knowledge only the profile has
- Tasks where agent CLIs are not available
- Research/investigation tasks (not implementation)

**How lane profiles work:**
Lane profiles (`claude_lane`, `claude-lane`, `agy-lane`) are orchestrator profiles. When dispatched, they:
1. Create an isolated git worktree
2. Spawn the agent CLI (`claude -p` or `agy -p`) with the task as prompt
3. Reconcile the diff, run tests from Hermes
4. Complete the task with `agent_lane` metadata

**Configuring lane profiles:** Use `hermes -p <profile> config set` to configure model, provider, and API keys per profile. The kanban dispatcher reads credentials from the default credential file, so profile-specific credential files are NOT used by workers.

The `backend-eng` and `frontend-eng` profiles can also self-delegate to agent lanes for large tasks (their AGENTS.md includes a router section).

**Valid OpenRouter models**: Use `openrouter/owl-alpha` or similar valid OpenRouter model names. `@preset/logos-coder` and `@preset/coder` are NOT valid model names — they will cause 401 "Missing Authentication header" errors. To find valid models, check `~/.hermes/config.yaml` for the default model setting.

**OpenRouter API key**: Stored in the protected credential file at the Hermes home directory. The agent CANNOT modify this file — only the user can. If workers get 403 "budget limit exceeded" or 401 "Missing Authentication" errors, the user must update the key and restart the gateway. After a key change, the gateway process must be hard-killed (not just `hermes gateway restart`) to clear the cached key from memory.

**OpenRouter credential resolution order** (critical for debugging auth failures):
1. `os.environ["OPENROUTER_API_KEY"]` — set by `load_hermes_dotenv()` from `$HERMES_HOME/.env`
2. `config.yaml` `providers.openrouter.api_key` — NOT used by `resolve_provider_client` for OpenRouter
3. Credential pool (`auth.json`) — can override env var if `override_existing: true` in Bitwarden config

When `resolve_provider_client` fails, it checks `os.environ` — NOT `config.yaml`. If the `.env` file has the key commented out or is missing it, workers get 401 even though `config.yaml` has the correct key. The profile `.env` at `~/.hermes/profiles/<name>/.env` IS loaded when `HERMES_HOME` points to the profile directory.

**`redact_secrets: true`** masks API key values in gateway status display and request dumps. Seeing `(not set)` or `***` in logs does NOT mean the key is missing — it's actively redacted. To verify a key is actually set, test it directly with curl or check the raw `.env` file.

**Crash-loop rate limit risk**: When workers crash with auth errors in a loop (e.g., 79+ consecutive failures), the resulting flood of failed requests can trigger OpenRouter's abuse protection, temporarily blocking the key. Symptoms: ALL requests return 401 "Missing Authentication header" even from direct curl tests with the same key. Recovery: wait for the rate limit cooldown period or generate a new key. Before debugging code, always test the key directly with curl to rule out rate-limiting.

**Profile name synchronization**: When creating replacement profiles with different names (e.g., `claude_lane` vs `claude-lane`), update the specialist roster table and routing rules in this skill immediately. Mismatched names cause the orchestrator to assign tasks to non-existent profiles.

Do not default everything to `ops`. Using the wrong profile produces lower-quality work.

When in doubt about which profile fits, ask the user before creating the task.

### Profile Configuration (IMPORTANT)

**Each profile has its own config at `~/.hermes/profiles/<name>/config.yaml`.** Use `<profile-name> config set` (not `hermes config set`) to configure a specific profile:

```bash
# CORRECT: sets model for the claude-lane profile only
hermes -p claude-lane config set model.default '@preset/logos-coder'

# WRONG: sets model for the default profile, not the lane profile
hermes config set model.default '@preset/logos-coder'
```

**Profile-specific `.env` files** at `~/.hermes/profiles/<name>/.env` ARE read by worker processes (via `load_hermes_dotenv()` when `HERMES_HOME` is set to the profile directory). The worker's `_try_openrouter()` function reads `OPENROUTER_API_KEY` from `os.environ` — it does NOT read `config.yaml` provider settings. Every worker profile MUST have its own `.env` with the full unmasked key. See `references/profile-credential-resolution.md` for full details.

**OpenRouter key resolution** (from `credential_pool.py`):
1. `~/.hermes/.env` (highest precedence — always wins)
2. `os.environ` environment variables
3. `config.yaml` provider settings (NOT used for OpenRouter credentials)

If workers get HTTP 403 "budget limit exceeded":
1. Update `OPENROUTER_API_KEY` in `~/.hermes/.env`
2. Restart the gateway: `hermes gateway restart`
3. Re-dispatch: `hermes kanban --board <slug> dispatch`

See `references/openrouter-auth-debugging.md` for the full credential resolution debugging guide, rate-limit cascade patterns, and common misdiagnosis traps.

## Pitfalls

**Reassignment vs. new task.** If a reviewer blocks with "needs changes," create a NEW task linked from the reviewer's task — don't re-run the same task with a stern look. The new task is assigned to the original implementer profile.

**Decompose the actual work, not just the profiles.** Creating specialist profiles is setup, not decomposition. The real task is breaking the project plan into small, assignable tasks on the board. After creating profiles, immediately create the first batch of tasks with proper assignees, descriptions, and parent dependencies. Never end a "setup kanban" session with only profiles and no tasks. If the session is interrupted by a blocker (e.g., service down, user unavailable), explicitly flag the pending decomposition as the next step and resume it at the earliest opportunity.

**Creative asset quality.** When delegating creative work (SVGs, images, icons), detailed visual specifications in the task body are essential. Vague descriptions like "create an SVG of X" produce generic output. Include: art style, specific elements required (gradients, shadows, facial features), reference examples, technical requirements (viewBox, color palette), and a quality checklist. Before delegating, search for existing high-quality assets that can be adapted (OpenClipart, Wikimedia Commons, SVGRepo). See `references/creative-asset-quality.md` for the full lesson.

**Task completion ≠ working software.** Workers can mark tasks done based on their own verification. When the user asks "does it work?", you MUST independently verify: check that built artifacts exist (binaries, installers), run test suites, inspect source code quality, and test integration scripts. Never declare a project working based solely on kanban status. This is especially critical for multi-phase projects where each phase builds on the previous one.

**Supabase Realtime postgres_changes subscription.** When using `supabase.channel(name)` with `postgres_changes` listeners in a React hook, you MUST use a unique channel name per hook instance (e.g., append `crypto.randomUUID()`). `supabase.channel(name)` returns the same internal channel object for the same name — even after `removeChannel()`. If the effect re-runs (React strict mode double-mount, sessionId change, multiple components), the second call gets an already-subscribed channel and `.on("postgres_changes")` throws "cannot add postgres_changes callbacks after subscribe()". See `references/supabase-realtime-postgres-changes.md` for the full fix pattern and failed approaches.

**Orchestrator executed work directly (protocol violation).** If you find yourself writing code, running git commit, or pushing fixes directly instead of creating kanban tasks — STOP. The user explicitly wants work routed through kanban with subagent delegation and self-verification. Even if the fix is trivial or you've already written it, create the task, assign it to the right profile, and let the dispatcher handle it. The only exception is when the orchestrator role is specifically acting as a worker (e.g., during initial board setup or research phases).

**Task completion discipline.** When you create tasks on a board, use `kanban_show` or `hermes kanban list` to verify they exist and are in the expected state (ready/done/blocked). Do not assume creation succeeded because the command returned without error. If a task has dependencies, verify the parent links were created correctly with `kanban_link`.

**Argument order for links.** `kanban_link(parent_id=..., child_id=...)` — parent first. Mixing them up demotes the wrong task to `todo`.

**No CLI for deleting links.** `hermes kanban link` has no `--delete` or `unlink` subcommand. To remove an incorrect parent link, you must use direct SQLite:
```python
import sqlite3
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()
c.execute("DELETE FROM task_links WHERE child_id=? AND parent_id=?", ('t_<child>', 't_<parent>'))
conn.commit()
conn.close()
```
The table is `task_links` (not `task_parents`). Always verify with `SELECT parent_id FROM task_links WHERE child_id=?` after deleting.

**Worker crash from rate limits.** When multiple workers crash simultaneously with `pid not alive`, check the worker logs for HTTP 429 rate limit errors. If the profile model is rate-limited, switch to an available model and reset blocked tasks. See `references/worker-crash-rate-limit-diagnosis.md` for the full diagnostic and fix procedure.

**Worker crash from wrong workspace.** When workers crash immediately (within seconds) with `pid not alive`, check the task workspace. If `workspace_kind='scratch'` but the task involves project source code, the worker has no source to work with and will fail. Fix: update `workspace_kind='worktree'` and `workspace_path` to `$PROJECTS_ROOT/<project>/.worktrees/<task-id>`. Always use `worktree` workspace for coding tasks — `scratch` is only for transient data/research.

**Dispatcher dispatch flow: todo → ready → running.** When `hermes kanban create` is used, the task lands in `todo` status. The dispatcher does NOT pick up `todo` tasks — they must be in `ready`. After creating a code task, always set it to `ready` via SQLite:
```python
c.execute("UPDATE tasks SET status='ready' WHERE id=?", (task_id,))
```
Then trigger dispatch with `hermes kanban --board <slug> dispatch`. The dispatcher will promote `ready` → `running` and spawn a worker. Verify with `hermes kanban --board <slug> show <id>`.

**Profile blocked-task backoff blocks ALL tasks for that profile.** When a profile has a blocked task with many consecutive failures (e.g., 10+ crashes), the dispatcher may throttle the entire profile — even new tasks in `ready` won't be spawned. Fix: archive the old blocked task:
```python
c.execute("UPDATE tasks SET status='archived' WHERE id=?", (blocked_task_id,))
```
Then reset the new task to `ready` and re-dispatch. This is why re-dispatching the same blocked task repeatedly never works — the profile itself is in a backoff state.

**Workspace path must point to the PROJECT directory, not the upstream code source.** When a project modifies code that lives inside another repo (e.g., adding slash commands to hermes-agent's `discord.py`), the workspace MUST still be `worktree` rooted at the project's own canonical directory (`/mnt/c/Users/<user>/Documents/Projects/<project-name>/`), NOT the upstream repo (`/home/<user>/.hermes/hermes-agent/`). The project directory contains symlinks (`src/`, `docs/`, `project-state.md`) that provide access to the real code. Workers need the project directory context. Never default to the upstream repo path — always use the project's own canonical path. If the project directory doesn't exist yet, create it first (coding lifecycle skill Phase 0).

**Cron job Vercel/Supabase monitoring.** When creating cron jobs that monitor Vercel deployments or Supabase health, the CLI commands may be blocked by security scans. Use the Vercel REST API via Python scripts (no pipes) and fetch Supabase keys from the Vercel API or app health endpoints. See `references/cron-vercel-supabase-monitoring.md` for the full patterns.

See `references/stale-task-replacement-pattern.md` for the workflow of replacing blocked tasks with fresh ones (verify stale → create replacement → link parent → fix workspace → verify dispatch).

See `references/board-health-diagnostics.md` for scratch workspace crash patterns and stale task detection.

**Worktree cleanup after merge.** When a coding task's worktree branch has been merged (via PR or cherry-pick), clean up the worktree to avoid disk accumulation:

```bash
cd $PROJECTS_ROOT/<project-name>/
git worktree remove .worktrees/<task-id>
git branch -D kanban/<task-id>
```

The Active Board Watcher should also include worktree cleanup in its health checks. Orphaned worktrees should be removed after merge confirmation. Run `git worktree prune` periodically to clean up stale references.

## Worker Concurrency Limits

The kanban dispatcher has two settings that control how many workers run simultaneously:

| Setting | Where | Default | Effect |
|---|---|---|---|
| `max_spawn` | API query param (`/api/dispatch?max=N`) | 8 | Live concurrency cap — max workers running at any time across the whole board |
| `max_in_progress` | `dispatch_once()` parameter | None (unlimited) | If set, dispatcher skips spawning when running tasks ≥ this value |

**Config.yaml integration is available.** To limit concurrency:

- **Persistent limit**: Add `max_spawn` to the kanban config section in `~/.hermes/config.yaml`:
  ```yaml
  kanban:
    max_spawn: 1
  ```
  Then restart the gateway. The gateway reads this natively — no patching required. See `references/kanban-worker-concurrency-limits.md` for full details.
- **Per-dispatch call**: `curl -s http://127.0.0.1:9119/api/dispatch?max=1` — spawns at most 1 worker this tick.

**Why this matters**: On rate-limited providers (OpenRouter free tier, etc.), spawning 8 concurrent workers can trigger 429 errors across the board. Limiting to 1-2 workers prevents cascading failures.

See `references/kanban-worker-concurrency-limits.md` for full details.

## Recovering stuck workers

When a worker profile keeps crashing, hallucinating, or getting blocked by its own mistakes (usually: wrong model, missing skill, broken credential), the kanban dashboard flags the task with a ⚠ badge and opens a **Recovery** section in the drawer. Three primary actions:

1. **Reclaim** (or `hermes kanban reclaim <task_id>`) — abort the running worker immediately and reset the task to `ready`. The existing claim TTL is ~15 min; this is the fast path out.
2. **Reassign** (or `hermes kanban reassign <task_id> <new-profile> --reclaim`) — switch the task to a different profile and let the dispatcher pick it up with a fresh worker.
3. **Change profile model** — the dashboard prints a copy-paste hint for `hermes -p <profile> model` since profile config lives on disk; edit it in a terminal, then Reclaim to retry with the new model.

Hallucination warnings appear on tasks where a worker's `kanban_complete(created_cards=[...])` claim included card ids that don't exist or weren't created by the worker's profile (the gate blocks the completion), or where the free-form summary references `t_<hex>` ids that don't resolve (advisory prose scan, non-blocking). Both produce audit events that persist even after recovery actions — the trail stays for debugging.

### Protocol violation recovery (bulk reset)

When multiple tasks are blocked due to protocol violations (workers exiting rc=0 without calling `kanban_complete`/`kanban_block`), you can bulk-reset them via the SQLite DB:

```python
import sqlite3, time
conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
c = conn.cursor()

blocked_tasks = ['t_<id1>', 't_<id2>', 't_<id3>']
for task_id in blocked_tasks:
    c.execute("UPDATE tasks SET status='ready', claim_lock=NULL, claim_expires=NULL, worker_pid=NULL, current_run_id=NULL, consecutive_failures=0, last_failure_error=NULL WHERE id=?", (task_id,))
    c.execute("INSERT INTO task_events (task_id, run_id, kind, payload, created_at) VALUES (?, NULL, 'unblocked', ?, ?)", (task_id, '{"reason": "manual unblock"}', int(time.time())))
conn.commit()
conn.close()
```

After reset, the dispatcher will automatically pick up the tasks on its next tick (~60s). Verify with `hermes kanban list`.

**Important:** Before bulk-resetting, check the worker logs (`~/.hermes/kanban/boards/<slug>/logs/<task_id>.log`) to understand why they crashed. If the root cause isn't fixed (e.g., API stream drops, token limits), the same crashes will repeat. See the `kanban-worker` skill's "Worker Crash / Protocol Violation Pattern" section for prevention strategies.

**Phantom blocked tasks (implemented but marked blocked).** When multiple tasks are blocked with `consecutive_failures=1` and `last_failure_error` contains "protocol violation" or "exited cleanly", the workers may have actually completed the work but exited before calling `kanban_complete`. Before resetting these tasks to `ready`, verify whether the implementation already exists:

```bash
# Check if the feature/command is already in the code
grep -n "async def slash_<command>" /path/to/project/file.py
# Or for general code tasks, check if the expected files exist and contain real code
```

If the implementation exists and is substantive (not stubs), **mark the task as done** instead of resetting to ready:
```python
c.execute("UPDATE tasks SET status='done', consecutive_failures=0, last_failure_error=NULL WHERE id=?", (task_id,))
```

If the implementation is missing or incomplete, reset to `ready` with workspace fix and retry. See `references/board-health-diagnostics.md` for the full "Phantom Blocked" pattern.

**`max_retries=None` defaults to 2.** When a task is created without an explicit `max_retries` value, the database stores `None`, which the dispatcher treats as 2. After 2 consecutive failures, the task becomes `blocked` (not `ready`). When resetting blocked tasks, always set `max_retries` to an explicit value (e.g., 3) to avoid immediately hitting the limit again.

See `references/dispatch-patterns.md` for the full dispatch flow, profile backoff patterns, and worker crash loop diagnosis.

## Reference decompositions

See `references/kanban-profile-setup-with-hindsight-banks.md` for the full profile creation + hindsight bank isolation workflow (creating profiles, configuring per-profile `hindsight/config.json`, bank-to-profile mapping, and verification).

See `references/rollsiege-decomposition-example.md` for a real-world example of decomposing a full project build plan (54 tasks, 6 phases) into a kanban board with parent dependencies.

See `references/verification-review-decomposition.md` for the pattern for decomposing "verify everything works" requests into parallel review tracks with PM triage fan-in.

See `references/agent-persona-decomposition-example.md` for a real-world example of a 20-task, 5-phase project decomposition (Agent Persona screen pet) with rich verification criteria on every task, plus a bug fix cycle log and lessons learned.

See `references/tauri-desktop-pitfalls.md` for Tauri-specific window architecture, threading, tray communication, port configuration, and animation pitfalls discovered through the Agent Persona project.

See `references/supabase-email-redirect.md` for the Supabase email confirmation redirect URL pitfall and fix pattern.

See `references/cron-vercel-supabase-monitoring.md` for Vercel API and Supabase health check patterns in cron jobs.

See `references/emoji-escaped-unicode.md` for the emoji rendering as escaped Unicode strings issue and fix pattern.

See `references/supabase-realtime-postgres-changes.md` for the Supabase Realtime postgres_changes "cannot add callbacks after subscribe" error and the module-level channel cache fix pattern.

See `references/cron-job-patterns.md` for cron job monitoring patterns, delivery target configuration, and common mistakes.

See `references/creative-asset-quality.md` for guidance on delegating creative work (SVGs, images, icons) with sufficient detail to avoid generic output.

See `references/discord-duplicate-slash-command-fix.md` for the Discord platform duplicate slash command registration fix (duplicate `@tree.command()` decorators in `discord.py`).

See `references/kanban-worker-concurrency-limits.md` for worker concurrency limit configuration (`max_spawn`, `max_in_progress`).
