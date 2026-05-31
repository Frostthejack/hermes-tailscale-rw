On this Windows host (luned), Hermes logs are at ~/AppData/Local/hermes/logs/ (e.g., gateway.log, errors.log), NOT at ~/.hermes/logs/ which read_file cannot find. The ~ expansion in read_file resolves differently than in terminal bash. systemctl is not available; use `hermes gateway status` (Scheduled Task-based) to check gateway health.
§
Kanban profile setup with hindsight bank isolation:
- Create profiles: `hermes profile create <name> --clone-from default`
- Each profile needs TWO config layers: (1) config.yaml `memory.provider: hindsight` + (2) `hindsight/config.json` with `bank_id`
- Hindsight config resolves: profile-scoped > legacy shared > env vars
- Bank-to-profile mapping: claude-lane → claude_code bank (NOT claude-lane); all others map 1:1
- Banks auto-create on first hindsight_retain call
- After creating profiles, gateway restart required for kanban dispatcher pickup
- Key reference: kanban-orchestrator/references/kanban-profile-setup-with-hindsight-banks.md
§
WSL→Windows Hermes migration checklist: Key gaps when migrating: (1) memory.provider='hindsight', (2) hindsight/config.json must exist, (3) kanban.orchestrator_profile needs real config, (4) discord channel prompts must be copied, (5) worker profiles must be started, (6) ollama/custom providers need re-adding. Never copy full config — merge incrementally. Reference: hermes-agent/references/wsl-windows-config-migration.md. Bitwarden self-hosting: official Bitwarden server via Docker (bitwarden.sh), or Vaultwarden for lightweight. Both work. See hermes-agent skill for config patterns.
§
WSL access from Windows Hermes: `wsl bash -c '...'` times out/blocked. Simple `wsl <cmd>` may compound shell commands work. For WSL filesystem inspection, ask user to run commands directly in WSL terminal. With `networkingMode=mirrored` in .wslconfig, WSL ~ maps to C:\Users\<user>\ and there is only ONE Hermes install (Windows). The real data dir is C:\Users\<user>\AppData\Local\hermes\ — not C:\Users\<user>\.hermes\ (which is shallow/legacy).