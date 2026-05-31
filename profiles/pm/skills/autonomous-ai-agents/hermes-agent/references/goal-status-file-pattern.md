# Goal Status File Pattern

## Problem
When running long `/goal` tasks, the user has no visibility into progress until the goal completes or a cron job polls. The agent works autonomously with no intermediate status reporting.

## Solution: Status File Injection

Modify the continuation prompt template in `hermes_cli/goals.py` to instruct the agent to write status updates to a file every turn. A separate cron job watches the file and forwards changes to the user.

### Step 1: Modify the Continuation Prompt

In `~/.hermes/hermes-agent/hermes_cli/goals.py`, the `CONTINUATION_PROMPT_TEMPLATE` (line ~70) controls what the agent sees on each loop iteration. Add a status file writing instruction:

```python
CONTINUATION_PROMPT_TEMPLATE = (
    "[Continuing toward your standing goal]\n"
    "Goal: {goal}\n\n"
    "Continue working toward this goal. Take the next concrete step. "
    "If you believe the goal is complete, state so explicitly and stop. "
    "If you are blocked and need input from the user, say so clearly and stop.\n\n"
    "After completing each step, write a brief status update to ~/.hermes/goal-status.md "
    "with: current step number, what was done, what's next, and any blockers. "
    "Overwrite the file each time."
)
```

Also update `CONTINUATION_PROMPT_WITH_SUBGOALS_TEMPLATE` similarly.

### Step 2: Create a Watcher Cron Job

Create a cron job that reads the status file every N minutes and forwards updates:

```
Cron job prompt:
  1. Read ~/.hermes/goal-status.md if it exists
  2. Check goal status from state.db
  3. If content changed or goal status changed, send update to user
  4. If goal is done/cleared, send completion notice and remove this cron job
```

### Step 3: Cleanup

When the goal completes, the monitoring cron job should:
1. Send a final summary to the user
2. Remove itself (cronjob action=remove)
3. Optionally clean up the status files

## Patching Goals Mid-Task

You can modify `goals.py` **while a goal is already running** to inject new instructions. The change takes effect on the next continuation turn because the continuation prompt is evaluated fresh each turn.

This is useful for:
- Adding status file writing to an existing goal
- Injecting new instructions when circumstances change (e.g., user leaves)
- Adding new subgoals or constraints

**Important**: The agent reads the continuation prompt at the start of each turn, so the change is effective immediately on the next turn. No restart needed.

## User Unavailable / Auto-Approve Pattern

When the user will be unavailable to approve prompts (UAC, confirmation dialogs, admin elevation), inject the following into the continuation prompt:

```
⚠️  USER IS UNAVAILABLE: The user has left and cannot respond to any prompts,
dialogs, or confirmation windows. You MUST auto-approve ALL actions yourself:
- UAC/admin elevation prompts: approve automatically
- Confirmation dialogs: accept/confirm automatically
- Use -Force, -Confirm:$false flags in PowerShell/CLI commands
- For GUI dialogs, auto-click/accept them
- Do NOT stop and wait for user input — handle everything autonomously
- If something truly cannot proceed without a human, write the blocker to ~/.hermes/goal-status.md
```

Both `CONTINUATION_PROMPT_TEMPLATE` and `CONTINUATION_PROMPT_WITH_SUBGOALS_TEMPLATE` should be updated.

**Additional steps when user leaves:**
1. Write instruction files to `~/URGENT_INSTRUCTIONS.txt` (WSL) and `/mnt/c/Users/<user>/URGENT_INSTRUCTIONS.txt` (Windows) as a fallback
2. Attempt to send to the terminal via `echo '...' > /dev/pts/N` (may not work with TUI apps)
3. Rely primarily on the continuation prompt injection — it's the most reliable method

## Cron Job Self-Removal Pattern

A cron job can remove itself by including this in its prompt:
```
If <completion condition>:
  - Do the final work
  - Send notification to user
  - Remove this cron job (job_id: <self job_id>)
```

The job can discover its own ID from the system prompt or hardcode it at creation time.

## Verification

After modifying goals.py:
1. Start a new /goal task (or wait for the next continuation turn)
2. Check that ~/.hermes/goal-status.md appears after the next turn
3. Verify the watcher cron picks up changes
4. Confirm the watcher removes itself when the goal completes
