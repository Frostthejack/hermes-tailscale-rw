# Kanban Worker — Protocol Violation & Rate Limit Patterns

## Worker Crash / Protocol Violation Pattern

When a worker exits cleanly (rc=0) without calling `kanban_complete` or `kanban_block`, the dispatcher logs "protocol violation" and marks the task as crashed. After hitting the retry limit, the task becomes **blocked**.

### OpenRouter Rate Limit Root Cause (Live Incident 2026-05-21)

**Verified details:**
- Profile: `backend-eng` → model `@preset/logos-coder` → resolves to `deepseek/deepseek-v4-pro-20260423` on OpenRouter
- Account: Paid tier ($10/week), NOT free tier — but still hit limits under concurrent worker load
- Failure point: `handle_max_iterations()` in `conversation_loop.py` makes a final summary API call → gets HTTP 429 → exception propagates PAST the `kanban_block` try/except → worker crashes with "protocol violation"
- Fix applied: Wrap `_handle_max_iterations()` in try/except so rate-limit failures don't prevent `kanban_block`:

```python
try:
    final_response = agent._handle_max_iterations(messages, api_call_count)
except Exception as _exc:
    logger.warning("handle_max_iterations failed (%s) — continuing so kanban_block can be called", _exc)
    final_response = f"[Iteration budget exhausted — summary generation failed: {_exc}]"
```

### Prevention Rules for Workers

1. **ALWAYS commit and push BEFORE calling `kanban_complete`** — if the session drops after `git push` but before `kanban_complete`, the orchestrator can verify the commit and complete the task
2. **Include commit hash in `kanban_complete` metadata** — `metadata={"commit": "abc123", ...}`
3. **Write `kanban_comment` checkpoints** every few minutes during long tasks
4. **Call `kanban_block` with progress summary** if you sense the session ending
5. **Never silently exit** — always call `kanban_complete` or `kanban_block` before the session ends

### Phantom Completions

A worker can complete implementation (files on disk) but the dispatcher marks the task blocked/crashed because the worker died before calling `kanban_complete`. 

**Detection:** Task blocked with `pid not alive` errors, but git log shows the work was committed.

**Resolution:**
1. Verify the implementation exists and compiles
2. If work is done: `hermes kanban unblock <id>` then complete with the commit hash
3. If work is NOT done: reset to `ready`, clear failure count, and re-dispatch

### Discovered Pitfalls (This Session)

- **10,497+ runs on a single task** — all crashed with protocol violation. The root cause was `handle_max_iterations` API failure propagating past `kanban_block`.
- **No rate limit headers on OpenRouter 200 responses** — can't detect rate limits from response headers; only see them on 429 errors
- **`@preset/logos-coder` is NOT a free model** — it resolves to a paid DeepSeek model, but the preset name is misleading
- **API key check**: Use `https://openrouter.ai/api/v1/auth/key` to verify limits; `is_free_tier: false` doesn't mean "no limits"
