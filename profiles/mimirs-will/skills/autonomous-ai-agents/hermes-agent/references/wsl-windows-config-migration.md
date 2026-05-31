# WSL ↔ Windows Hermes Config Migration Guide

## Purpose
When migrating Hermes Agent configuration from WSL to Windows (or reconciling the two), this guide documents the key differences and a safe merge strategy. Based on a real comparison done 2026-05-28 on a dual WSL/Windows install.

## Key Architectural Facts

- **Windows home**: `C:\Users\<user>\AppData\Local\hermes\` (access via `~/AppData/Local/hermes/` in git-bash)
- **WSL home**: `/home/<user>/.hermes/` in the WSL distro
- **Windows logs**: `~/AppData/Local/hermes/logs/` (NOT `~/.hermes/logs/` — `read_file` `~` resolves differently on Windows)
- **Hindsight on Windows** runs at `http://127.0.0.1:8888` — same port, but runs as a Windows process, not in WSL
- **`systemctl` is NOT available on Windows** — use `hermes gateway status` (Scheduled Task-based) to check gateway health

## Common Gaps (What WSL Has That Windows Usually Doesn't)

When a user sets up kanban in WSL first, then installs Hermes on Windows, these are the typical missing pieces on the Windows side:

### 1. Memory Provider — Hindsight
**WSL config**: `memory.provider: hindsight` in main config + `~/.hermes/hindsight/config.json` with bank setup
**Windows gap**: `memory.provider` is empty string → falls back to built-in memory only

**Fix**: 
- Set `memory.provider: hindsight` in the Windows config
- Create `~/.hermes/hindsight/config.json` with the bank config (see below)
- Ensure the hindsight server is running on Windows (`http://127.0.0.1:8888`)

### 2. Hindsight Config File
**Windows path**: `~/AppData/Local/hermes/hindsight/config.json` (in git-bash) or `%APPDATA%\Local\hermes\hindsight\config.json`

Minimum working config:
```json
{
  "mode": "local_external",
  "banks": {
    "hermes": {
      "bankId": "hermes",
      "budget": "mid",
      "enabled": true
    }
  },
  "api_url": "http://localhost:8888",
  "bank_id": "hermes",
  "recall_budget": "low",
  "auto_retain": true,
  "retain_every_n_turns": 5,
  "auto_recall": true,
  "retain_async": true,
  "recall_types": ["observation"],
  "recall_max_tokens": 2048
}
```

### 3. Kanban Orchestrator Config
**WSL**: `kanban.orchestrator_profile: orchestrator` + `auto_decompose_per_tick: 3`
**Windows gap**: Orchestrator profile directory exists but is empty; `auto_decompose_per_tick: 1`

**Fix**: 
- Create a proper config.yaml in the orchestrator profile directory
- Set `auto_decompose_per_tick: 3` for more aggressive task breakdown

### 4. Discord Channel Prompts
**WSL**: Multiple Discord channels have `channel_prompts` with kanban orchestrator instructions
**Windows gap**: `channel_prompts: {}` — empty

**Action**: Copy channel_prompts from WSL config manually. These contain project-specific orchestrator instructions.

### 5. Ollama/LLM Provider
**WSL**: `custom_providers` entry with local Ollama at `http://172.25.144.1:11434/v1`
**Windows gap**: Missing from Windows config

**Action**: Add if the user wants local LLM fallback. The IP may differ — use the Windows host IP accessible from the network.

### 6. Worker Profiles Stopped
**WSL**: Profiles are created and functional
**Windows gap**: All profiles except `default` show `gateway status: stopped`

**Fix**: Start profiles via the gateway. The dispatcher only picks up tasks for running profiles.

### 7. Per-Profile Kanban Skills
**WSL**: Each worker profile has `kanban-orchestrator`, `kanban-worker`, `kanban-codex-lane` skills in their skills dir
**Windows gap**: Skills may not be present in the Windows profile skill directories

**Action**: Copy the devops kanban skill directories to each Windows profile if missing.

### 8. Auto-Reflect Script
**WSL**: `~/.hermes/hindsight/auto_reflect.py` + crontab entry for curator-evolver
**Windows gap**: No equivalent scheduled task

**Action**: Create a Windows Task Scheduler entry or use Hermes cron to run the auto-reflect script.

## Safe Migration Procedure

**DO NOT** copy the entire WSL config over the Windows config. Instead:

1. **Identify gaps** using the checklist above
2. **Merge specific sections** — memory, kanban, discord prompts, providers
3. **Adjust paths** — WSL paths (`/home/...`) won't work on Windows; use `C:\Users\...` or `~/AppData/Local/...`
4. **Test incrementally** — after each change, restart the gateway and verify
5. **Verify with `hermes gateway status`** — the service is running
6. **Verify with `hermes profile list`** — profiles show as running

## Verification Commands

```bash
# From git-bash on Windows:
hermes gateway status          # Should show running (Scheduled Task)
hermes profile list            # Check which profiles are running
curl http://127.0.0.1:8888/health  # Hindsight health (if applicable)
cat ~/AppData/Local/hermes/config.yaml | grep -E "kanban|memory|hindsight"  # Quick config check
```
