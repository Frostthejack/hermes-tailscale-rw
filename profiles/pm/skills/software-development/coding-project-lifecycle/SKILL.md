---
name: coding-project-lifecycle
description: End-to-end lifecycle management for coding projects — from repo creation through phased execution with kanban delegation, review gates, and continuous monitoring. This is the orchestration layer that ties together project-management, kanban-orchestrator, writing-plans, and subagent-driven-development into a single repeatable flow.
version: 1.7.0
triggers:
  - start a coding project
  - new coding project
  - begin project
  - project lifecycle
  - coding project
  - start building
  - kick off project
  - create project repo
metadata:
  hermes:
    tags: [project-lifecycle, coding, kanban, orchestration, delegation, review-gates]
    related_skills: [project-management, kanban-orchestrator, kanban-worker, kanban-verification-gate, writing-plans, subagent-driven-development, test-driven-development, requesting-code-review, agent-lane, claude-code, antigravity-cli]
---

# Coding Project Lifecycle

> Orchestration layer that ties together project-management, kanban, planning, and subagent-driven development into a single repeatable flow for coding projects.

**Core principle:** Research → Plan → Build in strict phases. No phase progression without passing review. **Always test and verify the current phase before moving to the next.** Route work through kanban when tasks are parallelizable; execute directly only for sequential scaffolding/setup (Phase 0, initial project structure).

**Verification non-negotiable:** The user expects working software at every phase boundary. For desktop apps (Tauri/Electron), this means: build passes, EXE launches, process stays running, window appears, memory is reasonable, clean shutdown works. For web apps: build passes, dev server starts, pages render, no console errors. For Android apps: Gradle sync succeeds, `./gradlew assembleDebug` passes, APK installs and launches on device/emulator. Never declare a phase complete without running the verification sequence. See `references/tauri-verify-launch.md` for the Tauri-specific checklist. See `references/android-build-pitfalls.md` for Android-specific build issues.

## When to Use

Use this skill when the user wants to **start a new coding project** or **manage an existing one through a build phase**. Specifically:

- User says "let's build X" or "start coding project Y"
- Research is already done and an initial plan exists
- User wants structured execution with kanban delegation
- User wants review gates between phases

**Prerequisites before starting:**
1. Research phase is complete (user has provided or approved the concept)
2. Initial high-level plan exists (even rough is fine)
3. User has approved moving to the build phase

If research isn't done, stop and do research first. If no plan exists, create one with `writing-plans` before proceeding.

---

## Canonical Project Directory Convention

**All coding project files MUST live in a single, well-known location.** Agents must NEVER create project work in `/tmp`, `/scratch`, or any temporary/ad-hoc directory. Scattered project files are the #1 cause of lost work and agent confusion.

### Directory Layout

```
<PROJECTS_ROOT>/<project-name>/          ← All code lives here (the repo root)
  ├── src/                               ← Source code
  ├── docs/                              ← Symlink → vault project docs directory
  ├── project-state.md                   ← Symlink → vault project-state.md
  ├── docs/plans/                        ← Phase plan documents (in repo)
  └── .git/                              ← Git repository

<vault-path>/Projects/Personal/<project-name>/  ← Obsidian vault (docs only)
  └── project-state.md                   ← Source of truth for project state
```

### Detecting PROJECTS_ROOT

The projects root is environment-specific. Detect it dynamically:

```bash
# Option 1: Check if a Projects directory exists under the user's Windows profile
ls /mnt/c/Users/*/Documents/Projects/ 2>/dev/null

# Option 2: Check a known project location
ls /mnt/c/Users/*/Documents/Projects/ 2>/dev/null || \
ls ~/projects/ 2>/dev/null || \
ls ~/Documents/Projects/ 2>/dev/null

# Option 3: Ask the user — "Where should coding projects live?"
```

> **For this environment:** `PROJECTS_ROOT = /mnt/c/Users/luned/Documents/Projects/`

### Symlink Setup (Required in Phase 0)

During Phase 0, create symlinks so that agents working in the code directory always have immediate access to project docs:

```bash
# Create the vault directory for this project
mkdir -p <vault-path>/Projects/Personal/<project-name>/

# Create symlinks in the project repo
cd <PROJECTS_ROOT>/<project-name>/

# Symlink project-state.md
ln -sf <vault-path>/Projects/Personal/<project-name>/project-state.md project-state.md

# Symlink docs directory (if vault has additional docs beyond project-state.md)
# IMPORTANT: If docs/ already exists as a real directory, remove it first:
rm -rf docs
ln -sf <vault-path>/Projects/Personal/<project-name>/ docs
```

> **Edge case — docs/ already exists as a real directory:** If `docs/` is a real directory (not a symlink), `ln -sf` will create the symlink *inside* it instead of replacing it. Always `rm -rf docs` first, then `ln -sf`. Verify with `ls -la docs` — it should show `docs -> <vault-path>`, not `docs/` as a directory.

**Why symlinks:** When an agent picks up a kanban task, it works in `<PROJECTS_ROOT>/<project-name>/`. With symlinks, `project-state.md` and `docs/` are right there — no searching, no guessing, no "where is the project state?" confusion. The vault remains the single source of truth; symlinks just provide local access.

### Agent Directive

**Every kanban task MUST specify the working directory:**

```
WORKING DIRECTORY: $PROJECTS_ROOT/<project-name>/
```

Agents must `cd` to this directory before doing any work. No exceptions. If an agent cannot find the project directory, it must STOP and ask — not improvise a temp location.

---

## Existing Project Detection & Resume (CRITICAL)

**Before doing anything else, determine if this is a new or existing project.** An agent loading this skill on an already-active project must NOT re-run Phase 0 or recreate infrastructure.

### Step 0: Load Global Context (MANDATORY)

Before any project work, load the global context:

1. **Read HERMES.md:** `read_file("~/.hermes/HERMES.md")` — contains project index, memory architecture, active project table
2. **Read project info:** `read_file("~/.hermes/projects/info/<project-name>.md")` — contains operational details for this specific project
3. **If project-state.md exists in the code repo** (as a symlink), read the vault version directly instead

These files are the authoritative source for project details. Do NOT rely on MEMORY.md for project-specific information.

### Step 0.5: Detect Existing Project

Run these checks **in order** before any other action:

```bash
# 0. Detect PROJECTS_ROOT (canonical code location)
# Try common patterns in order:
PROJECTS_ROOT=""
for try in \
  /mnt/c/Users/*/Documents/Projects \
  "$HOME/projects" \
  "$HOME/Documents/Projects" \
  /mnt/c/Users/*/Projects; do
  if ls "$try" >/dev/null 2>&1; then
    PROJECTS_ROOT="$try"
    break
  fi
done
echo "PROJECTS_ROOT=$PROJECTS_ROOT"

# 1. Check if project directory exists at canonical location
ls $PROJECTS_ROOT/<project-name>/.git 2>/dev/null

# 2. Check if project-state.md exists in the vault (always under Personal)
# NOTE: Vault path is environment-specific. Detect it dynamically:
#   - Check ~/.hermes/config.yaml for vault path
#   - Or ask the user where their vault is located
#   - Common patterns:
#     /mnt/c/Users/<user>/Vault/<vault-name>/Projects/Personal/<project-name>/project-state.md
#     ~/vault/Projects/Personal/<project-name>/project-state.md
ls <vault-path>/Projects/Personal/<project-name>/project-state.md 2>/dev/null

# 3. Check if GitHub repo exists
gh repo view <github-user>/<project-name> 2>/dev/null

# 4. Check if local repo exists and has commits
git -C $PROJECTS_ROOT/<project-name> log --oneline -1 2>/dev/null

# 5. Check if kanban board exists
hermes kanban boards list 2>/dev/null | grep <project-slug>

# 6. Check for active cron jobs related to this project
hermes cron list 2>/dev/null | grep <project-name>
```

### Decision Matrix

| Check | Result | Action |
|-------|--------|--------|
| Project dir at canonical path | Found | This is the working directory. Do NOT use any other location. |
| Project dir NOT at canonical path | Not found | Clone/create it at `$PROJECTS_ROOT/<project-name>/` |
| project-state.md exists | Found | Read it. This is the source of truth for current state. |
| project-state.md missing | Not found | This may be a new project — proceed to Phase 0. |
| GitHub repo exists | Found | Do NOT recreate. Clone to canonical path if needed. |
| GitHub repo missing | Not found | Create it (Phase 0.1). Clone to canonical path. |
| Kanban board exists | Found | Do NOT recreate. Read current board state. |
| Kanban board missing | Not found | Create it (Phase 0.4). |
| Cron jobs exist | Found | Do NOT duplicate. Verify they're still running. |
| Cron jobs missing | Not found | Create them (Phase 0.5 / Phase 4). |

