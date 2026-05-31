# Hermes Agent — Global Instructions

## Memory Architecture

**DO NOT store project details in MEMORY.md.** MEMORY.md is limited to 2,200 chars and is injected into every system prompt. Keep it compact.

**For project information, use these files instead:**

1. **Project operational details:** `C:\Users\luned\AppData\Local\hermes\projects\info\<project-name>.md`
2. **Project state:** `C:\Users\luned\Vault\Encephalon-Mageia\Projects\Personal\<project>\project-state.md`
3. **Project index:** `C:\Users\luned\AppData\Local\hermes\projects\README.md`

When you need project details:
1. `ls /c/Users/luned/AppData/Local/hermes/projects/info/` to list known projects
2. `read_file("C:\Users\luned\AppData\Local\hermes\projects\info\<project>.md")` for operational details
3. Read the vault's `project-state.md` for current state

When you finish work on a project, update both the info file and the project-state.md, then commit the vault.

## Active Projects

| Project | Board | Info File |
|---------|-------|-----------|
| Hermes-Trading | hermes-trading | `hermes-trading.md` |
| Kanban CLI | N/A | `hermes-kanban.md` |

## Hermes-Trading System

The AI trading system is a long-running autonomous project. Key facts:
- **Paper trading starts:** Monday June 1, 2026 (first weekday after setup)
- **Starting equity:** $100 hypothetical
- **Board:** `hermes-trading` (max 2 concurrent tasks to avoid rate limits)
- **DB:** `~/.hermes/profiles/trading/data/trading.db` (WAL mode)
- **Scripts:** `C:\Users\luned\Documents\Projects\Hermes-Trading\scripts\`
- **Profile:** `~/.hermes/profiles/trading/.env` (Alpaca keys — paper only)
- **Kill switch:** `~/.hermes/profiles/trading/KILL_SWITCH` (touch to halt)
- **8 cron jobs active:** Premarket Scan, Intraday Scan, Monitor, Daily Recap, Weekly Review, Monthly Review, Kanban Watcher, Active Board Watcher
- **Reviews:** Month 1 (end of June), Month 2 (end of July) + go-live plan
- **Concurrency limit:** Max 2 kanban tasks dispatched simultaneously

## Coding Project Rules

- **All work goes through kanban** for projects with boards. No direct work outside the board.
- **Never create project files in /tmp, /scratch, or temp directories.** Code lives at `C:\Users\luned\Documents\Projects\<project>\`.
- **Symlinks:** `project-state.md` and `docs/` in the code repo are symlinks to the vault. Write to the vault, not through symlinks.
- **coding-project-lifecycle skill** governs the correct workflow. Load it before starting any coding project work.

## Memory Hygiene

- MEMORY.md: behavioral rules, tool quirks, system config only. Max 2,200 chars.
- USER.md: user preferences only. Max 1,375 chars.
- Project details → `C:\Users\luned\AppData\Local\hermes\projects\info\` files (unlimited size)
- Project state → vault `project-state.md` files
- Session outcomes → hindsight memory bank (auto-retained every 5 turns)

## Profiles

**Use profiles to isolate project-specific context.** Each profile lives at `C:\Users\luned\AppData\Local\hermes\profiles\<name>\` with its own `AGENTS.md` (and optionally `SOUL.md`, `models.json`). Profiles prevent project context from flooding MEMORY.md or bleeding into unrelated sessions.

| Profile | Purpose |
|---------|---------|
| `mimirs-will` | The Colony (thecolony.cc) — mimir-well agent identity, monitoring, research, wiki management |
| `claude-lane` | Claude Code delegation lane for RollSiege |
| `agy-lane` | Agent lane for autonomous coding |
| `backend-eng` | Backend engineering agent |
| `frontend-eng` | Frontend engineering agent |
| `ops` | Operations agent |
| `pm` | Project management agent |
| `researcher` | Research agent |
| `reviewer` | Code review agent |
| `writer` | Writing agent |
| `analyst` | Analysis agent |

**Cron jobs:** Set `profile: "<name>"` on cron jobs to run them under a specific profile. The `colony-notifications-monitor` job uses `profile: "colony"`.

**Delegation:** When the default profile needs to do Colony work, it should delegate to the `colony` profile via `delegate_task` or by loading the profile's AGENTS.md context.
