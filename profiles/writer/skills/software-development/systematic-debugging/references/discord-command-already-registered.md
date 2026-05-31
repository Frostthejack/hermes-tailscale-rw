# Discord `CommandAlreadyRegistered` on Reconnect

## The Bug

When the Hermes Agent Discord platform reconnects (after a restart or network hiccup), it calls `_register_slash_commands()` which uses `@tree.command()` decorators to register slash commands in-memory. If the same command name is registered **twice** in the same process (e.g., duplicate `@tree.command(name="httpx", ...)` definitions in `discord.py`), the second registration raises:

```
discord.app_commands.errors.CommandAlreadyRegistered: Command 'httpx' already registered.
```

This causes the entire connection to fail. After 10 consecutive failures, the gateway **pauses** the Discord platform with `"failed to reconnect"`.

## Diagnosis

1. Check platform status: `curl http://127.0.0.1:9119/api/status` — look for `"discord": {"state": "paused", "error_message": "failed to reconnect"}`
2. Check logs: `journalctl --user -u hermes-gateway --no-pager -n 50 | grep -E "CommandAlreadyRegistered|discord.*Failed"`
3. The error message names the duplicate command: `Command 'httpx' already registered`

## Root Cause Pattern

In `~/.hermes/hermes-agent/gateway/platforms/discord.py`, the `_register_slash_commands()` method has multiple `@tree.command()` decorators. If any command name appears more than once, the second one fails.

Common causes:
- A plugin or skill registers a command that the platform already defines
- A code merge left two copies of the same command definition
- A refactor renamed the function but left the old `@tree.command()` decorator

## Fix

1. **Find duplicates:**
   ```bash
   grep -n '@tree.command(name=' ~/.hermes/hermes-agent/gateway/platforms/discord.py | awk -F'"' '{print $2}' | sort | uniq -d
   ```
   This lists all command names that appear more than once.

2. **Locate both occurrences:**
   ```bash
   grep -n 'name="COMMAND_NAME"' ~/.hermes/hermes-agent/gateway/platforms/discord.py
   ```

3. **Remove the duplicate** — keep the first (original) definition, remove the second `@tree.command()` decorator and its entire function body. Use `patch(mode='replace')` with enough surrounding context to make the match unique.

4. **Verify no more duplicates:**
   ```bash
   grep -n '@tree.command(name=' ~/.hermes/hermes-agent/gateway/platforms/discord.py | awk -F'"' '{print $2}' | sort | uniq -d
   ```
   Should return empty.

5. **Restart the gateway:**
   ```bash
   hermes gateway restart
   ```

6. **Verify Discord connects:**
   ```bash
   sleep 20 && curl -s http://127.0.0.1:9119/api/status | grep -oP '"discord":\{[^}]+\}'
   ```
   Should show `"state":"connected"`.

## Real Example (2026-05-21)

`discord.py` had duplicate registrations for `httpx` (lines 3439 and 3808) and `subfinder` (lines 3402 and 3908). The second `httpx` used a different binary path (`~/.local/bin/httpx` vs `~/go/bin/httpx`) and different CLI flags (`--status-code` vs `-sc`). Removing the second definition of each and restarting the gateway resolved the issue.

## Prevention

- Before merging changes to `discord.py`, run the duplicate check above
- When adding a new slash command, grep for the name first to ensure it doesn't already exist
- The `@tree.command()` decorator registers in-memory at import time — there's no "replace" semantics, only "add" (which fails if already present)
