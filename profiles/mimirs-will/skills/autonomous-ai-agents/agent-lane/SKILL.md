---
name: agent-lane
description: >
  Use when a Hermes Kanban worker wants to delegate a coding task to an agent CLI
  (Claude Code, Antigravity CLI, Codex, or OpenCode) in an isolated workspace
  while Hermes keeps ownership of the task lifecycle, reconciliation, testing,
  and handoff. Defines the agent-lane pattern: agent CLIs are input lanes only;
  Hermes owns acceptance, testing, and board state.
version: 1.5.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [kanban, agent-lane, claude-code, antigravity-cli, codex, opencode, worktrees]
    related_skills: [claude-code, antigravity-cli, codex, opencode, kanban-codex-lane, kanban-worker]
---

# Agent Lane — Kanban Delegation Pattern

## Overview

This skill defines the **agent lane** convention: a Hermes Kanban worker delegates implementation work to an agent CLI (Claude Code, Antigravity CLI, Codex, or OpenCode) in an isolated workspace, then reconciles the output, runs verification, and writes the final `kanban_complete` or `kanban_block` handoff.

**Core principle:** The agent CLI is an *input lane only*. Hermes owns the Kanban lifecycle, final acceptance, test execution, safety, and cleanup.

This skill generalizes the `kanban-codex-lane` pattern to all agent CLIs.

## 🔑 AUTH & CREDENTIAL POOL PITFALLS (READ THIS FIRST)

Before any delegation works, the worker's API credentials MUST resolve correctly. A worker that hits 401 on its first API call exits rc=0 without calling `kanban_complete`, causing a **protocol violation** and infinite retry loop (observed: 79+ consecutive crashes on one task).

### Symptom
Worker log shows `HTTP 401: Missing Authentication header` on the very first API call. Duration: 1-2s. The worker never gets past initialization.

### Root Cause: `resolve_provider_client()` Requires OPENROUTER_API_KEY Env Var
The worker's agent initialization in `agent/agent_init.py` falls into the `else` branch
(line ~774) which calls `resolve_provider_client("openrouter", ...)`. This function checks
for the `OPENROUTER_API_KEY` **environment variable** — NOT `config.yaml` →
`providers.openrouter.api_key`.

If the env var is not set, `resolve_provider_client` logs "OPENROUTER_API_KEY not set"
and returns `None`. The worker then creates an OpenAI client with no api_key → immediate
401 "Missing Authentication header" → exits rc=0 without calling `kanban_complete`.

**This is the actual root cause.** The Bitwarden credential pool theory was investigated and
ruled out — the problem existed before Bitwarden was installed. The real issue is purely
that the env var is missing from the gateway process's environment.

### Fix: EnvironmentFile Drop-In + Per-Profile Gateways

The worker auth chain requires `OPENROUTER_API_KEY` at the OS level (`/proc/PID/environ`), not just in Python's `os.environ`. The verified fix is:

1. Create `~/.config/systemd/user/hermes-gateway.service.d/env.conf`:
   ```ini
   [Service]
   EnvironmentFile=%h/.hermes/.env
   ```
2. Restart gateway: `hermes gateway restart`
3. Verify: `cat /proc/$GW_PID/environ | grep OPENROUTER`

For profiles that still can't resolve the key, run a per-profile gateway:
```bash
hermes -p <profile> gateway run --replace &
```
**Caveat**: Multiple gateways competing for the same kanban DB causes `sqlite3.OperationalError: disk I/O error`.

### Claude -p Delegation Auth

`claude -p` requires `CLAUDE_CODE_OAUTH_TOKEN` in the worker's terminal environment. Extract from `~/.claude/.credentials.json` → `claudeAiOauth.accessToken` (108 chars). Also set `env_passthrough: [HOME, USER, LOGNAME, PATH, XDG_CONFIG_HOME]` in the profile's `config.yaml` so `terminal()` passes these to the worker shell.

