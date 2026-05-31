# Discord Platform — Duplicate Slash Command Registration Fix

## Symptom

Discord platform shows `state: paused` with error `failed to reconnect` in the gateway status API (`http://127.0.0.1:9119/api/status`).

Gateway logs show:
```
CommandAlreadyRegistered: Command 'httpx' already registered.
```
or
```
CommandAlreadyRegistered: Command 'subfinder' already registered.
```

The platform retries every 5 minutes, fails 10 times, then auto-pauses.

## Root Cause

The file `~/.hermes/hermes-agent/gateway/platforms/discord.py` contains **duplicate `@tree.command()` decorator registrations** for the same slash command name. When the gateway reconnects, the in-memory command tree already has the command from the first registration, so the second `@tree.command()` decorator raises `CommandAlreadyRegistered`.

This can happen after:
- A hermes-agent update that adds new slash commands
- A plugin that registers slash commands
- Manual edits to `discord.py`

## Diagnosis

Check for duplicate command registrations:
```bash
grep -n '@tree.command(name=' ~/.hermes/hermes-agent/gateway/platforms/discord.py | awk -F'"' '{print $2}' | sort | uniq -d
```

This will output any command names that appear more than once (e.g., `httpx`, `subfinder`).

## Fix

1. **Remove the duplicate registration** — keep the first (original) definition, remove the second:
   ```bash
   grep -n 'name="httpx"' ~/.hermes/hermes-agent/gateway/platforms/discord.py
   grep -n 'name="subfinder"' ~/.hermes/hermes-agent/gateway/platforms/discord.py
   ```
   Each will show two line numbers. Remove the second block (from the duplicate `@tree.command()` to just before the next `@tree.command()`).

2. **Restart the gateway:**
   ```bash
   hermes gateway restart
   ```

3. **Verify** — check that Discord shows `state: connected`:
   ```bash
   curl -s http://127.0.0.1:9119/api/status | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway_platforms']['discord'])"
   ```

## Prevention

After any `hermes update`, re-run the duplicate check above. The update may re-introduce duplicates if the upstream codebase has the same bug.

## Session History

- **2026-05-21**: Fixed duplicates for `httpx` (lines 3439+3808) and `subfinder` (lines 3402+3908). Gateway restarted successfully, Discord reconnected.