### Resume Flow (Existing Project Detected)

When the project already exists, follow this flow instead of Phase 0:

0. **Run hindsight recall + retain** — BEFORE reading project files, pull retained context from previous sessions:
   ```bash
   # Check hindsight health
   curl -s http://localhost:8888/health
   # Recall project memories
   curl -s -X POST http://localhost:8888/v1/default/banks/hermes/memories/recall \
     -H "Content-Type: application/json" \
     -d '{"query": "<project-name> bugs deployment issues", "budget": "high"}'
   ```
   After completing the session (or before context compaction), retain what you learned:
   ```bash
   curl -s -X POST http://localhost:8888/v1/default/banks/hermes/memories \
     -H "Content-Type: application/json" \
     -d '{"items": [{"content": "<session summary>", "tags": ["<project>", "orchestrator"], "type": "observation"}]}'
   ```
   > **IMPORTANT:** The hindsight API uses REST endpoints, NOT `hindsight_retain()` function calls. The retain endpoint is `POST /v1/default/banks/{bank_id}/memories` with body `{"items": [{content, tags, type}]}`. See `references/hindsight-api-patterns.md` for full details.
   >
   > **If hindsight times out:** Write retention to `~/.hermes/pending-retention/<project>-<date>.md` and retain in the next session. Don't skip it.

1. **Read project-state.md** — Understand current state, what's done, what's in progress, known issues
2. **Read kanban board** — `hermes kanban --board <slug> list` — see what tasks are done/in-progress/blocked/ready
3. **Verify "done" tasks actually have implementations** — For every task marked "done", read the expected source files and confirm the code exists and is functional. Do NOT trust kanban status alone. Reset any phantom "done" tasks to "ready" before proceeding.
4. **Verify all imports resolve** — Run `npx tsc --noEmit` (or equivalent) to check that every `import` in recently committed files resolves to an actual file on disk. Workers frequently add `import` statements for components/files that don't exist. A single missing component file (e.g., `GameSettingsModal.tsx` imported but never created) will break every Vercel deployment. Check specifically: (1) every `import` in newly committed files resolves to an actual file, (2) no `Module not found` errors exist.
5. **Determine current phase** — Based on verified task completion (not kanban labels), project-state.md, and git log
6. **Identify the next action:**
   - If a phase is **in progress** → Continue monitoring (Phase 3). Do NOT re-decompose tasks that already exist.
   - If a phase is **complete but review hasn't passed** → Ensure a reviewer task exists and is being worked
   - If a phase **review passed** and next phase hasn't been decomposed → Decompose next phase (Phase 2)
   - If all phases are complete → Project is done. Update project-state.md.
7. **Verify infrastructure** — Ensure cron jobs are running, board is active, vault is up to date
8. **Report status to user** — "Project X is in Phase N. Y tasks done, Z in progress, W remaining. Next: [specific next step]."

### External Project Evaluation (Research Integration)

When the user asks you to evaluate an external project/repo for potential integration into the current project:

1. **Research the repo** — Use `web_extract` on the GitHub URL and raw README. Use `web_search` for additional context.
2. **Produce a structured research document** — Save to `docs/research/<project-name>-analysis.md` with these sections:
   - **What It Is** — Summary, license, language, version
   - **Architecture** — Diagram + key technical details (IPC, rendering, event flow)
   - **Comparison Table** — Side-by-side with current project's approach
   - **Integration Opportunities** — Specific points where the external project's patterns could enhance the current project (labeled A, B, C...)
   - **Recommendations** — What to borrow, what to skip, and why
   - **Suggested Next Steps** — Concrete Phase N+1 candidates informed by the research
3. **Create a kanban research task** — Track the evaluation as a task assigned to `reviewer`
4. **Link research to decomposition** — Use the research findings to inform the next phase's task breakdown

**Key principle:** The research doc is the deliverable. The kanban task tracks it. The decomposition uses it. Don't skip the doc and jump straight to "should we use this?"

**Where to save research docs:** Always write to the **vault** project directory, NOT the code repo. The code repo's `docs/` is a symlink to the vault — writing to the repo's `docs/research/` creates a real file that will be lost when the symlink is set up or repaired. Write directly to `<vault-path>/Projects/Personal/<project-name>/research/<filename>.md`, then commit the vault repo.

**Reference:** See `references/hermes-visualizer-mood-mapping.md` for a concrete example of activity-to-state mapping from the hermes-visualizer-plugin evaluation.

### Context Compression Recovery

When the user asks for context compression ("do a context compression and start over") or when recovering from a compacted context:

1. **Run hindsight recall** (Step 0 above) — pull retained memories FIRST
2. **Run detection matrix** (Step 0: Detect Existing Project) — confirm project location and state
3. **Read project-state.md** — get current state from vault
4. **Read kanban board** — get current task status
5. **Resume from the last known state** — do NOT re-do work that was already completed

> **Key principle:** Context compaction loses the conversation but NOT the project state. The vault (project-state.md), kanban board, git log, and hindsight memories are the recovery sources. Always check all four before resuming work.

### What NOT to Do on an Existing Project

- **Do NOT recreate the GitHub repo** — check `gh repo view` first
- **Do NOT recreate the kanban board** — check `hermes kanban boards list` first
- **Do NOT recreate project-state.md** — read the existing one and update it
- **Do NOT recreate cron jobs** — check `hermes cron list` first, verify they're running
- **Do NOT re-decompose tasks that already exist on the board** — only decompose the NEXT phase
- **Do NOT reset task statuses** — respect the current state of the board
- **Do NOT start from Phase 0** unless ALL checks fail (truly a new project)

### Edge Cases

**Partial infrastructure:** Some things exist, some don't. Example: repo exists but no kanban board. In this case, only create what's missing. Always check each piece independently.

**Board slug ≠ project name:** The kanban board slug (e.g., `discord`) may not match the actual project name (e.g., `discord-osint`). Always ask the user to confirm the project name if it's not obvious from the board name. The project directory should be `$PROJECTS_ROOT/<project-name>/`, NOT derived from the board slug. Run the detection matrix to find or create the correct project directory. If the user says "the project is X" and the board slug is different, use X as the project name.

**Symlinks break git operations:** When `docs/` is a symlink to the vault, running `git add docs/plans/` from the repo fails with "pathspec is beyond a symbolic link." Git cannot traverse symlinks to external directories. To commit plan documents: (1) save files directly to the vault directory, (2) `cd` to the vault directory, (3) `git add` and `git commit` from there. Alternatively, maintain a real `docs/plans/` directory in the repo alongside the symlink for vault access.

**Stale project-state.md:** If the file exists but hasn't been updated recently, cross-reference with the actual kanban board state and git log. Update the file to reflect reality before proceeding.

**Board exists but empty:** If the board was created but no tasks were ever added, check with the user before decomposing. The project may have been abandoned or the board may be a leftover from a previous attempt.

**Tasks exist but all are done/archived:** The project may be complete. Verify with the user before starting new work.

### Project Directory Cleanup (Hygiene Remediation)

When resuming an existing project, the canonical directory may have accumulated junk files from previous debugging sessions. Clean these up **before** decomposing new work.

**Common junk patterns to remove:**
- One-off debug scripts: `check_*.py`, `fix_*.py`, `verify_*.py`, `deploy_*.py`, `trigger_*.py`, `test_*.py`, `update_*.py`, `get_*.py`, `list_*.py`, `debug_*.py`
- Shell scripts for one-off operations: `trigger_*.sh`, `verify-*.sh`
- Env/token dumps: `.vercel_token`, `env_response.json`, `db_url.txt`, `*.env.production`
- Backup files: `*.bak` anywhere in the repo
- Orphan directories: `home/`, `repo/`, `supabase/.temp/`, `workspace_*/`
- Workspace files that shouldn't be in the repo: `AGENTS.md`, `CLAUDE.md`
- Duplicate nested directories (e.g., `prisma/prisma/`)