### Prevention

- Always set `OPENROUTER_API_KEY` in default `~/.hermes/.env` (not just profile `.env`)
- Verify with: `systemctl --user show-environment | grep OPENROUTER`
- For new profiles: create `.env` BEFORE first dispatch, or credential pool seeds from parent env and marks entry exhausted on first 401

```bash
# 1. Get the real key from a working profile
cat ~/.hermes/profiles/agy-lane/.env | grep OPENROUTER_API_KEY

# 2. Write it to the default .env (commented-out → active)
sed -i 's|^# OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=***2138|' ~/.hermes/.env

# 3. Restart gateway (full stop/start)
hermes gateway stop; sleep 2; hermes gateway start
```

For new profiles, also create the profile `.env`:
```bash
echo "OPENROUTER_API_KEY=***" > ~/.hermes/profiles/<new-profile>/.env
```

### 🔑 Hindsight Bank Naming Pitfall (claude-lane → claude_code)

When configuring hindsight bank isolation for lane profiles, the bank ID does NOT always match the profile name:

| Profile | Hindsight Bank ID | Why |
|---------|------------------|-----|
| `claude-lane` | `claude_code` | The pre-existing Claude Code bank is named `claude_code`, not `claude-lane` |
| `agy-lane` | `agy-lane` | Auto-created on first retain |
| All others | `<profile-name>` | Bank ID matches profile name |

Using `bank_id: "claude-lane"` in the hindsight config creates a SEPARATE bank that won't share the existing 1500+ Claude Code memories. Always map `claude-lane` → `claude_code`.

### Prevention
- Always set `OPENROUTER_API_KEY` in the default `~/.hermes/.env` (not just profile `.env`)
- Verify the gateway picked it up: `systemctl --user show-environment | grep OPENROUTER`
- For new profiles: create the `.env` BEFORE the first dispatch, or the credential pool
  seeds from the parent env and marks the entry exhausted on first 401

### Diagnosis
```bash
# Check what key the worker actually sends (real key ~= 73 chars; masked ~= 15)
ls -lt ~/.hermes/profiles/<profile>/sessions/request_dump_*.json | head -3
python3 -c "
import json, glob
d = json.load(open(sorted(glob.glob('~/.hermes/profiles/<profile>/sessions/request_dump_*.json'))[-1]))
key = d['request']['headers']['Authorization'].replace('Bearer ', '')
print(f'Key length: {len(key)} — {\"OK\" if len(key) > 20 else \"MASKED\"}'  )
"

# Check credential pool
hermes auth list
# Look for: source env:OPENROUTER_API_KEY + secret_source bitwarden

# Check Bitwarden config
python3 -c "
import yaml; c = yaml.safe_load(open('/home/frostthejack/.hermes/config.yaml'))
print(c.get('secrets',{}).get('bitwarden',{}))
"
```

### Fix (try in order)

1. **Remove the credential pool entry:**
   ```bash
   hermes auth remove openrouter OPENROUTER_API_KEY
   ```
   This clears the key from `.env` and suppresses re-seeding.

2. **Full gateway restart (stop/start, NOT restart):**
   ```bash
   hermes gateway stop; sleep 2; hermes gateway start
   ```

3. **Verify pool is clean:** `hermes auth list` — openrouter should not appear.

4. **If gateway recreates the entry** (Bitwarden auto-seeds on restart):
   ```bash
   hermes config set secrets.bitwarden.enabled false
   # If gateway overwrites this: stop → edit config.yaml → remove auth.json credential_pool → start
   ```

5. **Nuclear option** — remove `BWS_ACCESS_TOKEN` from `.env` to sever Bitwarden entirely.

### Prevention
- Set `OPENROUTER_API_KEY` in the gateway systemd service environment, not just in config.yaml or .env
- The profile `.env` file is loaded by the CLI but NOT always by the gateway process
- Verify with: `systemctl --user show-environment | grep OPENROUTER`
- When a worker fails with 401, always check `resolve_provider_client()` first before investigating credential pools

