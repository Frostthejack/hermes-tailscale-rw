# Cron Job Retry Pattern — Handling API Failures

## Problem
Cron jobs that make API calls can fail with transient errors:
- `RuntimeError: HTTP 504: The operation was aborted` (OpenRouter upstream timeout)
- `RuntimeError: The operation was aborted` (connection drop)
- `HTTP 429: Rate limit exceeded` (provider rate limit)

These cause the cron job to fail silently and report stale/incorrect data.

## Solution
Add explicit retry instructions to the cron prompt:

```
IMPORTANT: If you encounter API errors (504, 429, "operation aborted"), retry up to 3 times with 5-second delays between attempts. If all retries fail, output "JOB FAILED: [error reason]" and exit.
```

## Implementation Notes
- The cron job agent will retry the entire operation, not just the failed API call
- 5-second delays prevent hammering a struggling provider
- After 3 failures, the job reports the error instead of silently failing
- The error output is delivered to the Discord thread so the user knows the job is broken

## When to Use
- Any cron job that makes API calls (board monitoring, state sync, CI review)
- Any cron job that reads/writes files on Windows filesystem (WSL can have transient 9P errors)
- Any cron job that depends on external services (GitHub API, Vercel, Supabase)

## Example: Board Monitor with Retry
```
Check the <project> kanban board and report progress.

IMPORTANT: If you encounter API errors (504, 429, "operation aborted"), retry up to 3 times with 5-second delays between attempts. If all retries fail, output "MONITOR FAILED: [error reason]" and exit.

Run: hermes kanban --board <slug> list
Only report if there are actual changes. If nothing changed, output "[SILENT]".
Do NOT load any skills.
```