**Safe cleanup procedure:**
```bash
cd $PROJECTS_ROOT/<project-name>/

# Preview what will be deleted (dry run)
find . -maxdepth 1 -name "check_*.py" -o -name "fix_*.py" -o -name "verify_*.py" \
  -o -name "deploy_*.py" -o -name "trigger_*.py" -o -name "test_*.py" \
  -o -name "update_*.py" -o -name "get_*.py" -o -name "list_*.py" \
  -o -name "debug_*.py" -o -name "AGENTS.md" -o -name "CLAUDE.md" \
  -o -name ".vercel_token" -o -name "db_url.txt" -o -name "env_response.json"

# Delete confirmed junk
rm -f check_*.py fix_*.py verify_*.py deploy_*.py trigger_*.py test_*.py \
      update_*.py get_*.py list_*.py debug_*.py AGENTS.md CLAUDE.md \
      .vercel_token db_url.txt env_response.json

# Remove orphan directories
rm -rf home/ repo/ supabase/.temp/

# Remove .bak files (but NOT from node_modules or .git)
find . -name "*.bak" -not -path "./node_modules/*" -not -path "./.git/*" -delete

# Remove duplicate nested directories
rm -rf prisma/prisma/  # if it exists

# Commit the cleanup
git add -A
git commit -m "chore: clean up debug/scratch scripts and junk files"
git push origin main
```

> **Safety rule:** Never delete `.env.local`, `.env`, `.gitignore`, `src/`, `prisma/`, `public/`, `e2e/`, `docs/` (symlink), `project-state.md` (symlink), or any config file you're unsure about. When in doubt, ask the user.

---

## The Full Lifecycle

```
Phase 0: Project Initiation     ← Orchestrator executes directly
Phase 1: Phase Planning         ← Orchestrator + PM profile
Phase 2: Task Decomposition     ← Orchestrator (kanban-orchestrator skill)
Phase 3: Execution              ← Dispatcher + Subagent Workers
Phase 4: Continuous Monitoring  ← Cron jobs + /goal watcher
```

---

## Phase 0: Project Initiation

**Who:** Orchestrator executes these steps directly (not delegated — this is setup).

### Step 0.1: Create GitHub Repository

```bash
# Create the repo (use the actual GitHub username, not hardcoded)
gh repo create <github-user>/<project-name> --public --description "<description>" --clone

# Or for private:
gh repo create <github-user>/<project-name> --private --description "<description>" --clone

# If using a template repo:
gh repo create <github-user>/<project-name> --template <template-repo> --clone
```

Set up the initial structure at the **canonical project path**:
```bash
# Ensure PROJECTS_ROOT exists
mkdir -p $PROJECTS_ROOT

# Clone to canonical path (if not already cloned by gh)
cd $PROJECTS_ROOT
gh repo clone <github-user>/<project-name> 2>/dev/null || true
cd <project-name>

# Initial commit
git add -A
git commit -m "feat: initial project scaffold"
git push origin main
```

> **IMPORTANT:** The project MUST be at `$PROJECTS_ROOT/<project-name>/`. Do NOT clone to `~/`, `/tmp/`, or any other location.

**Verify:** `gh repo view <github-user>/<project-name>` shows the repo exists and is not empty.

### Step 0.2: Set Up Local Development Environment

```bash
# Ensure we're at the canonical path
cd $PROJECTS_ROOT/<project-name>

# Install dependencies (adapt to project type)
# Node: npm install / pnpm install
# Python: pip install -r requirements.txt / poetry install
# Rust: cargo build
# Android: ./gradlew assembleDebug (from Windows, not WSL2 — see android-build-pitfalls.md)
# etc.

# Verify the project builds/runs
# npm run build / cargo build / python -m pytest --co / etc.
```

**Verify:** The project builds without errors. A fresh clone + install + build works.

### Step 0.3: Create project-state.md in the Vault + Set Up Symlinks

Create the file at:
```
<vault-path>/Projects/Personal/<Project>/project-state.md
```

> **Category is always `Personal`** for projects managed by this skill. Do NOT use `Work` or any other category.

**To create from the template:**
1. Copy the template from the vault: `<vault-path>/Templates/Project State Template.md`
2. Place it at the path above
3. Fill in all sections

Use the template from the `project-management` skill for the full structure. **Critical sections:**

- **Secrets / Environment Variables** — ALL API keys, tokens, env vars go here. This is the single source of truth. Format:
  ```markdown
  ## Secrets & Environment Variables
  
  | Variable | Value | Location |
  |----------|-------|----------|
  | `API_KEY` | `sk-xxx...` | `.env.local` |
  | `DATABASE_URL` | `postgres://...` | Vercel env vars |
  ```
  
  > **Security note:** This file is in a private git vault. Never commit secrets to the project repo itself.

- **Repo URL** — Link to GitHub repo
- **Local dev instructions** — Exact commands to run locally
- **Tech Stack** — Filled in from the plan
- **Canonical Path** — `$PROJECTS_ROOT/<project-name>/`

**Set up symlinks (CRITICAL — do not skip):**
```bash
cd $PROJECTS_ROOT/<project-name>/

# Symlink project-state.md from vault
ln -sf <vault-path>/Projects/Personal/<project-name>/project-state.md project-state.md

# Symlink docs directory from vault (if it has more than just project-state.md)
ln -sf <vault-path>/Projects/Personal/<project-name>/ docs
```

> **Why:** Every agent that picks up a kanban task will work in `$PROJECTS_ROOT/<project-name>/`. Symlinks ensure `project-state.md` and `docs/` are always locally accessible — no searching, no confusion.

**Commit and push the vault:**
```bash
cd <vault-path>
git add -A
git commit -m "feat: add project-state.md and symlinks for <project-name>"
git push origin Main
```

### Step 0.4: Create Kanban Board

**Check first** — the board may already exist from a previous session (see detection matrix Step 0 check 5). If it does, `hermes kanban boards create` will return "already exists" and switch to it. This is fine — just verify.

```bash
# Create the board (or switch to existing)
hermes kanban boards create <project-slug> --name "<Project Name>" --switch

