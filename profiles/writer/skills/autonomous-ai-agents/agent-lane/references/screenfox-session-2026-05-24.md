# ScreenFox Session 2026-05-24 — Agent Lane Validation

## Purpose
Validate the end-to-end agent-lane kanban delegation pattern.

## Key Findings

### `read_file` Truncates Long Values
The `read_file` tool displayed `sk-or-...2138` for the API key but the actual value was the full 73-char key. Verify with `xxd` or Python byte-level reads when debugging auth.

### Claude OAuth ≠ OpenRouter Key
- `claude -p` uses Claude Pro OAuth (separate system)
- OpenRouter key in profile config is for the Hermes worker's own LLM calls
- These are completely independent — don't confuse them

### Worktree Cherry-Pick Breaks with Build Artifacts
`git cherry-pick` fails when worktree has untracked build artifacts. Use manual file copy instead.

### Orchestrator Must Not Code Directly
When testing the agent-lane pattern, the orchestrator must dispatch to `claude -p`/`agy -p`, not implement directly.

### OAuth Token Expiry
Claude OAuth tokens expire after ~24h. Check with `claude auth status` and look at `expiresAt` field. Re-auth with `claude auth login`.
