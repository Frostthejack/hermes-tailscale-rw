---
name: kanban-verification-gate
description: Verification discipline for kanban tasks — no task is done without proof. Workers must run verification criteria and provide evidence, or a reviewer must independently confirm.
version: 1.0.0
metadata:
  hermes:
    tags: [kanban, verification, quality-gate, testing]
    related_skills: [kanban-orchestrator, kanban-worker]
---

# Kanban Verification Gate

> Every task on the board MUST be verified before it can be marked done. No exceptions.

## The Rule

**A task is NOT complete until its verification criteria have been executed and the results are documented.**

This applies to every task that has a `VERIFICATION:` comment or acceptance criteria in its body. If a task has no verification criteria, the worker must still provide a summary of what was done and how they confirmed it works.

## How Verification Works

### Option A: Self-Verification (Worker)

The worker who did the work runs the verification steps themselves and provides evidence:

1. Read the `VERIFICATION:` comment on the task (or the acceptance criteria in the body)
2. Execute EVERY verification step
3. Document the results in the `kanban_complete` summary:
   - Which steps passed
   - Which steps failed (if any, the task is NOT done — fix first)
   - Screenshots, test output, or curl responses as proof
4. Only call `kanban_complete` after ALL steps pass

Example of a good self-verification summary:
```
All verification steps passed:
(1) GET /api/characters → 200, returns 12 characters with abilities[]. Verified.
(2) GET /api/characters?class=SPELLCASTER → 200, returns 1 character (Swamp Witch). Verified.
(3) Each character includes abilities[], passiveAbilities[], triggeredAbilities[]. Verified.
(4) No console errors in browser devtools. Verified.
Test output: 14/14 passing.
```

Example of a BAD summary (no evidence):
```
Done, everything works.
```

### Option B: Independent Review (Reviewer Profile)

For critical tasks, complex features, or when self-verification is insufficient:

1. The worker marks the task with a comment: "Ready for review — verification needed"
2. A `reviewer` task is created (or an existing reviewer picks it up)
3. The reviewer independently runs the verification criteria
4. Reviewer documents findings in the task comment thread
5. If all criteria pass: reviewer approves, original worker marks done
6. If criteria fail: reviewer creates a new fix task assigned to the original worker

## When Independent Review is Required

Independent review is MANDATORY for:
- **E2E tests** — always reviewed, never self-verified
- **Production deployments** — always reviewed
- **Auth/security features** — always reviewed
- **Tasks that took 3+ runs** — the worker has demonstrated they can't reliably self-verify
- **Any task where the worker was blocked** — the blocker may have been resolved incorrectly

## Verification Evidence Types

Acceptable evidence (pick what's appropriate):

| Task Type | Evidence |
|---|---|
| API endpoint | curl responses, test output, Postman screenshots |
| UI component | Screenshots, screen recording, browser console output |
| Database | Query results, migration output, seed confirmation |
| Deployment | URL of working deployment, health check response |
| E2E test | Playwright test output, screenshots at each step |
| Config change | Before/after diff, service restart confirmation |

## Anti-Patterns (Do NOT)

- **"It compiles, so it works"** — compilation is not verification
- **"I tested it manually"** — what exactly did you test? Show the steps and results.
- **"The code looks correct"** — code review is not runtime verification
- **"Previous tasks passed, so this should work"** — each task is independent
- **Marking done and moving on** — if you're not willing to verify, you're not done
- **Trusting env vars in production** — always verify that environment variables (especially `NEXT_PUBLIC_APP_URL`, `DATABASE_URL`, Supabase keys) are correctly set in the deployment environment (Vercel, etc.), not just in `.env.local`. A common failure mode: code works locally because `.env.local` has the right values, but production uses defaults or stale values.

## CI Verification — MANDATORY for Code Tasks

For any kanban task that involves code changes (features, fixes, refactors, config changes):

1. **Push your changes** to the GitHub repo
2. **Wait for GitHub Actions** to complete (check with `gh run list --repo Frostthejack/rollsiege --limit 3`)
3. **Verify 0 failures** — all tests must pass
4. **Only then** call `kanban_complete`
5. **Include the passing run URL** in your completion summary

If CI fails:
- Do NOT mark the task done
- Fix the failures (either in the same task or create a new fix task)
- Re-push and re-verify
- Repeat until CI passes

**This is non-negotiable.** The #1 cause of cascading failures on this project is workers marking tasks done when CI is broken. A task is not "done" until the tests pass.

## For Orchestrators

When creating code tasks on the board:
1. ALWAYS include a `VERIFICATION:` comment with specific, executable test steps
2. ALWAYS include a CI verification step: "Push to repo, wait for GitHub Actions, verify 0 failures"
3. Assign verification type: self-verify or independent-review
4. For independent review, create the reviewer task alongside the work task
5. Set the reviewer task as a parent of any downstream tasks that depend on the verified work

## Deployment Gotchas

See [references/deployment-gotchas.md](references/deployment-gotchas.md) for common patterns:
- Supabase auth email redirects pointing to localhost
- Vercel duplicate deployments
- Environment variable mismatches between local and production
- Auth wall blocking dashboard feature testing

## Phantom Completion Detection

A **phantom completion** is when a task is marked "done" but the implementation is missing, incomplete, or was never started. This is the #1 cause of cascading project failures.

**Red flags that indicate phantom completions:**
- Multiple tasks in the same phase all marked "done" simultaneously (within seconds of each other)
- A "done" task has no corresponding git commit or code change
- The `kanban_complete` summary is vague ("done", "shipped", "implemented") with no file names, test results, or commit hashes
- A task marked "done" but the expected source file doesn't exist or is unchanged from before
- All tasks in a phase are "done" but the phase review criteria clearly aren't met

**What to do when you detect phantom completions:**
1. Read the expected source files — confirm the code actually exists
2. Check `git log` — confirm there's a commit for the work
3. Try to build — confirm the code compiles
4. If the implementation is missing: reset the task to `ready` and re-dispatch, or implement it directly
5. If multiple tasks in a phase are phantom: the entire phase needs to be re-done. Don't proceed to the next phase.
6. Report to the user: "Phase N has X phantom completions. Tasks Y and Z were marked done but have no implementation. Re-dispatching."

**Prevention:** The orchestrator should verify implementations exist (by reading source files) every time a worker marks a task done. Don't wait until the phase review to discover phantom completions.

## Board Hygiene

Periodically (via CI Reviewer cron job or manual audit):
1. Check all `done` tasks for verification evidence in their summaries
2. If a task was marked done without evidence, create a review task to retroactively verify
3. Track which profiles consistently skip verification and flag for process improvement