# Verify
hermes kanban boards show
hermes kanban --board <project-slug> list
```

The board slug should be a short lowercase identifier (e.g., `rollsiege`, `agent-persona`).

### Step 0.5: Set Up Cron Jobs

Set up **two** standing cron jobs for the project: a lightweight Kanban Watcher (frequent, reports changes) and an Active Board Watcher (less frequent, fixes issues automatically).

#### Job 1: Kanban Watcher (every 5 min)

Lightweight — checks board status and reports changes. Stays quiet when nothing changed.

Use the `cronjob` tool to create:

```
Name: <Project Name> Kanban Watcher
Prompt: |
  You are the <Project Name> Kanban Watcher. Check the <project-slug> kanban board for status changes.

  Run: hermes kanban --board <project-slug> list

  Report to the user:
  - Newly completed tasks
  - Newly blocked tasks
  - Phase changes
  - Overall progress summary

  If there are no changes, stay quiet (don't send a message).
Schedule: every 5m
repeat: forever
enabled_toolsets: ["terminal"]
deliver: "discord:<channel_id>:<thread_id>"
```

#### Job 2: Active Board Watcher (every 5 hours)

Comprehensive — checks board health, fixes crashed workers, detects phantom completions, verifies workspaces, checks build health. This is the proven pattern from the DaemonCore Active Board Watcher.

```
Name: <Project Name> Active Board Watcher
Prompt: |
  You are the <Project Name> Active Board Watcher. Check the board health and fix issues.

  ## Step 1: Check Board Status
  Run: hermes kanban --board <project-slug> list

  ## Step 2: Identify Problems

  Look for:
  - **Blocked tasks** — any task with status=blocked. Check if the blocker is resolved.
  - **Stuck running tasks** — tasks that have been running for a long time without progress. Check worker logs.
  - **Phantom completions** — tasks marked "done" but with no actual implementation. For each done task, verify the expected files exist and contain real code (not stubs).
  - **Tasks with consecutive_failures** — check the SQLite DB for tasks that have failed multiple times.
  - **Tasks with wrong workspace** — check if any tasks have workspace_kind='scratch' instead of workspace_kind='dir' pointing to the project directory.

  ## Step 3: Check Worker Health
  For any running or blocked tasks, check the worker logs:
  - ls ~/.hermes/kanban/boards/<project-slug>/logs/
  - Read the latest log for stuck tasks to understand why they're stuck

  Check the SQLite DB for failure details:
  ```bash
  sqlite3 ~/.hermes/kanban/boards/<project-slug>/kanban.db "SELECT id, title, status, consecutive_failures, last_failure_error FROM tasks WHERE status IN ('blocked', 'running') AND consecutive_failures > 0;"
  ```

  ## Step 4: Fix Issues

  **For blocked tasks with dead workers (pid not alive):**
  - Reset the task to ready: update status='ready', clear claim_lock/claim_expires/worker_pid/current_run_id, reset consecutive_failures=0
  - Add a task_event explaining the reset

  **For stuck running tasks (worker alive but no progress):**
  - Check if the worker is actually doing something or stuck in a loop
  - If stuck, reclaim the task and reset to ready

  **For phantom completions:**
  - Read the source files the task was supposed to create/modify
  - If files are missing or contain only stubs, reset the task to ready
  - Add a comment explaining why it was reset

  **For tasks blocked by incorrect parent dependencies:**
  - Check task_links table for incorrect parent relationships
  - Remove incorrect links

  **For tasks with wrong workspace (scratch instead of dir):**
  - Update workspace_kind to 'dir' and workspace_path to '<PROJECTS_ROOT>/<project-name>/'
  - Add a task_event explaining the fix

  ## Step 5: Verify Build Health
  Check if the project still builds:
  ```bash
  cd <PROJECTS_ROOT>/<project-name>/
  git status --short
  git log --oneline -5
  # Add build check: npm run build / npx tsc --noEmit / cargo build / etc.
  # For Android: ./gradlew assembleDebug (from Windows, not WSL2)
  ```

  ## Step 6: Verify Workspace Configuration
  For all tasks on the board, ensure workspace_kind is 'dir' and workspace_path points to the project:
  ```python
  import sqlite3
  conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<project-slug>/kanban.db')
  c = conn.cursor()
  c.execute("UPDATE tasks SET workspace_kind='dir', workspace_path='<PROJECTS_ROOT>/<project-name>/' WHERE workspace_kind='scratch'")
  conn.commit()
  conn.close()
  ```

  ## Step 7: Report
  Output a summary of:
  - What issues were found
  - What fixes were applied
  - Current board state after fixes
  - Any issues that need human attention

  If nothing needs attention, output "[SILENT]".
Schedule: every 300m
repeat: forever
enabled_toolsets: ["terminal", "file"]
deliver: "discord:<channel_id>:<thread_id>"
```

> **IMPORTANT — Cron Job Delivery:** Always set `deliver` to the explicit Discord thread ID for this project's thread. Do NOT use `"origin"` — it targets the current conversation context which may be a different project. Get the thread ID from the conversation context or ask the user.

> **IMPORTANT — Cron Job Prompt:** The prompt MUST explicitly name the correct project — use the project's kanban board slug in the `hermes kanban --board <slug>` command, and identify as the "<Project Name> Active Board Watcher" in the prompt text. A copied cron prompt from another project will check the wrong board.

> **IMPORTANT — Toolsets:** The Active Board Watcher MUST have `enabled_toolsets: ["terminal", "file"]` — it needs file access to read source files for phantom completion detection and terminal access for git/build checks. The Kanban Watcher only needs `["terminal"]`.

**Phase 0 Verification Checklist:**
- [ ] GitHub repo exists and has initial commit
- [ ] Project directory exists at `$PROJECTS_ROOT/<project-name>/`
- [ ] Symlinks created: `project-state.md` → vault, `docs/` → vault
- [ ] Local environment builds/runs from fresh clone
- [ ] project-state.md created in vault with secrets
- [ ] Vault committed and pushed
- [ ] Kanban board created and active
- [ ] Kanban Watcher cron job created (every 5m, terminal only)
- [ ] Active Board Watcher cron job created (every 300m, terminal + file)

**Report to user:** "Phase 0 complete. Repo: <url>. Board: <slug>. Code: `$PROJECTS_ROOT/<project-name>/`. Symlinks: `project-state.md` → vault. Cron: Kanban Watcher (5m) + Active Board Watcher (300m). Ready for Phase 1: Phase Planning."

---

## Phase 1: Phase Planning

**Who:** Orchestrator creates phase plans (can delegate to PM profile for complex projects).

### Step 1.1: Review Initial Plan

Read the existing research/plan. Identify the major phases. A typical project:

```
Phase 1: Foundation      — DB schema, auth, core API, base UI
Phase 2: Core Features   — Main feature set, business logic
Phase 3: Integration     — External APIs, real-time, file handling
Phase 4: Polish          — Testing, error handling, performance, deployment
```

Adjust based on the project. Some projects need fewer phases; complex ones need more.

### Step 1.2: Create Phase Plan Documents

For each phase, create a plan document in the repo:

```bash
mkdir -p docs/plans
```

Each phase plan follows the `writing-plans` format:

```markdown
# Phase N: <Phase Name> — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** <What this phase accomplishes>

**Depends on:** Phase N-1 (must be fully verified before starting)

**Review Gate:** At end of phase — reviewer must verify all criteria pass before Phase N+1 begins.

## Objectives
- [ ] Objective 1
- [ ] Objective 2

## Tasks Overview
| # | Task | Assignee | Est. |
|---|------|----------|------|
| N.1 | ... | backend-eng | 5 min |
| N.2 | ... | frontend-eng | 5 min |

## Phase Review Criteria
1. [ ] <Specific verifiable criterion>
2. [ ] <Specific criterion>
3. [ ] All tests pass (`npm test` / `pytest` / `cargo test`)
4. [ ] CI passes on GitHub Actions
5. [ ] No critical or important issues from reviewer
```

### Step 1.3: Get User Approval

Present the phase plan to the user. Wait for explicit approval before proceeding to Phase 2.

**Do not skip this gate.** The user must approve the phase breakdown before tasks are created.

---

## Phase 2: Task Decomposition

**Who:** Orchestrator (following `kanban-orchestrator` skill).

### Step 2.1: Decompose Each Phase into Kanban Tasks

For each phase plan, break every task into **bite-sized kanban tasks** (2-5 minutes each).

**Every kanban task MUST include:**

1. **Clear title** — what the task accomplishes
2. **Assignee** — the right specialist profile:
   - `claude-lane` — ALL coding tasks (complex work, multi-file, architecture). Uses `claude -p` in isolated worktree. **PREFERRED for all implementation.**
   - `agy-lane` — Quick fixes, smaller tasks, sandboxed execution. Uses `agy -p` in isolated worktree.
   - `reviewer` — Code review, quality gates
   - `ops` — Infrastructure, deployment, env config
   - `backend-eng` / `frontend-eng` — Only if agent lanes are unavailable
   
   **Agent Lane Delegation:** For the agent-lane pattern, ALL coding tasks go through `claude-lane` or `agy-lane`. The `agent-lane` skill provides the full pattern. The orchestrator must NEVER write code directly when a kanban board exists.
3. **WORKING DIRECTORY** — the canonical project path (REQUIRED, non-negotiable):
   ```
   WORKING DIRECTORY: $PROJECTS_ROOT/<project-name>/
   ```
   The agent MUST `cd` to this directory before doing any work. No exceptions.
4. **Body with exact details:**
   - File paths (exact, not vague)
   - Code examples where applicable
   - Commands to run with expected output
5. **VERIFICATION comment** — specific, executable test steps:
   ```
   VERIFICATION:
   (1) Run `pytest tests/test_feature.py -v` — expect 5/5 passing
   (2) Run `curl http://localhost:3000/api/endpoint` — expect 200 with JSON
   (3) Check no console errors in browser devtools
   ```
6. **CI verification step** (for all code tasks):
   ```
   CI: Push to repo, wait for GitHub Actions, verify 0 failures before marking done.
   ```

### Step 2.2: Create Review Gate Tasks

At the end of **each phase**, create a mandatory review task:

```
Title: "Phase N Review: <Phase Name>"
Assignee: reviewer
Body: |
  Review all work from Phase N: <Phase Name>.
  
  CHECK:
  - [ ] All phase objectives met
  - [ ] All tests pass (run full test suite)
  - [ ] CI passes on GitHub Actions
  - [ ] Code quality acceptable (no critical/important issues)
  - [ ] No security vulnerabilities
  - [ ] Error handling is appropriate
  - [ ] Documentation updated
  
  If issues found: create fix tasks assigned to the original implementer.
  Only approve when ALL criteria pass.
  
  VERIFICATION:
  (1) Run full test suite — all passing
  (2) `gh run list --repo <github-user>/<project> --limit 3` — latest run is green
  (3) Review all changed files for quality
```

**Link the review task as a parent of all Phase N+1 tasks.** This enforces the gate — no next-phase tasks can start until the review passes.

### Step 2.3: Create All Tasks on the Board

```bash
# Create tasks with full details (always include --assignee and --body)
hermes kanban --board <project-slug> create "Task title" --assignee backend-eng --body "Full task description with file paths, code examples, and VERIFICATION steps"

# Link dependencies (review gate as parent of next-phase tasks)
hermes kanban --board <project-slug> link <parent-id> <child-id>
```

**Rules:**
- Create ALL tasks for the current phase before starting execution
- Create the review gate task for the phase
- Link review gate as parent of next-phase tasks
- Do NOT pre-create tasks for future phases (decompose those when the phase starts)
- **Always include VERIFICATION steps in every task body** — specific, executable test commands with expected output
- **Always include CI verification** for code tasks: "Push to repo, wait for GitHub Actions, verify 0 failures"
- **ALWAYS set workspace_kind to `worktree` for code tasks.** The `hermes kanban create` CLI does NOT support `--workspace-kind` or `--workspace-path` flags. You MUST set the workspace after creation via SQLite:
  ```python
  import sqlite3
  conn = sqlite3.connect('/home/<user>/.hermes/kanban/boards/<slug>/kanban.db')
  c = conn.cursor()
  c.execute("UPDATE tasks SET workspace_kind='worktree', workspace_path='$PROJECTS_ROOT/<project-name>/.worktrees/' || id WHERE id=?", (task_id,))
  conn.commit()
  conn.close()
  ```
  For bulk creation, update ALL tasks at once:
  ```python
  c.execute("UPDATE tasks SET workspace_kind='worktree', workspace_path='$PROJECTS_ROOT/<project-name>/.worktrees/' || id WHERE workspace_kind='scratch' AND assignee IN ('backend-eng', 'frontend-eng', 'claude-lane', 'agy-lane')")
  ```
  **NEVER leave code tasks with `workspace_kind=scratch`** — scratch directories are empty temp dirs that get GC'd. Workers will crash immediately trying to read/write project files. The `worktree` workspace kind is the default for all coding tasks. See the `kanban-orchestrator` skill for workspace kind semantics.

  **Worktree branch naming convention:** `kanban/<task-id>` — short, unique, and clearly associated with the task. Workers create the worktree via `git worktree add .worktrees/<task-id> -b kanban/<task-id>`.

  **Orchestrator merge step:** After a worker marks a task `do` and the branch passes review, the orchestrator merges the worktree branch:
  ```bash
  cd $PROJECTS_ROOT/<project-name>/
  git checkout main
  git merge kanban/<task-id> --no-ff -m "merge: <task title> (<task-id>)"
  git push origin main
  # Clean up
  git worktree remove .worktrees/<task-id>
  git branch -D kanban/<task-id>
  ```
  Only after merge + cleanup should the orchestrator consider the phase's code fully integrated.

### Step 2.3.5: Pre-Decomposition Code Review (When Resuming Existing Project)

When resuming an existing project (detection matrix found existing infrastructure), perform a **comprehensive code review** BEFORE decomposing the next phase:

1. Read all key source files for the current area of work
2. Identify bugs, inconsistencies, missing features, and code quality issues
3. Categorize findings by severity: Critical (game-breaking), High (functional), Medium (quality)
4. Document findings in a structured list
5. Present findings to the user with a proposed task breakdown
6. Get user approval before creating kanban tasks

This step ensures the task decomposition is informed by actual code state, not just the plan document.

**Use the code review checklist:** See `references/code-review-checklist.md` for common bug patterns in web game projects (API route issues, frontend state issues, data flow issues, real-time issues).

### Step 2.4: Report to User

Present the task breakdown:
> "Phase N has been decomposed into X tasks on the `<project-slug>` board. A review gate task is in place at the end of the phase. The dispatcher will start picking up tasks now. You'll get updates as tasks complete."

### Step 2.5: Hindsight Retain (MANDATORY — do not skip)

**Before doing any other work**, run the hindsight recall + retain cycle:

1. **Recall** past context: Use the `memory` tool to search for project-related memories, or POST to the hindsight API at `http://localhost:8888/v1/default/banks/hermes/memories/recall` with `{"query": "<project-name> <topic>", "budget": "mid"}`

2. **Retain** what you learned: After completing the decomposition (or before context compaction), save key decisions and findings:
   ```
   memory(
       action="add",
       target="memory",
       content="[<project>] Phase N decomposition: [X] tasks created. Key decisions: [decisions]."
   )
   ```
   Also retain to the hindsight API if available:
   ```bash
   curl -s -X POST http://localhost:8888/v1/default/banks/hermes/memories \
     -H "Content-Type: application/json" \
     -d '{"items": [{"content": "<session summary>", "tags": ["<project>", "orchestrator", "phase-plan"], "type": "observation"}]}'
   ```

**This is not optional.** Every agent work session must end with a hindsight retention call. The kanban-worker skill says: "Every agent work session must end with a hindsight_retain call." The orchestrator should do it at session START (recall) and END (retain) too.

**Skill loading discipline:** Always use `skill_view(name)` to load skills. Never read raw skill files with `read_file` when a skill command exists. Skills contain specialized knowledge, API endpoints, and proven workflows that outperform general-purpose approaches. `read_file` on a SKILL.md misses the parsed structure and linked files that `skill_view()` provides.

See `kanban-worker` skill's "Hindsight Memory Retention" section and its `references/hindsight-retention-protocol.md` for the full protocol.

---

## Phase 3: Execution

**Who:** Dispatcher + Subagent Workers (orchestrator monitors, does NOT execute).

### Step 3.1: Verify Dispatcher is Running

```bash
hermes gateway status
# Ensure dispatch_in_gateway: true
```

The dispatcher picks up `ready` tasks automatically (~60s tick).

**If the dispatcher is NOT running:** The orchestrator must create tasks directly via `hermes kanban create` and may need to execute them directly or spawn subagents manually. Do NOT assume the dispatcher is active — always verify first.

### Step 3.2: Monitor Progress

Use the kanban board to track:
```bash
hermes kanban --board <project-slug> list
hermes kanban --board <project-slug> show <task-id>
```

**Orchestrator responsibilities during execution:**
- Monitor for blocked tasks and resolve blockers
- Ensure workers are following verification discipline
- **When a task is marked "done" by a worker, verify the implementation exists** before accepting it: read the expected source files, confirm the code is substantive (not stubs), and verify the build passes. If the implementation is missing or incomplete, reset the task to "ready" and re-dispatch or implement directly.
- **Merge worktree branches after task completion:** When a coding task is done and verified, merge its worktree branch into main, clean up the worktree, and push. See the merge procedure in Phase 2 Step 2.3.
- Update `project-state.md` as milestones are reached
- Notify user of phase completions and review results
- **Do NOT execute tasks directly** — if a worker fails, create a fix task
- **Periodically prune stale worktrees:** Run `git worktree prune` in the project directory to clean up orphaned worktree references.

### Step 3.3: Handle Review Gates

When a phase review task completes:

**If APPROVED:**
1. Notify user: "Phase N passed review"
2. Decompose Phase N+1 into kanban tasks (go to Phase 2 for the next phase)
3. Update `project-state.md`

**If REJECTED (issues found):**
1. Reviewer creates fix tasks for each issue
2. Fix tasks are assigned to the original implementer
3. After fixes, reviewer re-reviews
4. Only proceed to next phase when review passes

**No exceptions.** Do not start Phase N+1 tasks until Phase N review is approved.

### Step 3.4: Handle Blocked Tasks

When a worker blocks:
1. Read the block reason and comment thread
2. Determine if it's a user decision or a technical blocker
3. For user decisions: notify the user via Discord/Telegram with the specific question
4. For technical blockers: create a fix task or provide the worker with additional context
5. **Before unblocking**: Verify the blocker is actually resolved. If the blocker was "build broken", run `npm run build` or `npx tsc --noEmit` to confirm the build passes. If the blocker was "missing dependency", verify the dependency is installed. Don't unblock on faith — verify.
6. **Check for duplicates**: Before creating a new task, search the board for existing tasks that cover the same ground. Use `hermes kanban --board <slug> list` and scan titles. Creating duplicate tasks wastes worker time and causes confusion.
7. Unblock when resolved: `hermes kanban unblock <id>`
8. **Add context comment**: When unblocking, add a comment explaining what was fixed and any relevant context the worker needs (e.g., "Build fixed — GameSettingsModal.tsx was missing, now created. Vercel deployment is green.")

---

## Phase 4: Continuous Monitoring

Set up these cron jobs for ongoing project health. **All cron jobs should be created in Phase 0.5** — this section documents what each job does for reference.

### 4.1: Kanban Board Watcher (every 5 min)

Lightweight — monitors the board and reports changes. Stays quiet when nothing changed. Created in Phase 0.5 Job 1.

### 4.2: Active Board Watcher (every 5 hours)

Comprehensive — checks board health, fixes crashed workers, detects phantom completions, verifies workspaces, checks build health. This is the proven pattern from the DaemonCore Active Board Watcher. Created in Phase 0.5 Job 2.

**Key capabilities:**
- Detects and resets crashed workers (dead pid, stuck running tasks)
- Detects phantom completions (tasks marked "done" with no real implementation)
- Fixes workspace configuration (scratch → dir)
- Verifies build health (git status, build check)
- Reports only when issues are found (silent when healthy)

### 4.3: CI Reviewer (every 30 min)

Monitors GitHub Actions and auto-creates fix tasks on failure. See `kanban-orchestrator` skill's "CI Reviewer" section for the full pattern.

```
Name: <Project Name> CI Reviewer
Prompt: |
  You are the CI Reviewer for the <Project Name> project. Check the latest GitHub Actions workflow runs.

  Run: gh run list --repo <github-user>/<project-name> --limit 5

  If any run failed:
  1. Read the failure logs: gh run view <run-id> --log-failed
  2. Create a fix task on the kanban board with the error details
  3. Notify the user with the failure summary

  If all runs are green, output "[SILENT]".
Schedule: every 30m
repeat: forever
enabled_toolsets: ["terminal"]
deliver: "discord:<channel_id>:<thread_id>"
```

### 4.4: Project State Sync (every 2 hours)

```
Name: <Project Name> Project State Sync
Prompt: |
  You are the <Project Name> Project State Sync. Update the project-state.md in the vault with current project state.

  1. Read project-state.md from the vault at <vault-path>/Projects/Personal/<project-name>/project-state.md
  2. Check the kanban board: hermes kanban --board <project-slug> list
  3. Check git for new commits: cd <PROJECTS_ROOT>/<project-name>/ && git log --oneline -10
  4. Update project-state.md with current state (phase, task counts, recent commits, known issues)
  5. Commit and push the vault: cd <vault-path> && git add -A && git commit -m "sync: update project-state for <project-name>" && git push origin Main

  Output "[SILENT]" if successful.
Schedule: every 120m
repeat: forever
enabled_toolsets: ["terminal", "file"]
deliver: "discord:<channel_id>:<thread_id>"
```

### 4.5: Weekly Refresh (every Sunday 9am)

```
Name: <Project Name> Weekly Refresh
Prompt: |
  Weekly refresh for the <Project Name> project.

  1. Read project-state.md from the vault
  2. Check the kanban board for stale/abandoned tasks
  3. Review git log for the past week
  4. Update project-state.md with weekly summary
  5. Commit and push the vault
  6. Report weekly summary to user

  If the project is complete, note that in the report.
Schedule: 0 9 * * 0
repeat: forever
enabled_toolsets: ["terminal", "file"]
deliver: "discord:<channel_id>:<thread_id>"
```

### Cron Job Reference Table

| Job | Schedule | Toolsets | Purpose |
|-----|----------|----------|---------|
| Kanban Watcher | every 5m | terminal | Report board changes |
| Active Board Watcher | every 300m | terminal, file | Fix board health issues |
| CI Reviewer | every 30m | terminal | Monitor GitHub Actions |
| Project State Sync | every 120m | terminal, file | Update project-state.md |
| Weekly Refresh | Sunday 9am | terminal, file | Weekly summary |

### Cron Job Anti-Patterns

- **Do NOT use `"origin"` for deliver** — always use explicit `discord:<channel_id>:<thread_id>`
- **Do NOT skip `repeat: forever`** — omit and the job runs once and disappears
- **Do NOT forget `enabled_toolsets`** — without the right toolsets, the cron job can't do its job
- **Do NOT copy a cron prompt from another project without changing the board slug** — it will check the wrong board
- **Do NOT create duplicate cron jobs** — always check `hermes cron list` first

---

## project-state.md Secrets Management

**All project secrets go in project-state.md in the vault, NOT in the project repo.**

Format:
```markdown
## Secrets & Environment Variables

| Variable | Value | Location | Notes |
|----------|-------|----------|-------|
| `OPENAI_API_KEY` | `sk-xxx...` | `.env.local` | Rotate monthly |
| `DATABASE_URL` | `postgres://user:pass@host/db` | Vercel env | Production DB |
| `NEXT_PUBLIC_SUPABASE_URL` | `https://xxx.supabase.co` | Vercel env + `.env.local` | |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJ...` | Vercel env only | Never expose to client |
```

**Rules:**
- Never commit `.env` files to the project repo
- The vault is the single source of truth for all secrets
- When a worker needs a secret, it reads from the vault (or the orchestrator provides it)
- Rotate secrets periodically and update the vault

---

## Review Gate Discipline

**This is the most important part of the lifecycle. Do not compromise on review gates.**

### When Review is Required
- **Between every phase** — mandatory, non-negotiable
- **Before production deployment** — always
- **After any major architectural change** — always
- **When a worker needed 3+ runs** — the worker has shown unreliable self-verification

### Review Process
1. Reviewer task is created at end of phase with specific criteria
2. Reviewer independently runs ALL verification steps
3. Reviewer documents findings in the task comment thread
4. **If issues found:** Reviewer creates fix tasks → implementer fixes → reviewer re-reviews
5. **If all criteria pass:** Reviewer approves → next phase tasks become available
6. Orchestrator notifies the user of the result

### What Review Checks
- All phase objectives met
- Full test suite passes
- CI passes on GitHub Actions
- Code quality (no critical/important issues)
- Security (no vulnerabilities, secrets not exposed)
- Error handling is appropriate
- Documentation is updated
- No regressions from previous phases

---

## Anti-Patterns (Do NOT)

- **Skip Phase 0** — always create repo, local env, project-state.md, and board before building (UNLESS they already exist — run detection first)
- **Start coding without a plan** — always decompose into tasks first
- **Progress past a failed review** — fix issues first, then re-review
- **Orchestrator executes work directly** — fine for Phase 0 (scaffolding, repo setup, initial config) and sequential setup steps that can't be parallelized. For Phase 2+ feature work, always route through kanban.
- **NEVER edit project files directly when a kanban board exists** — Even for "obvious" or "trivial" fixes, create a kanban task first. The kanban board is the audit trail: every task has an event log, comments, run history, and worker output. Direct file edits leave no trace. When you need to debug what went wrong weeks later, the kanban board is the only reliable record. This applies to ALL work on projects with an active kanban board — not just feature work, but also build fixes, dependency updates, and configuration changes. Create the task → claim it → implement → verify → complete. No exceptions.
- **Create tasks without verification criteria** — every task needs VERIFICATION steps
- **Pre-create all phases at once** — decompose one phase at a time
- **Skip CI verification** — a task is not done until CI passes
- **Leave secrets in the repo** — all secrets in vault's project-state.md only
- **Forget to update project-state.md** — update after every work session
- **Forget to commit/push the vault** — always push when done
- **Assume the project name from the board slug** — The board slug (e.g., `discord`) is NOT necessarily the project name (e.g., `discord-osint`). Always confirm the project name with the user or through the detection matrix. The project directory is `$PROJECTS_ROOT/<project-name>/`, not derived from the board slug. If the user corrects you ("the project is X, not Y"), update the workspace path immediately via SQLite.
- **Skip existing project detection** — ALWAYS run the detection matrix before any other action. Never assume a project is new. Running the detection matrix first prevents: creating duplicate repos, pointing workspaces to wrong directories, recreating existing boards/cron jobs, and misidentifying the project name.
- **Resuming an existing project — kanban discipline still applies** — When you detect an existing project and resume work, the temptation is to "just fix the obvious issue directly." DON'T. Even when the fix is a one-liner (bumping a version, adding a repo), create a kanban task for it. The board is the only record of what changed and why. Direct edits during resume are the #1 cause of "mystery changes" that are impossible to trace later.
- **Workers may implement code but crash before kanban_complete** — When tasks are in `blocked` or `todo` state with worker crash errors (pid not alive, protocol violation), check `git log` and grep for the expected function before re-dispatching. The implementation may already exist. See `references/discord-slash-command-bug-patterns.md` pitfall #8.
- **Updating git-based projects on Windows filesystem from WSL** — When a project on `/mnt/c/` has dirty working tree state blocking `git pull`, check `git diff --stat HEAD` first. If all changes are upstream files (no local customizations), `git reset --hard HEAD` is safe. Then `git fetch` → checkout desired version → diff dependency files (`requirements.txt`, `package.json`) → install updates in the project's Python/Node environment. See `references/git-update-windows-fs-from-wsl.md` for the full procedure including ComfyUI-specific notes.
- **E2E test safety limits too tight for data values** — When an E2E test has a safety limit (maxRounds, maxIterations) that's close to the actual required iterations, the test exits before completion and the final assertion fails. Calculate: total HP / max damage per turn = required rounds. If maxRounds < required, the test will always fail. Fix: increase maxRounds with 50% headroom, or make it data-driven. See `systematic-debugging` skill's `references/e2e-test-safety-limits.md` for the full pattern.
- **Pointing workspaces to the source tree instead of the project directory** — When the code being modified lives in a shared source tree (e.g., hermes-agent gateway), the workspace must still be a `worktree` rooted at `$PROJECTS_ROOT/<project-name>/`, NOT the source tree. The project directory gets symlinks to the source tree. Workers need the project directory structure (project-state.md, docs/, plans/) accessible, not just the raw source files. The worktree is created from the project directory's git repo.
- **Skip hindsight recall on resume** — When resuming an existing project or recovering from context compaction, ALWAYS run hindsight recall (Step 0 of Resume Flow) before reading project files. The retained memories from previous sessions contain critical context about bugs, decisions, and patterns that aren't in project-state.md. Skipping this step means re-learning lessons already paid for.
- **Work in /tmp or /scratch** — NEVER create project files in `/tmp`, `/scratch`, `/var/tmp`, or any temporary directory. Project work MUST happen at `$PROJECTS_ROOT/<project-name>/`. Temp directories are for transient data only (downloads, extracts), never for project source code. If an agent needs to download something, it goes to `/tmp/` — but the actual project code stays in the canonical path.
- **Assume workers will commit their own changes** — Workers modify files in their own worktree. If a worker marks a task done but doesn't push the branch, the changes are LOST when the session ends. **Before accepting any "done" coding task, verify the branch was pushed:** `git fetch origin && git log origin/kanban/<task-id> --oneline -3`. If the branch has no commits, the work is phantom — reset the task and re-implement. After merging, clean up the worktree and branch.
- **Phantom task completions** — Workers can mark kanban tasks as "done" without actually implementing anything. This happens when API stream drops cause clean exits (protocol violation), or when workers self-verify incorrectly. **Always verify implementations exist by reading the actual source files** before accepting a "done" status. Check: (1) the expected file exists, (2) the file contains the expected code (not just stubs or placeholders), (3) the build still passes. If a "done" task has no implementation, reset it to "ready" and re-dispatch, or implement it directly. Do NOT proceed to the next phase with phantom completions.
- **Import resolution failures after worker commits** — Workers may add `import` statements for components/files that don't exist on disk. This causes `Module not found` build errors that break all deployments. **After every worker commit, run `npx tsc --noEmit` (or equivalent) to verify all imports resolve.** Specifically check: (1) every `import` in newly committed files resolves to an actual file, (2) no `Module not found` errors exist. This is especially critical when workers add new components, refactor imports, or wire up modals/panels. A single missing component file (e.g., `GameSettingsModal.tsx` imported but never created) will break every Vercel deployment until fixed. **When resuming an existing project, always run `npx tsc --noEmit` as part of Step 4 of the Resume Flow before trusting any "done" task statuses.**
- **Duplicate tasks on the board** — Creating a new task that overlaps with an existing one wastes worker time and causes confusion. Before creating any task, search the board (`hermes kanban --board <slug> list`) and scan titles for similar work. If a task exists, add a comment to it rather than creating a duplicate. If the existing task is blocked or done, unblock or reset it instead of creating a parallel one.
- **Context values not exposed** — Workers may call `useGameState()` (or similar context hooks) and destructure values like `setGameState` that the context provider doesn't actually expose. Always verify the context interface and value object include everything consumers destructure. If a worker adds `setGameState` to a context consumer but the provider doesn't expose it, the build will fail with "Cannot find name" or the value will be `undefined` at runtime. Check the context provider's return value and interface when adding new context consumers.
- **Fields from wrong type** — Workers may read fields from a type that doesn't have them (e.g., `initialSession.useDigitalBoard` when `SessionRow` from Prisma doesn't include that field). Use local `useState` for UI-only state, and verify any field accessed on database model types actually exists in the Prisma schema. When a worker adds a new UI state field (like `useDigitalBoard`), it should be local component state, not read from the database model.
- **Assume the dispatcher is NOT running** — Always verify with `hermes gateway status` before relying on automatic task dispatch. If the dispatcher is down, create tasks and execute them directly or via `delegate_task`.
- **Tauri build from wrong directory** — `cargo build` must be run from `src-tauri/`, not the project root. `Cargo.toml` lives in `src-tauri/`, not the repo root. Running from root gives `could not find Cargo.toml`.
- **`gh repo create --clone` clones to CWD, not canonical path** — When the canonical path is on `/mnt/c/` (Windows filesystem), `gh repo create --clone` clones to the current WSL directory (usually `~`), NOT to the canonical Windows path. This crosses the WSL/Windows boundary and can cause 9P metadata corruption if you try to `mv` it later. Instead: (1) create the repo without `--clone`, (2) `gh repo clone <user>/<repo> /mnt/c/Users/<user>/Documents/Projects/<repo>` directly to the canonical path. Never `mv` across WSL/Windows boundaries.
**Symlinks break git operations:** When `docs/` is a symlink to the vault, running `git add docs/plans/` from the repo fails with "pathspec is beyond a symbolic link." Git cannot traverse symlinks to external directories. To commit plan documents or other files under `docs/`: (1) save files directly to the vault directory, (2) `cd` to the vault directory, (3) `git add` and `git commit` from there. The repo's symlink makes `docs/` readable locally, but writable only from the vault side.

