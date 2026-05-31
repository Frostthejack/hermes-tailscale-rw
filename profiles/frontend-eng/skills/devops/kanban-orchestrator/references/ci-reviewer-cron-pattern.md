# CI Reviewer Cron Job Pattern

## Purpose
Automatically monitor GitHub Actions workflow runs after each push/PR, detect failures, and create kanban tasks to fix them. This closes the loop between "code is pushed" and "someone is fixing the breakage."

## Cron Job Setup

```
cronjob create:
  name: "<Project> CI Reviewer"
  schedule: every 30m
  skills: ["kanban-worker"]
  enabled_toolsets: ["terminal"]
```

## Prompt Template

```
You are the CI Reviewer for the <project> project. Your job is to check the latest GitHub Actions workflow runs, identify failures, and create kanban tasks to fix them.

Steps:
1. Run `cd <repo> && gh run list --limit 5 --json status,conclusion,workflowName,url,headBranch,databaseId`
2. For any run with conclusion "failure":
   a. Run `gh run view <databaseId> --json jobs` for failed job details
   b. Run `gh run view <databaseId> --log-failed` for error output
   c. Analyze: test failure, build error, deployment issue, or infrastructure?
   d. Check the kanban board: `hermes kanban --board <slug> list`
   e. If no existing task covers this failure, create one:
      `hermes kanban --board <slug> create "<title>" --assignee <profile> --body "<description>"`
      Assign to: backend-eng (API/test), frontend-eng (UI), ops (deploy/infra)
   f. Add a comment with the full error log excerpt
3. If all runs passing: report "All CI checks passing — no action needed"
4. If gh auth not configured: report that and create a task for ops to fix auth

Important: Only create NEW tasks for failures that don't already have a kanban task. Check the board first.
```

## Prerequisites

- `gh` CLI must be authenticated (`gh auth login` or `GH_TOKEN` env var)
- The kanban board must already be initialized
- The reviewer profile must exist (or use an existing profile like `ops`)

## Common Failure Patterns

| Pattern | Assignee | Priority |
|---|---|---|
| Test assertions failing | backend-eng or frontend-eng | high |
| Build/compile errors | backend-eng or frontend-eng | critical |
| Deployment timeout | ops | high |
| Database connection in CI | ops or backend-eng | critical |
| Missing env vars in CI | ops | high |

## Pitfalls

- **gh auth**: The cron job will silently fail if `gh` isn't authenticated. Always create a prerequisite ops task to set up auth.
- **Duplicate tasks**: Always check the board before creating a new task. Multiple failed runs of the same workflow should not create multiple tasks.
- **Stale failures**: If a failure is already fixed on a newer run, don't create a task for the old failure.