### Historical Note
The Bitwarden credential pool was initially suspected because `auth.json` had an `openrouter` entry with `secret_source: "bitwarden"`. However, the problem existed **before Bitwarden was installed**. The real issue is purely the missing env var. The credential pool entry was a red herring.

---

## Agent CLI Quick Reference

| Agent | Binary | Print Mode | Max Turns | Budget Cap | Tool Whitelist |
|-------|--------|-----------|-----------|------------|----------------|
| **Claude Code** | `claude` | `-p "prompt"` | `--max-turns N` | `--max-budget-usd N` | `--allowedTools "Read,Edit,Bash"` |
| **Antigravity CLI** | `agy` | `-p "prompt"` | `--print-timeout 5m0s` | None | settings.json only |
| **Codex** | `codex` | `exec "prompt"` | None | None | `--full-auto` / `--yolo` |
| **OpenCode** | `opencode` | N/A | N/A | N/A | N/A |

## When to Use an Agent Lane

Use when **all** of these are true:

- The Kanban task is coding, refactor, documentation, test, or mechanical migration work with clear acceptance criteria
- A bounded diff can be evaluated by Hermes in one run
- The repo can be copied or checked out in an isolated git worktree/branch
- Hermes can run the relevant tests after the agent exits
- The prompt can state all safety constraints and files that must not change

**Do NOT use** when **any** of these are true:

- The task requires human judgment not captured in the Kanban body
- The worker lacks repo access, agent CLI auth, or time to reconcile
- The prompt involves secret credentials the agent should not see

## Worker Session AGENTS.md Template

Each lane profile (claude-lane, agy-lane, etc.) must have an `AGENTS.md` that enforces:

1. **Isolation first** — always use a git worktree, never work in the shared repo
2. **Prompt-only delegation** — all code changes go through `claude -p` or `agy -p`, never direct file writes
3. **Diff review** — always review the agent's output diff before accepting
4. **Verification** — run the project's canonical test suite
5. **kanban_complete** — MUST be called with `agent_lane` metadata before the worker exits
6. **Cleanup** — remove worktree and temporary branches

Failure to call `kanban_complete` is a **protocol violation** — the dispatcher will keep retrying the task forever.

## Per-Profile Hindsight Bank Configuration

Each lane profile must have BOTH config layers for hindsight to work:

### Layer 1: config.yaml
`~/.hermes/profiles/<name>/config.yaml` must have:
```yaml
memory:
  provider: hindsight
  auto_retain: true
  auto_recall: true
```

### Layer 2: hindsight/config.json
`~/.hermes/profiles/<name>/hindsight/config.json`:
```json
{
  "mode": "local_external",
  "api_url": "http://localhost:8888",
  "bank_id": "<bank-id>",
  "auto_retain": true,
  "retain_every_n_turns": 1,
  "auto_recall": true,
  "retain_async": true
}
```

**Critical:** `bank_id` must match the hindsight bank name, NOT necessarily the profile name. See the pitfall above for `claude-lane` → `claude_code`.

See the `kanban-orchestrator` skill's `references/kanban-profile-setup-with-hindsight-banks.md` for the full workflow.

```
Orchestrator → creates task, assigns to agent-lane profile
    → Dispatcher spawns worker with that profile
        → Worker reads AGENTS.md
        → Creates isolated worktree
        → Dispatches to `claude -p` or `agy -p` with full task prompt
        → Reviews diff, runs tests
        → Calls kanban_complete with agent_lane metadata
        → Cleans up worktree
```

See `references/auth-debug.md` for detailed credential pool debugging steps.
See `references/gateway-env-injection.md` for the verified OS-level env fix (EnvironmentFile drop-in).
See `references/credential-pool-debugging.md` for new-profile-specific auth issues.