**Migrating an existing project to symlinks:** When resuming an existing project where `docs/` is a real directory (not a symlink) and the vault already exists:
1. Copy existing repo docs to the vault: `cp -r docs/* <vault-path>/Projects/Personal/<project-name>/`
2. Remove the real directory: `rm -rf docs`
3. Create the symlink: `ln -sf <vault-path>/Projects/Personal/<project-name>/ docs`
4. Verify: `ls -la docs` should show `docs -> <vault-path>`, not `docs/` as a directory
5. Commit the vault: `cd <vault-path> && git add -A && git commit && git push`
6. Commit the repo (git will show the symlink as `A docs` and old files as `D docs/...`): `git add docs && git commit && git push`
Do NOT skip step 1 — existing docs in the repo would be lost when `rm -rf docs` runs.
- **Cron job delivery must be explicit** — When creating cron jobs in Phase 0.5, always set `deliver` to the explicit Discord thread ID (e.g., `discord:<channel_id>:<thread_id>`), NOT `"origin"`. The `origin` delivery targets the current conversation context, which may be a different project's thread. Each project's watchers must deliver to their own thread. Get the thread ID from the user or from the conversation context. **Also, the cron prompt itself must explicitly name the correct project** — use the project's kanban board slug in the `hermes kanban --board <slug>` command, and identify as the "<Project Name> Active Board Watcher" in the prompt text. A copied cron prompt from another project will check the wrong board.
- **Active Board Watcher needs file toolset** — The Active Board Watcher cron job MUST have `enabled_toolsets: ["terminal", "file"]` because it reads source files to detect phantom completions. The Kanban Watcher only needs `["terminal"]`. Don't mix them up.
- **Two cron jobs, not one** — Every project needs BOTH a Kanban Watcher (every 5m, lightweight change reporting) AND an Active Board Watcher (every 300m, comprehensive health checks). The Kanban Watcher reports; the Active Board Watcher fixes. Don't skip either one.
- **Cronjob creation via tool may fail** — If `cronjob(action='create')` fails with an API error, use `cronjob(action='update')` on an existing paused job instead. Always check `cronjob(action=list)' first — reuse existing job IDs rather than creating new ones.
- **Review gate tasks auto-complete** — Creating a `reviewer`-assigned task on the board means the dispatcher may instantly mark it done. Don't expect to manually approve review gates — the dispatcher handles them. If you need the orchestrator to explicitly verify before approval, add the review criteria as comments on the task and check it after dispatch rather than expecting it to stay `ready`.
- **Kanban board may already exist** — When running Phase 0.4, the board might already exist from a previous session. `hermes kanban boards create <slug>` will return "already exists" and switch to it. This is fine — just verify with `hermes kanban --board <slug> list`. Do NOT try to recreate or reset it.
- **Android project scaffolding is repetitive** — For Android projects using Kotlin + Jetpack Compose + Hilt + Room, the initial scaffold follows a predictable pattern: Gradle config (build.gradle.kts, settings.gradle.kts, gradle.properties), AndroidManifest.xml, Room entities/DAOs/database, Hilt DI module, Compose theme, and MainActivity. Use `templates/android-compose-scaffold/` as a starting point when available, or follow the structure documented in `references/android-project-structure.md`.
- **Android builds from WSL2 are unreliable** — Gradle from WSL2 cannot reliably resolve Windows Android SDK paths. `local.properties` with `sdk.dir=C:\Users\...` fails because WSL2 sees `/mnt/c/`. Even with corrected paths, Gradle daemon incompatibilities between WSL2 and Windows cause build failures. **Always build Android projects from Windows PowerShell, not WSL2.** Use WSL2 for git, file editing, and code analysis only. See `references/android-build-pitfalls.md` for full details.
- **Complex PowerShell via shell** — Never pass PowerShell with `$()` interpolation via `powershell.exe -Command "..."` — the shell strips `$` signs. Write a `.ps1` file to `/tmp/` and run with `powershell.exe -ExecutionPolicy Bypass -file /tmp/<script>.ps1`.

---

## Integration with Other Skills

This skill is the **orchestration layer**. It calls these skills for their specific domains:

| Skill | Used For |
|-------|----------|
| `project-management` | project-state.md template, update triggers, vault git workflow |
| `kanban-orchestrator` | Task decomposition, specialist roster, anti-temptation rules |
| `kanban-worker` | Worker lifecycle, verification discipline, crash recovery |
| `kanban-verification-gate` | Review gate discipline, evidence requirements |
| `writing-plans` | Phase plan documents, bite-sized task format |
| `subagent-driven-development` | Per-task execution with 2-stage review |
| `test-driven-development` | TDD within individual tasks |
| `agent-lane` | Agent CLI delegation pattern — all coding tasks go through `claude-lane` or `agy-lane` profiles |
| `claude-code` | Claude Code CLI skill — used by `claude-lane` profile for complex reasoning tasks |
| `antigravity-cli` | Antigravity CLI skill — used by `agy-lane` profile for quick fixes and sandboxed work |
| `hermes-agent` | /goal setup, status file pattern, cron job configuration, hindsight API patterns (`references/hindsight-api-patterns.md`) |

## Tauri 2 Desktop Apps

For projects using Tauri 2 (Rust + web frontend), see:
- `references/tauri-cross-compile.md` — cross-compilation from WSL2 to Windows
- `references/tauri-verify-launch.md` — build verification and launch testing patterns
- `references/tauri-webhook-server.md` — in-process axum webhook server pattern
- `references/tauri-tray-menu-pattern.md` — system tray menu as primary control surface (replaces in-window buttons/panels)

**Key rule:** Always add `"tray-icon"` to Tauri features in `Cargo.toml` when using `TrayIconBuilder`, `MenuBuilder`, or `CheckMenuItemBuilder`.

**Architecture principle for Tauri apps:** When building a multi-character Tauri app, prefer a data-driven character registry over hardcoded JSX. Study a reference implementation (e.g., CodeWalkers), identify the minimal-change pattern that preserves the existing architecture, and adopt it. Don't over-engineer — keep it as close to the original plan as possible.

**Multi-character pet system patterns (from DaemonCore project):**
- Data-driven `CHARACTER_REGISTRY` with id/label/description/style per character
- `CharacterRenderer` dispatcher component that renders the correct SVG based on character ID
- Profile-based spawning: one pet per Hermes profile, Zustand store with localStorage persistence
- Art styles: cartoon (defined shapes, radial gradients, expressive eyes) vs abstract (feGaussianBlur glow filters, particle/sparkle systems, neon palettes)
- Pixie character: abstract fairy dust cloud (overlapping ellipses + polygon sparkles + bright core), NOT a literal pixie figure
- Priority state machine: dragging(10) > error(8) > notification(7) > done(5) > working(3) > thinking(2) > idle(1) > sleeping(0)
- Cross-fade transitions: 150ms opacity fade between SVG state changes
- Eye tracking: dx/dy from pet center to cursor, clamped to 6px, distance-based falloff
- Follow-mouse with distance (v2): pet follows cursor but maintains minimum distance threshold
- System tray menu: flat menu with separators, checkable items for toggles (Show Pet, Sounds, Follow Mouse, Theme, Size), clickable items for actions (Active Sessions, Quit). See `references/tauri-tray-menu-pattern.md`.
- Hybrid click-through: Rust `get_mouse_pos` command + `elementFromPoint` + bounding circle hit test + `set_ignore_cursor_events` + 250ms watchdog polling fallback. CSS `rgba(0,0,0,0.01)` background on container to capture mouse events.

## Discord Slash Commands

For projects adding Discord slash commands to the Hermes Agent gateway, see `references/discord-slash-command-bug-patterns.md` for common pitfalls including CLI flag argument splitting, mutually exclusive flags, Go binary path resolution, and the defer+edit response pattern.

For AI-generated character art and creative assets, see `references/comfyui-integration.md` for the ComfyUI integration pattern (SD 1.5, REST API, prompt tips).

## Android Project Scaffolding

For the standard Android project structure (Kotlin + Jetpack Compose + Hilt + Room), see `references/android-project-structure.md` for Gradle config, dependency versions, package layout, and key file templates. Use this as a starting point when scaffolding new Android projects in Phase 0.

For common Android build failures and dependency issues (WSL2 SDK path, Compose BOM version conflicts, Maven repos, Gradle daemon), see `references/android-build-pitfalls.md`.

## Vercel Deployment Debugging

For common Vercel build failures (missing components, Node version mismatches, Prisma generate, env vars, duplicate projects), see `references/vercel-build-debugging.md`.

---

## Quick Reference: Starting a New Project

```
User: "Let's build <project>"

