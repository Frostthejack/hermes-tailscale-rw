# Project State Sync — Cron Job Pattern

## Purpose
Syncs the current kanban board state + git activity into the project's `project-state.md` file in the vault, keeping the vault as the single source of truth for project status.

## When to Create
- During Phase 4 (Continuous Monitoring) of the coding project lifecycle
- After the kanban board is active and has tasks
- After the vault project-state.md exists

## Cron Config
```
Schedule: every 2h
enabled_toolsets: ["terminal", "file"]
deliver: "discord:<channel_id>:<thread_id>"
```

## Prompt Template
```
You are the <Project Name> Project State Sync. Update the project-state.md in the vault with current project state.

IMPORTANT: If you encounter API errors (504, 429, "operation aborted"), retry up to 3 times with 5-second delays between attempts. If all retries fail, output "SYNC FAILED: [error reason]" and exit.

Steps:
1. Read the current project-state.md from the vault:
   cat <vault-path>/Projects/Personal/<project-name>/project-state.md

2. Check the kanban board:
   hermes kanban --board <slug> list

3. Check git for recent commits:
   cd <project-path> && git log --oneline -10

4. Check for any uncommitted changes:
   cd <project-path> && git status --short

5. Update project-state.md with:
   - Current timestamp
   - Current phase and progress
   - Task counts (done, running, blocked, ready)
   - Recent commits
   - Any known issues or blockers
   - Update the "Last updated" timestamp

6. Write the updated file to the vault:
   <vault-path>/Projects/Personal/<project-name>/project-state.md

7. Commit and push the vault:
   cd <vault-path>
   git add Projects/Personal/<project-name>/project-state.md
   git commit -m "chore: sync <project-name> project state"
   git push origin Main

Output a brief summary of what was updated.
```

## DaemonCore Example
- Job ID: `9cb6fd1437ee`
- Schedule: every 2h
- Board: `daemoncore`
- Vault path: `/mnt/c/Users/luned/Vault/Encephalon-Mageia/Projects/Personal/DaemonCore/`
- Project path: `/mnt/c/Users/luned/Documents/Projects/DaemonCore/`
- Deliver: `discord:1505062204171489340:1505068413339308163`
