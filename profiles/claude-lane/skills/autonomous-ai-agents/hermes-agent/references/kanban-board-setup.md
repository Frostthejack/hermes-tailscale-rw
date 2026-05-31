# Kanban Board + Specialist Profile Setup Playbook

## Full Setup Workflow

### 1. Create the board

```bash
hermes kanban boards create <slug> --name "<Display Name>" --switch
```

The `--switch` flag sets the new board as active. Verify with:
```bash
hermes kanban boards list
```

**Gotcha:** The `hermes kanban boards show` and `hermes kanban boards current` commands
may report a different board than what `~/.hermes/kanban/current` contains. The `current`
file is the source of truth. If they disagree, run `hermes kanban boards switch <slug>`.

### 2. Initialize the DB

```bash
hermes kanban init
```

This is idempotent — safe to run on existing boards. It also auto-discovers profiles on disk.

### 3. Create specialist profiles

Clone from `default` to inherit model config, API keys, and skills:

```bash
for name in researcher analyst writer reviewer backend-eng frontend-eng ops pm; do
  hermes profile create "$name" --clone-from default
done
```

Each profile gets:
- A wrapper script at `~/.local/bin/<name>`
- Its own config at `~/.hermes/profiles/<name>/`
- Its own SOUL.md for personality customization

**Gotcha:** Cloned profiles inherit the model but show "no API keys yet" — they actually
inherit keys from the parent profile's `.env` at runtime. No need to run `<name> setup`
unless you want per-profile keys.

### 4. Verify profiles are recognized

```bash
hermes kanban assignees
```

Should list all profiles with `(idle)` status.

### 5. Verify the dispatcher

The gateway's embedded dispatcher handles task spawning. Confirm it's configured:

```bash
grep -A2 "^kanban:" ~/.hermes/config.yaml
# Should show:
#   dispatch_in_gateway: true
#   dispatch_interval_seconds: 60
```

Confirm the gateway is running:
```bash
hermes gateway status
```

### 6. Test dispatch with a smoke task

```bash
hermes kanban create "test: verify dispatch" \
  --assignee researcher \
  --body "Report that you're alive."
```

Wait up to 60 seconds (dispatch interval), then check:
```bash
hermes kanban show <task_id>
```

Should show `status: done` with a summary from the researcher profile. If it stays in
`ready`, manually trigger one dispatch cycle:
```bash
hermes kanban dispatch
```

**Gotcha:** The `--board` flag goes on `hermes kanban`, NOT after the subcommand:
- Correct: `hermes kanban --board rollsiege list`
- Wrong: `hermes kanban list --board rollsiege`

### 7. Clean up test tasks

```bash
hermes kanban archive <task_id>
```

## Standard Specialist Roster

| Profile | Role | Workspace |
|---------|------|-----------|
| `researcher` | Reads sources, gathers facts | `scratch` |
| `analyst` | Synthesizes, ranks, de-dupes | `scratch` |
| `writer` | Drafts prose | `scratch` or `dir:` |
| `reviewer` | Reviews output, gates approval | `scratch` |
| `backend-eng` | Server-side code | `worktree` |
| `frontend-eng` | Client-side code | `worktree` |
| `ops` | Scripts, services, deployments | `dir:` |
| `pm` | Specs, acceptance criteria | `scratch` |

## Customizing Profiles

Edit a profile's personality:
```bash
hermes profile show <name>          # See profile path
# Then edit ~/.hermes/profiles/<name>/SOUL.md
```

Change a profile's model:
```bash
hermes -p <name> model              # Interactive model picker
```

## Useful Board Commands

```bash
hermes kanban list                  # List all tasks
hermes kanban stats                 # Per-status counts
hermes kanban watch                 # Live event stream (Ctrl+C to exit)
hermes kanban show <id>             # Task details + events
hermes kanban tail <id>             # Follow event stream for one task
hermes kanban gc                    # Garbage-collect old workspaces/events
```

## Multi-Board Workflow

Each board is an isolated SQLite DB at `~/.hermes/kanban/boards/<slug>/kanban.db`.
The dispatcher loops across ALL boards every tick, so tasks on any board get picked up.

Switch active board:
```bash
hermes kanban boards switch <slug>
```

Or use `--board` on individual commands:
```bash
hermes kanban --board rollsiege list
hermes kanban --board mimiral create "task" --assignee writer
```