1. Confirm research is done and initial plan exists
2. Detect PROJECTS_ROOT (canonical code location)
3. Phase 0: Create repo → clone to $PROJECTS_ROOT/<project>/ → create project-state.md in vault → set up symlinks → create kanban board → set up Kanban Watcher cron (5m) + Active Board Watcher cron (300m)
4. Phase 1: Create phase plan documents, get user approval
5. Phase 2: Decompose Phase 1 into kanban tasks with verification criteria (every task specifies WORKING DIRECTORY)
6. Phase 3: Dispatcher picks up tasks, orchestrator monitors
7. Phase 3 Review Gate: Reviewer verifies Phase 1, approves or creates fixes
8. Repeat Phases 2-3 for each subsequent phase
9. Phase 4: Cron jobs monitor board (Kanban Watcher + Active Board Watcher), CI (CI Reviewer), and project state (Project State Sync + Weekly Refresh)
```

---

## Response Formatting for Status Reports & Reviews

**Always break large reports into smaller, scannable parts.** The user prefers digestible chunks over monolithic dumps.

- **Board status reports:** Show a compact summary table first (counts by state), then list tasks grouped by state only if asked. Never dump a raw 36-line kanban output as-is.
- **Phase reviews:** Break into short labeled sections: Summary → Build → Source → Tasks → Next Steps. Each section is a compact paragraph or list.
- **General rule:** If a response would exceed ~15 lines of dense content, break it into labeled sections. The user will ask for detail if they want more.

### Example — Board Status Report (GOOD)

```
**Mimiral Board — Phase 1 Complete**

