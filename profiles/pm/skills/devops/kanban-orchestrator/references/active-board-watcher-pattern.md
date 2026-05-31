# Active Board Watcher — Cron Job Pattern

A more aggressive board monitor that doesn't just report status — it diagnoses and fixes issues.

## When to use

Set this up for active projects where workers are frequently dispatched and you want automated recovery from common failure modes.

## Cron job configuration

```
Name: <Project> Active Board Watcher
Schedule: every 5h
enabled_toolsets: ["terminal", "file"]
deliver: "discord:<channel_id>:<thread_id>"
```

## Prompt template

Use the prompt from the DaemonCore Active Board Watcher (job_id: 92730cd2da79) as a reference. Key elements:
- Check board status with `hermes kanban --board <slug> list`
- Identify blocked tasks, stuck running tasks, phantom completions, consecutive failures
- Check worker logs and SQLite DB for failure details
- Auto-fix: reset blocked tasks with dead workers, verify phantom completions, fix incorrect parent dependencies
- Verify build health (git status, git log)
- Report findings or output [SILENT]

## Key differences from simple monitor

| Feature | Simple Monitor | Active Watcher |
|---------|---------------|----------------|
| Reports status | ✅ | ✅ |
| Auto-fixes blocked tasks | ❌ | ✅ |
| Verifies implementations | ❌ | ✅ |
| Detects phantom completions | ❌ | ✅ |
| Checks worker health | ❌ | ✅ |
| Schedule | Every 5-10 min | Every 5 hours |

## Common issues it catches

1. **Workers died after writing code** — `pid not alive` errors, task blocked, but implementation exists on disk
2. **Phantom completions** — task marked done but files are missing or contain stubs
3. **Incorrect parent dependencies** — tasks blocked by wrong parents
4. **Stale running tasks** — worker process exists but hasn't made progress
5. **Build breakage** — code was committed but doesn't compile
