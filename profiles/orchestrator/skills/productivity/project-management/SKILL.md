---
name: project-management
description: Manage project-state.md files for all active projects. Defines the template, update triggers, and vault git workflow.
triggers:
  - project state
  - project-state
  - update project
  - project status
  - project management
  - all projects status
  - what's the status of
---

# Project Management Skill

Maintain `project-state.md` files for every active project in the Encephalon-Mageia vault.

## Memory Architecture Context

> **Read `agent-capability-system` skill** for the full memory architecture breakdown. Key points:
> - MEMORY.md has a 2,200 char limit — do NOT store project details there
> - The `memory()` tool can only write to MEMORY.md/USER.md in `~/.hermes/memories/`
> - Use `write_file()` / `read_file()` for project info files
> - Hindsight is unlimited and searchable; MEMORY.md is bounded and flat
> - **HERMES.md** (`~/.hermes/HERMES.md`) is the durable auto-loaded context file — loads every session when `terminal.cwd` is set to `~/.hermes/` in config.yaml
> - **5-layer durability:** HERMES.md → projects/info/ → projects/README.md → MEMORY.md pointer → Hindsight retention → vault git

## Operational Project Info Files

In addition to `project-state.md` in the vault, create and maintain operational details at:
```
~/.hermes/projects/info/<project-name>.md
```

Use the template at `templates/project-info-template.md` when creating new project info files.

See `references/project-info-readme-template.md` for the full memory architecture summary and the durable README pattern for `~/.hermes/projects/README.md`.

These files store Hermes-infrastructure details that don't belong in project-state.md:
- Kanban board slug and task routing
- Cron job names and schedules
- Agent lane assignments
- Workspace paths and symlink status
- Kanban DB location and common queries

Format:
```markdown
# <Project Name> — Hermes Infra
- Code repo: <user>/<repo> → <local path>
- Vault: /mnt/c/Users/luned/Vault/Encephalon-Mageia/Projects/Personal/<project>/
- Board slug: <slug>
- Symlinks: docs/ → vault, project-state.md → vault
- Cron jobs: [list active jobs]
- Agent lanes: [claude-lane, agy-lane, etc.]
```

## Vault Location

All project-state files live at:
```
/mnt/c/Users/luned/Vault/Encephalon-Mageia/Projects/<Category>/<Project>/project-state.md
```

## Template Structure

Every `project-state.md` follows this template:

```markdown
# <Project Name> — Project State

> Last updated: <YYYY-MM-DD>
> Repo: <github link or N/A>
> Live URL: <url or N/A>
> Local dev: <how to run locally>

## What is <Project>?
<2-3 sentence description>

## Tech Stack
| Layer | Technology |
|-------|-----------|
| ... | ... |

## Architecture
<diagram, key files, API routes, data schema>

## Current State (<YYYY-MM-DD>)

### Done
- [x] ...

### In Progress
- [ ] ...

### Known Issues / TODO
- [ ] ...

## Deployment
<how to deploy>

## Verification Checklist
1. [ ] ...

## Recent Commits
- `<sha>` — <message>

## Git Config
<git author, package identifier, etc.>
```

## Update Triggers (ALL 4 must be implemented)

### Trigger 1: After Every Work Session
When finishing any work on a project:
1. Update the project's `project-state.md`
2. Update "Current State" (move items between Done/In Progress/TODO)
3. Update "Recent Commits" with latest SHAs
4. Update "Last updated" date
5. Update "Known Issues / TODO" if new issues discovered or resolved
6. **Credential audit:** If secrets are missing, truncated, or placeholder, follow the procedure in `coding-project-lifecycle/references/credential-audit-pattern.md` to discover and verify all credentials. Document findings with status indicators (✅ Complete / ⚠️ Truncated / ⚠️ Placeholder / ⚠️ Missing).
7. **Retain to hindsight memory bank** — call `hindsight_retain` with a summary of what was done, decisions made, and key findings. Tag with the project name and work type.
7. **Note:** An auto-consolidate cron job runs every 5 hours to synthesize recent memories across all banks via Hindsight's `/consolidate` endpoint. This is separate from manual `hindsight_retain` calls and happens automatically — no action needed per-session.
7. **Commit and push the vault** (see Vault Git Workflow below)

### Trigger 2: Periodic Refresh (Weekly Cron)
A scheduled cron job that:
1. Reads all `project-state.md` files from the vault
2. For each project with a repo, checks for new commits since "Last updated"
3. Updates "Recent Commits" section with any new commits
4. Updates "Last updated" date
5. Notifies the user if any project has significant changes (new commits, stale state)
6. **Commits and pushes the vault** after updates

### Trigger 3: On-Demand Refresh
When the user asks "update project state for X" or "what's the status of X":
1. Read the current `project-state.md`
2. Check the project's git repo for latest commits
3. Review recent kanban board changes for the project
4. Update all sections of the file
5. **Commits and pushes the vault** after updates

### Trigger 4: Kanban Sync
When kanban tasks change status on a project board:
1. Read the project's `project-state.md`
2. Cross-reference with current kanban board state
3. Update "Current State" to reflect completed/in-progress/blocked tasks
4. Update "Last updated" date
5. **Commits and pushes the vault** after updates

## Vault Git Workflow (CRITICAL)

**Every time any file in the Obsidian vault is written or modified:**

1. Stage all changes in the vault:
   ```bash
   cd /mnt/c/Users/luned/Vault/Encephalon-Mageia
   git add -A
   ```

2. Commit with a descriptive message:
   ```bash
   git commit -m "<type>: <description>"
   ```
   Use conventional commit types:
   - `update project-state.md: <what changed>` — for project state updates
   - `vault backup: <timestamp>` — for routine saves
   - `fix: <what was fixed>` — for corrections
   - `feat: <what was added>` — for new content

3. Push to remote:
   ```bash
   git push origin Main
   ```

**Rules:**
- You may change multiple files before pushing, but ALWAYS push when done with the vault
- Never leave vault changes uncommitted at the end of a session
- If the push fails, retry once, then notify the user
- Git author email: `lunedecente@gmail.com`

## Known Projects

| Project | Vault Path | Has State? | Board |
|---------|-----------|------------|-------|
| RollSiege | `Projects/Personal/RollSiege/` | ✅ Yes | `rollsiege` |
| Agent Persona | `Projects/Personal/Agent-Persona/` | ✅ Yes | `agent-persona` |
| DaemonCore | `Projects/Personal/DaemonCore/` | ✅ Yes | N/A |
| Agent Screen Pet | `Projects/Personal/Agent-Screen-Pet/` | ✅ Yes | N/A |
| Mimiral | `Projects/Personal/Mimiral/` | ✅ Yes | N/A |

## Cron Job Setup

To set up the weekly periodic refresh (Trigger 2):

```
hermes cron add "every Sunday at 9am" \
  --name "Weekly Project State Refresh" \
  --prompt "Run the project-management skill Trigger 2: check all project repos for new commits, update project-state.md files, commit and push vault." \
  --skills project-management \
  --deliver discord:<channel_id>:<thread_id>
```

## Quick Commands

### Check all project states
```bash
find /mnt/c/Users/luned/Vault/Encephalon-Mageia/Projects \
  -name "project-state.md" -exec echo "=== {} ===" \; -exec head -10 {} \;
```

### Check vault git status
```bash
cd /mnt/c/Users/luned/Vault/Encephalon-Mageia && git status
```

### Full vault push
```bash
cd /mnt/c/Users/luned/Vault/Encephalon-Mageia && git add -A && git commit -m "vault backup: $(date '+%Y-%m-%d %H:%M')" && git push origin Main
```
