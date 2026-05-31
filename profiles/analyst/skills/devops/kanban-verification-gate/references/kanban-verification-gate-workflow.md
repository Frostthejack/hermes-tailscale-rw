# Kanban Verification Gate 

## Post-Fix Workflow Update

**Verification is mandatory before `kanban_complete`** — no exceptions.

### For Code-Tasks (Engineer or Orchestrator)

**Rule:** Push → Wait for CI → Verify → Complete

```bash
# 1. Push (worker should do this, but double-check)
git add -A && git commit -m "fix: ..." && git push origin <branch>

# 2. Wait for GitHub Actions
gh run list --repo Frostthejack/rollsiege --limit 3
# All runs must show: status=completed conclusion=success

# 3. Verify
# - Check tests pass in the run
# - Verify the deployment URL works (if applicable)
# - Manually test critical paths

# 4. Only then complete in kanban
hermes kanban complete <id> --summary "..." --metadata '{"ci_url": "...", "commit": "..."}'
```

**Worker automatic check (optional):** Worker script can run `gh run list --limit 3` and fail if not all green.

### For Non-Code Tasks (Research, Review, Ops)

**Required evidence in summary:** specific findings, data, links, or commands run.

**Bad summary:** "Research done, caching looks fine."

**Good summary:** "Queried CloudWatch for /api/errors metric over 7 days. No significant increase. Checked Sentry — zero new errors since deploy abc123. Recommendation: keep current cache TTL of 300s. [CloudWatch screenshot attached]"

## Phantom Completion Detection

When a task is marked "done" but implementation is missing:

1. Red flag: No commit in git log for this task's time period
2. Red flag: Source files unchanged
3. Red flag: CI shows recent failures on this change

**Resolution in orchestrator:** Reset task to `ready`, notify user, mark old "done" entry as phantom in comments.

## CI Failures No Longer Accepted as "Works Locally"

**Old pattern (bad):**
- "Tests pass locally"
- Mark task done
- CI fails on push → cascading failures

**New pattern (required):**
- Push → CI runs → all pass → mark done → include CI run URL in summary

If CI fails, task is not done. Fix in same task or create a new fix task.

## Code Review Requirement Update

For every code task (backend-eng, frontend-eng):
1. Engineer creates task with VERIFICATION criteria
2. Engineer pushes code, CI runs
3. **Independent reviewer** (not the engineer) verifies CI passed and implementation matches criteria
4. Reviewer approves
5. Engineer marks done with review's approval note

This prevents "self-review" where engineers approve their own code.