| State | Count |
|-------|-------|
| Done | 41 |
| Running | 0 |
| Blocked | 0 |

All Phase 1 tasks verified. Build passing. Ready for Phase 2 review approval.
```

NOT: a raw dump of all 41 tasks.

### Example — Phase Review (GOOD)

```
**Phase 1 Review — Summary**

✅ 23 base tasks + 3 fix tasks + 1 review = 27/27 done

**Verified:**
- Build: assembleDebug passes (41 tasks up-to-date)
- Source: 39 .kt files under app/src/main/java/
- Board: 36 tasks all marked done

**Next:** Awaiting your Phase 2 approval to decompose Enhanced Reading.
```

After completing each phase of the lifecycle:

**Phase 0 complete when:**
- [ ] `gh repo view` shows the repo
- [ ] Project directory exists at `$PROJECTS_ROOT/<project-name>/`
- [ ] Symlinks created: `project-state.md` → vault, `docs/` → vault
- [ ] Fresh clone + install + build works
- [ ] project-state.md exists in vault with secrets
- [ ] Vault is committed and pushed
- [ ] Kanban board exists (`hermes kanban boards show`)
- [ ] Watcher cron job is active

**Phase 1 complete when:**
- [ ] Phase plan documents exist in `docs/plans/`
- [ ] User has explicitly approved the phase breakdown

**Phase 2 complete when:**
- [ ] All tasks for the current phase are on the board
- [ ] Every task has VERIFICATION criteria
- [ ] Review gate task exists and is linked as parent of next-phase tasks

**Phase 3 complete when:**
- [ ] All tasks for the phase are done
- [ ] Review gate has passed
- [ ] CI is green
- [ ] project-state.md is updated

**Phase 4 complete when:**
- [ ] All cron jobs are active and reporting
- [ ] Board watcher is forwarding updates
- [ ] CI reviewer is monitoring Actions